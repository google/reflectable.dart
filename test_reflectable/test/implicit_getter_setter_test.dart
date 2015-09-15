// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Explores properties of implicit getters and setters.

library test_reflectable.test.implicit_getter_setter_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(declarationsCapability, const InvokingCapability("f"));
}

const reflector = const Reflector();

@reflector
class A {
  A f1;
  final A f2;
  static A f3;
  static final A f4 = new A(null);
  static const f5 = 542;
  A(this.f2);
}

main() {
  ClassMirror classMirror = reflector.reflectType(A);

  test("implicit getter properties", () {
    MethodMirror f1GetterMirror = classMirror.instanceMembers["f1"];
    expect(f1GetterMirror.simpleName, "f1");
    expect(f1GetterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f1");
    expect(f1GetterMirror.isPrivate, isFalse);
    expect(f1GetterMirror.isTopLevel, isFalse);
    expect(f1GetterMirror.returnType.reflectedType, A);
    expect(f1GetterMirror.isStatic, isFalse);
    expect(f1GetterMirror.isAbstract, isFalse);
    expect(f1GetterMirror.isSynthetic, isTrue);
    expect(f1GetterMirror.isRegularMethod, isFalse);
    expect(f1GetterMirror.isOperator, isFalse);
    expect(f1GetterMirror.isGetter, isTrue);
    expect(f1GetterMirror.isSetter, isFalse);
    expect(f1GetterMirror.isConstructor, isFalse);
    expect(f1GetterMirror.constructorName, "");
    expect(f1GetterMirror.isConstConstructor, isFalse);
    expect(f1GetterMirror.isGenerativeConstructor, isFalse);
    expect(f1GetterMirror.isRedirectingConstructor, isFalse);
    expect(f1GetterMirror.isFactoryConstructor, isFalse);
    expect(f1GetterMirror.parameters.length, 0);
    expect(f1GetterMirror.owner, classMirror);

    MethodMirror f2getterMirror = classMirror.instanceMembers["f2"];
    expect(f2getterMirror.simpleName, "f2");
    expect(f2getterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f2");
    expect(f2getterMirror.isPrivate, isFalse);
    expect(f2getterMirror.isTopLevel, isFalse);
    expect(f2getterMirror.returnType.reflectedType, A);
    expect(f2getterMirror.isStatic, isFalse);
    expect(f2getterMirror.isAbstract, isFalse);
    expect(f2getterMirror.isSynthetic, isTrue);
    expect(f2getterMirror.isRegularMethod, isFalse);
    expect(f2getterMirror.isOperator, isFalse);
    expect(f2getterMirror.isGetter, isTrue);
    expect(f2getterMirror.isSetter, isFalse);
    expect(f2getterMirror.isConstructor, isFalse);
    expect(f2getterMirror.constructorName, "");
    expect(f2getterMirror.isConstConstructor, isFalse);
    expect(f2getterMirror.isGenerativeConstructor, isFalse);
    expect(f2getterMirror.isRedirectingConstructor, isFalse);
    expect(f2getterMirror.isFactoryConstructor, isFalse);
    expect(f2getterMirror.parameters.length, 0);
    expect(f2getterMirror.owner, classMirror);

    MethodMirror f3GetterMirror = classMirror.staticMembers["f3"];
    expect(f3GetterMirror.simpleName, "f3");
    expect(f3GetterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f3");
    expect(f3GetterMirror.isPrivate, isFalse);
    expect(f3GetterMirror.isTopLevel, isFalse);
    expect(f3GetterMirror.returnType.reflectedType, A);
    expect(f3GetterMirror.isStatic, isTrue);
    expect(f3GetterMirror.isAbstract, isFalse);
    expect(f3GetterMirror.isSynthetic, isTrue);
    expect(f3GetterMirror.isRegularMethod, isFalse);
    expect(f3GetterMirror.isOperator, isFalse);
    expect(f3GetterMirror.isGetter, isTrue);
    expect(f3GetterMirror.isSetter, isFalse);
    expect(f3GetterMirror.isConstructor, isFalse);
    expect(f3GetterMirror.constructorName, "");
    expect(f3GetterMirror.isConstConstructor, isFalse);
    expect(f3GetterMirror.isGenerativeConstructor, isFalse);
    expect(f3GetterMirror.isRedirectingConstructor, isFalse);
    expect(f3GetterMirror.isFactoryConstructor, isFalse);
    expect(f3GetterMirror.parameters.length, 0);
    expect(f3GetterMirror.owner, classMirror);

    MethodMirror f4GetterMirror = classMirror.staticMembers["f4"];
    expect(f4GetterMirror.simpleName, "f4");
    expect(f4GetterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f4");
    expect(f4GetterMirror.isPrivate, isFalse);
    expect(f4GetterMirror.isTopLevel, isFalse);
    expect(f4GetterMirror.returnType.reflectedType, A);
    expect(f4GetterMirror.isStatic, isTrue);
    expect(f4GetterMirror.isAbstract, isFalse);
    expect(f4GetterMirror.isSynthetic, isTrue);
    expect(f4GetterMirror.isRegularMethod, isFalse);
    expect(f4GetterMirror.isOperator, isFalse);
    expect(f4GetterMirror.isGetter, isTrue);
    expect(f4GetterMirror.isSetter, isFalse);
    expect(f4GetterMirror.isConstructor, isFalse);
    expect(f4GetterMirror.constructorName, "");
    expect(f4GetterMirror.isConstConstructor, isFalse);
    expect(f4GetterMirror.isGenerativeConstructor, isFalse);
    expect(f4GetterMirror.isRedirectingConstructor, isFalse);
    expect(f4GetterMirror.isFactoryConstructor, isFalse);
    expect(f4GetterMirror.parameters.length, 0);
    expect(f4GetterMirror.owner, classMirror);

    MethodMirror f5GetterMirror = classMirror.staticMembers["f5"];
    expect(f5GetterMirror.simpleName, "f5");
    expect(f5GetterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f5");
    expect(f5GetterMirror.isPrivate, isFalse);
    expect(f5GetterMirror.isTopLevel, isFalse);
    expect(f5GetterMirror.returnType.reflectedType, dynamic);
    expect(f5GetterMirror.isStatic, isTrue);
    expect(f5GetterMirror.isAbstract, isFalse);
    expect(f5GetterMirror.isSynthetic, isTrue);
    expect(f5GetterMirror.isRegularMethod, isFalse);
    expect(f5GetterMirror.isOperator, isFalse);
    expect(f5GetterMirror.isGetter, isTrue);
    expect(f5GetterMirror.isSetter, isFalse);
    expect(f5GetterMirror.isConstructor, isFalse);
    expect(f5GetterMirror.constructorName, "");
    expect(f5GetterMirror.isConstConstructor, isFalse);
    expect(f5GetterMirror.isGenerativeConstructor, isFalse);
    expect(f5GetterMirror.isRedirectingConstructor, isFalse);
    expect(f5GetterMirror.isFactoryConstructor, isFalse);
    expect(f5GetterMirror.parameters.length, 0);
    expect(f5GetterMirror.owner, classMirror);
  });

  test("implicit setter properties", () {
    MethodMirror f1SetterMirror = classMirror.instanceMembers["f1="];
    expect(f1SetterMirror.simpleName, "f1=");
    expect(f1SetterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f1=");
    expect(f1SetterMirror.isPrivate, isFalse);
    expect(f1SetterMirror.isTopLevel, isFalse);
    expect(f1SetterMirror.returnType.reflectedType, A);
    expect(f1SetterMirror.isStatic, isFalse);
    expect(f1SetterMirror.isAbstract, isFalse);
    expect(f1SetterMirror.isSynthetic, isTrue);
    expect(f1SetterMirror.isRegularMethod, isFalse);
    expect(f1SetterMirror.isOperator, isFalse);
    expect(f1SetterMirror.isGetter, isFalse);
    expect(f1SetterMirror.isSetter, isTrue);
    expect(f1SetterMirror.isConstructor, isFalse);
    expect(f1SetterMirror.constructorName, "");
    expect(f1SetterMirror.isConstConstructor, isFalse);
    expect(f1SetterMirror.isGenerativeConstructor, isFalse);
    expect(f1SetterMirror.isRedirectingConstructor, isFalse);
    expect(f1SetterMirror.isFactoryConstructor, isFalse);
    expect(f1SetterMirror.owner, classMirror);
    expect(f1SetterMirror.parameters.length, 1);
    expect(f1SetterMirror.parameters[0].simpleName, "f1");
    expect(f1SetterMirror.parameters[0].type.reflectedType, A);
    expect(f1SetterMirror.parameters[0].owner, f1SetterMirror);

    expect(classMirror.instanceMembers["f2="], null);

    MethodMirror f3SetterMirror = classMirror.staticMembers["f3="];
    expect(f3SetterMirror.simpleName, "f3=");
    expect(f3SetterMirror.qualifiedName,
        "test_reflectable.test.implicit_getter_setter_test.A.f3=");
    expect(f3SetterMirror.isPrivate, isFalse);
    expect(f3SetterMirror.isTopLevel, isFalse);
    expect(f3SetterMirror.returnType.reflectedType, A);
    expect(f3SetterMirror.isStatic, isTrue);
    expect(f3SetterMirror.isAbstract, isFalse);
    expect(f3SetterMirror.isSynthetic, isTrue);
    expect(f3SetterMirror.isRegularMethod, isFalse);
    expect(f3SetterMirror.isOperator, isFalse);
    expect(f3SetterMirror.isGetter, isFalse);
    expect(f3SetterMirror.isSetter, isTrue);
    expect(f3SetterMirror.isConstructor, isFalse);
    expect(f3SetterMirror.constructorName, "");
    expect(f3SetterMirror.isConstConstructor, isFalse);
    expect(f3SetterMirror.isGenerativeConstructor, isFalse);
    expect(f3SetterMirror.isRedirectingConstructor, isFalse);
    expect(f3SetterMirror.isFactoryConstructor, isFalse);
    expect(f3SetterMirror.owner, classMirror);
    expect(f3SetterMirror.parameters.length, 1);
    expect(f3SetterMirror.parameters[0].type.reflectedType, A);
    expect(f3SetterMirror.parameters[0].owner, f3SetterMirror);

    expect(classMirror.staticMembers["f4="], null);

    expect(classMirror.staticMembers["f5="], null);
  });
}
