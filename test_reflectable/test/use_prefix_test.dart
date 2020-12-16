// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Imports the core file of this package and gives it a
// prefix, then proceeds to use the imported material.

library test_reflectable.test.use_prefix_test;

import 'package:reflectable/reflectable.dart' as r;
import 'package:test/test.dart';
import 'use_prefix_test.reflectable.dart';

class MyReflectable extends r.Reflectable {
  const MyReflectable();
}

const myReflectable = MyReflectable();

@myReflectable
class A {}

void main() {
  initializeReflectable();

  test('reflect', () {
    var instanceMirror = myReflectable.reflect(A());
    expect(instanceMirror == null, isFalse);
  });
}
