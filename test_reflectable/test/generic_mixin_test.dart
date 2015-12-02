// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses a generic mixin.

library test_reflectable.test.generic_mixin_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(
            typeCapability, instanceInvokeCapability, reflectedTypeCapability);
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

main() {
  test('Generic mixin, instances', () {
    InstanceMirror instanceMirror = reflector.reflect(new B());
    expect(instanceMirror.invokeGetter("e"), null);
  });

  test('Generic mixin, classes', () {
    ClassMirror classMirror = reflector.reflectType(B);
    DeclarationMirror eMirror = classMirror.instanceMembers['e'];
    expect(eMirror, new isInstanceOf<MethodMirror>());
    MethodMirror eMethodMirror = eMirror;
    if (eMethodMirror.hasReflectedReturnType) {
      expect(eMethodMirror.reflectedReturnType, int);
    } else {
      expect(() => eMethodMirror.reflectedReturnType, throwsUnsupportedError);
    }
  });
}
