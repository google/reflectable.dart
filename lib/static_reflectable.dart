// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This is intended to replace `reflectable.dart` in transformed code.  It is
// just an empty outline that provides enough context to keep the transformed
// libraries compilable, and in particular, it does not import dart:mirrors.

library reflectable.static_reflectable;

import 'capability.dart';
export 'capability.dart';

import 'mirrors.dart';
export 'mirrors.dart';

abstract class Reflectable {
  // Intended to near-uniquely identify this class in target programs.
  static const thisClassName = "Reflectable";  // Update if renaming class!
  static const thisClassId = "4c5bb5484ffbe3f266cafa28ebc80a0efa78957e";

  /// Specifies limits on the support for reflective operations on instances
  /// of classes having an instance of this Reflectable as metadata.
  final List<ReflectCapability> capabilities;

  /// Const constructor, to enable usage as metadata.
  const Reflectable(this.capabilities);

  InstanceMirror reflect(Object reflectee) => _unsupported();
  ClassMirror reflectClass(Type type) => _unsupported();
  ClassMirror reflectType(Type type) => _unsupported();
  LibraryMirror findLibrary(Symbol library) => _unsupported();
  String getName(Symbol symbol) => _unsupported();
  Symbol getSymbol(String name, [LibraryMirror library]) => _unsupported();
  Map<Uri, LibraryMirror> get libraries => _unsupported();
  static final typeMirrorForObject = _unsupported();
  Symbol setterSymbol(Symbol getter) => _unsupported();
  Iterable<ClassMirror> get annotatedClasses => _unsupported();
}

_unsupported() => throw new UnimplementedError();
