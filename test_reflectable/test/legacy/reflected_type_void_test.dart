// Copyright (c) 2020, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

// File used to test reflectable code generation.
// Uses `reflectedType` to access a `Type` value reifying `void`.

// ignore_for_file: omit_local_variable_types

library test_reflectable.test.reflect_type_void;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'reflected_type_void_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(reflectedTypeCapability, invokingCapability,
            declarationsCapability);
}

const reflector = Reflector();

@reflector
class A {
  void m(void a1, List<void> a2) {}
}

void main() {
  initializeReflectable();

  ClassMirror aMirror = reflector.reflectType(A);
  Map<String, DeclarationMirror> declarations = aMirror.declarations;
  MethodMirror mMirror = declarations['m'];

  test('Reflecting types involving `void`', () {
    expect(mMirror.parameters[0].hasReflectedType, true);
    expect(mMirror.parameters[0].reflectedType, const TypeValue<void>().type);
    expect(mMirror.parameters[1].hasReflectedType, true);
    expect(mMirror.parameters[1].reflectedType,
        const TypeValue<List<void>>().type);
    expect(mMirror.hasReflectedReturnType, true);
    expect(mMirror.reflectedReturnType, const TypeValue<void>().type);
  });
}
