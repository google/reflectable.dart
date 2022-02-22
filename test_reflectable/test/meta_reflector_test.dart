// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflectable code generation.
/// Creates a `MetaReflector` which may be used to reflect on the set of
/// reflectors themselves. Illustrates how it is possible to avoid the
/// use of the method `Reflectable.getInstance` using an extra interface
/// `AllReflectorsCapable`, which also serves to illustrate why
/// `Reflectable.getInstance` is a useful addition to reflectable.
library test_reflectable.test.meta_reflector_test;

@GlobalQuantifyCapability(
    r'^reflectable.reflectable.Reflectable$', MetaReflector())
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'meta_reflector_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

abstract class AllReflectorsCapable implements Reflectable {
  Reflectable get self;
  Set<String> get scopes;
}

class MetaReflector extends Reflectable {
  const MetaReflector()
      : super(subtypeQuantifyCapability, newInstanceCapability);
  Set<Reflectable> get allReflectors {
    var result = <Reflectable>{};
    for (var classMirror in annotatedClasses) {
      if (classMirror.isAbstract) continue;
      var reflector = classMirror.newInstance('', []) as Reflectable;
      if (reflector is AllReflectorsCapable) {
        result.add(reflector.self);
      }
    }
    return result;
  }
}

Set<String> setOf(String s) => {s};

class Reflector extends Reflectable implements AllReflectorsCapable {
  const Reflector()
      : super(invokingCapability, declarationsCapability,
            typeRelationsCapability, libraryCapability);

  @override
  Reflectable get self => const Reflector();

  @override
  Set<String> get scopes => setOf('polymer');
}

class Reflector2 extends Reflectable implements AllReflectorsCapable {
  const Reflector2()
      : super(invokingCapability, metadataCapability, typeRelationsCapability,
            libraryCapability);

  @override
  Reflectable get self => const Reflector2();

  @override
  Set<String> get scopes => setOf('observe');
}

class ReflectorUpwardsClosed extends Reflectable
    implements AllReflectorsCapable {
  const ReflectorUpwardsClosed()
      : super(superclassQuantifyCapability, invokingCapability,
            declarationsCapability, typeRelationsCapability);

  @override
  Reflectable get self => const ReflectorUpwardsClosed();

  @override
  Set<String> get scopes => setOf('polymer')..add('observe');
}

class ReflectorUpwardsClosedToA extends Reflectable
    implements AllReflectorsCapable {
  const ReflectorUpwardsClosedToA()
      : super(const SuperclassQuantifyCapability(A), invokingCapability,
            declarationsCapability, typeRelationsCapability);

  @override
  Reflectable get self => const ReflectorUpwardsClosedToA();

  @override
  Set<String> get scopes => {};
}

class ReflectorUpwardsClosedUntilA extends Reflectable
    implements AllReflectorsCapable {
  const ReflectorUpwardsClosedUntilA()
      : super(
            const SuperclassQuantifyCapability(A, excludeUpperBound: true),
            invokingCapability,
            declarationsCapability,
            typeRelationsCapability);

  @override
  Reflectable get self => const ReflectorUpwardsClosedUntilA();

  @override
  Set<String> get scopes => {};
}

@Reflector()
@Reflector2()
@P()
class M1 {
  void foo() {}
  // ignore:prefer_typing_uninitialized_variables
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
  Object? field;
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
    expect(dMirror.mixin, m1Mirror);
    expect(dMirror.superclass!.mixin, aMirror);
    expect(bMirror.superclass!.declarations['foo']!.owner, m1Mirror);
    expect(bMirror.superclass!.declarations['field']!.owner, m1Mirror);
    expect(bMirror.superclass!.declarations['staticBar'], null);
    expect(bMirror.superclass!.hasReflectedType, true);
    expect(bMirror.superclass!.reflectedType, const TypeMatcher<Type>());
    expect(bMirror.superclass!.superclass!.reflectedType,
        const TypeMatcher<Type>());
  });
}

Matcher throwsANoSuchCapabilityException =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());

void main() {
  initializeReflectable();

  Set<Reflectable> allReflectors = const MetaReflector().allReflectors;

  test('MetaReflector, set of reflectors', () {
    expect(allReflectors, {
      const Reflector(),
      const Reflector2(),
      const ReflectorUpwardsClosed(),
      const ReflectorUpwardsClosedToA(),
      const ReflectorUpwardsClosedUntilA(),
    });
    expect(
        allReflectors.where((Reflectable reflector) =>
            reflector is AllReflectorsCapable &&
            reflector.scopes.contains('polymer')),
        {const Reflector(), const ReflectorUpwardsClosed()});
    expect(
        allReflectors.where((Reflectable reflector) =>
            reflector is AllReflectorsCapable &&
            reflector.scopes.contains('observe')),
        {const Reflector2(), const ReflectorUpwardsClosed()});
  });

  allReflectors
      .where((Reflectable reflector) =>
          reflector is AllReflectorsCapable &&
          reflector.scopes.contains('polymer'))
      .forEach(
          (Reflectable reflector) => testReflector(reflector, '$reflector'));

  test('MetaReflector, select by name', () {
    var reflector2 = allReflectors
        .firstWhere((Reflectable reflector) => '$reflector'.contains('2'));
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
    expect(bMirror.superclass!.mixin, m1Mirror);
    // Test that the mixin-application does not inherit the metadata from its
    // mixin.
    expect(bMirror.superclass!.metadata, isEmpty);
    expect(
        () => bMirror.superclass!.superclass, throwsANoSuchCapabilityException);
    expect(cMirror.superclass!.superclass!.mixin, m2Mirror);
    expect(cMirror.superclass!.mixin, m3Mirror);
    expect(cMirror.superclass!.superclass!.superclass, bMirror);
    expect(() => dMirror.superclass, throwsANoSuchCapabilityException);
  });

  test('MetaReflector, select by capability', () {
    var reflector = allReflectors.firstWhere((Reflectable reflector) {
      return (reflector.capabilities.any((ReflectCapability capability) =>
          capability is SuperclassQuantifyCapability &&
          capability.upperBound == A &&
          !capability.excludeUpperBound));
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
    expect(dMirror.mixin, m1Mirror);
    expect(dMirror.superclass, aMirror);
  });
}
