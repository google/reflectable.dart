// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.no_such_capability_test;

import 'package:reflectable/reflectable.dart' as r;
import 'package:unittest/unittest.dart';
import 'no_such_capability_test.reflectable.dart';

class MyReflectable extends r.Reflectable {
  const MyReflectable()
      : super(const r.StaticInvokeCapability("nonExisting"),
            const r.InstanceInvokeCapability("nonExisting"));
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

Matcher throwsReflectableNoMethod =
    throwsA(const isInstanceOf<r.ReflectableNoSuchMethodError>());

main() {
  initializeReflectable();

  test('reflect', () {
    r.InstanceMirror instanceMirror = myReflectable.reflect(new A());
    expect(() => instanceMirror.invoke("foo", []),
        throwsA(const isInstanceOf<r.ReflectableNoSuchMethodError>()));
    r.ClassMirror classMirror = myReflectable.reflectType(A);
    expect(() => classMirror.invoke("foo", []),
        throwsA(const isInstanceOf<r.ReflectableNoSuchMethodError>()));
    // When we have the capability we get the NoSuchMethodError, not
    // NoSuchCapabilityError.
    expect(() => instanceMirror.invoke("nonExisting", []),
        throwsReflectableNoMethod);

    // When we have the capability we get the NoSuchMethodError, not
    // NoSuchCapabilityError.
    expect(
        () => classMirror.invoke("nonExisting", []), throwsReflectableNoMethod);
  });
}
