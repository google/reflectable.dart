// (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_implementation;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:barback/barback.dart';
import 'package:barback/src/transformer/transform.dart';
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

/// Report the errors given to [errorReporter]
void reportErrors(RecordingErrorListener errorListener,
                  ErrorReporter errorReporter,
                  Source source) {
  // TODO(eernst): Show the given errors to the user. The following
  // approach ensures in a simple manner that the errors are not suppressed.
  List<AnalysisError> errors = errorListener.getErrorsForSource(source);
  if (!errors.isEmpty) print(errors);
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
    // Surprisingly, we have to use [ConstTopLevelVariableElementImpl]
    // here (or a similar type).  This is because none of the "public name"
    // types (types whose name does not end in `..Impl`) declare the getter
    // `evaluationResult`.  Another possible choice of type would be
    // [VariableElementImpl], but with that one we would have to test
    // `isConst` as well.
    if (variable is ConstTopLevelVariableElementImpl) {
      EvaluationResultImpl result = variable.evaluationResult;
      bool isOk = checkInheritance(result.value.type,
                                   focusClass.type,
                                   errorReporter);
      return isOk ? result.value.type.element : null;
    } else {
      // Not a const top level variable, not relevant.
      return null;
    }
  }
  // Otherwise [element] is some other construct which is not supported.
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
      reportErrors(errorListener, errorReporter, unit.source);
    }
  }
  return result;
}

/// Auxiliary class, used in _findMissingImports.
class _Import {
  final LibraryElement importer;
  final LibraryElement imported;
  _Import(this.importer, this.imported);
  bool operator ==(Object other) {
    if (other is _Import) {
      return importer == other.importer && imported == other.imported;
    } else {
      return false;
    }
  }
}

/// Return a map which maps the library for each class in [reflectableClasses]
/// in the field `metadataClass` to the set of libraries of the corresponding
/// field `annotatedClass`, thus specifying which `import` directives we
/// need to add during code transformation.
Map<LibraryElement, Set<LibraryElement>>
    _findMissingImports(List<ReflectableClassData> reflectableClasses) {
  Map<LibraryElement, Set<LibraryElement>> result =
      <LibraryElement, Set<LibraryElement>>{};
       
  // Gather all the required imports.
  Set<_Import> requiredImports = new Set<_Import>();
  Set<LibraryElement> requiredImporters = new Set<LibraryElement>();
  for (ReflectableClassData classData in reflectableClasses) {
    LibraryElement metadataLibrary = classData.metadataClass.library;
    LibraryElement annotatedLibrary = classData.annotatedClass.library;
    if (metadataLibrary != annotatedLibrary) {
      requiredImports.add(new _Import(metadataLibrary, annotatedLibrary));
      requiredImporters.add(metadataLibrary);
    }
  }

  // Transfer all required and non-existing imports into [result],
  // represented as a mapping from each importer to the set of
  // libraries that it must import.
  for (LibraryElement importer in requiredImporters) {
    Set<LibraryElement> importeds = requiredImports
        .where((_Import _import) => _import.importer == importer)
        .map((_Import _import) => _import.imported);
    result[importer] = importeds;
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
/// URI of the import/export of `reflectableLibrary` specified by
/// [uriReferencedElement] is replaced by the given [newUri]; it is
/// required that `uriReferencedElement is` either an `ImportElement`
/// or an `ExportElement`.
void _replaceUriReferencedElement(SourceManager sourceManager,
                                  UriReferencedElement uriReferencedElement,
                                  String newUri) {
  // This is intended to work for imports and exports only, i.e., not
  // for compilation units. When this constraint is satisfied, `.node`
  // will return a `NamespaceDirective`.
  assert(uriReferencedElement is ImportElement ||
         uriReferencedElement is ExportElement);
  int uriStart = uriReferencedElement.uriOffset;
  if (uriStart == -1) {
    // Encountered a synthetic element.  We do not expect imports or
    // exports of reflectable to be synthetic, so we make it an error.
    throw new UnimplementedError();
  }
  int uriEnd = uriReferencedElement.uriEnd;
  // If we have `uriStart != -1 && uriEnd == -1` then there is a bug
  // in the implementation of [uriReferencedElement].
  assert(uriEnd != -1);
  sourceManager.replace(uriStart, uriEnd, "'$newUri'");
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
  // TODO(eernst): Create an issue for the analyzer, because
  // `exportElement.node == null`, and also
  // `exportElement.displayName == null`, which means that we cannot
  // use the obvious methods: neither `reportErrorForElement` nor
  // `reportErrorForOffset`.  Currently falling back on the Uri.
  errorReporter.reportErrorForOffset(
      TransformationErrorCode.REFLECTABLE_LIBRARY_EXPORTED,
      exportElement.uriOffset,
      exportElement.uriEnd,
      []);
  // We cannot compile a program where an unknown library (namely
  // `reflectableLibrary`, whose import has been deleted) must be
  // exported, so continuing from here without changing anything will
  // not work.  However, if `reflectableLibrary` was exported but never
  // used then we would still be able to compile the program without the
  // export.  So we eliminate the export.

  // TODO(eernst): Commented out until issue above reported and resolved
  // (currently crashes because `exportElement.node == null`):
  //
  // NamespaceDirective namespaceDirective = exportElement.node;
  // int directiveStart = namespaceDirective.offset;
  // if (directiveStart == -1) {
  //   // Encountered a synthetic element.  We do not expect exports of
  //   // reflectable to be synthetic, so we make it an error.
  //   throw new UnimplementedError();
  // }
  // int directiveEnd = namespaceDirective.end;
  // // If we have `directiveStart != -1 && directiveEnd == -1` then there
  // // is a bug in the implementation of [exportElement].
  // assert(directiveEnd != -1);
  // sourceManager.replace(directiveStart, directiveEnd, "");
}

// TODO(eernst): Make sure this name is unique.
String _staticClassMirrorName(String targetClassName) =>
    "Static_${targetClassName}_ClassMirror";

// TODO(eernst): Make sure this name is unique.
String _staticInstanceMirrorName(String targetClassName) =>
    "Static_${targetClassName}_InstanceMirror";

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

/// Find a suitable index for insertion of additional import directives
/// into [targetLibrary].
int _newImportIndex(LibraryElement targetLibrary) {
  // Index in [source] where the new import directive is inserted, we
  // use 0 as the default placement (at the front of the file), but
  // make a heroic attempt to find a better placement first.
  int index = 0;
  ImportElement importElement = _findLastImport(targetLibrary);
  if (importElement != null) {
    index = importElement.node.end;
  } else {
    // No non-synthetic import directives present.
    ExportElement exportElement = _findFirstExport(targetLibrary);
    if (exportElement != null) {
      // Put the new import before the exports
      index = exportElement.node.offset;
    } else {
      // No non-synthetic import nor export directives present.
      LibraryDirective libraryDirective =
          targetLibrary.definingCompilationUnit.node.directives
          .firstWhere((directive) => directive is LibraryDirective,
                      orElse: () => null);
      if (libraryDirective != null) {
        // Put the new import after the library name directive.
        index = libraryDirective.end;
      } else {
        // No library directive either, keep index == 0.
      }
    }
  }
  return index;
}

/// Transform all imports of [reflectableLibrary] to import the thin
/// outline version (`static_reflectable.dart`), such that we do not
/// indirectly import `dart:mirrors`.  Remove all exports of
/// [reflectableLibrary] and emit a diagnostic message about the fact
/// that such an import was encountered (and it violates the constraints
/// of this package, and hence we must remove it).  All the operations
/// are using [targetLibrary] to find the source code offsets, and using
/// [sourceManager] to actually modify the source code.  We require that
/// there is an import which has no `show` and no `hide` clause (this is
/// a potentially temporary restriction, we may implement support for
/// more cases later on, but for now we just prohibit `show` and `hide`).
/// The returned value is the [PrefixElement] that is used to give
/// [reflectableLibrary] a prefix; `null` is returned if there is
/// no such prefix.
PrefixElement _transformSourceDirectives(LibraryElement reflectableLibrary,
                                         LibraryElement targetLibrary,
                                         SourceManager sourceManager) {
  RecordingErrorListener errorListener = new RecordingErrorListener();
  ErrorReporter errorReporter =
      new ErrorReporter(errorListener, targetLibrary.source);
  List<ImportElement> editedImports = <ImportElement>[];

  void replaceImportOfReflectable(UriReferencedElement element) {
    _replaceUriReferencedElement(
        sourceManager, element,
        "package:reflectable/static_reflectable.dart");
    editedImports.add(element);
  }

  void emitDiagnosticForExportDirective(UriReferencedElement element) =>
      _emitDiagnosticForExportDirective(sourceManager, element, errorReporter);

  void handleErrors() =>
      reportErrors(errorListener, errorReporter, targetLibrary.source);

  // Transform all imports and exports of reflectable.
  targetLibrary.imports
      .where((element) => element.importedLibrary == reflectableLibrary)
      .forEach(replaceImportOfReflectable);
  targetLibrary.exports
      .where((element) => element.exportedLibrary == reflectableLibrary)
      .forEach(emitDiagnosticForExportDirective);

  // If [reflectableLibrary] is never imported then it has no prefix.
  if (editedImports.isEmpty) {
    handleErrors();
    return null;
  }

  bool isOK(ImportElement importElement) {
    // We do not support a deferred load of Reflectable.
    if (importElement.isDeferred) return false;
    // We do not currently support `show` nor `hide` clauses,
    // otherwise this one is OK.
    return importElement.combinators.isEmpty;
  }

  // Try to select a good import
  for (ImportElement importElement in editedImports) {
    if (isOK(importElement)) {
      handleErrors();
      return importElement.prefix;
    }
  }

  // No good imports found, but we do have some imports, so they are all bad.
  // Let us complain about the first one.  In the unlikely case that we have
  // multiple imports of Reflectable, and they are all bad, this means that
  // the user will get one error message, then fix the issue, then get
  // another error message about the next line of code, essentially.  This
  // is not nice, but it is very unlikely at it will affect anybody who
  // isn't specifically looking for it.
  errorReporter.reportErrorForOffset(
      TransformationErrorCode.REFLECTABLE_LIBRARY_UNSUPPORTED_IMPORT,
      editedImports[0].node.offset,
      editedImports[0].node.length,
      []);
  handleErrors();
  return null;
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
                             PrefixElement prefixElement,
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
  String prefix = prefixElement == null ? "" : "${prefixElement.name}.";
  insert("  ${prefix}InstanceMirror "
         "reflect(Object reflectee) {\n$reflectCases\n  }");

  // In front of all the generated material, indicate that it is generated.
  insert("\n  $generatedComment: Rest of class");
}

/// Find classes in among `metadataClass` from [reflectableClasses]
/// whose `library` is [targetLibrary], and transform them using
/// _transformMetadataClass.
void _transformMetadataClasses(List<ReflectableClassData> reflectableClasses,
                               LibraryElement targetLibrary,
                               SourceManager sourceManager,
                               PrefixElement prefixElement) {
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
                            prefixElement,
                            errorReporter);
  }

  reflectableClasses.where(isInTargetLibrary).forEach(addMetadataClass);
  metadataClasses.forEach(transformMetadataClass);
}

/// Compute a relative path such that it denotes the file at
/// [destinationPath] when used from the location of the file
/// [sourcePath].
String _relativePath(String destinationPath, String sourcePath) {
  List<String> destinationSplit = path.split(destinationPath);
  List<String> sourceSplit = path.split(sourcePath);
  while (destinationSplit.length > 1 && sourceSplit.length > 1 &&
         destinationSplit[0] == sourceSplit[0]) {
    destinationSplit = destinationSplit.sublist(1);
    sourceSplit = sourceSplit.sublist(1);
  }
  while (sourceSplit.length > 1) {
    sourceSplit = sourceSplit.sublist(1);
    destinationSplit.insert(0, "..");
  }
  return path.joinAll(destinationSplit);
}

/// Returns the result of transforming the given [source] code, which is
/// assumed to be the contents of the file associated with the
/// [targetLibrary], which is the library currently being transformed.
/// [reflectableClasses] models the define/use relation where
/// Reflectable metadata classes declare material for use as metadata
/// and Reflectable annotated classes use that material.
/// [libraryToAssetMap] is used in the generation of `import` directives
/// that enable Reflectable metadata classes to see static mirror
/// classes that it must be able to `reflect` which are declared in
/// other libraries; [missingImports] lists the required imports which
/// are not already present, i.e., the ones that must be added.
/// [reflectableLibrary] is assumed to be the library that declares the
/// class [Reflectable].
///
/// TODO(eernst): The transformation has only been implemented
/// partially at this time.
///
/// TODO(eernst): Note that this function uses instances of [AstNode]
/// and [Token] to get the correct offset into the [source] of specific
/// constructs in the code.  This is potentially costly, because this
/// (intermediate) parsing related information may have been evicted
/// since parsing, and the source code will then be parsed again.
/// However, we do not have an alternative unless we want to parse
/// everything ourselves.  But it would be useful to be able to give
/// barback a hint that this information should preferably be preserved.
String _transformSource(LibraryElement reflectableLibrary,
                        List<ReflectableClassData> reflectableClasses,
                        Map<LibraryElement, Asset> libraryToAssetMap,
                        Map<LibraryElement, Set<LibraryElement>> missingImports,
                        LibraryElement targetLibrary,
                        String source) {
  // Used to manage replacements of code snippets by other code snippets
  // in [source].
  SourceManager sourceManager = new SourceManager(source);

  // Used to accumulate generated classes, maps, etc.
  String generatedSource = "";

  // Transform selected existing elements in [targetLibrary].
  PrefixElement prefixElement = _transformSourceDirectives(reflectableLibrary,
                                                           targetLibrary,
                                                           sourceManager);
  _transformMetadataClasses(reflectableClasses,
                            targetLibrary,
                            sourceManager,
                            prefixElement);

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

  // If needed, add an import such that generated classes can see their
  // superclasses.  Note that we make no attempt at following the style guide,
  // e.g., by keeping the imports sorted.  Also add imports such that each
  // Reflectable metadata class can see all its Reflectable annotated classes
  // (such that the implementation of `reflect` etc. will work).
  String newImport = generatedSource.length == 0 ?
      "" : "\nimport 'package:reflectable/src/mirrors_unimpl.dart';";
  Set<LibraryElement> importsToAdd = missingImports[targetLibrary];
  if (importsToAdd != null) {
    String targetPath = libraryToAssetMap[targetLibrary].id.path;
    for (LibraryElement importToAdd in importsToAdd) {
      String pathToAdd = libraryToAssetMap[importToAdd].id.path;
      newImport += "\nimport '${_relativePath(pathToAdd, targetPath)}';";
    }
  }
  if (!newImport.isEmpty) {
    // Insert the import directive at the chosen location.
    int newImportIndex = _newImportIndex(targetLibrary);
    sourceManager.replace(newImportIndex, newImportIndex, newImport);
  }
  return generatedSource.length == 0 ? sourceManager.source :
      "${sourceManager.source}\n"
      "$generatedComment: Rest of file\n"
      "$generatedSource";
}

/// Wrapper of `AggregateTransform` of type `Transform`, allowing us to
/// get a `Resolver` for a given `AggregateTransform` with a given
/// selection of a primary entry point.
/// TODO(eernst): We will just use this temporarily; code_transformers
/// may be enhanced to support a variant of Resolvers.get that takes an
/// [AggregateTransform] and an [Asset] rather than a [Transform], in
/// which case we can drop this class and use that method.
class AggregateTransformWrapper implements Transform {
  final AggregateTransform _aggregateTransform;
  final Asset primaryInput;
  AggregateTransformWrapper(this._aggregateTransform, this.primaryInput);
  TransformLogger get logger => _aggregateTransform.logger;
  Future<Asset> getInput(AssetId id) => _aggregateTransform.getInput(id);
  Future<String> readInputAsString(AssetId id, {Encoding encoding}) =>
      _aggregateTransform.readInputAsString(id, encoding: encoding);
  Stream<List<int>> readInput(AssetId id) => _aggregateTransform.readInput(id);
  Future<bool> hasInput(AssetId id) => _aggregateTransform.hasInput(id);
  void addOutput(Asset output) => _aggregateTransform.addOutput(output);
  void consumePrimary() => _aggregateTransform.consumePrimary(primaryInput.id);
}

/// Determines whether or not the given [asset] is a `FileAsset`
/// (defined in package:analyzer/src/asset/internal_asset.dart).
///
/// TODO(eernst): This test does not use a maintainable or
/// well-documented approach, but there does not seem to be a
/// "nice" way to decide whether an Asset is a FileAsset, e.g.,
/// we do not want to import internal_asset.dart in order to
/// be able to perform an `is` test.
bool _isFileAsset(Asset asset) => "$asset".substring(0,5) == "File ";

/// Computes the absolute (full) path of the given [asset].
///
/// TODO(eernst): There is no well-documented way, if any at all,
/// to obtain the full path of a given asset (which would only make
/// sense for a FileAsset anyway), but it happens to be possible to
/// extract it from its `toString()`.
String _assetPath(Asset asset) {
  String assetString = asset.toString();
  return assetString.substring(0, assetString.length - 1).substring(6);
}

String _packagePrefixString =
    r'^[^' + (path.separator == '\\' ? r'\\' : '/') + r'|]*\|';
RegExp _packagePrefix = new RegExp(_packagePrefixString);

/// Returns the relative path embedded in the given [fullName], which is
/// expected to be obtained from `Element.fullName` or some other source
/// using the same format. This means that the package prefix (for
/// 'reflectable|lib/my_file.dart' it is 'reflectable|') is stripped off,
/// and the rest is returned unchanged. When [fullName] does not contain
/// such a prefix it is assumed to be a path and returned unchanged.
String _fullNameToRelativePath(String fullName) {
  if (fullName == null) return null;
  Match match = _packagePrefix.firstMatch(fullName);
  if (match == null) return fullName;
  return path.normalize(fullName.substring(match.end));
}

/// Returns the package name embedded in the given [fullName], which is
/// expected to be obtained from `Element.fullName` or some other source
/// using the same format. The package name is a prefix of [fullName] (for
/// 'reflectable|lib/my_file.dart' it is 'reflectable'). When [fullName]
/// does not contain such a prefix it is considered to be unknown and
/// `null` is returned.
String _fullNameToPackage(String fullName) {
  if (fullName == null) return null;
  Match match = _packagePrefix.firstMatch(fullName);
  if (match == null) return null;
  return fullName.substring(0, match.end - 1);
}

/// Returns the normalized, posix style version of the given [path], i.e.,
/// removes superfluous constructs (e.g., '/some/./path/../otherpath'
/// can be reduced to 'some/otherpath') and switches to '/' as the path
/// separator.
String _posixNormalizePath(String pathToNormalize) {
  path.Context context = new path.Context(style: path.Style.posix);
  return context.joinAll(path.split(pathToNormalize));
}

/// Performs the transformation which eliminates all imports of
/// `package:reflectable/reflectable.dart` and instead provides a set of
/// statically generated mirror classes.
Future apply(AggregateTransform aggregateTransform, List<String> entryPoints) {
  // The type argument in the return type is omitted because the
  // documentation on barback and on transformers do not specify it.
  Resolvers resolvers = new Resolvers(dartSdkDirectory);
  List<Asset> inputs;
  Map<Asset, String> inputToSourceMap = <Asset, String>{};

  return aggregateTransform.primaryInputs.toList().then((List<Asset> assets) {
    inputs = assets;
    return Future.wait(assets.map((Asset asset) {
      return asset.readAsString().then((String source) {
        assert(!inputToSourceMap.containsKey(asset));
        inputToSourceMap[asset] = source;
      });
    }));
  }).then((_) {
    // [inputs] has been filled in; check that it is not empty.
    if (inputs.isEmpty) {
      // It is a warning, not an error, to have nothing to transform.
      aggregateTransform.logger.warning("Warning: Nothing to transform");
      // Terminate with a non-failing status code to the OS.
      exit(0);
    }

    // Connect the entry points to the corresponding assets.
    Map<String, Asset> entryPointMap = <String, Asset>{};
    for (String entryPoint in entryPoints) {
      L: {
        for (Asset input in inputs) {
          if (input.id.path.endsWith(_posixNormalizePath(entryPoint))) {
            aggregateTransform.logger.info("Registering entry point: $input");
            entryPointMap[entryPoint] = input;
            break L;
          }
        }
        // Error: 'entry_points:' declared [entryPoint] to be one of our
        // inputs, but no entry exists for it in [inputs].
        aggregateTransform.logger.error(
            "Error: Missing entry point: $entryPoint");
      }
    }

    return Future.wait(entryPoints.map((String entryPoint) {
      Asset entryPointAsset = entryPointMap[entryPoint];
      String entryPointPackage = entryPointAsset.id.package;
      Transform transform =
          new AggregateTransformWrapper(aggregateTransform, entryPointAsset);

      return resolvers.get(transform).then((Resolver resolver) {
        LibraryElement reflectableLibrary =
            resolver.getLibraryByName("reflectable.reflectable");
        if (reflectableLibrary == null) {
          // Stop and do not consumePrimary, i.e., let the original source
          // pass through without changes.
          return new Future.value();
        }

        List<ReflectableClassData> reflectableClasses =
            _findReflectableClasses(reflectableLibrary, resolver);
        Map<LibraryElement, Set<LibraryElement>> missingImports =
            _findMissingImports(reflectableClasses);
        Map<LibraryElement, Asset> libraryToAssetMap =
            <LibraryElement, Asset>{};

        for (LibraryElement libraryElement in resolver.libraries) {
          Source source = libraryElement.definingCompilationUnit.source;
          if (source == null) continue;  // No source: cannot be transformed.
          String targetPath = _fullNameToRelativePath(source.fullName);
          if (targetPath == null) continue;  // No path: cannot be transformed.
          if (_fullNameToPackage(source.fullName) != entryPointPackage) {
            // TODO(eernst): Needs generalization if we start supporting
            // transformation of libraries in other packages.
            continue;  // Library in different package: cannot be transformed.
          }
          // Compute `libraryToAssetMap`.
          for (Asset input in inputs) {
            if (_isFileAsset(input)) {
              if (_assetPath(input).endsWith(_posixNormalizePath(targetPath))) {
                // NB: This test would yield an incorrect result in the
                // case where multiple paths in the package have a shared
                // suffix (e.g., we have both '/path/one/ending/like/this'
                // and '/path/two/ending/like/this', and we check for
                // 'ending/like/this'). However, this will not actually
                // happen because the suffix that we are searching for is
                // the full relative path from the package root directory,
                // not just an arbitrary suffix.
                libraryToAssetMap[libraryElement] = input;
              }
            }
          }
        }

        Set<Asset> alreadyTransformed = new Set<Asset>();

        for (LibraryElement targetLibrary in resolver.libraries) {
          Asset targetAsset = libraryToAssetMap[targetLibrary];
          if (targetAsset == null) continue;
          if (alreadyTransformed.contains(targetAsset)) {
            // It is not safe to transform a library that contains a Reflectable
            // metadata class relative to multiple entry points, because each
            // entry point defines a set of libraries which amounts to the
            // complete program, and different sets of libraries correspond to
            // potentially different sets of static mirror classes as well as
            // potentially different sets of added import directives. Hence, we
            // must reject the transformation in cases where there is such a
            // clash.
            //
            // TODO(eernst): It would actually be safe to allow for multiple
            // transformations of the same library done relative to different
            // entry points _if_ the result of those transformations were the
            // same (for instance, if both of them left that library unchanged)
            // but we do not currently detect this case. This means that we
            // might be able to allow for the transformation of more packages
            // than the ones that we accept now, that is, it is a safe future
            // enhancement to detect such a case and allow it.
            bool metadataClassIsInTarget(ReflectableClassData classData) =>
                classData.metadataClass.library == targetLibrary;
            if (reflectableClasses.any(metadataClassIsInTarget)) {
              aggregateTransform.logger.error(
                  "Error: Multiple entry points transform $targetAsset.");
            }
          } else {
            alreadyTransformed.add(targetAsset);
          }
          String source = inputToSourceMap[targetAsset];
          String transformedSource = _transformSource(reflectableLibrary,
                                                      reflectableClasses,
                                                      libraryToAssetMap,
                                                      missingImports,
                                                      targetLibrary,
                                                      source);
          // Transform user provided code.
          aggregateTransform.consumePrimary(targetAsset.id);
          transform.addOutput(new Asset.fromString(targetAsset.id,
                                                   transformedSource));
        }
      });
    }));
  });
}
