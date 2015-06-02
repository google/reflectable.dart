// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.to_be_transformed.no_such_capability_test;

import 'package:reflectable/reflectable.dart' as r;
import 'package:unittest/unittest.dart';

class MyReflectable extends r.Reflectable {
  const MyReflectable(): super(const <r.ReflectCapability>[]);
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

main() {
  test('reflect', () {
    r.InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(() => instanceMirror.invoke("foo", []),
           throwsA(const isInstanceOf<r.NoSuchInvokeCapabilityError>()));
  });
}
