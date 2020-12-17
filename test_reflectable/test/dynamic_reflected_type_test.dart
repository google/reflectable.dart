// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses `dynamicReflectedType`.

library test_reflectable.test.dynamic_reflected_type_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'dynamic_reflected_type_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

const reflector = Reflector();

@reflector
class A {}

@reflector
class B<E> {}

Matcher throwsUnsupported = throwsA(const TypeMatcher<UnsupportedError>());

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

void main() {
  initializeReflectable();

  var aMirror = reflector.reflectType(A) as ClassMirror;
  var bMirror = reflector.reflectType(B) as ClassMirror;
  var bInstantiationMirror = reflector.reflect(B<int>()).type as ClassMirror;
  testDynamicReflectedType('non-generic class', aMirror, A);
  testDynamicReflectedType('generic class', bMirror, B);
  testDynamicReflectedType('generic instantiation', bInstantiationMirror, B);
}
