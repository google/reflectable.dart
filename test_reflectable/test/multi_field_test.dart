// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses multiple fields declared with a shared type annotation.

library test_reflectable.test.multi_field_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'multi_field_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(reflectedTypeCapability, invokingCapability,
            declarationsCapability);
}

const reflector = Reflector();

class C {
  const C();
}

const c = C();

class MetaReflector extends Reflectable {
  const MetaReflector()
      : super(reflectedTypeCapability, const InvokingMetaCapability(C),
            declarationsCapability);
}

const metaReflector = MetaReflector();

@reflector
class A {
  int i = 7, j = 7;
  static int k = 294, l = 343;
}

@metaReflector
class B {
  @c
  int i = 7, j = 7;
  late int notI, notJ;
  @C()
  static int k = 294, l = 343;
  static late int notK, notL;
}

final Matcher throwsReflectableNoMethod =
    throwsA(TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  initializeReflectable();

  var theA = A();
  var theB = B();
  var aInstanceMirror = reflector.reflect(theA),
      bInstanceMirror = metaReflector.reflect(theB);
  var aClassMirror = aInstanceMirror.type, bClassMirror = bInstanceMirror.type;

  test('multiple declarations with one type annotation, read', () {
    expect(aInstanceMirror.invokeGetter('i'), 1 + 42 / theA.i);
    expect(aInstanceMirror.invokeGetter('j'), 42 - (theA.i * (theA.j - 2)));
    expect(aClassMirror.invokeGetter('k'), 294);
    expect(aClassMirror.invokeGetter('l'), 343);

    expect(bInstanceMirror.invokeGetter('i'), 1 + 42 / theB.i);
    expect(bInstanceMirror.invokeGetter('j'), 42 - (theB.i * (theB.j - 2)));
    expect(bClassMirror.invokeGetter('k'), 294);
    expect(bClassMirror.invokeGetter('l'), 343);
    expect(
        () => bInstanceMirror.invokeGetter('notI'), throwsReflectableNoMethod);
    expect(
        () => bInstanceMirror.invokeGetter('notJ'), throwsReflectableNoMethod);
    expect(() => bClassMirror.invokeGetter('notK'), throwsReflectableNoMethod);
    expect(() => bClassMirror.invokeGetter('notL'), throwsReflectableNoMethod);
  });

  test('multiple declarations with one type annotation, write', () {
    aInstanceMirror.invokeSetter('i', 5);
    expect(theA.i, 5);
    aInstanceMirror.invokeSetter('j', 50);
    expect(theA.j, 50);
    aClassMirror.invokeSetter('k', 500);
    expect(A.k, 500);
    aClassMirror.invokeSetter('l', 5000);
    expect(A.l, 5000);
  });

  test('multiple declarations with one type annotation, declarations', () {
    Map<String, DeclarationMirror> declarations = aClassMirror.declarations;
    // Four visible declarations, one implicit default constructor.
    expect(declarations.length, 5);
    var iDeclaration = declarations['i'];
    expect(iDeclaration is VariableMirror && iDeclaration.reflectedType == int,
        true);
    expect(iDeclaration is VariableMirror && iDeclaration.isStatic, false);
    var jDeclaration = declarations['j'];
    expect(jDeclaration is VariableMirror && jDeclaration.reflectedType == int,
        true);
    expect(jDeclaration is VariableMirror && jDeclaration.isStatic, false);
    var kDeclaration = declarations['k'];
    expect(kDeclaration is VariableMirror && kDeclaration.isStatic, true);
    expect(kDeclaration is VariableMirror && kDeclaration.reflectedType == int,
        true);
    var lDeclaration = declarations['l'];
    expect(lDeclaration is VariableMirror && lDeclaration.isStatic, true);
    expect(lDeclaration is VariableMirror && lDeclaration.reflectedType == int,
        true);
  });
}
