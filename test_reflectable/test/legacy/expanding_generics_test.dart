// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Checks that the occurrence of an expanding generic type (where
// class `C` takes one type argument `X` and uses `C<C<X>>` as a
// type annotation.

library test_reflectable.test.expanding_generics_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'expanding_generics_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

const reflector = Reflector();

@reflector
class C<X> {
  C<C<X>> get boom => null;
}

class Typer<X> { Type get type => X; }
final Type COfInt = Typer<C<int>>().type;

void runTest(String message, ClassMirror classMirror) {
  test('Obtain mirror for expanding generic $message', () {
    expect(classMirror, isNotNull);
    expect(classMirror.hasReflectedType, true);
    expect(classMirror.reflectedType, COfInt);
  });
}

void main() {
  initializeReflectable();

  test('Reject reflection directly on instantiated generic class', () {
    expect(reflector.canReflectType(COfInt), false);
  });
  var instanceMirror = reflector.reflect(C<int>());
  runTest('using `reflect`, then `type`.', instanceMirror.type);
}
