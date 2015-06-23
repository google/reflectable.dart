// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and gives it a
// prefix, then proceeds to use the imported material.

library test_reflectable.test.use_prefix_test;

import 'package:reflectable/reflectable.dart' as r;
import 'package:unittest/unittest.dart';

class MyReflectable extends r.Reflectable {
  const MyReflectable();
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

main() {
  test('reflect', () {
    r.InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(instanceMirror == null, isFalse);
  });
}

