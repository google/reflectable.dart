// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `dynamicReflectedType`.

library test_reflectable.test.dynamic_reflected_type_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'dynamic_reflected_type_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

const reflector = const Reflector();

@reflector
class A {}

@reflector
class B<E> {}

Matcher throwsUnsupported = throwsA(const isInstanceOf<UnsupportedError>());

void testDynamicReflectedType(
    String message, ClassMirror classMirror, Type expectedType) {
  test('Dynamic reflected type, $message', () {
    if (classMirror.hasDynamicReflectedType) {
      expect(classMirror.dynamicReflectedType, expectedType);
    } else {
      expect(() => classMirror.dynamicReflectedType, throwsUnsupported);
    }
  });
}

main() {
  initializeReflectable();

  ClassMirror aMirror = reflector.reflectType(A);
  ClassMirror bMirror = reflector.reflectType(B);
  ClassMirror bInstantiationMirror = reflector.reflect(new B<int>()).type;
  testDynamicReflectedType('non-generic class', aMirror, A);
  testDynamicReflectedType('generic class', bMirror, B);
  testDynamicReflectedType('generic instantiation', bInstantiationMirror, B);
}
