// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This is the main library in package reflectable.

// TODO(eernst) doc: Write "library dartdoc" for this library.

library reflectable.reflectable;

import 'capability.dart';
import 'mirrors.dart';
import 'src/reflectable_builder_based.dart' as implementation;
import 'src/reflectable_class_constants.dart' as reflectable_class_constants;

export 'capability.dart';
export 'mirrors.dart';

abstract class ReflectableInterface {
  /// Returns true if this reflector has capabilities for the given instance.
  bool canReflect(Object o);

  /// Returns a mirror of the given object [reflectee].
  ///
  /// Throws a [NoSuchCapabilityError] if the class of [o] has not been marked
  /// for reflection.
  InstanceMirror reflect(Object o);

  /// Returns true if this reflector has capabilities for the given Type.
  bool canReflectType(Type type);

  /// Returns a mirror of the given type [type].
  ///
  /// In the case where
  /// [type] is a parameterized type, i.e., a generic class which has
  /// been applied to a list of actual type arguments, the returned mirror
  /// will have no declared type variables, but it has a list of actual
  /// type arguments. If a mirror of the generic class as such is needed,
  /// it can be obtained from `originalDeclaration`. That mirror will
  /// have no actual type arguments, but it will have declared type
  /// variables. Other types than classes are not (yet) supported.
  TypeMirror reflectType(Type type);

  /// Returns a mirror of the given library [library].
  LibraryMirror findLibrary(String library);

  /// Returns a map of all libraries in the current isolate.
  Map<Uri, LibraryMirror> get libraries;

  /// Returns an [Iterable] of all the classes that can be reflected over in
  /// this [Reflectable].
  Iterable<ClassMirror> get annotatedClasses;
}

/// [Reflectable] is used as metadata, marking classes for reflection.
///
/// If a class has an instance of a subclass of this class in its
/// [metadata]<sup>1</sup> then it will be included in the root set of classes
/// with support for reflection based on this package.  Other classes
/// outside the root set may also be included, e.g., if it is specified
/// that all subtypes of a given class in the root set are included.
/// For classes and instances not included, all reflective operations
/// will throw an exception.  For included classes and instances,
/// invocations of the operations in mirrors.dart are supported if
/// the [ReflectCapability] values given as constructor arguments
/// include the capability to run those operations; the operations
/// will throw an exception if the relevant capability is not included.
///
/// Terminology: We use the term *reflector class* to denote a
/// direct subclass of [Reflectable] with a zero-argument `const`
/// constructor that is used as metadata on a class in the target
/// program in one of the two supported manners: as a `const`
/// constructor expression (`@MyReflectable()`), or as an identifier
/// (`@myReflectable`) which is a top-level `const` whose value is
/// an instance of the given reflector class
/// (`const myReflectable = const MyReflectable();`).  We use the
/// term *reflector-annotated class* to denote a class whose
/// metadata includes an instance of a reflector class.
///
/// Note that the role played by this class includes much of the role
/// played by a [MirrorSystem] with dart:mirrors.
///
/// -----
/// **Footnotes:**
/// 1. Currently, the only setup which is supported is when
/// the metadata object is an instance of a direct subclass of the
/// class [Reflectable], say `MyReflectable`, and that subclass defines
/// a `const` constructor taking zero arguments.  This ensures that
/// every subclass of Reflectable used as metadata is a singleton class,
/// which means that the behavior of the instance can be expressed by
/// generating code in the class.  Generalizations of this setup may
/// be supported in the future if compelling use cases come up.
abstract class Reflectable extends implementation.ReflectableImpl
    implements ReflectableInterface {
  // Intended to near-uniquely identify this class in target programs.
  static const thisClassName = reflectable_class_constants.name;
  static const thisClassId = reflectable_class_constants.id;

  /// Const constructor, to enable usage as metadata, allowing for varargs
  /// style invocation with up to ten arguments.
  const Reflectable(
      [ReflectCapability cap0,
      ReflectCapability cap1,
      ReflectCapability cap2,
      ReflectCapability cap3,
      ReflectCapability cap4,
      ReflectCapability cap5,
      ReflectCapability cap6,
      ReflectCapability cap7,
      ReflectCapability cap8,
      ReflectCapability cap9])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const Reflectable.fromList(List<ReflectCapability> capabilities)
      : super.fromList(capabilities);

  /// Returns the canonicalized instance of the given reflector [type].
  ///
  /// If [type] is not a subclass of [Reflectable], or if it is such a class
  /// but no entities are covered (that is, it is unused, so we don't have
  /// any reflection data for it) then [null] is returned.
  static Reflectable getInstance(Type type) {
    for (var reflector in implementation.reflectors) {
      if (reflector.runtimeType == type) return reflector;
    }
    return null;
  }
}

/// Used to describe the invocation when a no-such-method situation arises.
/// We need to use this variant of the standard `Invocation` class, because
/// we have no access to the [Symbol] for the `memberName`.
abstract class StringInvocation {
  String get memberName;
  List get positionalArguments;
  Map<Symbol, dynamic> get namedArguments;
  bool get isMethod;
  bool get isGetter;
  bool get isSetter;
  bool get isAccessor => isGetter || isSetter;
}
