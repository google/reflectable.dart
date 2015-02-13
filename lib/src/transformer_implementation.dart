// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'dart:async';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import '../reflectable.dart';

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
  // This class not found in target program.
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

/// Returns a list of classes from the current isolate which are
/// annotated with metadata whose type is a subtype of [Reflectable].
List<ClassElement> _findReflectableClasses(LibraryElement reflectableLibrary,
                                           Resolver resolver) {
  ClassElement focusClass =
      _findReflectableClassElement(reflectableLibrary, resolver);
  if (focusClass == null) return [];
  List<ClassElement> result = new List<ClassElement>();
  for (LibraryElement library in resolver.libraries) {
    for (CompilationUnitElement unit in library.units) {
      for (ClassElement type in unit.types) {
        for (ElementAnnotation metadataItem in type.metadata) {
          if (_isReflectableAnnotation(metadataItem, focusClass)) {
            result.add(type);
          }
        }
      }
    }
  }
  return result;
}

String _transformSource(LibraryElement reflectableLibrary,
                        LibraryElement transformedLibrary,
                        String source) {
  // TODO(eernst): implement the transformation.
  String result = source;
  List<ImportElement> importElements = transformedLibrary.imports;

  bool doesImportReflectable(ImportElement element) {
    return element.importedLibrary == reflectableLibrary;
  }

  /// Compute the name of the file holding the generated library.
  /// TODO(eernst): When implementing this based on the name of the
  /// transformed library, remember that single quotes in the returned
  /// string will invalidate the code generated at the call site for
  /// this function.
  String nameOfGeneratedFile() {
    return 'reflectable_dummy.dart';
  }

  /// Replace import of reflectableLibrary by import of generated
  /// library by means of side-effects on [result].
  void editImport(ImportElement element) {
    int uriStart = element.uriOffset;
    if (uriStart == -1) {
      // TODO(eernst): Encountered a synthetic element.  We do not
      // expect imports of reflectable to be synthetic, so at this point
      // we make it an error.
      throw new UnimplementedError();
    }
    int uriEnd = element.uriEnd;
    // `uriStart != -1 && uriEnd == -1` would be a bug in `ImportElement`.
    assert(uriEnd != -1);
    String prefix = result.substring(0, uriStart);
    String postfix = result.substring(uriEnd);
    result = "$prefix'${nameOfGeneratedFile()}'$postfix";
  }

  // [editImport] modifies [result].
  importElements.where(doesImportReflectable).forEach(editImport);
  return result;
}

/// Performs the transformation which is the main purpose of this
/// package.
Future apply(Transform transform) {
  Asset input = transform.primaryInput;
  Resolvers resolvers = new Resolvers(dartSdkDirectory);
  return resolvers.get(transform).then((resolver) {
    LibraryElement transformedLibrary = resolver.getLibrary(input.id);
    LibraryElement reflectableLibrary =
        resolver.getLibraryByName("reflectable.reflectable");
    if (reflectableLibrary == null) {
      // Stop and do not consumePrimary, i.e., let the original source
      // pass through without changes.
      return new Future.value();
    }
    // TODO(eernst): Temporarily we use 'reflectable_dummy.dart' as
    // a stand-in for the generated library.  Do not translate it.
    // When it is not used any more, remove this comment + if.
    if (input.id.toString() ==
        "reflectable|test/to_be_transformed/reflectable_dummy.dart") {
      return new Future.value();
    }
    List<ClassElement> reflectableClasses =
        _findReflectableClasses(reflectableLibrary, resolver);
    return input.readAsString().then((source) {
      if (_doesImport(transformedLibrary, reflectableLibrary)) {
        String transformedSource = _transformSource(reflectableLibrary,
                                                    transformedLibrary,
                                                    source);
        transform.consumePrimary();
        transform.addOutput(new Asset.fromString(input.id, transformedSource));
      } else {
        // We do not consumePrimary, i.e., let the original source pass
        // through without changes.
      }
    });
  });
}
