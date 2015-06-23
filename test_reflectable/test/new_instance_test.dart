// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `invoke`.

library test_reflectable.test.new_instance_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(newInstanceCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class A {
  A() : f = 42;
  A.positional(int x) : f = x - 42;
  A.optional(int x, int y, [int z = 1, w])
      : f = x + y + z * 42 + (w == null ? 10 : w);
  A.argNamed(int x, int y, {int z: 42, int p})
      : f = x + y - z - (p == null ? 10 : p);
  int f = 0;
}

main() {
  ClassMirror classMirror = myReflectable.reflectType(A);
  test('newInstance unnamed constructor, no arguments', () {
    expect((classMirror.newInstance("", []) as A).f, 42);
  });
  test('newInstance named constructor, simple argument list, one argument', () {
    expect((classMirror.newInstance("positional", [84]) as A).f, 42);
  });
  test('newInstance optional arguments, all used', () {
    expect((classMirror.newInstance("optional", [1, 2, 3, 4]) as A).f, 133);
  });
  test('newInstance optional arguments, none used', () {
    expect((classMirror.newInstance("optional", [1, 2]) as A).f, 55);
  });
  test('newInstance optional arguments, some used', () {
    expect((classMirror.newInstance("optional", [1, 2, 3]) as A).f, 139);
  });
  test('newInstance named arguments, all used', () {
    expect((classMirror.newInstance("argNamed", [1, 2], {#z: 3, #p: 0}) as A).f,
        0);
  });
  test('newInstance named arguments, some used', () {
    expect((classMirror.newInstance("argNamed", [1, 2], {#z: 3}) as A).f, -10);
    expect((classMirror.newInstance("argNamed", [1, 2], {#p: 3}) as A).f, -42);
  });
  test('newInstance named arguments, unused', () {
    expect((classMirror.newInstance("argNamed", [1, 2]) as A).f, -49);
    expect((classMirror.newInstance("argNamed", [1, 2], {}) as A).f, -49);
  });
}
