// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.subtype_quantify_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'subtype_quantify_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(subtypeQuantifyCapability, instanceInvokeCapability,
            typeRelationsCapability);
}

const reflector = Reflector();

@reflector
class A {
  int foo() => 42;
}

class B extends A {
  @override
  int foo() => 43;
}

class C implements A {
  @override
  int foo() => 44;
}

mixin class M {
  int foo() => 45;
}

class D = C with M;

class E extends C with M {
  @override
  int foo() => 46;
}

class F {}

Matcher throwsNoSuchCapabilityError =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());
Matcher isClassMirror = const TypeMatcher<ClassMirror>();

void main() {
  initializeReflectable();

  test('Subtype quantification supports annotated class', () {
    expect(reflector.canReflectType(A), true);
    expect(reflector.canReflect(A()), true);
    expect(reflector.reflectType(A), isClassMirror);
    expect(reflector.reflect(A()).invoke('foo', []), 42);
  });

  test('Subtype quantification supports subclass', () {
    expect(reflector.canReflectType(B), true);
    expect(reflector.canReflect(B()), true);
    expect(reflector.reflectType(B), isClassMirror);
    expect(reflector.reflect(B()).invoke('foo', []), 43);
  });

  test('Subtype quantification supports subtype', () {
    expect(reflector.canReflectType(C), true);
    expect(reflector.canReflect(C()), true);
    expect(reflector.reflectType(C), isClassMirror);
    expect(reflector.reflect(C()).invoke('foo', []), 44);
  });

  test('Subtype quantification supports mixins', () {
    expect(reflector.canReflectType(D), true);
    expect(reflector.canReflect(D()), true);
    expect(reflector.reflectType(D), isClassMirror);
    expect(reflector.reflect(D()).invoke('foo', []), 45);
    expect(reflector.canReflectType(E), true);
    expect(reflector.canReflect(E()), true);
    expect(reflector.reflectType(E), isClassMirror);
    expect(reflector.reflect(E()).invoke('foo', []), 46);
  });

  test('Subtype quantification supports mixin applications', () {
    var eMirror = reflector.reflectType(E) as ClassMirror;
    expect(eMirror.superclass, isClassMirror);
    // TODO(eernst) implement: Cover the different kinds of mixin applications.
  });

  test('Subtype quantification does not support unrelated class', () {
    expect(reflector.canReflectType(F), false);
    expect(reflector.canReflect(F()), false);
    expect(() => reflector.reflectType(F), throwsNoSuchCapabilityError);
    expect(() => reflector.reflect(F()), throwsNoSuchCapabilityError);
  });
}
