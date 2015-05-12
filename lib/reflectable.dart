// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This is the main library in package reflectable.

// TODO(eernst): The implementation of class Reflectable below
// will be introduced gradually; missing parts are replaced
// by _unsupported(), which will throw an `UnimplementedError`.
// TODO(eernst): Write "library dartdoc" for this library.

library reflectable.reflectable;

import 'src/reflectable_implementation.dart' as implementation;
import 'src/reflectable_class_constants.dart' as reflectable_class_constants;

import 'capability.dart';
export 'capability.dart';

import 'mirrors.dart';
export 'mirrors.dart';

/// [Reflectable] is used as metadata, marking classes for reflection.
///
/// If a class has an instance of a subclass of this class in its
/// [metadata]<sup>1</sup> then it will be included in the root set of classes
/// with support for reflection based on this package.  Other classes
/// outside the root set may also be included, e.g., if it is specified
/// that all subclasses of a given class in the root set are included.
/// For classes and instances not included, all reflective operations
/// will throw an exception.  For included classes and instances,
/// invocations of the operations in mirrors.dart are supported if
/// those operations and their arguments conform to the constraints
/// expressed using the [ReflectCapability] which is given as a
/// constructor argument, and the operations will throw an exception if
/// they do not conform to said constraints.
///
/// Terminology: We use the term *Reflectable metadata class* to
/// denote a direct subclass of [Reflectable] with a zero-argument
/// `const` constructor that is used as metadata on a class in the
/// target program in one of the two supported manners: as a `const`
/// constructor expression (`@MyReflectable()`), or as an identifier
/// (`@myReflectable`) which is a top-level `const` whose value is
/// an instance of the given Reflectable metadata class
/// (`const myReflectable = const MyReflectable();`).  We use the
/// term *Reflectable annotated class* to denote a class whose
/// metadata includes an instance of a Reflectable metadata class.
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
class Reflectable {
  // Intended to near-uniquely identify this class in target programs.
  static const thisClassName = reflectable_class_constants.name;
  static const thisClassId = reflectable_class_constants.id;

  /// Specifies limits on the support for reflective operations on instances
  /// of classes having an instance of this Reflectable as metadata.
  final List<ReflectCapability> capabilities;

  /// Const constructor, to enable usage as metadata.
  const Reflectable(this.capabilities);

  // dart:mirrors
  // -------------------------------------------------------
  // The following declarations are identical to top level
  // declarations in dart:mirrors for better portability. The
  // 'Currently skip' comments indicate omitted declarations.

  // Currently skip 'MirrorSystem currentMirrorSystem'

  /// Returns a mirror of the given object [reflectee]
  InstanceMirror reflect(Object reflectee) =>
      implementation.reflect(reflectee, this);

  /// Returns a mirror of the given class [type].  If [type] is a
  /// parameterized type, i.e., an application of a generic class
  /// to a list of actual type arguments, then the returned value
  /// mirrors the original class declaration, i.e., the generic
  /// class which has declared type variables, but has not received
  /// any type arguments.  Other types than classes are (not yet)
  /// supported.
  ClassMirror reflectClass(Type type) =>
      implementation.reflectClass(type, this);

  /// Returns a mirror of the given type [type].  The returned value
  /// will also mirror the type if it is a parameterized type, i.e.,
  /// a generic class which has been applied to a list of actual
  /// type arguments.  In that case it has no declared type variables,
  /// but it has a list of actual type arguments.  Other types than
  /// classes are (not yet) supported.
  ClassMirror reflectType(Type type) =>
      _unsupported();

  // MirrorSystem
  // -------------------------------------------------------
  // The following declarations are identical to declarations in
  // MirrorSystem from dart:mirrors for better portability. The
  // 'Currently skip' comments indicate omitted declarations.

  /// Returns a mirror of the given library [library].
  LibraryMirror findLibrary(Symbol library) {
    return implementation.findLibrary(library, this);
  }

  /// Returns the name associated with the given [symbol].
  /// TODO(eernst): This name is problematic ('get' gives no
  /// information about what it does; consider nameFor, translateSymbol
  /// symbolToString, ..).
  String getName(Symbol symbol) => _unsupported();

  /// Returns the symbol associated with the given [name].
  /// TODO(eernst): Currently [library] is ignored.
  Symbol getSymbol(String name, [LibraryMirror library]) =>
      _unsupported();

  // Currently skip 'IsolateMirror get isolate'

  /// Returns a map of all libraries in the current isolate.
  Map<Uri, LibraryMirror> get libraries => implementation.libraries(this);

  // Reflectable
  // -------------------------------------------------------
  // The following declarations are particular to this package
  // and may be changed without ill effects on portability.

  /// A mirror for the [Object] class.
  static final typeMirrorForObject = _unsupported();

  /// Returns a Symbol representing the name of the setter corresponding
  /// to the name [getter], which is assumed to be the name of a getter.
  Symbol setterSymbol(Symbol getter) => _unsupported();

  /// Returns an [Iterable] of all the classes that can be reflected over in
  /// this [Reflectable].
  Iterable<ClassMirror> get annotatedClasses {
    return implementation.annotatedClasses(this);
  }
}

_unsupported() => throw new UnimplementedError();
