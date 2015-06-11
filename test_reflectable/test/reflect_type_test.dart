// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.to_be_transformed.reflect_type_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super();
}

@MyReflectable()
class A {}

class B {}

main() {
  test("reflectType", () {
    ClassMirror cm = const MyReflectable().reflectType(A);
    expect(cm, new isInstanceOf<ClassMirror>());
    expect(cm.simpleName, "A");
    expect(() => const MyReflectable().reflectType(B),
        throwsA(new isInstanceOf<NoSuchCapabilityError>()));
  });
}
