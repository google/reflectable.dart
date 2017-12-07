// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect' across file boundaries.  Main file of program.

library test_reflectable.test.three_files_test;

import 'package:reflectable/mirrors.dart';
import 'package:unittest/unittest.dart';
import 'three_files_dir/three_files_aux.dart';
import 'three_files_meta.dart';

@myReflectable
class A {}

main() {
  test('reflect local', () {
    InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(instanceMirror == null, isFalse);
  });
  test('reflect imported', () {
    InstanceMirror instanceMirror = myReflectable.reflect(new B());
    expect(instanceMirror == null, isFalse);
  });
}
