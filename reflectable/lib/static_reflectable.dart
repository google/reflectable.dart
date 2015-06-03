// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This is intended to replace `reflectable.dart` in transformed code.  It is
// just an empty outline that provides enough context to keep the transformed
// libraries compilable, and in particular, it does not import dart:mirrors.

library reflectable.static_reflectable;

import 'capability.dart';
import 'mirrors.dart';
import 'src/reflectable_base.dart';
import 'src/reflectable_class_constants.dart' as reflectable_class_constants;

export 'capability.dart';
export 'mirrors.dart';

abstract class Reflectable extends ReflectableBase {
  // Intended to near-uniquely identify this class in target programs.
  static const thisClassName = reflectable_class_constants.name;
  static const thisClassId = reflectable_class_constants.id;

  /// Const constructor, to enable usage as metadata, allowing for varargs
  /// style invocation with up to ten arguments.
  const Reflectable([ReflectCapability cap0 = null,
      ReflectCapability cap1 = null, ReflectCapability cap2 = null,
      ReflectCapability cap3 = null, ReflectCapability cap4 = null,
      ReflectCapability cap5 = null, ReflectCapability cap6 = null,
      ReflectCapability cap7 = null, ReflectCapability cap8 = null,
      ReflectCapability cap9 = null])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const Reflectable.fromList(List<ReflectCapability> capabilities)
      : super.fromList(capabilities);

  InstanceMirror reflect(Object reflectee) => _unsupported();
  ClassMirror reflectClass(Type type) => _unsupported();
  ClassMirror reflectType(Type type) => _unsupported();
  LibraryMirror findLibrary(String library) => _unsupported();
  Map<Uri, LibraryMirror> get libraries => _unsupported();
  static final typeMirrorForObject = _unsupported();
  Iterable<ClassMirror> get annotatedClasses => _unsupported();
}

_unsupported() => throw new UnimplementedError();
