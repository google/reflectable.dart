// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.mixin_test;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";

class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, declarationsCapability, libraryCapability);
}

// Note the class `A` is not annotated by this.
class Reflector2 extends Reflectable {
  const Reflector2() : super(invokingCapability, libraryCapability);
}

class ReflectorUpwardsClosed extends Reflectable {
  const ReflectorUpwardsClosed()
      : super(invokingCapability, typeRelationsCapability,
            declarationsCapability, libraryCapability);
}

@Reflector()
@Reflector2()
class M1 {
  foo() {}
  var field;
  static staticFoo(x) {}
}

@Reflector()
@Reflector2()
class M2 {}

@Reflector()
@Reflector2()
class M3 {}

@Reflector()
class A {
  foo() {}
  var field;
  static staticFoo(x) {}
  static staticBar() {}
}

@Reflector()
@Reflector2()
class B extends A with M1 {}

@Reflector()
@Reflector2()
@ReflectorUpwardsClosed()
class C extends B with M2, M3 {}

testReflector(Reflectable reflector, String desc) {
  test("Mixins, $desc", () {
    ClassMirror aMirror = reflector.reflectType(A);
    ClassMirror bMirror = reflector.reflectType(B);
    ClassMirror cMirror = reflector.reflectType(C);
    ClassMirror m1Mirror = reflector.reflectType(M1);
    ClassMirror m2Mirror = reflector.reflectType(M2);
    ClassMirror m3Mirror = reflector.reflectType(M3);
    expect(aMirror.mixin, aMirror);
    expect(bMirror.mixin, bMirror);
    expect(cMirror.mixin, cMirror);
    expect(m1Mirror.mixin, m1Mirror);
    expect(m2Mirror.mixin, m2Mirror);
    expect(m3Mirror.mixin, m3Mirror);
    expect(bMirror.superclass.mixin, m1Mirror);
    expect(cMirror.superclass.superclass.mixin, m2Mirror);
    expect(cMirror.superclass.mixin, m3Mirror);
    expect(cMirror.superclass.superclass.superclass, bMirror);
    expect(
        bMirror.superclass.simpleName,
        "test_reflectable.test.mixin_test.A with "
        "test_reflectable.test.mixin_test.M1");
    expect(bMirror.superclass.declarations["foo"].owner, m1Mirror);
    expect(bMirror.superclass.declarations["field"].owner, m1Mirror);
    expect(bMirror.superclass.declarations["staticBar"], null);
    expect(bMirror.superclass.hasReflectedType, true);
    expect(bMirror.superclass.reflectedType, const isInstanceOf<Type>());
    expect(bMirror.superclass.superclass.reflectedType,
        const isInstanceOf<Type>());
  });
}

Matcher throwsANoSuchCapabilityException =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());

main() {
  testReflector(const Reflector(), "Each is annotated");
  testReflector(const ReflectorUpwardsClosed(), "Upwards closed");
  test("Mixin, Superclass not supported", () {
    var reflector2 = const Reflector2();
    ClassMirror bMirror = reflector2.reflectType(B);
    ClassMirror cMirror = reflector2.reflectType(C);
    ClassMirror m1Mirror = reflector2.reflectType(M1);
    ClassMirror m2Mirror = reflector2.reflectType(M2);
    ClassMirror m3Mirror = reflector2.reflectType(M3);
    expect(bMirror.mixin, bMirror);
    expect(cMirror.mixin, cMirror);
    expect(m1Mirror.mixin, m1Mirror);
    expect(m2Mirror.mixin, m2Mirror);
    expect(m3Mirror.mixin, m3Mirror);
    expect(bMirror.superclass.mixin, m1Mirror);
    expect(
        () => bMirror.superclass.superclass, throwsANoSuchCapabilityException);
    expect(cMirror.superclass.superclass.mixin, m2Mirror);
    expect(cMirror.superclass.mixin, m3Mirror);
    expect(cMirror.superclass.superclass.superclass, bMirror);
  });
}
