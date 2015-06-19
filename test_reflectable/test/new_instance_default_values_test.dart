// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `invoke`.

library reflectable.test.to_be_transformed.new_instance_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(newInstanceCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class A {
  static const localConstant = 10;
  A.optional([int z = localConstant]) : f = z;
  int f = 0;
}

main() {
  ClassMirror classMirror = myReflectable.reflectType(A);
  test('newInstance named arguments default argument, local constant', () {
    expect((classMirror.newInstance("optional", [], {}) as A).f, 10);
  });
}
