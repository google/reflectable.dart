// This file has been transformed by reflectable.
// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and uses the
// class Reflectable as an annotation.

library reflectable.test.to_be_transformed.use_annotation;
// Import modified by reflectable:
import 'package:reflectable/static_reflectable.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);

  // Generated: Rest of class
  InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == A) {
      return new Static_A_InstanceMirror(reflectee);
    }
    throw new UnimplementedError("`reflect` on unexpected object '$reflectee'");
  }
}

@MyReflectable()
class A {}

// Generated: Rest of file

class Static_A_ClassMirror extends ClassMirrorUnimpl {
}

class Static_A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  Static_A_InstanceMirror(this.reflectee);
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
  }
}
