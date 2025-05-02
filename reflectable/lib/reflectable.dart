// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

///
/// Basic, code generation based reflection in Dart,
/// with support for introspection and dynamic invocation.
///
/// *Introspection* is that subset of reflection by which a running
/// program can examine its own structure. For example, a function
/// that prints out the names of all the members of an arbitrary object.
///
/// *Dynamic invocation* refers the ability to evaluate code that has not
/// been literally specified at compile time, such as calling a method
/// whose name is provided as an argument (because it is looked up in a
/// database, or provided interactively by the user).
///
/// Reflectable uses capabilities to specify the level of support, as
/// specified
/// [here](https://github.com/google/reflectable.dart/blob/master/reflectable/doc/TheDesignOfReflectableCapabilities.md).
/// The rationale is that unlimited support for reflection tends to be too
/// expensive in terms of program size, but if only few features are needed
/// then a small set of capabilities it is likely to be much smaller.
///
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
  const Reflectable([
    super.cap0,
    super.cap1,
    super.cap2,
    super.cap3,
    super.cap4,
    super.cap5,
    super.cap6,
    super.cap7,
    super.cap8,
    super.cap9,
  ]);

  const Reflectable.fromList(super.capabilities) : super.fromList();

  /// Returns the canonicalized instance of the given reflector [type].
  ///
  /// If [type] is not a subclass of [Reflectable], or if it is such a class
  /// but no entities are covered (that is, it is unused, so we don't have
  /// any reflection data for it) then [null] is returned.
  static Reflectable? getInstance(Type type) {
    for (Reflectable reflector in implementation.reflectors) {
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
