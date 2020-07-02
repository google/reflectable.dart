// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses default values.

library test_reflectable.test.default_values_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'default_values_lib.dart' as prefix;
import 'default_values_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(newInstanceCapability, typeCapability);
}

const myReflectable = MyReflectable();

const String globalConstant = '20';

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
      w = const [String, null, myReflectable, B(named: 24), <int, Type>{1: A}]])
      : f = x,
        g = y,
        h = z,
        i = w;
  int f = 0;
  bool g;
  String h;
  List i;
}

void main() {
  initializeReflectable();

  ClassMirror classMirror = myReflectable.reflectType(A);
  test('optional argument default value, imported local constant', () {
    expect((classMirror.newInstance('optional', [], {}) as A).f, 42);
  });
  test('optional argument default value, using identical', () {
    expect((classMirror.newInstance('optional', [], {}) as A).g, true);
  });
  test('optional argument default value, imported local constant', () {
    expect((classMirror.newInstance('optional', [], {}) as A).h, '2121');
  });
  test('optional argument default value, ', () {
    expect((classMirror.newInstance('optional', [], {}) as A).i, [
      String,
      null,
      myReflectable,
      const B(named: 24),
      const {1: A}
    ]);
  });
}
