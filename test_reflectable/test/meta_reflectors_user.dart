// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Part of the entry point 'reflectors_test.dart'.
//
// Independence: This library depends on the domain classes `M1`..`M3`,
// `A`..`D`, `P`, and it dynamically uses the reflectors, but it does not
// statically depend on 'meta_reflectors_definer.dart' nor on
// 'meta_reflectors_domain_definer.dart'.

library test_reflectable.test.meta_reflectors_user;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";
import "meta_reflectors_meta.dart";
import "meta_reflectors_domain.dart";

testReflector(Reflectable reflector, String desc) {
  test("Mixin, $desc", () {
    ClassMirror aMirror = reflector.reflectType(A);
    ClassMirror bMirror = reflector.reflectType(B);
    ClassMirror cMirror = reflector.reflectType(C);
    ClassMirror dMirror = reflector.reflectType(D);
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
    expect(dMirror.mixin, m1Mirror);
    expect(dMirror.superclass.mixin, aMirror);
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

Iterable<String> getNames(Iterable<Reflectable> reflectables) {
  return reflectables.map((Reflectable reflector) {
    String fullString = reflector.toString();
    return fullString.substring(13, fullString.length - 1);
  });
}

runTests() {
  List<Reflectable> reflectors =
      const AllReflectorsMetaReflector().reflectors.toList();

  test("MetaReflector, set of reflectors", () {
    expect(
        getNames(reflectors).toSet(),
        [
          "Reflector",
          "Reflector2",
          "ReflectorUpwardsClosed",
          "ReflectorUpwardsClosedToA",
          "ReflectorUpwardsClosedUntilA",
          "ScopeMetaReflector",
          "AllReflectorsMetaReflector"
        ].toSet());
    expect(getNames(const ScopeMetaReflector().reflectablesOfScope("polymer")),
        ["Reflector", "ReflectorUpwardsClosed"].toSet());
    expect(getNames(const ScopeMetaReflector().reflectablesOfScope("observe")),
        ["Reflector2", "ReflectorUpwardsClosed"].toSet());
  });

  const ScopeMetaReflector().reflectablesOfScope("polymer").forEach(
      (Reflectable reflector) => testReflector(reflector, "$reflector"));

  test("MetaReflector, select by name", () {
    var reflector2 = reflectors
        .firstWhere((Reflectable reflector) => "$reflector".contains("2"));
    ClassMirror bMirror = reflector2.reflectType(B);
    ClassMirror cMirror = reflector2.reflectType(C);
    ClassMirror dMirror = reflector2.reflectType(D);
    ClassMirror m1Mirror = reflector2.reflectType(M1);
    ClassMirror m2Mirror = reflector2.reflectType(M2);
    ClassMirror m3Mirror = reflector2.reflectType(M3);
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

  test("MetaReflector, select by capability", () {
    var reflector = reflectors.firstWhere((Reflectable reflector) {
      return (reflector.capabilities.any((ReflectCapability capability) =>
          capability is SuperclassQuantifyCapability &&
              capability.upperBound == A &&
              !capability.excludeUpperBound));
    });
    ClassMirror aMirror = reflector.reflectType(A);
    ClassMirror bMirror = reflector.reflectType(B);
    ClassMirror cMirror = reflector.reflectType(C);
    ClassMirror dMirror = reflector.reflectType(D);
    expect(() => reflector.reflectType(M1), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M2), throwsANoSuchCapabilityException);
    expect(() => reflector.reflectType(M3), throwsANoSuchCapabilityException);
    expect(() => bMirror.superclass.mixin, throwsANoSuchCapabilityException);
    expect(bMirror.superclass.superclass, aMirror);
    expect(() => cMirror.superclass.mixin, throwsANoSuchCapabilityException);
    expect(() => cMirror.superclass.superclass.mixin,
        throwsANoSuchCapabilityException);
    expect(cMirror.superclass.superclass.superclass, bMirror);
    expect(() => dMirror.mixin, throwsANoSuchCapabilityException);
    expect(dMirror.superclass, aMirror);
  });
}
