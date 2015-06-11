// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable_test.declarations_test;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";

class Reflector extends Reflectable {
  const Reflector() : super(instanceInvokeCapability);
}

@Reflector()
class A {
  foo() {}
}

@Reflector()
class B extends A {
  bar() {}
}

main() {
  const reflector = const Reflector();
  test("Test declarations", () {
    // TODO(sigurdm): Adapt this test when we support constructors, fields,
    // getters and setters in declarations.
    expect(reflector.reflectType(A).declarations.values
        .where((DeclarationMirror x) => x is MethodMirror && x.isRegularMethod)
        .map((x) => x.simpleName), ["foo"]);
    expect(reflector.reflectType(B).declarations.values
        .where((DeclarationMirror x) => x is MethodMirror && x.isRegularMethod)
        .map((x) => x.simpleName), ["bar"]);
  });
}
