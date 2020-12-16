// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// File used to test reflectable code generation.
// Uses a generic mixin.

library test_reflectable.test.generic_mixin_test;

// See https://github.com/dart-lang/reflectable/issues/59 for an explanation
// why we need to explicitly request coverage for `num`.
@GlobalQuantifyCapability(r'^dart.core.num$', reflector)
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'generic_mixin_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(typeRelationsCapability, instanceInvokeCapability,
            reflectedTypeCapability);
}

const reflector = Reflector();

@reflector
class M<E> {
  late E e;
}

@reflector
class A {}

@reflector
class B extends A with M<int> {}

@reflector
class C<E> extends A with M<E> {}

@reflector
class MM<E> = A with M<E>;

@reflector
class D<E> extends MM<E> {}

void main() {
  initializeReflectable();

  test('Generic mixin, instance', () {
    InstanceMirror bMirror = reflector.reflect(B());
    expect(bMirror.invokeGetter('e'), null);
    InstanceMirror cMirror = reflector.reflect(C<int>());
    expect(cMirror.invokeGetter('e'), null);
    InstanceMirror dMirror = reflector.reflect(D<int>());
    expect(dMirror.invokeGetter('e'), null);
  });

  test('Generic mixin, super of plain class', () {
    ClassMirror bMirror = reflector.reflectType(B) as ClassMirror;
    DeclarationMirror eMirror = bMirror.instanceMembers['e']!;
    expect(eMirror, TypeMatcher<MethodMirror>());
    MethodMirror eMethodMirror = eMirror as MethodMirror;
    if (eMethodMirror.hasReflectedReturnType) {
      expect(eMethodMirror.reflectedReturnType, int);
    } else {
      expect(() => eMethodMirror.reflectedReturnType, throwsUnsupportedError);
    }
  });

  test('Generic mixin, super of generic class', () {
    ClassMirror cMirror = reflector.reflect(C<num>()).type as ClassMirror;
    DeclarationMirror ceMirror = cMirror.instanceMembers['e']!;
    expect(ceMirror, TypeMatcher<MethodMirror>());
    MethodMirror ceMethodMirror = ceMirror as MethodMirror;
    if (ceMethodMirror.hasReflectedReturnType) {
      expect(ceMethodMirror.reflectedReturnType, num);
    } else {
      expect(() => ceMethodMirror.reflectedReturnType, throwsUnsupportedError);
    }
  });

  test('Generic mixin, named super of generic class', () {
    ClassMirror dMirror = reflector.reflect(D<num>()).type as ClassMirror;
    DeclarationMirror deMirror = dMirror.instanceMembers['e']!;
    expect(deMirror, TypeMatcher<MethodMirror>());
    MethodMirror deMethodMirror = deMirror as MethodMirror;
    if (deMethodMirror.hasReflectedReturnType) {
      expect(deMethodMirror.reflectedReturnType, num);
    } else {
      expect(() => deMethodMirror.reflectedReturnType, throwsUnsupportedError);
    }
  });
}
