// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflectable code generation.
/// Uses `correspondingSetterCapability` to get support for setters.
@topLevelInvokeMetaReflector
@topLevelInvokeFrReflector
library test_reflectable.test.corresponding_setter_test;

import 'package:test/test.dart';
import 'package:reflectable/reflectable.dart';
import 'corresponding_setter_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

const String methodRegExp = r'f.*r$';

class InvokingMetaReflector extends Reflectable {
  const InvokingMetaReflector()
      : super(correspondingSetterQuantifyCapability,
            const InvokingMetaCapability(P));
}

class InstanceInvokeMetaReflector extends Reflectable {
  const InstanceInvokeMetaReflector()
      : super(correspondingSetterQuantifyCapability,
            const InstanceInvokeMetaCapability(P));
}

class StaticInvokeMetaReflector extends Reflectable {
  const StaticInvokeMetaReflector()
      : super(correspondingSetterQuantifyCapability,
            const StaticInvokeMetaCapability(P));
}

class TopLevelInvokeMetaReflector extends Reflectable {
  const TopLevelInvokeMetaReflector()
      : super(correspondingSetterQuantifyCapability,
            const TopLevelInvokeMetaCapability(P), libraryCapability);
}

class InvokingFrReflector extends Reflectable {
  const InvokingFrReflector()
      : super(correspondingSetterQuantifyCapability,
            const InvokingCapability(methodRegExp));
}

class InstanceInvokeFrReflector extends Reflectable {
  const InstanceInvokeFrReflector()
      : super(correspondingSetterQuantifyCapability,
            const InstanceInvokeCapability(methodRegExp));
}

class StaticInvokeFrReflector extends Reflectable {
  const StaticInvokeFrReflector()
      : super(correspondingSetterQuantifyCapability,
            const StaticInvokeCapability(methodRegExp));
}

class TopLevelInvokeFrReflector extends Reflectable {
  const TopLevelInvokeFrReflector()
      : super(correspondingSetterQuantifyCapability,
            const TopLevelInvokeCapability(methodRegExp), libraryCapability);
}

const invokingMetaReflector = InvokingMetaReflector();
const instanceInvokeMetaReflector = InstanceInvokeMetaReflector();
const staticInvokeMetaReflector = StaticInvokeMetaReflector();
const topLevelInvokeMetaReflector = TopLevelInvokeMetaReflector();
const invokingFrReflector = InvokingFrReflector();
const instanceInvokeFrReflector = InstanceInvokeFrReflector();
const staticInvokeFrReflector = StaticInvokeFrReflector();
const topLevelInvokeFrReflector = TopLevelInvokeFrReflector();

final Map<Type, String> description = <Type, String>{
  InvokingMetaReflector: 'Invoking',
  InstanceInvokeMetaReflector: 'InstanceInvoke',
  StaticInvokeMetaReflector: 'StaticInvoke',
  TopLevelInvokeMetaReflector: 'TopLevelInvoke',
  InvokingFrReflector: 'InvokingFr',
  InstanceInvokeFrReflector: 'InstanceInvokeFr',
  StaticInvokeFrReflector: 'StaticInvokeFr',
  TopLevelInvokeFrReflector: 'TopLevelInvokeFr'
};

class P {
  const P();
}

@invokingMetaReflector
@instanceInvokeMetaReflector
@invokingFrReflector
@instanceInvokeFrReflector
class A {
  @P()
  int get foo => 44;
  @P()
  int get foobar => 45;
  set foo(int x) => field = x;
  set foobar(int x) => field = x;
  int field = 46;

  void reset() {
    field = 46;
  }
}

@invokingMetaReflector
@staticInvokeMetaReflector
@invokingFrReflector
@staticInvokeFrReflector
class B {
  @P()
  static int get foo => 44;
  @P()
  static int get foobar => 45;

  static set foo(int x) {
    field = x;
  }

  static set foobar(int x) {
    field = x;
  }

  static void reset() {
    field = 46;
  }

  static int field = 46;
}

int fooBarVariable = 41;

@P()
int get fooBar => 14;

set fooBar(int newValue) {
  fooBarVariable = newValue;
}

Matcher throwsReflectableNoMethod =
    throwsA(TypeMatcher<ReflectableNoSuchMethodError>());

void testInstance(Reflectable mirrorSystem, A reflectee, {bool broad = false}) {
  test('Instance invocation: ${description[mirrorSystem.runtimeType]}', () {
    reflectee.reset();
    var instanceMirror = mirrorSystem.reflect(reflectee);
    if (broad) {
      expect(instanceMirror.invokeGetter('foo'), 44);
    } else {
      expect(() {
        instanceMirror.invokeGetter('foo');
      }, throwsReflectableNoMethod);
    }
    expect(instanceMirror.invokeGetter('foobar'), 45);
    expect(reflectee.field, 46);
    if (broad) {
      expect(instanceMirror.invokeSetter('foo=', 100), 100);
      expect(reflectee.field, 100);
    } else {
      expect(() {
        instanceMirror.invokeSetter('foo=', 100);
      }, throwsReflectableNoMethod);
      expect(reflectee.field, 46);
    }
    expect(instanceMirror.invokeSetter('foobar=', 100), 100);
    expect(reflectee.field, 100);
  });
}

void testStatic(Reflectable mirrorSystem, Type reflectee,
    void Function() classResetter, int Function() classGetter,
    {bool broad = false}) {
  test('Static invocation: ${description[mirrorSystem.runtimeType]}', () {
    classResetter();
    ClassMirror classMirror =
        mirrorSystem.reflectType(reflectee) as ClassMirror;
    if (broad) {
      expect(classMirror.invokeGetter('foo'), 44);
    } else {
      expect(() {
        classMirror.invokeGetter('foo');
      }, throwsReflectableNoMethod);
    }
    expect(classMirror.invokeGetter('foobar'), 45);
    expect(B.field, 46);
    if (broad) {
      expect(classMirror.invokeSetter('foo=', 100), 100);
      expect(classGetter(), 100);
    } else {
      expect(() {
        classMirror.invokeSetter('foo=', 100);
      }, throwsReflectableNoMethod);
      expect(classGetter(), 46);
    }
    expect(classMirror.invokeSetter('foobar=', 100), 100);
    expect(classGetter(), 100);
  });
}

void testTopLevel(Reflectable mirrorSystem) {
  test('Top level invocation: ${description[mirrorSystem.runtimeType]}', () {
    var libraryMirror = mirrorSystem
        .findLibrary('test_reflectable.test.corresponding_setter_test');
    expect(libraryMirror.invokeGetter('fooBar'), 14);
    int oldValue = fooBarVariable;
    libraryMirror.invokeSetter('fooBar=', oldValue + 1);
    expect(fooBarVariable, oldValue + 1);
  });
}

void main() {
  initializeReflectable();

  var a = A();
  testInstance(invokingMetaReflector, a, broad: true);
  testInstance(instanceInvokeMetaReflector, a, broad: true);
  testInstance(invokingFrReflector, a);
  testInstance(instanceInvokeFrReflector, a);

  void reset() => B.reset();
  int field() => B.field;

  testStatic(invokingMetaReflector, B, reset, field, broad: true);
  testStatic(staticInvokeMetaReflector, B, reset, field, broad: true);
  testStatic(invokingFrReflector, B, reset, field);
  testStatic(staticInvokeFrReflector, B, reset, field);

  testTopLevel(topLevelInvokeMetaReflector);
  testTopLevel(topLevelInvokeFrReflector);
}
