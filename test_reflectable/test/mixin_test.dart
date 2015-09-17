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
  const Reflector2()
      : super(invokingCapability, metadataCapability, libraryCapability);
}

class ReflectorUpwardsClosed extends Reflectable {
  const ReflectorUpwardsClosed()
      : super(superclassQuantifyCapability, invokingCapability,
            declarationsCapability, typeRelationsCapability);
}

class ReflectorUpwardsClosedToA extends Reflectable {
  const ReflectorUpwardsClosedToA()
      : super(const SuperclassQuantifyCapability(A), invokingCapability,
            declarationsCapability);
}

class ReflectorUpwardsClosedUntilA extends Reflectable {
  const ReflectorUpwardsClosedUntilA()
      : super(const SuperclassQuantifyCapability(A, excludeUpperBound: true),
            invokingCapability, declarationsCapability);
}

@Reflector()
@Reflector2()
@P()
class M1 {
  foo() {}
  var field;
  static staticFoo(x) {}
}

class P {
  const P();
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
@ReflectorUpwardsClosedToA()
@ReflectorUpwardsClosedUntilA()
class C extends B with M2, M3 {}

testReflector(Reflectable reflector, String desc) {
  test("Mixin, $desc", () {
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
  testReflector(const Reflector(), "each is annotated");
  testReflector(const ReflectorUpwardsClosed(), "upwards closed");
  test("Mixin, superclasses not included", () {
    var reflector2 = const Reflector2();
    ClassMirror bMirror = reflector2.reflectType(B);
    ClassMirror cMirror = reflector2.reflectType(C);
    ClassMirror m1Mirror = reflector2.reflectType(M1);
    ClassMirror m2Mirror = reflector2.reflectType(M2);
    ClassMirror m3Mirror = reflector2.reflectType(M3);
    expect(bMirror.mixin, bMirror);
    expect(cMirror.mixin, cMirror);
    expect(m1Mirror.mixin, m1Mirror);
    // Test that metadata is preserved.
    expect(m1Mirror.metadata, contains(const P()));
    expect(m2Mirror.mixin, m2Mirror);
    expect(m3Mirror.mixin, m3Mirror);
    expect(bMirror.superclass.mixin, m1Mirror);
    // Test that the mixin-application does not inherit the metadata from its
    // mixin.
    expect(bMirror.superclass.metadata, isEmpty);
    expect(
        () => bMirror.superclass.superclass, throwsANoSuchCapabilityException);
    expect(cMirror.superclass.superclass.mixin, m2Mirror);
    expect(cMirror.superclass.mixin, m3Mirror);
    expect(cMirror.superclass.superclass.superclass, bMirror);
  });
  test("Mixin, superclasses included up to bound", () {
    var reflector = const ReflectorUpwardsClosedToA();
    ClassMirror aMirror = reflector.reflectType(A);
    ClassMirror bMirror = reflector.reflectType(B);
    ClassMirror cMirror = reflector.reflectType(C);
    expect(() => reflector.reflectType(M1), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M2), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M3), throwsANoSuchCapabilityException);
    expect(() => bMirror.superclass.mixin, throwsANoSuchCapabilityException);
    expect(bMirror.superclass.superclass, aMirror);
    expect(() => cMirror.superclass.mixin, throwsANoSuchCapabilityException);
    expect(() => cMirror.superclass.superclass.mixin,
        throwsANoSuchCapabilityException);
    expect(cMirror.superclass.superclass.superclass, bMirror);
  });
  test("Mixin, superclasses included up to but not including bound", () {
    var reflector = const ReflectorUpwardsClosedUntilA();
    ClassMirror bMirror = reflector.reflectType(B);
    ClassMirror cMirror = reflector.reflectType(C);
    expect(() => reflector.reflectType(A), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M1), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M2), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M3), throwsANoSuchCapabilityException);
    expect(() => cMirror.superclass.mixin, throwsANoSuchCapabilityException);
    expect(() => cMirror.superclass.superclass.mixin,
        throwsANoSuchCapabilityException);
    expect(cMirror.superclass.superclass.superclass, bMirror);
    expect(cMirror.superclass.superclass.superclass.superclass != null, true);
    expect(() => cMirror.superclass.superclass.superclass.superclass.superclass,
        throwsANoSuchCapabilityException);
  });
  test("Mixin, naming", () {
    var reflector2 = const Reflector2();
    ClassMirror bMirror = reflector2.reflectType(B);
    ClassMirror cMirror = reflector2.reflectType(C);
    ClassMirror aWithM1Mirror = bMirror.superclass;
    ClassMirror bWithM2Mirror = cMirror.superclass.superclass;
    ClassMirror bWithM2WithM3Mirror = cMirror.superclass;
    expect(
        aWithM1Mirror.simpleName,
        "test_reflectable.test.mixin_test.A with "
        "test_reflectable.test.mixin_test.M1");
    expect(
        bWithM2Mirror.simpleName,
        "test_reflectable.test.mixin_test.B with "
        "test_reflectable.test.mixin_test.M2");
    expect(
        bWithM2WithM3Mirror.simpleName,
        "test_reflectable.test.mixin_test.B with "
        "test_reflectable.test.mixin_test.M2, "
        "test_reflectable.test.mixin_test.M3");
    expect(
        aWithM1Mirror.qualifiedName,
        "test_reflectable.test.mixin_test."
        "test_reflectable.test.mixin_test.A with "
        "test_reflectable.test.mixin_test.M1");
    expect(
        bWithM2Mirror.qualifiedName,
        "test_reflectable.test.mixin_test."
        "test_reflectable.test.mixin_test.B with "
        "test_reflectable.test.mixin_test.M2");
    expect(
        bWithM2WithM3Mirror.qualifiedName,
        "test_reflectable.test.mixin_test."
        "test_reflectable.test.mixin_test.B with "
        "test_reflectable.test.mixin_test.M2, "
        "test_reflectable.test.mixin_test.M3");
  });
}
