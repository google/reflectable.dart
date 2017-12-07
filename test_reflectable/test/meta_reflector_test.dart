// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File being transformed by the reflectable transformer.
/// Creates a `MetaReflector` which may be used to reflect on the set of
/// reflectors themselves. Illustrates how it is possible to avoid the
/// use of the method `Reflectable.getInstance` using an extra interface
/// `AllReflectorsCapable`, which also serves to illustrate why
/// `Reflectable.getInstance` is a useful addition to reflectable.
library test_reflectable.test.meta_reflector_test;

@GlobalQuantifyCapability(
    r"^reflectable.reflectable.Reflectable$", const MetaReflector())
import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";
import 'meta_reflector_test.reflectable.dart';

abstract class AllReflectorsCapable implements Reflectable {
  Reflectable get self;
  Set<String> get scopes;
}

class MetaReflector extends Reflectable {
  const MetaReflector()
      : super(subtypeQuantifyCapability, newInstanceCapability);
  Set<Reflectable> get allReflectors {
    Set<Reflectable> result = new Set<Reflectable>();
    annotatedClasses.forEach((ClassMirror classMirror) {
      if (classMirror.isAbstract) return;
      Reflectable reflector = classMirror.newInstance("", []);
      if (reflector is AllReflectorsCapable) {
        result.add(reflector.self);
      }
    });
    return result;
  }
}

Set<String> setOf(String s) => new Set<String>.from(<String>[s]);

class Reflector extends Reflectable implements AllReflectorsCapable {
  const Reflector()
      : super(invokingCapability, declarationsCapability,
            typeRelationsCapability, libraryCapability);
  Reflectable get self => const Reflector();
  Set<String> get scopes => setOf("polymer");
}

class Reflector2 extends Reflectable implements AllReflectorsCapable {
  const Reflector2()
      : super(invokingCapability, metadataCapability, typeRelationsCapability,
            libraryCapability);
  Reflectable get self => const Reflector2();
  Set<String> get scopes => setOf("observe");
}

class ReflectorUpwardsClosed extends Reflectable
    implements AllReflectorsCapable {
  const ReflectorUpwardsClosed()
      : super(superclassQuantifyCapability, invokingCapability,
            declarationsCapability, typeRelationsCapability);
  Reflectable get self => const ReflectorUpwardsClosed();
  Set<String> get scopes => setOf("polymer")..add("observe");
}

class ReflectorUpwardsClosedToA extends Reflectable
    implements AllReflectorsCapable {
  const ReflectorUpwardsClosedToA()
      : super(const SuperclassQuantifyCapability(A), invokingCapability,
            declarationsCapability, typeRelationsCapability);
  Reflectable get self => const ReflectorUpwardsClosedToA();
  Set<String> get scopes => new Set<String>();
}

class ReflectorUpwardsClosedUntilA extends Reflectable
    implements AllReflectorsCapable {
  const ReflectorUpwardsClosedUntilA()
      : super(
            const SuperclassQuantifyCapability(A, excludeUpperBound: true),
            invokingCapability,
            declarationsCapability,
            typeRelationsCapability);
  Reflectable get self => const ReflectorUpwardsClosedUntilA();
  Set<String> get scopes => new Set<String>();
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

@Reflector()
@Reflector2()
@ReflectorUpwardsClosed()
@ReflectorUpwardsClosedToA()
@ReflectorUpwardsClosedUntilA()
class D = A with M1;

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

main() {
  initializeReflectable();

  Set<Reflectable> allReflectors = const MetaReflector().allReflectors;

  test("MetaReflector, set of reflectors", () {
    expect(
        allReflectors,
        [
          const Reflector(),
          const Reflector2(),
          const ReflectorUpwardsClosed(),
          const ReflectorUpwardsClosedToA(),
          const ReflectorUpwardsClosedUntilA()
        ].toSet());
    expect(
        allReflectors.where((Reflectable reflector) =>
            reflector is AllReflectorsCapable &&
            reflector.scopes.contains("polymer")),
        [const Reflector(), const ReflectorUpwardsClosed()].toSet());
    expect(
        allReflectors.where((Reflectable reflector) =>
            reflector is AllReflectorsCapable &&
            reflector.scopes.contains("observe")),
        [const Reflector2(), const ReflectorUpwardsClosed()].toSet());
  });

  allReflectors
      .where((Reflectable reflector) =>
          reflector is AllReflectorsCapable &&
          reflector.scopes.contains("polymer"))
      .forEach(
          (Reflectable reflector) => testReflector(reflector, "$reflector"));

  test("MetaReflector, select by name", () {
    var reflector2 = allReflectors
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
    var reflector = allReflectors.firstWhere((Reflectable reflector) {
      return (reflector.capabilities.any((ReflectCapability capability) =>
              capability is SuperclassQuantifyCapability &&
              capability.upperBound == A &&
              !capability.excludeUpperBound));
    });
    ClassMirror aMirror = reflector.reflectType(A);
    ClassMirror bMirror = reflector.reflectType(B);
    ClassMirror cMirror = reflector.reflectType(C);
    ClassMirror dMirror = reflector.reflectType(D);
    ClassMirror m1Mirror = reflector.reflectType(M1);
    ClassMirror m2Mirror = reflector.reflectType(M2);
    ClassMirror m3Mirror = reflector.reflectType(M3);
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
}
