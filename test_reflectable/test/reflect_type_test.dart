// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.reflect_type_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(typeCapability);
}

@MyReflectable()
class A {}

class B {}

main() {
  const myReflectable = const MyReflectable();
  test("reflectType", () {
    ClassMirror cm = myReflectable.reflectType(A);
    expect(cm, new isInstanceOf<ClassMirror>());
    expect(cm.simpleName, "A");
    expect(() => const MyReflectable().reflectType(B),
        throwsA(new isInstanceOf<NoSuchCapabilityError>()));
  });
  test("InstanceMirror.type", () {
    ClassMirror cm = const MyReflectable().reflectType(A);
    ClassMirror cm2 = myReflectable.reflect(new A()).type;
    expect(cm.qualifiedName, cm2.qualifiedName);
  });
}
