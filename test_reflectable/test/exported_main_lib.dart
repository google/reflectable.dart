// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.exported_main_lib;

import "package:unittest/unittest.dart";

import "package:reflectable/reflectable.dart";

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

@Reflector()
class C {}

main() {
  test("exported main", () {
    expect(const Reflector().canReflectType(C), true);
  });
}