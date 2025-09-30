// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Part of the entry point 'reflectors_test.dart'.
//
// Independence: This library depends on the domain classes `M1`..`M3`,
// `A`..`D`, `P`, and it dynamically uses the reflectors, but it does not
// statically depend on 'meta_reflectors_definer.dart' nor on
// 'meta_reflectors_domain_definer.dart'.

library test_reflectable.test.meta_reflectors_user;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'meta_reflectors_meta.dart';
import 'meta_reflectors_domain.dart';

// ignore_for_file: omit_local_variable_types

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
    expect(bMirror.superclass!.mixin, m1Mirror);
    expect(cMirror.superclass!.superclass!.mixin, m2Mirror);
    expect(cMirror.superclass!.mixin, m3Mirror);
    expect(cMirror.superclass!.superclass!.superclass, bMirror);
    expect(dMirror.mixin, dMirror);
    expect(dMirror.superclass!.mixin, m1Mirror);
    expect(dMirror.superclass!.superclass!.mixin, aMirror);
    expect(bMirror.superclass!.declarations['foo']!.owner, m1Mirror);
    expect(bMirror.superclass!.declarations['field']!.owner, m1Mirror);
    expect(bMirror.superclass!.declarations['staticBar'], null);
    expect(bMirror.superclass!.hasReflectedType, true);
    expect(bMirror.superclass!.reflectedType, const TypeMatcher<Type>());
    expect(
      bMirror.superclass!.superclass!.reflectedType,
      const TypeMatcher<Type>(),
    );
  });
}

Matcher throwsANoSuchCapabilityException = throwsA(
  const TypeMatcher<NoSuchCapabilityError>(),
);

Iterable<String> getNames(Iterable<Reflectable> reflectables) {
  return reflectables.map((Reflectable reflector) {
    var fullString = reflector.toString();
    return fullString.substring(13, fullString.length - 1);
  });
}

void runTests() {
  List<Reflectable> reflectors = const AllReflectorsMetaReflector().reflectors
      .toList();

  test('MetaReflector, set of reflectors', () {
    expect(getNames(reflectors).toSet(), {
      'Reflector',
      'Reflector2',
      'ReflectorUpwardsClosed',
      'ReflectorUpwardsClosedToA',
      'ReflectorUpwardsClosedUntilA',
      'ScopeMetaReflector',
      'AllReflectorsMetaReflector',
    });
    expect(
      getNames(const ScopeMetaReflector().reflectablesOfScope('polymer')),
      {'Reflector', 'ReflectorUpwardsClosed'},
    );
    expect(
      getNames(const ScopeMetaReflector().reflectablesOfScope('observe')),
      {'Reflector2', 'ReflectorUpwardsClosed'},
    );
  });

  const ScopeMetaReflector()
      .reflectablesOfScope('polymer')
      .forEach(
        (Reflectable reflector) => testReflector(reflector, '$reflector'),
      );

  test('MetaReflector, select by name', () {
    var reflector2 = reflectors.firstWhere(
      (Reflectable reflector) => '$reflector'.contains('2'),
    );
    var bMirror = reflector2.reflectType(B) as ClassMirror;
    var cMirror = reflector2.reflectType(C) as ClassMirror;
    var dMirror = reflector2.reflectType(D) as ClassMirror;
    var m1Mirror = reflector2.reflectType(M1) as ClassMirror;
    var m2Mirror = reflector2.reflectType(M2) as ClassMirror;
    var m3Mirror = reflector2.reflectType(M3) as ClassMirror;
    expect(bMirror.mixin, bMirror);
    expect(cMirror.mixin, cMirror);
    expect(dMirror.mixin, dMirror);
    expect(m1Mirror.mixin, m1Mirror);
    // Test that metadata is preserved.
    expect(m1Mirror.metadata, contains(const P()));
    expect(m2Mirror.mixin, m2Mirror);
    expect(m3Mirror.mixin, m3Mirror);
    expect(bMirror.superclass!.mixin, m1Mirror);
    // Test that the mixin-application does not inherit the metadata from its
    // mixin.
    expect(bMirror.superclass!.metadata, isEmpty);
    expect(
      () => bMirror.superclass!.superclass,
      throwsANoSuchCapabilityException,
    );
    expect(cMirror.superclass!.superclass!.mixin, m2Mirror);
    expect(cMirror.superclass!.mixin, m3Mirror);
    expect(cMirror.superclass!.superclass!.superclass, bMirror);
    expect(
      () => dMirror.superclass!.superclass,
      throwsANoSuchCapabilityException,
    );
  });

  test('MetaReflector, select by capability', () {
    var reflector = reflectors.firstWhere((Reflectable reflector) {
      return (reflector.capabilities.any(
        (ReflectCapability capability) =>
            capability is SuperclassQuantifyCapability &&
            capability.upperBound == A &&
            !capability.excludeUpperBound,
      ));
    });
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
    expect(bMirror.superclass!.mixin, m1Mirror);
    expect(bMirror.superclass!.superclass, aMirror);
    expect(cMirror.superclass!.mixin, m3Mirror);
    expect(cMirror.superclass!.superclass!.mixin, m2Mirror);
    expect(cMirror.superclass!.superclass!.superclass, bMirror);
    expect(dMirror.mixin, dMirror);
    expect(dMirror.superclass!.mixin, m1Mirror);
    expect(dMirror.superclass!.superclass, aMirror);
  });
}
