// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// File being transformed by the reflectable transformer.
// Accesses the `typeArguments` of an anonymous mixin application.
//
// This test exists in order to provide a concrete case illustrating the
// issue 'https://github.com/dart-lang/sdk/issues/25344'. If it is decided
// that the correct behavior of `typeArguments` for anonymous mixin
// applications is as recommended there then this test can work, otherwise
// the test should be adjusted.

library test_reflectable.test.generic_mixin_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(typeRelationsCapability, instanceInvokeCapability,
            reflectedTypeCapability);
}

const reflector = const Reflector();

@reflector
class M<E> {
  E e;
}

@reflector
class A {}

@reflector
class B extends A with M<int> {}

@reflector
class C<E> extends A with M<E> {}

main() {
  test('Anonymous mixin application', () {
    ClassMirror bmMirror = reflector.reflectType(B).superclass;
    DeclarationMirror beMirror = bmMirror.instanceMembers['e'];
    expect(beMirror, new isInstanceOf<MethodMirror>());
    MethodMirror beMethodMirror = beMirror;
    if (beMethodMirror.hasReflectedReturnType) {
      expect(beMethodMirror.reflectedReturnType, int);
    } else {
      expect(() => beMethodMirror.reflectedReturnType, throwsUnsupportedError);
    }
    ClassMirror cMirror = reflector.reflectType(new C<A>().runtimeType);
    ClassMirror cmMirror = cMirror.superclass;
    expect(cMirror.typeArguments.length, 1);
    expect(cMirror.typeArguments[0].hasReflectedType, isTrue);
    expect(cMirror.typeArguments[0].reflectedType, num);
    expect(cmMirror.typeArguments.length, 1);
    expect(cmMirror.typeArguments[0].hasReflectedType, isTrue);
    expect(cmMirror.typeArguments[0].reflectedType, A);
    DeclarationMirror ceMirror = cmMirror.instanceMembers['e'];
    expect(ceMirror, new isInstanceOf<MethodMirror>());
    MethodMirror ceMethodMirror = ceMirror;
    if (ceMethodMirror.hasReflectedReturnType) {
      expect(ceMethodMirror.reflectedReturnType, A);
    } else {
      expect(() => ceMethodMirror.reflectedReturnType, throwsUnsupportedError);
    }
  });
}
