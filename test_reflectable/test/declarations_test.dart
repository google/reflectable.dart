// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test_reflectable.test.declarations_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'declarations_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(instanceInvokeCapability, newInstanceCapability,
            declarationsCapability);
}

// TODO(sigurdm) implement: Adapt this test when we support fields.

@Reflector()
abstract class A {
  A();
  A.redirecting() : this();
  factory A.factory() {
    return B();
  }
  const factory A.redirectingFactory() = B.c;
  const A.c();
  void foo() {}
  int get getter1 => 10;
  int get getter2;
  set setter1(x) => null;
  A operator +(Object other) {
    return this;
  }
}

@Reflector()
class B extends A {
  void bar() {}
  set setter2(x) => null;
  @override
  int get getter1 => 11;
  @override
  int get getter2 => 12;
  const B.c() : super.c();
  B();
}

void main() {
  initializeReflectable();

  const reflector = Reflector();
  var aMirror = reflector.reflectType(A) as ClassMirror;
  var bMirror = reflector.reflectType(B) as ClassMirror;
  Map<String, DeclarationMirror> declarationsA = aMirror.declarations;
  Map<String, DeclarationMirror> declarationsB = bMirror.declarations;

  test('declarations', () {
    expect(declarationsA.values.map((x) => x.simpleName), {
      'foo',
      'getter1',
      'getter2',
      'setter1=',
      '+',
      'A',
      'A.redirecting',
      'A.factory',
      'A.redirectingFactory',
      'A.c',
    });

    expect(declarationsB.values.map((x) => x.simpleName),
        {'bar', 'getter1', 'getter2', 'setter2=', 'B.c', 'B'});
  });

  test('MethodMirror properties', () {
    var foo = declarationsA['foo'] as MethodMirror;
    expect(foo.isRegularMethod, isTrue);
    expect(foo.isStatic, isFalse);
    expect(foo.isGetter, isFalse);
    expect(foo.isSetter, isFalse);
    expect(foo.isPrivate, isFalse);
    expect(foo.isAbstract, isFalse);
    expect(foo.isConstructor, isFalse);
    expect(foo.isGenerativeConstructor, isFalse);
    expect(foo.isFactoryConstructor, isFalse);
    expect(foo.isConstConstructor, isFalse);
    expect(foo.isRedirectingConstructor, isFalse);
    expect(foo.isOperator, isFalse);
    expect(foo.isSynthetic, isFalse);
    expect(foo.isTopLevel, isFalse);
    var getter2A = declarationsA['getter2'] as MethodMirror;
    expect(getter2A.isRegularMethod, isFalse);
    expect(getter2A.isStatic, isFalse);
    expect(getter2A.isGetter, isTrue);
    expect(getter2A.isSetter, isFalse);
    expect(getter2A.isPrivate, isFalse);
    expect(getter2A.isAbstract, isTrue);
    expect(getter2A.isConstructor, isFalse);
    expect(getter2A.isGenerativeConstructor, isFalse);
    expect(getter2A.isFactoryConstructor, isFalse);
    expect(getter2A.isConstConstructor, isFalse);
    expect(getter2A.isRedirectingConstructor, isFalse);
    expect(getter2A.isOperator, isFalse);
    expect(getter2A.isSynthetic, isFalse);
    expect(getter2A.isTopLevel, isFalse);
    var setter1 = declarationsA['setter1='] as MethodMirror;
    expect(setter1.isRegularMethod, isFalse);
    expect(setter1.isStatic, isFalse);
    expect(setter1.isGetter, isFalse);
    expect(setter1.isSetter, isTrue);
    expect(setter1.isPrivate, isFalse);
    expect(setter1.isAbstract, isFalse);
    expect(setter1.isOperator, isFalse);
    expect(setter1.isSynthetic, isFalse);
    var operatorPlus = declarationsA['+'] as MethodMirror;
    expect(operatorPlus.isRegularMethod, isTrue);
    expect(operatorPlus.isStatic, isFalse);
    expect(operatorPlus.isGetter, isFalse);
    expect(operatorPlus.isSetter, isFalse);
    expect(operatorPlus.isPrivate, isFalse);
    expect(operatorPlus.isAbstract, isFalse);
    expect(operatorPlus.isConstructor, isFalse);
    expect(operatorPlus.isOperator, isTrue);
    var constructorA = declarationsA['A'] as MethodMirror;
    expect(constructorA.isRegularMethod, isFalse);
    expect(constructorA.isStatic, isFalse);
    expect(constructorA.isGetter, isFalse);
    expect(constructorA.isSetter, isFalse);
    expect(constructorA.isPrivate, isFalse);
    expect(constructorA.isAbstract, isFalse);
    expect(constructorA.isConstructor, isTrue);
    expect(constructorA.isGenerativeConstructor, isTrue);
    expect(constructorA.isFactoryConstructor, isFalse);
    expect(constructorA.isConstConstructor, isFalse);
    expect(constructorA.isRedirectingConstructor, isFalse);
    expect(constructorA.isOperator, isFalse);
    expect(constructorA.isSynthetic, isFalse);
    expect(constructorA.isTopLevel, isFalse);
    var redirectingConstructorA =
        declarationsA['A.redirecting'] as MethodMirror;
    expect(redirectingConstructorA.isConstructor, isTrue);
    expect(redirectingConstructorA.isGenerativeConstructor, isTrue);
    expect(redirectingConstructorA.isFactoryConstructor, isFalse);
    expect(redirectingConstructorA.isConstConstructor, isFalse);
    expect(redirectingConstructorA.isRedirectingConstructor, isTrue);
    var factoryConstructorA = declarationsA['A.factory'] as MethodMirror;
    expect(factoryConstructorA.isConstructor, isTrue);
    expect(factoryConstructorA.isGenerativeConstructor, isFalse);
    expect(factoryConstructorA.isFactoryConstructor, isTrue);
    expect(factoryConstructorA.isConstConstructor, isFalse);
    expect(factoryConstructorA.isRedirectingConstructor, isFalse);
    var constConstructorA = declarationsA['A.c'] as MethodMirror;
    expect(constConstructorA.isConstructor, isTrue);
    expect(constConstructorA.isGenerativeConstructor, isTrue);
    expect(constConstructorA.isFactoryConstructor, isFalse);
    expect(constConstructorA.isConstConstructor, isTrue);
    expect(constConstructorA.isRedirectingConstructor, isFalse);
    var redirectingFactoryConstructorA =
        declarationsA['A.redirectingFactory'] as MethodMirror;
    expect(redirectingFactoryConstructorA.isConstructor, isTrue);
    expect(redirectingFactoryConstructorA.isGenerativeConstructor, isFalse);
    expect(redirectingFactoryConstructorA.isFactoryConstructor, isTrue);
    expect(redirectingFactoryConstructorA.isConstConstructor, isTrue);
    expect(redirectingFactoryConstructorA.isRedirectingConstructor, isTrue);
  });

  test('instanceMethods', () {
    var aMirror = reflector.reflectType(A) as ClassMirror;
    Map<String, DeclarationMirror> instanceMembersA = aMirror.instanceMembers;
    expect(instanceMembersA.values.map((x) => x.simpleName), {
      'toString',
      'hashCode',
      '==',
      'noSuchMethod',
      'runtimeType',
      'foo',
      'getter1',
      'setter1=',
      '+',
    });
    var bMirror = reflector.reflectType(B) as ClassMirror;
    Map<String, DeclarationMirror> instanceMembersB = bMirror.instanceMembers;
    expect(instanceMembersB.values.map((x) => x.simpleName), {
      'toString',
      'hashCode',
      '==',
      'noSuchMethod',
      'runtimeType',
      'foo',
      'bar',
      'getter1',
      'getter2',
      'setter1=',
      'setter2=',
      '+',
    });
  });
}
