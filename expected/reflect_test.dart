// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect'.

library reflectable.test.to_be_transformed.reflect_test;

import 'reflectable_reflect_test.dart';
import 'package:unittest/unittest.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';


const myReflectable = const Reflectable(const <ReflectCapability>[]);

@myReflectable
class A {
  // Generated: _reflectable__Class__Identifier
  static const int _reflectable__Class__Identifier = 1000;
  // Generated: reflectable__Class__Identifier
  int get reflectable__Class__Identifier => _reflectable__Class__Identifier;

}

main() {
  test('reflect', () {
    InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(instanceMirror == null, isFalse);
  });
}


// Generated: Rest of file

class _A_ClassMirror extends ClassMirrorUnimpl {}
class _A_InstanceMirror extends InstanceMirrorUnimpl {}

