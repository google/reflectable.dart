// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.mixin_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'mixin_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, declarationsCapability,
            typeRelationsCapability, libraryCapability);
}

// Note the class `A` is not annotated by this.
class Reflector2 extends Reflectable {
  const Reflector2()
      : super(invokingCapability, typeRelationsCapability, metadataCapability,
            libraryCapability);
}

class Reflector3 extends Reflectable {
  const Reflector3()
      : super(invokingCapability, declarationsCapability, libraryCapability,
            typeCapability);
}

class ReflectorUpwardsClosed extends Reflectable {
  const ReflectorUpwardsClosed()
      : super(superclassQuantifyCapability, invokingCapability,
            declarationsCapability, typeRelationsCapability);
}

class ReflectorUpwardsClosedToA extends Reflectable {
  const ReflectorUpwardsClosedToA()
      : super(const SuperclassQuantifyCapability(A), invokingCapability,
            declarationsCapability, typeRelationsCapability);
}

class ReflectorUpwardsClosedUntilA extends Reflectable {
  const ReflectorUpwardsClosedUntilA()
      : super(
            const SuperclassQuantifyCapability(A, excludeUpperBound: true),
            invokingCapability,
            typeRelationsCapability,
            declarationsCapability);
}

@Reflector()
@Reflector2()
@P()
class M1 {
  void foo() {}
  var field;
  static void staticFoo(x) {}
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
  void foo() {}
  var field;
  static void staticFoo(x) {}
  static void staticBar() {}
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

@Reflector()
@Reflector2()
@ReflectorUpwardsClosed()
@ReflectorUpwardsClosedToA()
@ReflectorUpwardsClosedUntilA()
class D = A with M1;

class M4 {}

@Reflector3()
class M5 {}

class M6 {}

class AA {}

@Reflector()
class BB extends AA with M4, M5, M6 {}

void testReflector(Reflectable reflector, String desc) {
  test('Mixin, $desc', () {
    var aMirror = reflector.reflectType(A) as ClassMirror;
    var bMirror = reflector.reflectType(B) as ClassMirror;
    var cMirror = reflector.reflectType(C) as ClassMirror;
    var dMirror = reflector.reflectType(D) as ClassMirror;
    var m1Mirror = reflector.reflectType(M1) as ClassMirror;
    var m2Mirror = reflector.reflectType(M2) as ClassMirror;
    var m3Mirror = reflector.reflectType(M3) as ClassMirror;
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
    expect(dMirror.mixin, m1Mirror);
    expect(dMirror.superclass.mixin, aMirror);
    expect(bMirror.superclass.declarations['foo']!.owner, m1Mirror);
    expect(bMirror.superclass.declarations['field']!.owner, m1Mirror);
    expect(bMirror.superclass.declarations['staticBar'], null);
    expect(bMirror.superclass.hasReflectedType, true);
    expect(bMirror.superclass.reflectedType, const TypeMatcher<Type>());
    expect(bMirror.superclass.superclass.reflectedType,
        const TypeMatcher<Type>());
  });
}

Matcher throwsANoSuchCapabilityException =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());

void main() {
  initializeReflectable();

  testReflector(const Reflector(), 'each is annotated');
  testReflector(const ReflectorUpwardsClosed(), 'upwards closed');
  test('Mixin, superclasses not included', () {
    var reflector2 = const Reflector2();
    var bMirror = reflector2.reflectType(B) as ClassMirror;
    var cMirror = reflector2.reflectType(C) as ClassMirror;
    var dMirror = reflector2.reflectType(D) as ClassMirror;
    var m1Mirror = reflector2.reflectType(M1) as ClassMirror;
    var m2Mirror = reflector2.reflectType(M2) as ClassMirror;
    var m3Mirror = reflector2.reflectType(M3) as ClassMirror;
    expect(bMirror.mixin, bMirror);
    expect(cMirror.mixin, cMirror);
    expect(dMirror.mixin, m1Mirror);
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
    expect(() => dMirror.superclass, throwsANoSuchCapabilityException);
  });
  test('Mixin, superclasses included up to bound', () {
    var reflector = const ReflectorUpwardsClosedToA();
    var aMirror = reflector.reflectType(A) as ClassMirror;
    var bMirror = reflector.reflectType(B) as ClassMirror;
    var cMirror = reflector.reflectType(C) as ClassMirror;
    var dMirror = reflector.reflectType(D) as ClassMirror;
    var m1Mirror = reflector.reflectType(M1) as ClassMirror;
    var m2Mirror = reflector.reflectType(M2) as ClassMirror;
    var m3Mirror = reflector.reflectType(M3) as ClassMirror;
    expect(reflector.reflectType(M1), m1Mirror);
    expect(reflector.reflectType(M2), m2Mirror);
    expect(reflector.reflectType(M3), m3Mirror);
    expect(bMirror.superclass.mixin, m1Mirror);
    expect(bMirror.superclass.superclass, aMirror);
    expect(cMirror.superclass.mixin, m3Mirror);
    expect(cMirror.superclass.superclass.mixin, m2Mirror);
    expect(cMirror.superclass.superclass.superclass, bMirror);
    expect(dMirror.mixin, m1Mirror);
    expect(dMirror.superclass, aMirror);
  });
  test('Mixin, superclasses included up to but not including bound', () {
    var reflector = const ReflectorUpwardsClosedUntilA();
    var bMirror = reflector.reflectType(B) as ClassMirror;
    var cMirror = reflector.reflectType(C) as ClassMirror;
    var dMirror = reflector.reflectType(D) as ClassMirror;
    var m1Mirror = reflector.reflectType(M1) as ClassMirror;
    var m2Mirror = reflector.reflectType(M2) as ClassMirror;
    var m3Mirror = reflector.reflectType(M3) as ClassMirror;
    expect(() => reflector.reflectType(A), throwsANoSuchCapabilityException);
    expect(reflector.reflectType(M1), m1Mirror);
    expect(reflector.reflectType(M2), m2Mirror);
    expect(reflector.reflectType(M3), m3Mirror);
    expect(cMirror.superclass.mixin, m3Mirror);
    expect(cMirror.superclass.superclass.mixin, m2Mirror);
    expect(cMirror.superclass.superclass.superclass, bMirror);
    expect(cMirror.superclass.superclass.superclass.superclass != null, true);
    expect(() => cMirror.superclass.superclass.superclass.superclass.superclass,
        throwsANoSuchCapabilityException);
    expect(dMirror.mixin, m1Mirror);
    expect(() => dMirror.superclass, throwsANoSuchCapabilityException);
  });
  test('Mixin, naming', () {
    var reflector2 = const Reflector2();
    var bMirror = reflector2.reflectType(B) as ClassMirror;
    var cMirror = reflector2.reflectType(C) as ClassMirror;
    var dMirror = reflector2.reflectType(D) as ClassMirror;
    ClassMirror aWithM1Mirror = bMirror.superclass;
    ClassMirror bWithM2Mirror = cMirror.superclass.superclass;
    ClassMirror bWithM2WithM3Mirror = cMirror.superclass;
    expect(bMirror.simpleName, 'B');
    expect(cMirror.simpleName, 'C');
    expect(dMirror.simpleName, 'D');
    expect(
        aWithM1Mirror.simpleName,
        'test_reflectable.test.mixin_test.A with '
        'test_reflectable.test.mixin_test.M1');
    expect(
        bWithM2Mirror.simpleName,
        'test_reflectable.test.mixin_test.B with '
        'test_reflectable.test.mixin_test.M2');
    expect(
        bWithM2WithM3Mirror.simpleName,
        'test_reflectable.test.mixin_test.B with '
        'test_reflectable.test.mixin_test.M2, '
        'test_reflectable.test.mixin_test.M3');
    expect(cMirror.simpleName, 'C');
    expect(dMirror.simpleName, 'D');

    expect(bMirror.qualifiedName, 'test_reflectable.test.mixin_test.B');
    expect(cMirror.qualifiedName, 'test_reflectable.test.mixin_test.C');
    expect(dMirror.qualifiedName, 'test_reflectable.test.mixin_test.D');
    expect(
        aWithM1Mirror.qualifiedName,
        'test_reflectable.test.mixin_test.'
        'test_reflectable.test.mixin_test.A with '
        'test_reflectable.test.mixin_test.M1');
    expect(
        bWithM2Mirror.qualifiedName,
        'test_reflectable.test.mixin_test.'
        'test_reflectable.test.mixin_test.B with '
        'test_reflectable.test.mixin_test.M2');
    expect(
        bWithM2WithM3Mirror.qualifiedName,
        'test_reflectable.test.mixin_test.'
        'test_reflectable.test.mixin_test.B with '
        'test_reflectable.test.mixin_test.M2, '
        'test_reflectable.test.mixin_test.M3');
    expect(cMirror.qualifiedName, 'test_reflectable.test.mixin_test.C');
    expect(dMirror.qualifiedName, 'test_reflectable.test.mixin_test.D');
  });
  test('Mixins, some covered and some uncovered', () {
    expect(
        const Reflector().reflectType(BB), const TypeMatcher<ClassMirror>());
  });
}
