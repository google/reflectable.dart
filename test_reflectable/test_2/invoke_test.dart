// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Uses `invoke`.

library test_reflectable.test.invoke_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'invoke_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(invokingCapability);
}

const myReflectable = MyReflectable();

@myReflectable
class A {
  int arg0() => 42;
  int arg1(int x) => x - 42;
  int arg1to3(int x, int y, [int z = 0, w]) => x + y + z * 42;
  int argNamed(int x, int y, {int z = 42}) => x + y - z;
  int operator +(x) => 42 + x;
  int operator [](x) => 42 + x;
  void operator []=(x, v) { f = x + v; }
  int operator -() => -f;
  int operator ~() => f + 2;

  int f = 0;

  static int noArguments() => 42;
  static int oneArgument(x) => x - 42;
  static int optionalArguments(x, y, [z = 0, w]) => x + y + z * 42;
  static int namedArguments(int x, int y, {int z = 42}) => x + y - z;
}

void main() {
  initializeReflectable();

  var instance = A();
  var instanceMirror = myReflectable.reflect(instance);
  test('invoke with no arguments', () {
    expect(instanceMirror.invoke('arg0', []), 42);
  });
  test('invoke with simple argument list, one argument', () {
    expect(instanceMirror.invoke('arg1', [84]), 42);
  });
  test('invoke with mandatory arguments, omitting optional ones', () {
    expect(instanceMirror.invoke('arg1to3', [40, 2]), 42);
  });
  test('invoke with mandatory arguments, plus some optional ones', () {
    expect(instanceMirror.invoke('arg1to3', [1, -1, 1]), 42);
  });
  test('invoke with mandatory arguments, plus all optional ones', () {
    expect(instanceMirror.invoke('arg1to3', [21, 21, 0, 'Ignored']), 42);
  });
  test('invoke with mandatory arguments, omitting named ones', () {
    expect(instanceMirror.invoke('argNamed', [55, 29]), 42);
  });
  test('invoke with mandatory arguments, plus named ones', () {
    expect(instanceMirror.invoke('argNamed', [21, 21], {#z: 0}), 42);
  });
  test('invoke operator +', () {
    expect(instanceMirror.invoke('+', [42]), 84);
  });
  test('invoke operator []', () {
    expect(instanceMirror.invoke('[]', [42]), 84);
  });
  test('invoke operator []=', () {
    instanceMirror.invoke('[]=', [1, 2]);
    expect(instance.f, 3);
  });
  test('invoke operator unary-', () {
    expect(instanceMirror.invoke('unary-', []), -3);
  });
  test('invoke operator ~', () {
    expect(instanceMirror.invoke('~', []), 5);
  });

  ClassMirror classMirror = myReflectable.reflectType(A);
  test('static invoke with no arguments', () {
    expect(classMirror.invoke('noArguments', []), 42);
  });
  test('static invoke with simple argument list, one argument', () {
    expect(classMirror.invoke('oneArgument', [84]), 42);
  });
  test('static invoke with mandatory arguments, omitting optional ones', () {
    expect(classMirror.invoke('optionalArguments', [40, 2]), 42);
  });
  test('static invoke with mandatory arguments, plus some optional ones', () {
    expect(classMirror.invoke('optionalArguments', [1, -1, 1]), 42);
  });
  test('static invoke with mandatory arguments, plus all optional ones', () {
    expect(classMirror.invoke('optionalArguments', [21, 21, 0, 'Ignored']), 42);
  });
  test('static invoke with mandatory arguments, omitting named ones', () {
    expect(classMirror.invoke('namedArguments', [55, 29]), 42);
  });
  test('static invoke with mandatory arguments, plus named ones', () {
    expect(classMirror.invoke('namedArguments', [21, 21], {#z: 0}), 42);
  });
}
