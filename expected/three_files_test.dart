// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect' across file boundaries.  Main file of program.

library reflectable.test.to_be_transformed.three_files_test;

import 'package:reflectable/mirrors.dart';
import 'package:unittest/unittest.dart';
import 'three_files_aux.dart';
import 'three_files_meta.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

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

// Generated: Rest of file

class Static_A_ClassMirror extends ClassMirrorUnimpl {
}

class Static_A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  Static_A_InstanceMirror(this.reflectee);
}
