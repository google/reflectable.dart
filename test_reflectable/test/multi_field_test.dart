// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses multiple fields declared with a shared type annotation.

library test_reflectable.test.multi_field_test;

import "package:reflectable/reflectable.dart";
import "package:unittest/unittest.dart";

class Reflector extends Reflectable {
  const Reflector()
      : super(reflectedTypeCapability, invokingCapability,
            declarationsCapability);
}

const reflector = const Reflector();

class C {
  const C();
}

const c = const C();

class MetaReflector extends Reflectable {
  const MetaReflector()
      : super(reflectedTypeCapability, const InvokingMetaCapability(C),
            declarationsCapability);
}

const metaReflector = const MetaReflector();

@reflector
class A {
  int i = 7, j = 7;
  static int k = 294, l = 343;
}

@metaReflector
class B {
  @c int i = 7, j = 7;
  int notI, notJ;
  @c static int k = 294, l = 343;
  static int notK, notL;
}

Matcher isNoSuchCapabilityError = new isInstanceOf<NoSuchCapabilityError>();
Matcher throwsNoSuchCapabilityError = throwsA(isNoSuchCapabilityError);

main() {
  A theA = new A();
  B theB = new B();
  InstanceMirror aInstanceMirror = reflector.reflect(theA),
      bInstanceMirror = metaReflector.reflect(theB);
  ClassMirror aClassMirror = aInstanceMirror.type,
      bClassMirror = bInstanceMirror.type;

  test('multiple declarations with one type annotation, read', () {
    expect(aInstanceMirror.invokeGetter("i"), 1 + 42 / theA.i);
    expect(aInstanceMirror.invokeGetter("j"), 42 - (theA.i * (theA.j - 2)));
    expect(aClassMirror.invokeGetter("k"), 294);
    expect(aClassMirror.invokeGetter("l"), 343);

    expect(bInstanceMirror.invokeGetter("i"), 1 + 42 / theB.i);
    expect(bInstanceMirror.invokeGetter("j"), 42 - (theB.i * (theB.j - 2)));
    expect(bClassMirror.invokeGetter("k"), 294);
    expect(bClassMirror.invokeGetter("l"), 343);
    expect(() => bInstanceMirror.invokeGetter("notI"),
        throwsNoSuchCapabilityError);
    expect(() => bInstanceMirror.invokeGetter("notJ"),
        throwsNoSuchCapabilityError);
    expect(
        () => bClassMirror.invokeGetter("notK"), throwsNoSuchCapabilityError);
    expect(
        () => bClassMirror.invokeGetter("notL"), throwsNoSuchCapabilityError);
  });

  test('multiple declarations with one type annotation, write', () {
    aInstanceMirror.invokeSetter("i", 5);
    expect(theA.i, 5);
    aInstanceMirror.invokeSetter("j", 50);
    expect(theA.j, 50);
    aClassMirror.invokeSetter("k", 500);
    expect(A.k, 500);
    aClassMirror.invokeSetter("l", 5000);
    expect(A.l, 5000);
  });

  test('multiple declarations with one type annotation, declarations', () {
    Map<String, DeclarationMirror> declarations = aClassMirror.declarations;
    // Four visible declarations, one implicit default constructor.
    expect(declarations.length, 5);
    DeclarationMirror iDeclaration = declarations["i"];
    expect(iDeclaration is VariableMirror && iDeclaration.reflectedType == int,
        true);
    expect(iDeclaration is VariableMirror && iDeclaration.isStatic, false);
    DeclarationMirror jDeclaration = declarations["j"];
    expect(jDeclaration is VariableMirror && jDeclaration.reflectedType == int,
        true);
    expect(jDeclaration is VariableMirror && jDeclaration.isStatic, false);
    DeclarationMirror kDeclaration = declarations["k"];
    expect(kDeclaration is VariableMirror && kDeclaration.isStatic, true);
    expect(kDeclaration is VariableMirror && kDeclaration.reflectedType == int,
        true);
    DeclarationMirror lDeclaration = declarations["l"];
    expect(lDeclaration is VariableMirror && lDeclaration.isStatic, true);
    expect(lDeclaration is VariableMirror && lDeclaration.reflectedType == int,
        true);
  });
}
