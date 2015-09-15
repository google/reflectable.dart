// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Checks that the occurrence of an expanding generic type (where
// class `C` takes one type argument `X` and uses `C<C<X>>` as a
// type annotation.

library test_reflectable.test.expanding_generics_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(declarationsCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class C<X> {
  C<C<X>> get boom => null;
}

class Typer<X> { Type get type => X; }
final Type COfInt = new Typer<C<int>>().type;

main() {
  test("Obtain a mirror for the expanding generic class", () {
    ClassMirror classMirror = myReflectable.reflectType(COfInt);
    expect(classMirror.hasReflectedType, true);
    expect(classMirror.reflectedType, COfInt);
  });
}
