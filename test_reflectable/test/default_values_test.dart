// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses default values.

library test_reflectable.test.new_instance_default_values_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'default_values_lib.dart' as prefix;

class MyReflectable extends Reflectable {
  const MyReflectable() : super(newInstanceCapability);
}

const myReflectable = const MyReflectable();

const String globalConstant = "20";

class B {
  const B({int named});
}

@myReflectable
class A {
  static const localConstant = 10;
  static const localConstantImportedValue =
      2 * (localConstant + prefix.globalConstant.length);
  A.optional(
      [int x = prefix.A.localConstant + 31,
      bool y = identical(globalConstant, globalConstant),
      z = prefix.globalConstant + prefix.globalConstant,
      w = const [
    String,
    null,
    myReflectable,
    const B(named: 24),
    const <int, Type>{1: A}
  ]])
      : f = x,
        g = y,
        h = z,
        i = w;
  int f = 0;
  bool g;
  String h;
  List i;
}

main() {
  ClassMirror classMirror = myReflectable.reflectType(A);
  test('optional argument default value, imported local constant', () {
    expect((classMirror.newInstance("optional", [], {}) as A).f, 42);
  });
  test('optional argument default value, using identical', () {
    expect((classMirror.newInstance("optional", [], {}) as A).g, true);
  });
  test('optional argument default value, imported local constant', () {
    expect((classMirror.newInstance("optional", [], {}) as A).h, "2121");
  });
  test('optional argument default value, ', () {
    expect((classMirror.newInstance("optional", [], {}) as A).i, [
      String,
      null,
      myReflectable,
      const B(named: 24),
      const {1: A}
    ]);
  });
}
