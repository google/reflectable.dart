// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and gives it a
// prefix, then proceeds to use the imported material.

library reflectable.test.to_be_transformed.use_prefix_test;
import 'package:reflectable/static_reflectable.dart' as r;
import 'package:unittest/unittest.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

class MyReflectable extends r.Reflectable {
  const MyReflectable(): super(const <r.ReflectCapability>[]);

  // Generated: Rest of class
  r.InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == A) {
      return new Static_A_InstanceMirror(reflectee);
    }
    throw new UnimplementedError();
  }
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

main() {
  test('reflect', () {
    r.InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(instanceMirror == null, isFalse);
  });
}


// Generated: Rest of file

class Static_A_ClassMirror extends ClassMirrorUnimpl {
}

class Static_A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  Static_A_InstanceMirror(this.reflectee);
}
