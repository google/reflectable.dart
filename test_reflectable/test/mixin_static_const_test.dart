// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.mixin_static_const_test;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";

class Reflector extends Reflectable {
  const Reflector() : super(invokingCapability, declarationsCapability);
}
const reflector = const Reflector();

class A {}

@reflector
class M {
  static const String s = 'dart';
}

@reflector
class B extends A with M {}

void main() {
  test("Static const not present in mixin application", () {
    ClassMirror mMirror = reflector.reflectType(M);
    expect(mMirror.declarations['s'] != null, true);
    ClassMirror classMirror = reflector.reflectType(B);
    expect(classMirror.declarations['s'], null);
  });
}
