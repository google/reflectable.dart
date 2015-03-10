// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect'.

library reflectable.test.to_be_transformed.reflect_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

const myReflectable = const Reflectable(const <ReflectCapability>[]);

@myReflectable
class A {}

main() {
  test('reflect', () {
    InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(instanceMirror == null, isFalse);
  });
}
