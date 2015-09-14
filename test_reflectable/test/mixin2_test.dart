// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// Regression test.

library test_reflectable.test.mixin2_test;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";

class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, declarationsCapability, libraryCapability,
            typeCapability);
}

class M1 {}

@Reflector()
class M2 {}

class M3 {}

class A {}

@Reflector()
class B extends A with M1, M2, M3 {}

main() {
  test("", () {
    expect(
        const Reflector().reflectType(B), const isInstanceOf<ClassMirror>());

  });
}
