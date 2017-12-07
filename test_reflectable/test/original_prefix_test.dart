// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses a declaration from the original main file (this one)
// in an expression that will be copied in generated code.

library test_reflectable.test.original_prefix_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'original_prefix_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(newInstanceCapability, instanceInvokeCapability);
}

const myReflectable = const MyReflectable();

const int defaultX = 0x2A;
const int _defaultY = defaultX;

@myReflectable
class C {
  final String s;
  C([int x = defaultX, int y = _defaultY]) : s =
    "${x.toString().length+2}${y ~/ 15}";
}

main() {
  initializeReflectable();

  test("Original prefix", () {
    ClassMirror classMirror = myReflectable.reflectType(C);
    C c = classMirror.newInstance("", []);
    expect(c.s, "42");
  });
}
