// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This is the main library in package reflectable.

// TODO(eernst): The implementation of class Reflectable below
// will be introduced gradually; missing parts are replaced
// by 'throw "Not yet implemented"'.
// TODO(eernst): Write "library dartdoc" for this library.

library reflectable.reflectable;

import 'capability.dart';
export 'capability.dart';

import 'mirrors.dart';
export 'mirrors.dart';

/// [Reflectable] is used as metadata, marking classes for reflection.
///
/// If a class has an instance of a subclass of this class in its
/// [metadata] then it will be included in the root set of classes
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
/// Note that the role played by this class includes much of the role
/// played by a [MirrorSystem] with dart:mirrors.
class Reflectable {
  // Intended to near-uniquely identify this class in target programs.
  static const thisClassName = "Reflectable";  // Update if renaming class!
  static const thisClassId = "4c5bb5484ffbe3f266cafa28ebc80a0efa78957e";

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

  /// Returns a mirror of the given object [obj]
  InstanceMirror reflect(Object reflectee) =>
      throw new UnimplementedError();

  /// Returns a mirror of the given class [type].  If [type] is a
  /// parameterized type, i.e., an application of a generic class
  /// to a list of actual type arguments, then the returned value
  /// mirrors the original class declaration, i.e., the generic
  /// class which has declared type variables, but has not received
  /// any type arguments.  Other types than classes are (not yet)
  /// supported.
  ClassMirror reflectClass(Type type) =>
      throw new UnimplementedError();

  /// Returns a mirror of the given type [type].  The returned value
  /// will also mirror the type if it is a parameterized type, i.e.,
  /// a generic class which has been applied to a list of actual
  /// type arguments.  In that case it has no declared type variables,
  /// but it has a list of actual type arguments.  Other types than
  /// classes are (not yet) supported.
  ClassMirror reflectType(Type type) =>
      throw new UnimplementedError();

  // MirrorSystem
  // -------------------------------------------------------
  // The following declarations are identical to declarations in
  // MirrorSystem from dart:mirrors for better portability. The
  // 'Currently skip' comments indicate omitted declarations.

  /// Returns a mirror of the given library [library].
  LibraryMirror findLibrary(Symbol library) => throw new UnimplementedError();

  /// Returns the name associated with the given [symbol].
  /// TODO(eernst): This name is problematic ('get' gives no
  /// information about what it does; consider nameFor, translateSymbol
  /// symbolToString, ..).
  String getName(Symbol symbol) => throw new UnimplementedError();

  /// Returns the symbol associated with the given [name].
  /// TODO(eernst): Currently [library] is ignored.
  Symbol getSymbol(String name, [LibraryMirror library]) =>
      throw new UnimplementedError();

  // Currently skip 'IsolateMirror get isolate'

  /// Returns a map of all libraries in the current isolate.
  Map<Uri, LibraryMirror> get libraries => throw new UnimplementedError();

  // Reflectable
  // -------------------------------------------------------
  // The following declarations are particular to this package
  // and may be changed without ill effects on portability.

  /// A mirror for the [Object] class.
  static final typeMirrorForObject = throw new UnimplementedError();

  /// Returns a Symbol representing the name of the setter corresponding
  /// to the name [getter], which is assumed to be the name of a getter.
  Symbol setterSymbol(Symbol getter) => throw new UnimplementedError();
}
