// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

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
    var mMirror = reflector.reflectType(M) as ClassMirror;
    expect(mMirror.declarations['s'] != null, true);
    var classMirror = reflector.reflectType(B) as ClassMirror;
    expect(classMirror.declarations['s'], null);
  });
}
