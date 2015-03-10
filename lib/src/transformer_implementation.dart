// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'dart:async';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:path/path.dart' as path;
import 'package:reflectable/reflectable.dart';
import 'source_manager.dart';

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
/// reflectable.dart).  It uses [resolver] to retrieve the dart.core
/// library such that constant evaluation can take place.
///
/// Discussion of approach: Checking that we have found the correct
/// [Reflectable] class is crucial for correctness, and the "obvious"
/// approach of just looking up the library and then the class with the
/// right names using [resolver] is unsafe.  The problems are as
/// follows: (1) Library names are not guaranteed to be unique in a
/// given program, so we might look up a different library named
/// reflectable.reflectable, and a class Reflectable in there.  (2)
/// Library URIs (which must be unique in a given program) are not known
/// across all usage locations for reflectable.dart, so we cannot easily
/// predict all the possible URIs that could be used to import
/// reflectable.dart; and it would be awkward to require that all user
/// programs must use exactly one specific URI to import
/// reflectable.dart.  So we use [Reflectable.thisClassId] which is very
/// unlikely to occur with the same value elsewhere by accident.
bool _equalsClassReflectable(ClassElement type, Resolver resolver) {
  FieldElement idField = type.getField("thisClassId");
  if (idField == null || !idField.isStatic) return false;
  if (idField is ConstFieldElementImpl) {
    LibraryElement coreLibrary = resolver.getLibraryByName("dart.core");
    TypeProvider typeProvider = new TypeProviderImpl(coreLibrary);
    DartObject dartObjectThisClassId =
        new DartObjectImpl(typeProvider.stringType,
                           new StringState(Reflectable.thisClassId));
    EvaluationResultImpl idResult = idField.evaluationResult;
    if (idResult is ValidResult) {
      DartObject idValue = idResult.value;
      return idValue == dartObjectThisClassId;
    }
  }
  // Not a const field, cannot be the right class.
  return false;
}

/// Returns the ClassElement in the target program which corresponds to class
/// [Reflectable].  The [resolver] is used to get the library for this code in
/// the target program (if present), and the dart.core library for constant
/// evaluation.
ClassElement _findReflectableClassElement(LibraryElement reflectableLibrary,
                                          Resolver resolver) {
  for (CompilationUnitElement unit in reflectableLibrary.units) {
    for (ClassElement type in unit.types) {
      if (type.name == Reflectable.thisClassName &&
          _equalsClassReflectable(type, resolver)) {
        return type;
      }
    }
  }
  // Class [Reflectable] was not found in the target program.
  return null;
}

/// Returns true iff [possibleSubtype] is a subclass of [type], including the
/// reflexive and transitive cases.
bool _isSubclassOf(InterfaceType possibleSubtype, InterfaceType type) {
  if (possibleSubtype == type) return true;
  InterfaceType superclass = possibleSubtype.superclass;
  if (superclass == null) return false;
  return _isSubclassOf(superclass, type);
}

/// Returns true iff the [elementAnnotation] is an
/// instance of [focusClass] or a subclass thereof.
bool _isReflectableAnnotation(ElementAnnotation elementAnnotation,
                              ClassElement focusClass) {
  // TODO(eernst): The documentation in analyzer/lib/src/generated/element.dart
  // does not reveal whether elementAnnotation.element can ever be null.
  // Clarify that.
  if (elementAnnotation.element != null) {
    Element element = elementAnnotation.element;
    // TODO(eernst): Handle all possible shapes of const values; currently only
    // constructor expressions and simple identifiers are handled.
    if (element is ConstructorElement) {
      return _isSubclassOf(element.enclosingElement.type, focusClass.type);
    }
    if (element is PropertyAccessorElement) {
      PropertyInducingElement variable = element.variable;
      // Surprisingly, we have to use the type VariableElementImpl
      // here.  This is because VariableElement does not declare
      // evaluationResult (presumably it is "secret").
      if (variable is VariableElementImpl && variable.isConst) {
        VariableElementImpl variableImpl = variable as VariableElementImpl;
        EvaluationResultImpl result = variableImpl.evaluationResult;
        if (result is ValidResult) {
          return _isSubclassOf(result.value.type, focusClass.type);
        }
      }
    }
    // This annotation does not conform to the type Reflectable.
    return false;
  }
  // This annotation does not have an associated element, so there is nothing to
  // reflect upon.
  return false;
}

/// Returns true iff the given [library] imports [targetLibrary], which
/// must be non-null.
bool _doesImport(LibraryElement library, LibraryElement targetLibrary) {
  List<LibraryElement> importedLibraries = library.importedLibraries;
  return importedLibraries.contains(targetLibrary);
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
Map<int, ClassElement>
    _findReflectableClasses(LibraryElement reflectableLibrary,
                            Resolver resolver) {
  int reflectableClassId = 1000;  // First class id; grows sequentially.
  ClassElement focusClass =
      _findReflectableClassElement(reflectableLibrary, resolver);
  if (focusClass == null) return <int, ClassElement>{};
  Map<int, ClassElement> result = new Map<int, ClassElement>();
  for (LibraryElement library in resolver.libraries) {
    for (CompilationUnitElement unit in library.units) {
      for (ClassElement type in unit.types) {
        for (ElementAnnotation metadataItem in type.metadata) {
          if (_isReflectableAnnotation(metadataItem, focusClass)) {
            result.putIfAbsent(reflectableClassId, () => type);
            reflectableClassId++;
          }
        }
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

/// Perform `sourceManager.replace` such that the import/export of
/// reflectableLibrary specified by [element] is replaced by an
/// import/export of the generated library.
void _editUriReferencedElement(SourceManager sourceManager,
                               UriReferencedElement element,
                               String newUri) {
  int uriStart = element.uriOffset;
  if (uriStart == -1) {
    // Encountered a synthetic element.  We do not expect imports of
    // reflectable to be synthetic, so we make it an error.
    throw new UnimplementedError();
  }
  int uriEnd = element.uriEnd;
  // If we have `uriStart != -1 && uriEnd == -1` then there is a bug
  // in the implementation of [element].
  assert(uriEnd != -1);
  sourceManager.replace(uriStart, uriEnd, "'$newUri'");
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
                        Map<int, ClassElement> reflectableClasses,
                        LibraryElement targetLibrary,
                        String nameOfGeneratedFile,
                        String source) {
  // Used to manage replacements of code snippets by other code snippets
  // in [source].
  SourceManager sourceManager = new SourceManager(source);

  // Used to accumulate generated classes, maps, etc.
  String generatedSource = "";

  void editUriOfReflectable(UriReferencedElement element) {
    _editUriReferencedElement(sourceManager, element, nameOfGeneratedFile);
  }

  // Transform all imports and exports of reflectable.
  targetLibrary.imports
      .where((element) => element.importedLibrary == reflectableLibrary)
      .forEach(editUriOfReflectable);
  targetLibrary.exports
      .where((element) => element.exportedLibrary == reflectableLibrary)
      .forEach(editUriOfReflectable);

  // Insert an id into each class whose metadata includes an instance of
  // a subclass of Reflectable.
  for (int classId in reflectableClasses.keys) {
    ClassElement classElement = reflectableClasses[classId];
    String className = classElement.node.name.name.toString();

    // We only transform classes in the [targetLibrary].
    if (classElement.library != targetLibrary) continue;

    // Insert the identifier declaration into the body of the class.
    int classBodyOffset = classElement.node.leftBracket.end;
    sourceManager.replace(
        classBodyOffset,
        classBodyOffset,"""

  $generatedComment: _$classIdentifier
  static const int _$classIdentifier = $classId;
  $generatedComment: $classIdentifier
  int get $classIdentifier => _$classIdentifier;

""");

    // Generate a static mirror for this class
    generatedSource +=
        "class ${_staticClassMirrorName(className)} "
        "extends ClassMirrorUnimpl {}\n";

    // Generate a static mirror for instances of this class
    generatedSource +=
        "class ${_staticInstanceMirrorName(className)} "
        "extends InstanceMirrorUnimpl {}\n";
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

/// Generate the source code defining the static mirror classes that
/// are required for the given target program.
/// TODO(eernst): Not yet implemented, will just return a near-const string.
/// Will take more arguments in order to be able to do the job.
String _generateSource(Resolver resolver,
                       LibraryElement reflectableLibrary,
                       Map<int, ClassElement> reflectableClasses,
                       String nameOfGeneratedLibrary) {
  String template = """
// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This file is temporary: We will definitely need to change the import
// of 'package:reflectable/reflectable.dart' because that import will
// make the target program dependent on 'dart:mirrors', but the
// generated code and its placement in files is currently being modified
// extensively.  For now, this file will just include reflectable such
// that the compilability of code that depends on reflectable will
// remain unchanged.

library reflectable.test.to_be_transformed.$nameOfGeneratedLibrary;

import 'package:reflectable/reflectable.dart';
export 'package:reflectable/reflectable.dart';

""";
  return '$template// ${reflectableClasses.values.join('\n// ')}\n';
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
        Map<int, ClassElement> reflectableClasses =
            _findReflectableClasses(reflectableLibrary, resolver);
        String pathOfTransformedFile = input.id.path;
        String nameOfGeneratedFile =
            'reflectable_${escape(path.split(pathOfTransformedFile).last)}';
        String pathOfGeneratedFile =
            path.join(path.dirname(pathOfTransformedFile), nameOfGeneratedFile);
        String transformedSource = _transformSource(reflectableLibrary,
                                                    reflectableClasses,
                                                    targetLibrary,
                                                    nameOfGeneratedFile,
                                                    source);
        // Transform user provided code.
        transform.consumePrimary();
        transform.addOutput(new Asset.fromString(input.id, transformedSource));
        // Generate the file containing the static mirrors.
        AssetId generatedFileId =
            new AssetId(input.id.package, pathOfGeneratedFile);
        String nameOfGeneratedLibrary = 
            path.basenameWithoutExtension(nameOfGeneratedFile);
        String generatedSource = _generateSource(resolver,
                                                 reflectableLibrary,
                                                 reflectableClasses,
                                                 nameOfGeneratedLibrary);
        transform.addOutput(new Asset.fromString(generatedFileId,
                                                 generatedSource));
      } else {
        // We do not consumePrimary, i.e., let the original source pass
        // through without changes.
      }
    });
  });
}
