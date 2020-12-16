// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Uses 'reflect' across file boundaries.  Main file of program.

library test_reflectable.test.three_files_test;

import 'package:test/test.dart';
import 'three_files_dir/three_files_aux.dart';
import 'three_files_meta.dart';
import 'three_files_test.reflectable.dart';

@myReflectable
class A {}

void main() {
  initializeReflectable();

  test('reflect local', () {
    var instanceMirror = myReflectable.reflect(A());
    expect(instanceMirror == null, isFalse);
  });
  test('reflect imported', () {
    var instanceMirror = myReflectable.reflect(B());
    expect(instanceMirror == null, isFalse);
  });
}
