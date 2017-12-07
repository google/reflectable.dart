// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.subtype_quantify_test;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";
import 'subtype_quantify_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(subtypeQuantifyCapability, instanceInvokeCapability,
            typeRelationsCapability);
}

const reflector = const Reflector();

@reflector
class A {
  foo() => 42;
}

class B extends A {
  foo() => 43;
}

class C implements A {
  foo() => 44;
}

class M {
  foo() => 45;
}

class D = C with M;

class E extends C with M {
  foo() => 46;
}

class F {}

Matcher throwsNoSuchCapabilityError =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());
Matcher isClassMirror = const isInstanceOf<ClassMirror>();

main() {
  initializeReflectable();

  test("Subtype quantification supports annotated class", () {
    expect(reflector.canReflectType(A), true);
    expect(reflector.canReflect(new A()), true);
    expect(reflector.reflectType(A), isClassMirror);
    expect(reflector.reflect(new A()).invoke("foo", []), 42);
  });

  test("Subtype quantification supports subclass", () {
    expect(reflector.canReflectType(B), true);
    expect(reflector.canReflect(new B()), true);
    expect(reflector.reflectType(B), isClassMirror);
    expect(reflector.reflect(new B()).invoke("foo", []), 43);
  });

  test("Subtype quantification supports subtype", () {
    expect(reflector.canReflectType(C), true);
    expect(reflector.canReflect(new C()), true);
    expect(reflector.reflectType(C), isClassMirror);
    expect(reflector.reflect(new C()).invoke("foo", []), 44);
  });

  test("Subtype quantification supports mixins", () {
    expect(reflector.canReflectType(D), true);
    expect(reflector.canReflect(new D()), true);
    expect(reflector.reflectType(D), isClassMirror);
    expect(reflector.reflect(new D()).invoke("foo", []), 45);
    expect(reflector.canReflectType(E), true);
    expect(reflector.canReflect(new E()), true);
    expect(reflector.reflectType(E), isClassMirror);
    expect(reflector.reflect(new E()).invoke("foo", []), 46);
  });

  test("Subtype quantification supports mixin applications", () {
    ClassMirror eMirror = reflector.reflectType(E);
    expect(eMirror.superclass, isClassMirror);
    // TODO(eernst) implement: Cover the different kinds of mixin applications.
  });

  test("Subtype quantification does not support unrelated class", () {
    expect(reflector.canReflectType(F), false);
    expect(reflector.canReflect(new F()), false);
    expect(() => reflector.reflectType(F), throwsNoSuchCapabilityError);
    expect(() => reflector.reflect(new F()), throwsNoSuchCapabilityError);
  });
}
