// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// NB: if changing this library directive, change the literal
// string in getClassElement to maintain that they are equal.
library reflectable.reflectable;

import 'package:code_transformers/resolver.dart';
import 'package:analyzer/src/generated/element.dart';
import 'src/implementation.dart' as implementation;

import 'capability.dart';
export 'capability.dart';

import 'mirror.dart';
export 'mirror.dart';

/// Used as metadata, marking classes for use with reflectable.
class ReflectableX {
  // Intended to near-uniquely identify this class in target programs.
  static const thisClassName = "ReflectableX";  // Update if renaming class!
  static const thisClassId = "4c5bb5484ffbe3f266cafa28ebc80a0efa78957e";

  /// Specifies limits on the support for reflective operations on instances
  /// of classes having an instance of this Reflectable as metadata.
  final List<Capability> capabilities;

  /// Const constructor, to enable usage as metadata.
  const ReflectableX(this.capabilities);

  /// Returns a mirror of the given object [obj]
  InstanceMirror reflect(obj) => implementation.reflect(obj);

  /// Returns a mirror of the given class [typ].  Other types than classes
  /// are (not yet) supported.
  ClassMirror reflectClass(Type typ) => implementation.reflectClass(typ);

  /// Returns a mirror of the given library [lib].
  LibraryMirror findLibrary(Symbol lib) => implementation.findLibrary(lib);

  /// Returns a map of all libraries in the current isolate.
  Map<Uri, LibraryMirror> get libraries => implementation.libraries;

  /// Returns a library of this app that declares a 'main' method at top-level.
  LibraryMirror get mainLibrary => implementation.mainLibrary;

  /// Returns a list of classes which are (1) part of the current runtime
  /// environment, and (2) annotated with metadata of ThisType.
  static List<ClassElement> classes(Resolver resolver) =>
      implementation.classes(resolver);
}

/// Returns a Symbol representing the name of the setter corresponding
/// to the name [getter], which is assumed to be the name of a getter.
Symbol setterName(Symbol getter) => implementation.setterName(getter);

/// A mirror for the [Object] class.
final typeMirrorForObject = implementation.typeMirrorForObject;

/// Returns the name associated with the given [symbol].
String symbolToName(Symbol symbol) => implementation.symbolToName(symbol);

/// Returns the symbol associated with the given [name].
Symbol nameToSymbol(String name) => implementation.nameToSymbol(name);

