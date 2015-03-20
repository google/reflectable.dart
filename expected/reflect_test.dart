// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect'.

library reflectable.test.to_be_transformed.reflect_test;

import 'package:reflectable/static_reflectable.dart';
import 'package:unittest/unittest.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';


class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);

  // Generated: Rest of class
  InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == A) {
      return new _A_InstanceMirror(reflectee);
    }
    throw new UnimplementedError();
  }
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

main() {
  test('reflect', () {
    InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(instanceMirror == null, isFalse);
  });
}


// Generated: Rest of file


class _A_ClassMirror extends ClassMirrorUnimpl {
}

class _A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  _A_InstanceMirror(this.reflectee);
}

