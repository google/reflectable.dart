// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.global_quantify_test;

@GlobalQuantifyCapability(
    r"^test_reflectable.test.global_quantify_test.(A|B)$", reflector)
@GlobalQuantifyMetaCapability(
    Mark, reflector)
import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";

class Reflector extends Reflectable {
  const Reflector() : super(const InstanceInvokeCapability("foo"));
}

const reflector = const Reflector();

class Mark {
  const Mark();
}

class A {
  foo() => 42;
}

class B {
  foo() => 43;
}

class C {
  foo() => 44;
}

@Mark()
class D {
  foo() => 45;
}

Matcher throwsNoSuchCapabilityError =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());

main() {
  test("GlobalQuantifyCapability", () {
    expect(reflector.reflectType(A), const isInstanceOf<ClassMirror>());
    expect(reflector.reflect(new A()).invoke("foo", []), 42);
    expect(reflector.reflectType(B), const isInstanceOf<ClassMirror>());
    expect(reflector.reflect(new B()).invoke("foo", []), 43);
    expect(() => reflector.reflectType(C), throwsNoSuchCapabilityError);
    expect(() => reflector.reflect(new C()), throwsNoSuchCapabilityError);
  });
  test("GlobalQuantifyMetaCapability", () {
    expect(reflector.reflectType(B), const isInstanceOf<ClassMirror>());
    expect(reflector.reflect(new D()).invoke("foo", []), 45);
  });
}
