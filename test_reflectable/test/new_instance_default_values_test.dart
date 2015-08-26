// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses default values on optional arguments.

library test_reflectable.test.new_instance_default_values_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(newInstanceCapability);
}

const myReflectable = const MyReflectable();

const String globalConstant = "20";

@myReflectable
class A {
  static const localConstant = 10;
  A.optional([int x = localConstant, String y = globalConstant]) : f = x, g = y;
  int f = 0;
  String g;
}

main() {
  ClassMirror classMirror = myReflectable.reflectType(A);
  test('newInstance named arguments default argument, local constant', () {
    expect((classMirror.newInstance("optional", [], {}) as A).f, 10);
  });
  test('newInstance named arguments default argument, global constant', () {
    expect((classMirror.newInstance("optional", [], {}) as A).g, "20");
  });
}
