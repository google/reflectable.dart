// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `invoke`.

library reflectable.test.to_be_transformed.invoke_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(invokingCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class A {
  int arg0() => 42;
  int arg1(int x) => x - 42;
  int arg1to3(int x, int y, [int z = 0, w]) => x + y + z * 42;
  int argNamed(int x, int y, {int z: 42}) => x + y - z;
}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
  test('invoke with no arguments', () {
    expect(instanceMirror.invoke("arg0", []), 42);
  });
  test('invoke with simple argument list, one argument', () {
    expect(instanceMirror.invoke("arg1", [84]), 42);
  });
  test('invoke with mandatory arguments, omitting optional ones', () {
    expect(instanceMirror.invoke("arg1to3", [40, 2]), 42);
  });
  test('invoke with mandatory arguments, plus some optional ones', () {
    expect(instanceMirror.invoke("arg1to3", [1, -1, 1]), 42);
  });
  test('invoke with mandatory arguments, plus all optional ones', () {
    expect(instanceMirror.invoke("arg1to3", [21, 21, 0, "Ignored"]), 42);
  });
  test('invoke with mandatory arguments, omitting named ones', () {
    expect(instanceMirror.invoke("argNamed", [55, 29]), 42);
  });
  test('invoke with mandatory arguments, plus named ones', () {
    expect(instanceMirror.invoke("argNamed", [21, 21], {#z: 0}), 42);
  });
}
