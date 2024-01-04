// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses `isSubtypeOf` and `isAssignableTo`.

library test_reflectable.test.subtype_test;

@GlobalQuantifyCapability(
    r'^test_reflectable\.test\.subtype_test\..*', Reflector())
@GlobalQuantifyCapability(
    r'^test_reflectable\.test\.subtype_test\..*', InsufficientReflector())
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'subtype_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(superclassQuantifyCapability, typeRelationsCapability);
}

class InsufficientReflector extends Reflectable {
  const InsufficientReflector() : super(typeCapability);
}

class A {}

class B extends A {}

class C extends B {}

class D {}

class E extends D implements B {}

class F implements E, D {}

mixin class M1 {}

mixin class M2 {}

class G extends D with M1, M2 {}

class H = D with M1, M2;

Matcher throwsNoCapability =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());

void main() {
  initializeReflectable();

  Reflectable reflector = const Reflector();
  Reflectable insufficientReflector = const InsufficientReflector();

  var aMirror = reflector.reflectType(A) as ClassMirror;
  var bMirror = reflector.reflectType(B) as ClassMirror;
  var cMirror = reflector.reflectType(C) as ClassMirror;
  var dMirror = reflector.reflectType(D) as ClassMirror;
  var eMirror = reflector.reflectType(E) as ClassMirror;
  var fMirror = reflector.reflectType(F) as ClassMirror;
  var gMirror = reflector.reflectType(G) as ClassMirror;
  var hMirror = reflector.reflectType(H) as ClassMirror;
  var m1Mirror = reflector.reflectType(M1) as ClassMirror;
  var m2Mirror = reflector.reflectType(M2) as ClassMirror;

  test('isSubtypeOf', () {
    // Test reflexivity.
    expect(aMirror.isSubtypeOf(aMirror), isTrue);
    // Test unrelated classes.
    expect(m1Mirror.isSubtypeOf(m2Mirror), isFalse);
    // Test `extends` edges.
    expect(bMirror.isSubtypeOf(aMirror), isTrue);
    expect(aMirror.isSubtypeOf(bMirror), isFalse);
    expect(cMirror.isSubtypeOf(aMirror), isTrue);
    expect(aMirror.isSubtypeOf(cMirror), isFalse);
    // Test `implements` edges.
    expect(eMirror.isSubtypeOf(bMirror), isTrue);
    expect(bMirror.isSubtypeOf(eMirror), isFalse);
    expect(fMirror.isSubtypeOf(bMirror), isTrue);
    expect(bMirror.isSubtypeOf(fMirror), isFalse);
    // Test mixin paths.
    expect(gMirror.isSubtypeOf(m1Mirror), isTrue);
    expect(m1Mirror.isSubtypeOf(gMirror), isFalse);
    expect(gMirror.isSubtypeOf(m2Mirror), isTrue);
    expect(m2Mirror.isSubtypeOf(gMirror), isFalse);
    expect(hMirror.isSubtypeOf(m1Mirror), isTrue);
    expect(m1Mirror.isSubtypeOf(hMirror), isFalse);
    expect(hMirror.isSubtypeOf(m2Mirror), isTrue);
    expect(m2Mirror.isSubtypeOf(hMirror), isFalse);
    // Test mixed `extends` and `implements` paths.
    expect(eMirror.isSubtypeOf(aMirror), isTrue);
    expect(aMirror.isSubtypeOf(eMirror), isFalse);
    expect(fMirror.isSubtypeOf(aMirror), isTrue);
    expect(aMirror.isSubtypeOf(fMirror), isFalse);
    expect(fMirror.isSubtypeOf(dMirror), isTrue);
    expect(dMirror.isSubtypeOf(fMirror), isFalse);
    // Misc remaining cases.
    expect(gMirror.isSubtypeOf(dMirror), isTrue);
    expect(dMirror.isSubtypeOf(gMirror), isFalse);
    expect(hMirror.isSubtypeOf(dMirror), isTrue);
    expect(dMirror.isSubtypeOf(hMirror), isFalse);
    expect(eMirror.isSubtypeOf(cMirror), isFalse);
    expect(fMirror.isSubtypeOf(cMirror), isFalse);
    expect(gMirror.isSubtypeOf(cMirror), isFalse);
    expect(hMirror.isSubtypeOf(cMirror), isFalse);
    expect(cMirror.isSubtypeOf(eMirror), isFalse);
    expect(cMirror.isSubtypeOf(fMirror), isFalse);
    expect(cMirror.isSubtypeOf(gMirror), isFalse);
    expect(cMirror.isSubtypeOf(hMirror), isFalse);
  });

  test('isSubtypeOf, without capability', () {
    expect(
        () => insufficientReflector
            .reflectType(B)
            .isSubtypeOf(insufficientReflector.reflectType(A)),
        throwsNoCapability);
  });

  test('isAssignableTo', () {
    // Test reflexivity.
    expect(aMirror.isAssignableTo(aMirror), isTrue);
    // Test unrelated classes.
    expect(m1Mirror.isAssignableTo(m2Mirror), isFalse);
    // Test `extends` edges.
    expect(bMirror.isAssignableTo(aMirror), isTrue);
    expect(aMirror.isAssignableTo(bMirror), isTrue);
    expect(cMirror.isAssignableTo(aMirror), isTrue);
    expect(aMirror.isAssignableTo(cMirror), isTrue);
    // Test `implements` edges.
    expect(eMirror.isAssignableTo(bMirror), isTrue);
    expect(bMirror.isAssignableTo(eMirror), isTrue);
    expect(fMirror.isAssignableTo(bMirror), isTrue);
    expect(bMirror.isAssignableTo(fMirror), isTrue);
    // Test mixin paths.
    expect(gMirror.isAssignableTo(m1Mirror), isTrue);
    expect(m1Mirror.isAssignableTo(gMirror), isTrue);
    expect(gMirror.isAssignableTo(m2Mirror), isTrue);
    expect(m2Mirror.isAssignableTo(gMirror), isTrue);
    expect(hMirror.isAssignableTo(m1Mirror), isTrue);
    expect(m1Mirror.isAssignableTo(hMirror), isTrue);
    expect(hMirror.isAssignableTo(m2Mirror), isTrue);
    expect(m2Mirror.isAssignableTo(hMirror), isTrue);
    // Test mixed `extends` and `implements` paths.
    expect(eMirror.isAssignableTo(aMirror), isTrue);
    expect(aMirror.isAssignableTo(eMirror), isTrue);
    expect(fMirror.isAssignableTo(aMirror), isTrue);
    expect(aMirror.isAssignableTo(fMirror), isTrue);
    expect(fMirror.isAssignableTo(dMirror), isTrue);
    expect(dMirror.isAssignableTo(fMirror), isTrue);
    // Misc remaining cases.
    expect(gMirror.isAssignableTo(dMirror), isTrue);
    expect(dMirror.isAssignableTo(gMirror), isTrue);
    expect(hMirror.isAssignableTo(dMirror), isTrue);
    expect(dMirror.isAssignableTo(hMirror), isTrue);
    expect(eMirror.isAssignableTo(cMirror), isFalse);
    expect(fMirror.isAssignableTo(cMirror), isFalse);
    expect(gMirror.isAssignableTo(cMirror), isFalse);
    expect(hMirror.isAssignableTo(cMirror), isFalse);
    expect(cMirror.isAssignableTo(eMirror), isFalse);
    expect(cMirror.isAssignableTo(fMirror), isFalse);
    expect(cMirror.isAssignableTo(gMirror), isFalse);
    expect(cMirror.isAssignableTo(hMirror), isFalse);
  });

  test('isAssignableTo, without capability', () {
    expect(
        () => insufficientReflector
            .reflectType(B)
            .isAssignableTo(insufficientReflector.reflectType(A)),
        throwsNoCapability);
  });
}
