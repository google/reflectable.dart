// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses class properties such as `isEnum`, `isOriginalDeclaration`, etc.

@reflector
library test_reflectable.test.class_property_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(
            libraryCapability, declarationsCapability, typeRelationsCapability);
}

const Reflector reflector = const Reflector();

@reflector
abstract class A {}

@reflector
class _B {}

final justToAvoidUnused_B = new _B();

@reflector
enum C { monday, tuesday, otherDays }

@reflector
class D<X> {}

main() {
  LibraryMirror libraryMirror =
      reflector.findLibrary("test_reflectable.test.class_property_test");
  ClassMirror aMirror = libraryMirror.declarations["A"];
  ClassMirror bMirror = libraryMirror.declarations["_B"];
  ClassMirror cMirror = libraryMirror.declarations["C"];
  ClassMirror dMirror = libraryMirror.declarations["D"];
  D<int> dOfInt = new D<int>();
  InstanceMirror dOfIntInstanceMirror = reflector.reflect(dOfInt);
  ClassMirror dOfIntMirror = dOfIntInstanceMirror.type;

  test('isAbstract', () {
    expect(aMirror.isAbstract, true);
    expect(bMirror.isAbstract, false);
    expect(cMirror.isAbstract, false);
    expect(dMirror.isAbstract, false);
    expect(dOfIntMirror.isAbstract, false);
  });
  test('isPrivate', () {
    expect(aMirror.isPrivate, false);
    expect(bMirror.isPrivate, true);
    expect(cMirror.isPrivate, false);
    expect(dMirror.isPrivate, false);
    expect(dOfIntMirror.isPrivate, false);
  });
  test('hasReflectedType', () {
    expect(aMirror.hasReflectedType, true);
    expect(bMirror.hasReflectedType, true);
    expect(cMirror.hasReflectedType, true);
    expect(dMirror.hasReflectedType, false);
    expect(dOfIntMirror.hasReflectedType, true);
  });
  test('isTopLevel', () {
    expect(aMirror.isTopLevel, true);
    expect(bMirror.isTopLevel, true);
    expect(cMirror.isTopLevel, true);
    expect(dMirror.isTopLevel, true);
    expect(dOfIntMirror.isTopLevel, true);
  });
  test('isEnum', () {
    expect(aMirror.isEnum, false);
    expect(bMirror.isEnum, false);
    expect(cMirror.isEnum, true);
    expect(dMirror.isEnum, false);
    expect(dOfIntMirror.isEnum, false);
  });
  test('isOriginalDeclaration', () {
    expect(aMirror.isOriginalDeclaration, true);
    expect(bMirror.isOriginalDeclaration, true);
    expect(cMirror.isOriginalDeclaration, true);
    expect(dMirror.isOriginalDeclaration, true);
    expect(dOfIntMirror.isOriginalDeclaration, false);
  });
}
