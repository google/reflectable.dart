// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

library test_reflectable.test.mixin_static_const_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'mixin_static_const_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(invokingCapability, declarationsCapability);
}

const reflector = Reflector();

class A {}

@reflector
class M {
  static const String s = 'dart';
}

@reflector
class B extends A with M {}

void main() {
  initializeReflectable();

  test('Static const not present in mixin application', () {
    ClassMirror mMirror = reflector.reflectType(M);
    expect(mMirror.declarations['s'] != null, true);
    ClassMirror classMirror = reflector.reflectType(B);
    expect(classMirror.declarations['s'], null);
  });
}
