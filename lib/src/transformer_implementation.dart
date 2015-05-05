// (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_implementation;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors' as dm;
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:barback/barback.dart';
import 'package:barback/src/transformer/transform.dart';
import 'package:code_transformers/resolver.dart';
import "reflectable_class_constants.dart" as reflectable_class_constants;
import 'source_manager.dart';
import 'transformer_errors.dart';
import '../capability.dart';

String getName(Symbol symbol) => dm.MirrorSystem.getName(symbol);

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
      return idResult.value.stringValue == reflectable_class_constants.id;
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
      if (type.name == reflectable_class_constants.name &&
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
  // Show the given errors to the user.  Note that we cannot stop the
  // transformation with an error-valued `exitCode`, because the
  // package-bots are unable to consider a failing transformation as an
  // expected outcome, they just turn red for the whole series of
  // tests because "we crashed before any of them were executed".
  //
  // TODO(eernst): We should test transformer error handling separately,
  // writing a test that runs `pub build` in a separate directory for
  // every single negative transformer test (such that the failing `pub
  // build` indicates the failure of transformation for exactly one test
  // case, and the `pub build` is one executed from our test program, not
  // the "global" pub build that the package-bots use for the set of
  // tests as a whole). When that is in place we will move all negative
  // transformer test cases from `to_be_transformed` into those new
  // directories, and we will then add code below to stop with an error
  // value in `exitCode` when `!errors.isEmpty`.
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
        .map((_Import _import) => _import.imported).toSet();
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
    throw new UnimplementedError("Encountered synthetic import of reflectable");
  }
  int uriEnd = uriReferencedElement.uriEnd;
  // If we have `uriStart != -1 && uriEnd == -1` then there is a bug
  // in the implementation of [uriReferencedElement].
  assert(uriEnd != -1);

  int elementOffset = uriReferencedElement.node.offset;
  String elementType;
  if (uriReferencedElement is ExportElement) {
    elementType = "Export";
  } else if (uriReferencedElement is ImportElement) {
    elementType = "Import";
  } else {
    throw new ArgumentError("Unexpected element $uriReferencedElement");
  }
  sourceManager.replace(elementOffset, elementOffset,
                        "// $elementType modified by reflectable:\n");
  sourceManager.replace(uriStart, uriEnd, "'$newUri'");
}

/// Returns the name of the given [classElement].  Note that we may have
/// multiple classes in a program with the same name in this sense,
/// because they can be in different libraries, and clashes may have
/// been avoided because the classes are private, because no single
/// library imports both, or because all importers of both use prefixes
/// on one or both of them to resolve the name clash.  Hence, name
/// clashes must be taken into account when using the return value.
String _classElementName(ClassElement classElement) =>
    classElement.node.name.name.toString();

// _staticClassNamePrefixMap, _antiNameClashSaltInitValue, _antiNameClashSalt:
// Auxiliary state used to generate names which are unlikely to clash with
// existing names and which cannot possibly clash with each other, because they
// contain the number [_antiNameClashSalt], which is updated each time it is
// used.
Map<ClassElement, String> _staticClassNamePrefixMap = <ClassElement, String>{};
int _antiNameClashSaltInitValue = 9238478278;
int _antiNameClashSalt = _antiNameClashSaltInitValue;

/// Reset [_antiNameClashSalt] to its initial value, such that
/// transformation of a given program can be deterministic even though
/// the order of transformation of a set of programs may differ from
/// between multiple runs of `pub build`.  Also reset caching data
/// structures depending on [_antiNameClashSalt]:
/// [_staticClassNamePrefixMap].
void resetAntiNameClashSalt() {
  _antiNameClashSalt = _antiNameClashSaltInitValue;
  _staticClassNamePrefixMap.clear();
}

/// Returns the shared prefix of names of generated entities
/// associated with [targetClass]. Uses [_antiNameClashSalt]
/// to prevent name clashes among generated names, and to make
/// name clashes with user-defined names unlikely.
String _staticNamePrefix(ClassElement targetClass) {
  String namePrefix = _staticClassNamePrefixMap[targetClass];
  if (namePrefix == null) {
    String nameOfTargetClass = _classElementName(targetClass);
    // TODO(eernst): Use the following version "with Salt" when we have
    // switched to the version of `checktransforms_test` that only checks
    // a handful of the very simplest transformations:
    //   namePrefix = "Static_${nameOfTargetClass}_${_antiNameClashSalt++}";
    // Currently we use the following version of this statement in order to
    // avoid the salt, because it breaks `checktransforms_test`:
    namePrefix = "Static_${nameOfTargetClass}";
    _staticClassNamePrefixMap[targetClass] = namePrefix;
  }
  return namePrefix;
}

/// Returns the name of the statically generated subclass of ClassMirror
/// corresponding to the given [targetClass]. Uses [_antiNameClashSalt]
/// to make name clashes unlikely.
String _staticClassMirrorName(ClassElement targetClass) =>
    "${_staticNamePrefix(targetClass)}_ClassMirror";

// Returns the name of the statically generated subclass of InstanceMirror
// corresponding to the given [targetClass]. Uses [_antiNameClashSalt]
/// to make name clashes unlikely.
String _staticInstanceMirrorName(ClassElement targetClass) =>
    "${_staticNamePrefix(targetClass)}_InstanceMirror";

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
                                         ErrorReporter errorReporter,
                                         LibraryElement targetLibrary,
                                         SourceManager sourceManager) {
  List<ImportElement> editedImports = <ImportElement>[];

  void replaceUriOfReflectable(UriReferencedElement element) {
    _replaceUriReferencedElement(
        sourceManager, element,
        "package:reflectable/static_reflectable.dart");
    if (element is ImportElement) editedImports.add(element);
  }

  // Exemption: We do not transform 'reflectable_implementation.dart'.
  if ("$targetLibrary" == "reflectable.src.reflectable_implementation") {
    return null;
  }

  // Transform all imports and exports of reflectable.
  targetLibrary.imports
      .where((element) => element.importedLibrary == reflectableLibrary)
      .forEach(replaceUriOfReflectable);
  targetLibrary.exports
      .where((element) => element.exportedLibrary == reflectableLibrary)
      .forEach(replaceUriOfReflectable);

  // If [reflectableLibrary] is never imported then it has no prefix.
  if (editedImports.isEmpty) return null;

  bool isOK(ImportElement importElement) {
    // We do not support a deferred load of Reflectable.
    if (importElement.isDeferred) {
      errorReporter.reportErrorForOffset(
          TransformationErrorCode.REFLECTABLE_LIBRARY_UNSUPPORTED_DEFERRED,
          importElement.node.offset,
          importElement.node.length,
          []);
      return false;
    }
    // We do not currently support `show` nor `hide` clauses,
    // otherwise this one is OK.
    if (importElement.combinators.isEmpty) return true;
    for (NamespaceCombinator combinator in importElement.combinators) {
      if (combinator is HideElementCombinator) {
        errorReporter.reportErrorForOffset(
          TransformationErrorCode.REFLECTABLE_LIBRARY_UNSUPPORTED_HIDE,
          importElement.node.offset,
          importElement.node.length,
          []);
      }
      assert(combinator is ShowElementCombinator);
      errorReporter.reportErrorForOffset(
          TransformationErrorCode.REFLECTABLE_LIBRARY_UNSUPPORTED_SHOW,
          importElement.node.offset,
          importElement.node.length,
          []);
    }
    return false;
  }

  // Check the imports, report problems with them if any, and try
  // to select the prefix of a good import to return.  If no good
  // imports are found we return `null`.
  PrefixElement goodPrefix = null;
  for (ImportElement importElement in editedImports) {
    if (isOK(importElement)) goodPrefix = importElement.prefix;
  }
  return goodPrefix;
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
                             ErrorReporter errorReporter,
                             SourceManager sourceManager,
                             PrefixElement prefixElement) {
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

  String reflectCaseOfClass(ClassElement classElement) =>
      "    if (reflectee.runtimeType == ${_classElementName(classElement)}) {\n"
      "      return new ${_staticInstanceMirrorName(classElement)}(reflectee);\n"
      "    }\n";

  String reflectCases = "";  // Accumulates the body of the `reflect` method.

  // Add each supported case to [reflectCases].
  annotatedClasses.forEach((ClassElement annotatedClass) {
    reflectCases += reflectCaseOfClass(annotatedClass);
  });

  // Add failure case to [reflectCases]: No matching classes, so the
  // user is asking for a kind of reflection that was not requested,
  // which is a runtime error.
  // TODO(eernst): Should use the Reflectable specific exception that Sigurd
  // introduced in a not-yet-landed CL.
  reflectCases += "    throw new "
      "UnimplementedError(\"`reflect` on unexpected object '\$reflectee'\");";

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
                               ErrorReporter errorReporter,
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

  void transformMetadataClass(ClassElement metadataClass) {
    List<ClassElement> annotatedClasses = reflectableClasses
        .where((classData) => classData.metadataClass == metadataClass)
        .map((classData) => classData.annotatedClass)
        .toList();
    _transformMetadataClass(
        metadataClass, annotatedClasses, errorReporter, sourceManager,
        prefixElement);
  }

  reflectableClasses.where(isInTargetLibrary).forEach(addMetadataClass);
  metadataClasses.forEach(transformMetadataClass);
}

/// Returns the source code for the reflection free subclass of
/// [ClassMirror] which is specialized for a `reflectedType` which
/// is the class modeled by [classElement].
String _staticClassMirrorCode(ClassElement classElement, capabilities) {
  return """
class ${_staticClassMirrorName(classElement)} extends ClassMirrorUnimpl {
}
""";
}

/// Perform some very simple steps that are consistent with Dart
/// semantics for the evaluation of constant expressions, such that
/// information about the value of a given `const` variable can be
/// obtained.  It is intended to help recognizing values of type
/// [ReflectCapability], so we only cover cases needed for that.
/// In particular, we cover lookup (e.g., with `const x = e` we can
/// see that the value of `x` is `e`, and that step may be repeated
/// if `e` is an [Identifier], or in general if it has a shape that
/// is covered); similarly, `C.y` is evaluated to `42` if `C` is a
/// class containing a declaration like `static const y = 42`. We do
/// not perform any kind of arithmetic simplification.
Expression _constEvaluate(Expression expression, ErrorReporter errorReporter) {
  // [Identifier] can be [PrefixedIdentifier] and [SimpleIdentifier]
  // (and [LibraryIdentifier], but that is only used in [PartOfDirective],
  // so even when we use a library prefix like in `myLibrary.MyClass` it
  // will be a [PrefixedIdentifier] containing two [SimpleIdentifier]s).
  if (expression is SimpleIdentifier) {
    if (expression.staticElement is PropertyAccessorElement) {
      PropertyAccessorElement propertyAccessor = expression.staticElement;
      PropertyInducingElement variable = propertyAccessor.variable;
      // We expect to be called only on `const` expressions.
      if (!variable.isConst) {
        errorReporter.reportErrorForNode(
            TransformationErrorCode.REFLECTABLE_SUPER_ARGUMENT_NON_CONST,
            expression,
            []);
      }
      VariableDeclaration variableDeclaration = variable.node;
      return _constEvaluate(variableDeclaration.initializer, errorReporter);
    }
  }
  if (expression is PrefixedIdentifier) {
    SimpleIdentifier simpleIdentifier = expression.identifier;
    if (simpleIdentifier.staticElement is PropertyAccessorElement) {
      PropertyAccessorElement propertyAccessor = simpleIdentifier.staticElement;
      PropertyInducingElement variable = propertyAccessor.variable;
      // We expect to be called only on `const` expressions.
      if (!variable.isConst) {
        errorReporter.reportErrorForNode(
            TransformationErrorCode.REFLECTABLE_SUPER_ARGUMENT_NON_CONST,
            expression,
            []);
      }
      VariableDeclaration variableDeclaration = variable.node;
      return _constEvaluate(variableDeclaration.initializer, errorReporter);
    }
  }
  // No evaluation steps succeeded, return [expression] unchanged.
  return expression;
}

/// Returns the [ReflectCapability] denoted by the given [initializer].
ReflectCapability _capabilityOfExpression(LibraryElement capabilityLibrary,
                                          ErrorReporter errorReporter,
                                          Expression expression) {
  Expression evaluatedExpression = _constEvaluate(expression, errorReporter);

  DartType dartType = evaluatedExpression.bestType;
  // The AST must have been resolved at this point.
  assert(dartType != null);

  // We insist that the type must be a class, and we insist that it must
  // be in the given `capabilityLibrary` (because we could never know
  // how to interpret the meaning of a user-written capability class, so
  // users cannot write their own capability classes).
  if (dartType is! ClassElement) {
    errorReporter.reportErrorForNode(
        TransformationErrorCode.REFLECTABLE_SUPER_ARGUMENT_NON_CLASS,
        expression, [dartType]);
  }
  ClassElement classElement = dartType.element;
  if (classElement.library != capabilityLibrary) {
    errorReporter.reportErrorForNode(
        TransformationErrorCode.REFLECTABLE_SUPER_ARGUMENT_WRONG_LIBRARY,
        expression, [classElement, capabilityLibrary]);
  }
  switch (classElement.name) {
    case "_InvokeMembersCapability":
      return invokeMembersCapability;
    case "InvokeMembersWithMetadataCapability":
      throw new UnimplementedError("$classElement not yet supported");
    case "InvokeInstanceMembersUpToSuperCapability":
      throw new UnimplementedError("$classElement not yet supported");
    case "_InvokeStaticMembersCapability":
      return invokeStaticMembersCapability;
    case "InvokeInstanceMemberCapability":
      throw new UnimplementedError("$classElement not yet supported");
    case "InvokeStaticMemberCapability":
      throw new UnimplementedError("$classElement not yet supported");
    default:
      throw new UnimplementedError("Unexpected capability $classElement");
  }
}

/// Returns the list of Capabilities given to the `super` constructor
/// invocation in the subclass of class [Reflectable] that is modeled
/// by [classElement].
List<ReflectCapability> _capabilitiesOf(LibraryElement capabilityLibrary,
                                        ErrorReporter errorReporter,
                                        ClassElement classElement) {
  List<ConstructorElement> constructors = classElement.constructors;
  // The `super()` arguments must be unique, so there must be 1 constructor.
  assert(constructors.length == 1);
  ConstructorElement constructorElement = constructors[0];
  // It can only be a const constructor, because this class has been
  // used for metadata; it is a bug in the transformer if not.
  // It must also be a default constructor.
  assert(constructorElement.isConst);
  // TODO(eernst): Ensure that some other location in this transformer
  // checks that the metadataClass constructor is indeed a default
  // constructor, such that this can be a mere assertion rather than
  // a user-oriented error report.
  assert(constructorElement.isDefaultConstructor);
  NodeList<ConstructorInitializer> initializers =
      constructorElement.node.initializers;
  // We insist that the initializer is exactly one element, a `super(<_>[])`.
  // TODO(eernst): Ensure that this has already been checked and met with a
  // user-oriented error report.
  assert(initializers.length == 1);
  SuperConstructorInvocation superInvocation = initializers[0];
  assert(superInvocation.constructorName == null);
  NodeList<Expression> arguments = superInvocation.argumentList.arguments;
  assert(arguments.length == 1);
  ListLiteral listLiteral = arguments[0];
  NodeList<Expression> expressions = listLiteral.elements;

  ReflectCapability capabilityOfExpression(Expression expression) =>
      _capabilityOfExpression(capabilityLibrary, errorReporter, expression);

  return expressions.map(capabilityOfExpression);
}

/// Returns `true` iff the given [capabilities] specify that `invoke`
/// must be supported on the given symbols.
bool _capableOfInstanceInvoke(List<ReflectCapability> capabilities,
                              [List<Symbol> symbols]) {
  if (capabilities.contains(invokeInstanceMembersCapability)) return true;
  if (capabilities.contains(invokeMembersCapability)) return true;

  bool handleMetadataCapability(ReflectCapability capability) {
    if (capability is! InvokeMembersWithMetadataCapability) return false;
    // TODO(eernst): Handle InvokeMembersWithMetadataCapability
    throw new UnimplementedError();
  }
  if (capabilities.any(handleMetadataCapability)) return true;

  bool handleMembersUpToSuperCapability(ReflectCapability capability) {
    if (capability is InvokeInstanceMembersUpToSuperCapability) {
      if (capability.superType == Object) return true;
      // TODO(eernst): Handle InvokeInstanceMembersUpToSuperCapability up
      // to something non-trivival.
      throw new UnimplementedError();
    } else {
      return false;
    }
  }
  if (capabilities.any(handleMembersUpToSuperCapability)) return true;

  if (symbols != null) {
    bool handleInstanceMemberCapabilities(Symbol symbol) {
      bool handleInstanceMemberCapability(ReflectCapability capability) {
        if (capability is InvokeInstanceMemberCapability) {
          return capability.name == symbol;
        } else {
          return false;
        }
      }
      return capabilities.any(handleInstanceMemberCapability);
    }
    if (symbols.every(handleInstanceMemberCapabilities)) return true;
  }

  return false;
}

/// Returns a list of those methods for which Reflectable support is
/// explicitly requested (using `InvokeInstanceMemberCapability`),
/// but which are not defined by the given class or any of its
/// superclasses.
List<Symbol> _unusedMethodsForCapabilities(ClassElement classElement,
    List<ReflectCapability> capabilities) {
  List<Symbol> result = <Symbol>[];
  capabilities.forEach((capability) {
    if (capability is InvokeInstanceMemberCapability) {
      String name = getName(capability.name);
      if (classElement.lookUpMethod(name, classElement.library) == null) {
        result.add(capability.name);
      }
    }
  });
  return result;
}

/// Returns a [String] containing generated code for the `invoke`
/// method of the static `InstanceMirror` class corresponding to
/// the given [classElement], bounded by the permissions given
/// in [capabilities].
///
/// TODO(eernst): Named parameters not yet supported.
String _staticInstanceMirrorInvokeCode(ClassElement classElement,
    List<ReflectCapability> capabilities) {
  String invokeCode = """
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
""";

  ClassElement currentClass = classElement;
  while (currentClass != null) {
    for (MethodElement methodElement in currentClass.methods) {
      MethodDeclaration methodDeclaration = methodElement.node;
      if (methodDeclaration.isOperator) {
        // TODO(eernst): We currently ignore method declarations when
        // they are operators. One issue is generation of code (which
        // does not work if we go ahead naively).
      } else {
        String methodName = methodDeclaration.name.name;
        Symbol methodSymbol = new Symbol(methodName);
        if (_capableOfInstanceInvoke(capabilities, <Symbol>[methodSymbol])) {
        invokeCode += """
    if (memberName == #$methodName) {
      return Function.apply(
          reflectee.$methodName, positionalArguments, namedArguments);
    }
""";
        }
      }
    }
    InterfaceType supertype = currentClass.supertype;
    currentClass = supertype == null ? null : supertype.element;
  }

  // Handle the cases where permission is given even though there is
  // no corresponding method. One case is where _all_ methods can be
  // invoked. Another case is when the user has specified a symbol
  // #foo and a Reflectable metadata value @myReflectable allowing
  // for invocation of `foo`, and then attached @myReflectable to a
  // class that does not define nor inherit any method `foo`.  In these
  // cases we invoke `noSuchMethod`.
  if (_capableOfInstanceInvoke(capabilities)) {
    // We have the capability to invoke _all_ methods, and since the
    // requested one does not fit, it should give rise to an invocation
    // of `noSuchMethod`.
    // TODO(eernst): Cf. the problem mentioned below in relation to the
    // invocation of `noSuchMethod`: It might be a good intermediate
    // solution to create our own implementation of Invocation holding
    // the information mentioned below; it would not be able to support
    // `delegate`, but for a broad range of purposes it might still be
    // useful.
    invokeCode += """
    // Want `reflectee.noSuchMethod(invocation);` where `invocation` holds
    // memberName, positionalArguments, and namedArguments.  But we cannot
    // create an instance of [Invocation] in user code.
    throw new UnimplementedError('Cannot call `noSuchMethod`');
""";
  } else {
    List<Symbol> unusedSymbols =
        _unusedMethodsForCapabilities(classElement, capabilities);
    if (!unusedSymbols.isEmpty) {
      // These symbols must give rise to an invocation of `noSuchMethod`.
      String unusedSymbolsListed = "<String>[${getName(unusedSymbols[0])}";
      for (Symbol unusedSymbol in unusedSymbols.skip(1)) {
        unusedSymbolsListed += ", ${getName(unusedSymbol)}";
      }
      unusedSymbolsListed += "]";
      invokeCode += """
    List<Symbol> noSuchMethodSymbols = $unusedSymbolsListed;
    if (noSuchMemberSymbols.contains(memberName)) {
      // Want `reflectee.noSuchMethod(invocation);` where `invocation` holds
      // memberName, positionalArguments, and namedArguments.  But we cannot
      // create an instance of [Invocation] in user code.
      throw new UnimplementedError('Cannot call `noSuchMethod`');
    }
""";
    }
  }

  invokeCode += """
  }
""";
  return invokeCode;
}

/// Returns the source code for the reflection free subclass of
/// [InstanceMirror] which is specialized for a `reflectee` which
/// is an instance of the class modeled by [classElement].  The
/// generated code will provide support as specified by
/// [capabilities].
String _staticInstanceMirrorCode(ClassElement classElement,
    List<ReflectCapability> capabilities) {
  // The `rest` of the code is the entire body of the static mirror class,
  // except for the declaration of `reflectee`, and a constructor.
  String rest = "";
  rest += _staticInstanceMirrorInvokeCode(classElement, capabilities);
  // TODO(eernst): add code for other mirror methods than `invoke`.
  return """
class ${_staticInstanceMirrorName(classElement)} extends InstanceMirrorUnimpl {
  final ${_classElementName(classElement)} reflectee;
  ${_staticInstanceMirrorName(classElement)}(this.reflectee);
$rest}
""";
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
                        LibraryElement capabilityLibrary,
                        List<ReflectableClassData> reflectableClasses,
                        Map<LibraryElement, Set<LibraryElement>> missingImports,
                        TransformLogger logger,
                        ErrorReporter errorReporter,
                        LibraryElement targetLibrary,
                        String source,
                        Resolver resolver) {
  // Used to manage replacements of code snippets by other code snippets
  // in [source].
  SourceManager sourceManager = new SourceManager(source);
  sourceManager.replace(0, 0,
                        "// This file has been transformed by reflectable.\n");

  // Used to accumulate generated classes, maps, etc.
  String generatedSource = "";

  // Transform selected existing elements in [targetLibrary].
  PrefixElement prefixElement = _transformSourceDirectives(
      reflectableLibrary, errorReporter, targetLibrary, sourceManager);
  _transformMetadataClasses(
      reflectableClasses, errorReporter, targetLibrary, sourceManager,
      prefixElement);

  for (ReflectableClassData classData in reflectableClasses) {
    ClassElement annotatedClass = classData.annotatedClass;
    if (annotatedClass.library != targetLibrary) continue;
    List<ReflectCapability> capabilities = _capabilitiesOf(
        capabilityLibrary, errorReporter, classData.metadataClass);

    // Generate static mirrors.
    generatedSource +=
        "\n" + _staticClassMirrorCode(annotatedClass, capabilities) +
        "\n" + _staticInstanceMirrorCode(annotatedClass, capabilities);
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
    AssetId targetId = resolver.getSourceAssetId(targetLibrary);
    for (LibraryElement importToAdd in importsToAdd) {
      Uri importUri = resolver.getImportUri(importToAdd, from: targetId);
      print(importUri);
      newImport += "\nimport '$importUri';";
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
  Future<String> readInputAsString(AssetId id, {Encoding encoding}) {
    return _aggregateTransform.readInputAsString(id, encoding: encoding);
  }
  Stream<List<int>> readInput(AssetId id) => _aggregateTransform.readInput(id);
  Future<bool> hasInput(AssetId id) => _aggregateTransform.hasInput(id);
  void addOutput(Asset output) => _aggregateTransform.addOutput(output);
  void consumePrimary() => _aggregateTransform.consumePrimary(primaryInput.id);
}

/// Performs the transformation which eliminates all imports of
/// `package:reflectable/reflectable.dart` and instead provides a set of
/// statically generated mirror classes.
Future apply(AggregateTransform aggregateTransform,
    List<String> entryPoints) async {
  // The type argument in the return type is omitted because the
  // documentation on barback and on transformers do not specify it.
  Resolvers resolvers = new Resolvers(dartSdkDirectory);

  List<Asset> assets = await aggregateTransform.primaryInputs.toList();

  if (assets.isEmpty) {
    // It is a warning, not an error, to have nothing to transform.
    aggregateTransform.logger.warning("Warning: Nothing to transform");
    // Terminate with a non-failing status code to the OS.
    exit(0);
  }

  for (String entryPoint in entryPoints) {
    // Find the asset corresponding to [entryPoint]
    Asset entryPointAsset =
        assets.firstWhere((Asset asset) => asset.id.path.endsWith(entryPoint),
            orElse: () => null);
    if (entryPointAsset == null) {
      aggregateTransform.logger.warning(
          "Error: Missing entry point: $entryPoint");
      continue;
    }
    Transform wrappedTransform =
        new AggregateTransformWrapper(aggregateTransform, entryPointAsset);
    resetAntiNameClashSalt();  // Each entry point has a closed world.

    Resolver resolver = await resolvers.get(wrappedTransform);
    LibraryElement reflectableLibrary =
        resolver.getLibraryByName("reflectable.reflectable");
    if (reflectableLibrary == null) {
      // Stop and do not consumePrimary, i.e., let the original source
      // pass through without changes.
      continue;
    }
    // If [reflectableLibrary] is present then [capabilityLibrary]
    // must also be present, because the former imports and exports
    // the latter.
    LibraryElement capabilityLibrary =
        resolver.getLibraryByName("reflectable.capability");
    List<ReflectableClassData> reflectableClasses =
        _findReflectableClasses(reflectableLibrary, resolver);
    Map<LibraryElement, Set<LibraryElement>> missingImports =
        _findMissingImports(reflectableClasses);

    // An entry `assetId -> entryPoint` in this map means that `entryPoint`
    // has been transforming `assetId`.
    Map<AssetId, String> transformedViaEntryPoint = new Map<AssetId, String>();

    Map<LibraryElement, String> libraryPaths =
        new Map<LibraryElement, String>();

    for (Asset asset in assets) {
      LibraryElement targetLibrary = resolver.getLibrary(asset.id);
      libraryPaths[targetLibrary] = asset.id.path;
    }

    for (Asset asset in assets) {
      LibraryElement targetLibrary = resolver.getLibrary(asset.id);
      if (targetLibrary == null) continue;

      bool metadataClassIsInTarget(ReflectableClassData classData) {
        return classData.metadataClass.library == targetLibrary;
      }

      if (reflectableClasses.any(metadataClassIsInTarget)) {
        if (transformedViaEntryPoint.containsKey(asset.id)) {
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
          String previousEntryPoint = transformedViaEntryPoint[asset.id];

          aggregateTransform.logger.error(
              "Error: $asset is transformed twice, "
              " both via $entryPoint and $previousEntryPoint.");
          continue;
        }
        transformedViaEntryPoint[asset.id] = entryPoint;
      }
      String source = await asset.readAsString();
      RecordingErrorListener errorListener = new RecordingErrorListener();
      ErrorReporter errorReporter =
          new ErrorReporter(errorListener, targetLibrary.source);
      String transformedSource = _transformSource(
          reflectableLibrary, capabilityLibrary, reflectableClasses,
          missingImports, aggregateTransform.logger,
          errorReporter, targetLibrary, source, resolver);
      // Transform user provided code.
      aggregateTransform.consumePrimary(asset.id);
      wrappedTransform.addOutput(
          new Asset.fromString(asset.id, transformedSource));
    }
    resolver.release();
  }
}
