// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_implementation;

import 'dart:async';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:path/path.dart' as path;
import 'package:reflectable/reflectable.dart';
import 'source_manager.dart';
import 'transformer_errors.dart';

// TODO(eernst): Keep in mind, with reference to
// http://dartbug.com/21654 comment #5, that it would be very valuable
// if this transformation can interact smoothly with incremental
// compilation.  By nature, that is hard to achieve for a
// source-to-source translation scheme, but a long source-to-source
// translation step which is invoked frequently will certainly destroy
// the immediate feedback otherwise offered by incremental compilation.
// WORKAROUND: A work-around for this issue which is worth considering
// is to drop the translation entirely during most of development,
// because we will then simply work on a normal Dart program that uses
// dart:mirrors, which should have the same behavior as the translated
// program, and this could work quite well in practice, except for
// debugging which is concerned with the generated code (but that would
// ideally be an infrequent occurrence).

/// Checks whether the given [type] from the target program is "our"
/// class [Reflectable] by looking up the static field
/// [Reflectable.thisClassId] and checking its value (which is a 40
/// character string computed by sha1sum on an old version of
/// reflectable.dart).
///
/// Discussion of approach: Checking that we have found the correct
/// [Reflectable] class is crucial for correctness, and the "obvious"
/// approach of just looking up the library and then the class with the
/// right names using [resolver] is unsafe.  The problems are as
/// follows: (1) Library names are not guaranteed to be unique in a
/// given program, so we might look up a different library named
/// reflectable.reflectable, and a class named Reflectable in there.  (2)
/// Library URIs (which must be unique in a given program) are not known
/// across all usage locations for reflectable.dart, so we cannot easily
/// predict all the possible URIs that could be used to import
/// reflectable.dart; and it would be awkward to require that all user
/// programs must use exactly one specific URI to import
/// reflectable.dart.  So we use [Reflectable.thisClassId] which is very
/// unlikely to occur with the same value elsewhere by accident.
bool _equalsClassReflectable(ClassElement type) {
  FieldElement idField = type.getField("thisClassId");
  if (idField == null || !idField.isStatic) return false;
  if (idField is ConstFieldElementImpl) {
    EvaluationResultImpl idResult = idField.evaluationResult;
    if (idResult != null) {
      return idResult.value.stringValue == Reflectable.thisClassId;
    }
    // idResult == null: analyzer/.../element.dart does not specify
    // whether this could happen, but it is surely not the right
    // class, so we fall through.
  }
  // Not a const field, cannot be the right class.
  return false;
}

/// Returns the ClassElement in the target program which corresponds to class
/// [Reflectable].
ClassElement _findReflectableClassElement(LibraryElement reflectableLibrary) {
  for (CompilationUnitElement unit in reflectableLibrary.units) {
    for (ClassElement type in unit.types) {
      if (type.name == Reflectable.thisClassName &&
          _equalsClassReflectable(type)) {
        return type;
      }
    }
  }
  // Class [Reflectable] was not found in the target program.
  return null;
}

/// Returns true iff [possibleSubtype] is a direct subclass of [type].
bool _isDirectSubclassOf(InterfaceType possibleSubtype, InterfaceType type) {
  InterfaceType superclass = possibleSubtype.superclass;
  // Even if `superclass == null` (superclass of Object), the equality
  // test will produce the correct result.
  return type == superclass;
}

/// Returns true iff [possibleSubtype] is a subclass of [type], including the
/// reflexive and transitive cases.
bool _isSubclassOf(InterfaceType possibleSubtype, InterfaceType type) {
  if (possibleSubtype == type) return true;
  InterfaceType superclass = possibleSubtype.superclass;
  if (superclass == null) return false;
  return _isSubclassOf(superclass, type);
}

/// Returns the metadata class in [elementAnnotation] if it is an
/// instance of a direct subclass of [focusClass], otherwise returns
/// `null`.  Uses [errorReporter] to report an error if it is a subclass
/// of [focusClass] which is not a direct subclass of [focusClass],
/// because such a class is not supported as a Reflectable metadata
/// class.
ClassElement _getReflectableAnnotation(ElementAnnotation elementAnnotation,
                                       ClassElement focusClass,
                                       ErrorReporter errorReporter) {
  if (elementAnnotation.element == null) {
    // TODO(eernst): The documentation in
    // analyzer/lib/src/generated/element.dart does not reveal whether
    // elementAnnotation.element can ever be null. The following action
    // is based on the assumption that it means "there is no annotation
    // here anyway".
    return null;
  }

  /// Checks that the inheritance hierarchy placement of [type]
  /// conforms to the constraints relative to [classReflectable],
  /// which is intended to refer to the class Reflectable defined
  /// in package:reflectable/reflectable.dart. In case of violations,
  /// raises an error using the given [errorReporter].
  bool checkInheritance(InterfaceType type,
                        InterfaceType classReflectable,
                        ErrorReporter errorReporter) {
    if (!_isSubclassOf(type, classReflectable)) {
      // Not a subclass of [classReflectable] at all.
      return false;
    }
    if (!_isDirectSubclassOf(type, classReflectable)) {
      // Instance of [classReflectable], or of indirect subclass
      // of [classReflectable]: Not supported, report an error.
      errorReporter.reportErrorForElement(
          TransformationErrorCode.REFLECTABLE_METADATA_NOT_DIRECT_SUBCLASS,
          elementAnnotation.element,
          []);
      return false;
    }
    // A direct subclass of [classReflectable], all OK.
    return true;
  }

  Element element = elementAnnotation.element;
  // TODO(eernst): Currently we only handle constructor expressions
  // and simple identifiers.  May be generalized later.
  if (element is ConstructorElement) {
    bool isOk = checkInheritance(element.enclosingElement.type,
                                 focusClass.type,
                                 errorReporter);
    return isOk ? element.enclosingElement.type.element : null;
  } else if (element is PropertyAccessorElement) {
    PropertyInducingElement variable = element.variable;
    // Surprisingly, we have to use the type VariableElementImpl
    // here.  This is because VariableElement does not declare
    // evaluationResult (presumably it is "secret").
    if (variable is VariableElementImpl && variable.isConst) {
      VariableElementImpl variableImpl = variable as VariableElementImpl;
      EvaluationResultImpl result = variableImpl.evaluationResult;
      bool isOk = checkInheritance(result.value.type,
                                   focusClass.type,
                                   errorReporter);
      return isOk ? result.value.type.element : null;
    }
  } else /* element is something else */ {
    // This syntactic form of annotation is not supported.
    //
    // TODO(eernst): We need to consider whether there could be some other
    // syntactic constructs that are incorrectly assumed by programmers to
    // be usable with Reflectable.  Currently, such constructs will silently
    // have no effect; it might be better to emit a diagnostic message (a
    // hint?) in order to notify the programmer that "it does not work".
    // The trade-off is that such constructs may have been written by
    // programmers who are doing something else, intentionally.  To emit a
    // diagnostic message, we must check whether there is a Reflectable
    // somewhere inside this syntactic construct, and then emit the message
    // in cases that we "consider likely to be misunderstood".
    return null;
  }
}

/// Returns true iff the given [library] imports [targetLibrary], which
/// must be non-null.
bool _doesImport(LibraryElement library, LibraryElement targetLibrary) {
  List<LibraryElement> importedLibraries = library.importedLibraries;
  return importedLibraries.contains(targetLibrary);
}

/// Used to hold data that describes a Reflectable annotated class,
/// including that class itself and its associated Reflectable
/// metadata class.
class ReflectableClassData {
  final ClassElement annotatedClass;
  final ClassElement metadataClass;
  ReflectableClassData(this.annotatedClass, this.metadataClass);
}

/// Returns a list of classes from the scope of [resolver] which are
/// annotated with metadata whose type is a subtype of [Reflectable].
/// [reflectableLibrary] is assumed to be the library that contains the
/// declaration of the class [Reflectable].
///
/// TODO(eernst): Make sure it works also when other packages are being
/// used by the target program which have already been transformed by
/// this transformer (e.g., there would be a clash on the use of
/// reflectableClassId with values near 1000 for more than one class).
List<ReflectableClassData>
    _findReflectableClasses(LibraryElement reflectableLibrary,
                            Resolver resolver) {
  ClassElement focusClass = _findReflectableClassElement(reflectableLibrary);
  List<ReflectableClassData> result = <ReflectableClassData>[];
  if (focusClass == null) return result;
  for (LibraryElement library in resolver.libraries) {
    for (CompilationUnitElement unit in library.units) {
      RecordingErrorListener errorListener = new RecordingErrorListener();
      ErrorReporter errorReporter =
          new ErrorReporter(errorListener, unit.source);
      for (ClassElement type in unit.types) {
        for (ElementAnnotation metadatum in type.metadata) {
          ClassElement metadataClass =
              _getReflectableAnnotation(metadatum, focusClass, errorReporter);
          if (metadataClass != null) {
            result.add(new ReflectableClassData(type, metadataClass));
          }
        }
      }
      List<AnalysisError> errors =
          errorListener.getErrorsForSource(unit.source);
      if (!errors.isEmpty) {
        // TODO(eernst): Resolve how to show the errors. Later on,
        // find an appropriate general approach to the handling of
        // "compilation" errors.
        print(errors);
        throw new UnimplementedError();
      }
    }
  }
  return result;
}

/// Used as the name of the generated feature in each class whose
/// metadata includes an instance `o` of a subclass of Reflectable, such
/// that its runtime type can be established without actually calling
/// `o.runtimeType` on the instance for which a mirror is to be
/// constructed and delivered.  This identifier violates the Dart style
/// guide with respect to naming in order to make name clashes less
/// likely.  Each class will then have a declaration following this
/// pattern at the very beginning:
///
///   const int reflectable__Class__Identifier = 3889;
///
/// where 3889 is a unique identifier for the enclosing class in
/// the given program.  Classes with no 'reflectable__Class__Identifier'
/// are considered to be outside the scope of this package, and no
/// static mirrors will be delivered for them.
const String classIdentifier = 'reflectable__Class__Identifier';

/// Perform `replace` on the given [sourceManager] such that the
/// import/export of `reflectableLibrary` specified by
/// [uriReferencedElement] is replaced by the given [replacement]; it is
/// required that `uriReferencedElement is! CompilationUnitElement`.
void _replaceUriReferencedElement(SourceManager sourceManager,
                                  UriReferencedElement uriReferencedElement,
                                  String replacement) {
  // This is intended to work for imports and exports only, i.e., not
  // for compilation units. When this constraint is satisfied, `.node`
  // will return a `NamespaceDirective`.
  assert(uriReferencedElement is ImportElement ||
         uriReferencedElement is ExportElement);
  NamespaceDirective namespaceDirective = uriReferencedElement.node;
  int directiveStart = namespaceDirective.offset;
  if (directiveStart == -1) {
    // Encountered a synthetic element.  We do not expect imports or
    // exports of reflectable to be synthetic, so we make it an error.
    throw new UnimplementedError();
  }
  int directiveEnd = namespaceDirective.end;
  // If we have `directiveStart != -1 && directiveEnd == -1` then there
  // is a bug in the implementation of [uriReferencedElement].
  assert(directiveEnd != -1);
  sourceManager.replace(directiveStart, directiveEnd, replacement);
}

/// Eliminate the import of `reflectableLibrary` specified by
/// [importElement] from the source of [sourceManager].
void _replaceImportDirective(SourceManager sourceManager,
                             ImportElement importElement,
                             String replacement) {
  _replaceUriReferencedElement(sourceManager, importElement, replacement);
}

/// Perform `sourceManager.replace` such that the export of
/// `reflectableLibrary` specified by [exportElement] is eliminated and
/// an error message is emitted. This transformer will not work if
/// `reflectableLibrary` is exported: that library must be totally
/// eliminated from the transformed program, such that the program does
/// not indirectly import 'dart:mirrors'.
void _emitDiagnosticForExportDirective(SourceManager sourceManager,
                                       ExportElement exportElement,
                                       ErrorReporter errorReporter) {
  errorReporter.reportErrorForElement(
      TransformationErrorCode.REFLECTABLE_LIBRARY_EXPORTED,
      exportElement,
      []);
  // We cannot compile a program where an unknown library (namely
  // `reflectableLibrary`, whose import has been deleted) must be
  // exported, so continuing from here without changing anything will
  // not work.  However, if `reflectableLibrary` was exported but never
  // used then we would still be able to compile the program without the
  // export.  So we eliminate the export.
  //
  // TODO(eernst): Add a test that reveals whether
  // `reportErrorForElement` terminates the program; if so, we might
  // want to raise a warning rather than an error; in any case, we need
  // to extend the dartdoc of this method to describe its termination
  // properties.
  _replaceUriReferencedElement(sourceManager, exportElement, "");
}

// TODO(eernst): Make sure this name is unique.
String _staticClassMirrorName(String targetClassName) =>
    "_${targetClassName}_ClassMirror";

// TODO(eernst): Make sure this name is unique.
String _staticInstanceMirrorName(String targetClassName) =>
    "_${targetClassName}_InstanceMirror";

const String generatedComment = "// Generated";

ImportElement _findLastImport(LibraryElement library) {
  if (library.imports.isNotEmpty) {
    ImportElement importElement = library.imports.lastWhere(
        (importElement) => importElement.node != null,
        orElse: () => null);
    if (importElement != null) {
      // Found an import element with a node (i.e., a non-synthetic one).
      return importElement;
    } else {
      // No non-synthetic imports.
      return null;
    }
  }
  // library.imports.isEmpty
  return null;
}

ExportElement _findFirstExport(LibraryElement library) {
  if (library.exports.isNotEmpty) {
    ExportElement exportElement = library.exports.firstWhere(
        (exportElement) => exportElement.node != null,
        orElse: () => null);
    if (exportElement != null) {
      // Found an export element with a node (i.e., a non-synthetic one)
      return exportElement;
    } else {
      // No non-synthetic exports.
      return null;
    }
  }
  // library.exports.isEmpty
  return null;
}

/// Transform all imports of [reflectableLibrary] to import the thin
/// outline version (`static_reflectable.dart`), such that we do not
/// indirectly import `dart:mirrors`.  Remove all exports of
/// [reflectableLibrary] and emit a diagnostic message about the fact
/// that such an import was encountered (and it violates the constraints
/// of this package, and hence we must remove it).  All the operations
/// are using [targetLibrary] to find the source code offsets, and using
/// [sourceManager] to actually modify the source code.
void _transformSourceDirectives(LibraryElement reflectableLibrary,
                                LibraryElement targetLibrary,
                                SourceManager sourceManager) {
  RecordingErrorListener errorListener = new RecordingErrorListener();
  ErrorReporter errorReporter =
      new ErrorReporter(errorListener, targetLibrary.source);

  void replaceImportOfReflectable(UriReferencedElement element) {
    _replaceUriReferencedElement(
        sourceManager, element,
        "import 'package:reflectable/static_reflectable.dart';");
  }

  void emitDiagnosticForExportDirective(UriReferencedElement element) =>
      _emitDiagnosticForExportDirective(sourceManager, element, errorReporter);

  // Transform all imports and exports of reflectable.
  targetLibrary.imports
      .where((element) => element.importedLibrary == reflectableLibrary)
      .forEach(replaceImportOfReflectable);
  targetLibrary.exports
      .where((element) => element.exportedLibrary == reflectableLibrary)
      .forEach(emitDiagnosticForExportDirective);
}

/// Transform the given [metadataClass] by adding features needed to
/// implement the abstract methods in Reflectable from the library
/// `static_reflectable.dart`.  Use [sourceManager] to perform the
/// actual source code modification.  The [annotatedClasses] is the
/// set of Reflectable annotated class whose metadata includes an
/// instance of [metadataClass], i.e., the set of classes whose
/// instances [metadataClass] must provide reflection for.
void _transformMetadataClass(ClassElement metadataClass,
                             List<ClassElement> annotatedClasses,
                             SourceManager sourceManager,
                             ErrorReporter errorReporter) {
  // A ClassElement can be associated with an [EnumDeclaration], but
  // this is not supported for a Reflectable metadata class.
  if (metadataClass.node is EnumDeclaration) {
    errorReporter.reportErrorForElement(
        TransformationErrorCode.REFLECTABLE_IS_ENUM,
        metadataClass,
        []);
  }
  // Otherwise it is a ClassDeclaration.
  ClassDeclaration classDeclaration = metadataClass.node;
  int insertionIndex = classDeclaration.rightBracket.offset;

  // Now insert generated material at insertionIndex; note that we insert
  // the elements in reverse order, because we always push all the already
  // inserted elements ahead for each new element inserted.

  void insert(String code) {
    sourceManager.replace(insertionIndex, insertionIndex, "$code\n");
  }

  String reflectCaseOfName(String className) =>
      "    if (reflectee.runtimeType == $className) {\n"
      "      return new ${_staticInstanceMirrorName(className)}(reflectee);\n"
      "    }\n";

  String reflectCases = "";  // Accumulates the body of the `reflect` method.

  // Add each supported case to [reflectCases].
  annotatedClasses.forEach((ClassElement annotatedClass) {
      String className = annotatedClass.node.name.name.toString();
      reflectCases += reflectCaseOfName(className);
    });

  // Add failure case to [reflectCases]: No matching classes, so the
  // user is asking for a kind of reflection that was not requested,
  // which is a runtime error.
  // TODO(eernst): Consider more carefully *what* to throw here.
  reflectCases += "    throw new UnimplementedError();";

  // Add the `reflect` method to [metadataClass].
  insert("  InstanceMirror reflect(Object reflectee) {\n$reflectCases\n  }");

  // In front of all the generated material, indicate that it is generated.
  insert("\n  $generatedComment: Rest of class");
}

/// Find classes in among `metadataClass` from [reflectableClasses]
/// whose `library` is [targetLibrary], and transform them using
/// _transformMetadataClass.
void _transformMetadataClasses(List<ReflectableClassData> reflectableClasses,
                               LibraryElement targetLibrary,
                               SourceManager sourceManager) {
  bool isInTargetLibrary(ReflectableClassData classData) {
    return classData.metadataClass.library == targetLibrary;
  }

  Set<ClassElement> metadataClasses = new Set<ClassElement>();

  void addMetadataClass(ReflectableClassData classData) {
    metadataClasses.add(classData.metadataClass);
  }

  RecordingErrorListener errorListener = new RecordingErrorListener();
  ErrorReporter errorReporter =
      new ErrorReporter(errorListener, targetLibrary.source);

  void transformMetadataClass(ClassElement metadataClass) {
    List<ClassElement> annotatedClasses = reflectableClasses
        .where((classData) => classData.metadataClass == metadataClass)
        .map((classData) => classData.annotatedClass)
        .toList();
    _transformMetadataClass(metadataClass,
                            annotatedClasses,
                            sourceManager,
                            errorReporter);
  }

  reflectableClasses.where(isInTargetLibrary).forEach(addMetadataClass);
  metadataClasses.forEach(transformMetadataClass);
}

/// Returns the result of transforming the given [source] code, which is
/// assumed to be the contents of the file associated with the
/// [targetLibrary], which is the library currently being
/// transformed.  [transformedPath] is the path of that library, used to
/// find the file name of the library, which is again used to construct
/// the name of the generated file
/// [reflectableLibrary] is assumed to be the library that declareds the
/// class [Reflectable].
///
/// TODO(eernst): The transformation has only been implemented
/// partially at this time.
///
/// TODO(eernst): Note that this function uses instances of [AstNode]
/// and [Token] to get the correct offset into [source] of specific
/// constructs in the code.  This is potentially costly, because this
/// (intermediate) parsing related information may have been evicted
/// since parsing, and the source code will then be parsed again.
/// However, we do not have an alternative unless we want to parse
/// everything ourselves.  But it would be useful to be able to give
/// barback a hint that this information should preferably be preserved.
String _transformSource(LibraryElement reflectableLibrary,
                        List<ReflectableClassData> reflectableClasses,
                        LibraryElement targetLibrary,
                        String source) {
  // Used to manage replacements of code snippets by other code snippets
  // in [source].
  SourceManager sourceManager = new SourceManager(source);

  // Used to accumulate generated classes, maps, etc.
  String generatedSource = "";

  // Transform selected existing elements in [targetLibrary].
  _transformSourceDirectives(reflectableLibrary, targetLibrary, sourceManager);
  _transformMetadataClasses(reflectableClasses, targetLibrary, sourceManager);

  for (ReflectableClassData classData in reflectableClasses) {
    ClassElement annotatedClass = classData.annotatedClass;
    String className = annotatedClass.node.name.name.toString();

    // We only transform classes in the [targetLibrary].
    if (annotatedClass.library != targetLibrary) continue;

    // Generate a static mirror for this class.
    generatedSource += """\n
class ${_staticClassMirrorName(className)} extends ClassMirrorUnimpl {
}
""";

    // Generate a static mirror for instances of this class.
    generatedSource += """\n
class ${_staticInstanceMirrorName(className)} extends InstanceMirrorUnimpl {
  final $className reflectee;
  ${_staticInstanceMirrorName(className)}(this.reflectee);
}
""";
  }

  if (generatedSource.length == 0) {
    return sourceManager.source;
  } else {
    // Add an import such that generated classes can see their superclasses.
    // Note that we make no attempt at following the style guide, e.g., by
    // keeping the imports sorted.
    String newImport =
        "\nimport 'package:reflectable/src/mirrors_unimpl.dart';\n";
    // Index in [source] where the new import directive is inserted, we
    // use 0 as the default placement (at the front of the file), but
    // make a heroic attempt to find a better placement first.
    int newImportIndex = 0;
    ImportElement importElement = _findLastImport(targetLibrary);
    if (importElement != null) {
      newImportIndex = importElement.node.end;
    } else {
      // No non-synthetic import directives present.
      ExportElement exportElement = _findFirstExport(targetLibrary);
      if (exportElement != null) {
        // Put the new import before the exports
        newImportIndex = exportElement.node.offset;
      } else {
        // No non-synthetic import nor export directives present.
        LibraryDirective libraryDirective =
            targetLibrary.definingCompilationUnit.node.directives
            .firstWhere((directive) => directive is LibraryDirective,
                        orElse: () => null);
        if (libraryDirective != null) {
          // Put the new import after the library name directive.
          newImportIndex = libraryDirective.end;
        } else {
          // No library directive either, keep newImportIndex == 0.
        }
      }
    }
    // Finally insert the import directive at the chosen location.
    sourceManager.replace(newImportIndex, newImportIndex, newImport);

    return """
${sourceManager.source}

$generatedComment: Rest of file

$generatedSource
""";
  }
}

/// Escape the given [charToEscape] in [toBeEscaped].
String escapeChar(String toBeEscaped, String charToEscape) {
  String result = toBeEscaped;
  int noOfEscapes = 0;
  for (int index = toBeEscaped.indexOf(charToEscape);
       index != -1;
       index = toBeEscaped.indexOf(charToEscape, index + 1)) {
    String prefix = result.substring(0, index + noOfEscapes);
    String suffix = result.substring(index + noOfEscapes);
    result = "$prefix\\$suffix";
    noOfEscapes++;
  }
  return result;
}

/// Escape characters from [path] that will disrupt its usage
/// in generated code.
String escape(String path) {
  String result = path;
  if (result.contains(new RegExp(r"['$\\]"))) {
    // Disruptive characters in [path], escape them
    result = escapeChar(result, "\\");
    result = escapeChar(result, "\$");
    result = escapeChar(result, "'");
  }
  return result;
}

/// Performs the transformation which eliminates all imports of
/// `package:reflectable/reflectable.dart` and instead provides a set of
/// statically generated mirror classes.
Future apply(Transform transform) {
  // The type argument in the return type is omitted because the
  // documentation on barback and on transformers do not specify it.
  Asset input = transform.primaryInput;
  Resolvers resolvers = new Resolvers(dartSdkDirectory);
  return resolvers.get(transform).then((resolver) {
    LibraryElement targetLibrary = resolver.getLibrary(input.id);
    LibraryElement reflectableLibrary =
        resolver.getLibraryByName("reflectable.reflectable");
    if (reflectableLibrary == null) {
      // Stop and do not consumePrimary, i.e., let the original source
      // pass through without changes.
      return new Future.value();
    }
    return input.readAsString().then((source) {
      if (_doesImport(targetLibrary, reflectableLibrary)) {
        List<ReflectableClassData> reflectableClasses =
            _findReflectableClasses(reflectableLibrary, resolver);
        String pathOfTransformedFile = input.id.path;
        String transformedSource = _transformSource(reflectableLibrary,
                                                    reflectableClasses,
                                                    targetLibrary,
                                                    source);
        // Transform user provided code.
        transform.consumePrimary();
        transform.addOutput(new Asset.fromString(input.id, transformedSource));
      } else {
        // We do not consumePrimary, i.e., let the original source pass
        // through without changes.
      }
    });
  });
}
