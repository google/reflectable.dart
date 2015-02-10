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

/// Performs the transformation which is the main purpose of this
/// package.
/// TODO(eernst): Will transform code; currently just scans
/// all libraries and in there all classes, selecting the classes that
/// have metadata which is a subtype of Reflectable, and writes the
/// names of the selected classes in files named *.clslist, with one
/// file <name>.clslist for each file <name>.dart in the input.
Future apply(Transform transform) {
  Asset input = transform.primaryInput;
  List<ClassElement> classes;
  Resolvers resolvers = new Resolvers(dartSdkDirectory);
  return resolvers.get(transform).then((resolver) {
    classes = reflectable_classes(resolver);
    return input.readAsString();
  }).then((source) {
    AssetId classListId = input.id.changeExtension(".clslist");
    transform.addOutput(new Asset.fromString(classListId, classes.join("\n")));
  });
}

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
ClassElement _findReflectableClassElement(Resolver resolver) {
  LibraryElement lib = resolver.getLibraryByName("reflectable.reflectable");
  if (lib == null) return null;
  List<CompilationUnitElement> units = lib.units;
  for (CompilationUnitElement unit in units) {
    List<ClassElement> types = unit.types;
    for (ClassElement type in types) {
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
      PropertyInducingElement pie = element.variable;
      // Surprisingly, we have to use the type VariableElementImpl
      // here.  This is because VariableElement does not declare
      // evaluationResult (presumably it is "secret").
      if (pie is VariableElementImpl && pie.isConst) {
        VariableElementImpl vei = pie as VariableElementImpl;
        EvaluationResultImpl result = vei.evaluationResult;
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

/// Returns a list of classes from the current isolate which are
/// annotated with metadata whose type is a subtype of [Reflectable].
List<ClassElement> reflectable_classes(Resolver resolver) {
  ClassElement focusClass = _findReflectableClassElement(resolver);
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
