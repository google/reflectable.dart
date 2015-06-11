// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect', with a constraint to invocation based on
// 'InvokeInstanceMemberCapability'.

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(const InstanceInvokeCapability("x"));
}
const myReflectable = const MyReflectable();

@myReflectable
class Foo {
  x() => 42;
  y(int n) => "Hello";
}

main() {
  test("Invoking x", () {
    expect(myReflectable.reflect(new Foo()).invoke("x", []), 42);
  });
}
