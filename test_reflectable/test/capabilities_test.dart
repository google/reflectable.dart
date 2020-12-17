// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests that reflection is constrained according to capabilities.
// TODO(sigurdm) implement: Write tests that covers all capabilities.

library test_reflectable.test.capabilities_test;

import 'package:test/test.dart';
import 'package:reflectable/reflectable.dart' as r;
import 'package:reflectable/capability.dart' as c;
import 'capabilities_test.reflectable.dart';

class StaticReflector extends r.Reflectable {
  const StaticReflector()
      : super(
            const c.StaticInvokeCapability('foo'),
            const c.StaticInvokeCapability('getFoo'),
            const c.StaticInvokeCapability('setFoo='),
            const c.StaticInvokeCapability('nonExisting'),
            const c.StaticInvokeMetaCapability(C),
            c.declarationsCapability);
}

const staticReflector = StaticReflector();

class ABase {
  static int notIncluded() => 48;
}

@staticReflector
class A extends ABase {
  static int foo() => 42;
  static int bar() => 43;
  static int get getFoo => 44;
  static int get getBar => 45;
  static set setFoo(int x) => field = x;
  static set setBar(int x) => field = x;
  static int field = 46;
  @C()
  static int boo() => 47;
}

class C {
  const C();
}

class InstanceReflector extends r.Reflectable {
  const InstanceReflector()
      : super(
            const c.InstanceInvokeCapability('foo'),
            const c.InstanceInvokeCapability('getFoo'),
            const c.InstanceInvokeCapability('setFoo='),
            const c.InstanceInvokeCapability('nonExisting'),
            const c.InstanceInvokeMetaCapability(C),
            c.declarationsCapability);
}

const instanceReflector = InstanceReflector();

class BBase {
  @C()
  int includedByInvokeInBBase() => 48;
}

@instanceReflector
class B extends BBase {
  int foo() => 42;
  int bar() => 43;
  int get getFoo => 44;
  int get getBar => 45;
  set setFoo(int x) => field = x;
  set setBar(int x) => field = x;
  int field = 46;
  @C()
  int boo() => 47;

  // Tricky case! Not included for invocation by `instanceReflector`: No
  // regexp match, and no matching metadata. So we can invoke it because
  // of the declaration in `BBase` (which is visible for invocation and
  // `instanceMembers` even though `BBase` is not covered). But we still
  // get this _implementation_ at runtime.
  // TODO(eernst) implement: Test the same situation with a mixin.
  @override
  int includedByInvokeInBBase() => 49;
}

class BSubclass extends B {}

class BImplementer implements B {
  @override
  int foo() => 42;

  @override
  int bar() => 43;

  @override
  int get getFoo => 44;

  @override
  int get getBar => 45;

  @override
  set setFoo(int x) => field = x;

  @override
  set setBar(int x) => field = x;

  @override
  int field = 46;

  @override
  int boo() => 47;

  @override
  int includedByInvokeInBBase() => 48;
}

Matcher throwsNoCapability =
    throwsA(TypeMatcher<c.NoSuchCapabilityError>());
Matcher throwsReflectableNoMethod =
    throwsA(TypeMatcher<c.ReflectableNoSuchMethodError>());

void testDynamic(B o, String description) {
  test('Dynamic invocation $description', () {
    expect(instanceReflector.canReflect(o), true);
    expect(instanceReflector.canReflectType(o.runtimeType), true);
    var instanceMirror = instanceReflector.reflect(o);
    expect(instanceMirror.invoke('foo', []), 42);
    expect(instanceMirror.invoke('boo', []), 47);
    expect(() => instanceMirror.invoke('bar', []), throwsReflectableNoMethod);
    expect(instanceMirror.invokeGetter('getFoo'), 44);
    expect(
        () => instanceMirror.invokeGetter('getBar'), throwsReflectableNoMethod);
    expect(o.field, 46);
    expect(instanceMirror.invokeSetter('setFoo=', 100), 100);
    expect(o.field, 100);
    expect(() => instanceMirror.invokeSetter('setBar=', 100),
        throwsReflectableNoMethod);
    expect(instanceMirror.invoke('includedByInvokeInBBase', []), 49);
  });
}

void main() {
  initializeReflectable();

  test('Static invocation', () {
    var classMirror = staticReflector.reflectType(A) as r.ClassMirror;
    expect(classMirror.invoke('foo', []), 42);
    expect(() => classMirror.invoke('bar', []), throwsReflectableNoMethod);
    expect(classMirror.invokeGetter('getFoo'), 44);
    expect(() => classMirror.invokeGetter('getBar'), throwsReflectableNoMethod);
    expect(A.field, 46);
    expect(classMirror.invokeSetter('setFoo=', 100), 100);
    expect(A.field, 100);
    expect(() => classMirror.invokeSetter('setBar=', 100),
        throwsReflectableNoMethod);
    expect(classMirror.declarations.keys,
      {'foo', 'setFoo=', 'getFoo', 'boo'});
    expect(classMirror.invoke('boo', []), 47);
  });
  testDynamic(B(), 'Annotated');

  test('Declarations', () {
    expect(instanceReflector.reflect(B()).type.declarations.keys,
      {'foo', 'setFoo=', 'getFoo', 'boo'});
  });

  test("Can't reflect subclass of annotated", () {
    expect(instanceReflector.canReflect(BSubclass()), false);
    expect(instanceReflector.canReflectType(BSubclass), false);
    expect(
        () => instanceReflector.reflect(BSubclass()), throwsNoCapability);
  });

  test("Can't reflect subtype of annotated", () {
    expect(instanceReflector.canReflect(BImplementer()), false);
    expect(instanceReflector.canReflectType(BImplementer), false);
    expect(() => instanceReflector.reflect(BImplementer()),
        throwsNoCapability);
  });

  test("Can't reflect unnanotated", () {
    expect(instanceReflector.canReflect(C()), false);
    expect(instanceReflector.canReflectType(C), false);
    expect(() => instanceReflector.reflect(C()), throwsNoCapability);
  });
}
