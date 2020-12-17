// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses `invoker` on methods with various argument list shapes.

library test_reflectable.test.invoker_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'invoker_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class MyReflectable extends Reflectable {
  const MyReflectable() : super(invokingCapability, typeCapability);
}

const myReflectable = MyReflectable();

@myReflectable
class A {
  int f;
  A(this.f);
  int arg0() => 42 + f;
  int arg1(int x) => x - 42 + f;
  int arg1to3(int x, int y, [int z = 0, w]) => x + y + z * 42 + f;
  int argNamed(int x, int y, {int z = 42}) => x + y - z + f;
}

void main() {
  initializeReflectable();

  var instance1 = A(0);
  var instance2 = A(1);
  var classMirror = myReflectable.reflectType(A) as ClassMirror;
  test('invoker with no arguments', () {
    Function arg0Invoker = classMirror.invoker('arg0');
    expect(arg0Invoker(instance1)(), 42);
    expect(arg0Invoker(instance2)(), 43);
  });
  test('invoker with simple argument list, one argument', () {
    Function arg1Invoker = classMirror.invoker('arg1');
    expect(arg1Invoker(instance1)(84), 42);
    expect(arg1Invoker(instance2)(84), 43);
  });
  test('invoker with mandatory arguments, omitting optional ones', () {
    Function arg1to3Invoker = classMirror.invoker('arg1to3');
    expect(arg1to3Invoker(instance1)(40, 2), 42);
    expect(arg1to3Invoker(instance2)(40, 2), 43);
  });
  test('invoker with mandatory arguments, plus some optional ones', () {
    Function arg1to3Invoker = classMirror.invoker('arg1to3');
    expect(arg1to3Invoker(instance1)(1, -1, 1), 42);
    expect(arg1to3Invoker(instance2)(1, -1, 1), 43);
  });
  test('invoker with mandatory arguments, plus all optional ones', () {
    Function arg1to3Invoker = classMirror.invoker('arg1to3');
    expect(arg1to3Invoker(instance1)(21, 21, 0, 'Ignored'), 42);
    expect(arg1to3Invoker(instance2)(21, 21, 0, 'Ignored'), 43);
  });
  test('invoker with mandatory arguments, omitting named ones', () {
    Function argNamedInvoker = classMirror.invoker('argNamed');
    expect(argNamedInvoker(instance1)(55, 29), 42);
    expect(argNamedInvoker(instance2)(55, 29), 43);
  });
  test('invoker with mandatory arguments, plus named ones', () {
    Function argNamedInvoker = classMirror.invoker('argNamed');
    expect(argNamedInvoker(instance1)(21, 21, z: 0), 42);
    expect(argNamedInvoker(instance2)(21, 21, z: 0), 43);
  });
}
