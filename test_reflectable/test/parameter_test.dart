// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Accesses method parameters and their properties, such as
// existence, being optional, type annotations.

library test_reflectable.test.parameter_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

// TODO(eernst) implement: Avoid testing the same things twice in this test and
// in 'parameter_mirrors_test.dart'.

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(typeCapability, invokingCapability, declarationsCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class MyClass {
  int arg0() => null;
  int arg1(int x) => null;
  int arg2to4(MyClass x, int y, [MyReflectable z, w = 41.99999999]) => null;
  int argNamed(int x, y, {num z}) => null;

  int operator +(int x) => null;
  int operator [](int x) => null;
  void operator []=(int x, v) {}

  static int noArguments() => null;
  static int oneArgument(String x) => null;
  static int optionalArguments(MyClass x, double y,
          [MyReflectable z, dynamic w = 42]) =>
      null;
  static int namedArguments(String x, List y, {String z: "4" + "2"}) => null;
}

final throwsNoCapability = throwsA(const isInstanceOf<NoSuchCapabilityError>());

main() {
  ClassMirror myClassMirror = myReflectable.reflectType(MyClass);
  Map<String, DeclarationMirror> declarations = myClassMirror.declarations;

  MethodMirror arg0Mirror = declarations["arg0"];
  MethodMirror arg1Mirror = declarations["arg1"];
  MethodMirror arg2to4Mirror = declarations["arg2to4"];
  MethodMirror argNamedMirror = declarations["argNamed"];
  MethodMirror opPlusMirror = declarations["+"];
  MethodMirror opBracketMirror = declarations["[]"];
  MethodMirror opBracketEqualsMirror = declarations["[]="];
  MethodMirror noArgumentsMirror = declarations["noArguments"];
  MethodMirror oneArgumentMirror = declarations["oneArgument"];
  MethodMirror optionalArgumentsMirror = declarations["optionalArguments"];
  MethodMirror namedArgumentsMirror = declarations["namedArguments"];

  test('parameter list properties, instance methods', () {
    expect(arg0Mirror.parameters.length, 0);

    expect(arg1Mirror.parameters.length, 1);
    ParameterMirror arg1Parameter0 = arg1Mirror.parameters[0];
    expect(arg1Parameter0.isOptional, false);
    expect(arg1Parameter0.isNamed, false);
    expect(arg1Parameter0.isStatic, false);
    expect(arg1Parameter0.isConst, false);
    expect(arg1Parameter0.isFinal, false);
    expect(arg1Parameter0.isPrivate, false);
    expect(arg1Parameter0.isTopLevel, false);

    expect(arg2to4Mirror.parameters.length, 4);
    ParameterMirror arg2to4Parameter0 = arg2to4Mirror.parameters[0];
    ParameterMirror arg2to4Parameter1 = arg2to4Mirror.parameters[1];
    ParameterMirror arg2to4Parameter2 = arg2to4Mirror.parameters[2];
    ParameterMirror arg2to4Parameter3 = arg2to4Mirror.parameters[3];
    expect(arg2to4Parameter0.isOptional, false);
    expect(arg2to4Parameter0.type.reflectedType, MyClass);
    expect(arg2to4Parameter1.isOptional, false);
    expect(arg2to4Parameter1.type.reflectedType, int);
    expect(arg2to4Parameter2.isOptional, true);
    expect(arg2to4Parameter2.isNamed, false);
    expect(arg2to4Parameter2.type.reflectedType, MyReflectable);
    expect(arg2to4Parameter3.isOptional, true);
    expect(arg2to4Parameter3.isNamed, false);
    expect(arg2to4Parameter3.type.reflectedType, dynamic);
    expect(arg2to4Parameter3.hasDefaultValue, true);
    expect(arg2to4Parameter3.defaultValue, 41.99999999);

    expect(argNamedMirror.parameters.length, 3);
    ParameterMirror argNamedParameter0 = argNamedMirror.parameters[0];
    ParameterMirror argNamedParameter1 = argNamedMirror.parameters[1];
    ParameterMirror argNamedParameter2 = argNamedMirror.parameters[2];
    expect(argNamedParameter0.isOptional, false);
    expect(argNamedParameter0.type.reflectedType, int);
    expect(argNamedParameter1.isOptional, false);
    expect(argNamedParameter1.type.reflectedType, dynamic);
    expect(argNamedParameter2.isOptional, true);
    expect(argNamedParameter2.isNamed, true);
    expect(argNamedParameter2.type.reflectedType, num);
    expect(argNamedParameter2.hasDefaultValue, false);
    expect(argNamedParameter2.defaultValue, null);
  });

  test('parameter list properties, operators', () {
    expect(opPlusMirror.parameters.length, 1);
    ParameterMirror opPlusParameter0 = opPlusMirror.parameters[0];
    expect(opPlusParameter0.isOptional, false);
    expect(opPlusParameter0.type.reflectedType, int);

    expect(opBracketMirror.parameters.length, 1);
    expect(opBracketMirror.parameters[0].isOptional, false);

    expect(opBracketEqualsMirror.parameters.length, 2);
    ParameterMirror opBracketEqualsParameter0 =
        opBracketEqualsMirror.parameters[0];
    ParameterMirror opBracketEqualsParameter1 =
        opBracketEqualsMirror.parameters[1];
    expect(opBracketEqualsParameter0.isOptional, false);
    expect(opBracketEqualsParameter0.type.reflectedType, int);
    expect(opBracketEqualsParameter1.isOptional, false);
    expect(opBracketEqualsParameter1.type.reflectedType, dynamic);
  });

  test('parameter list properties, static methods', () {
    expect(noArgumentsMirror.parameters.length, 0);

    expect(oneArgumentMirror.parameters.length, 1);
    expect(oneArgumentMirror.parameters[0].isOptional, false);

    expect(optionalArgumentsMirror.parameters.length, 4);
    ParameterMirror optionalArgumentsParameter0 =
        optionalArgumentsMirror.parameters[0];
    ParameterMirror optionalArgumentsParameter1 =
        optionalArgumentsMirror.parameters[1];
    ParameterMirror optionalArgumentsParameter2 =
        optionalArgumentsMirror.parameters[2];
    ParameterMirror optionalArgumentsParameter3 =
        optionalArgumentsMirror.parameters[3];
    expect(optionalArgumentsParameter0.isOptional, false);
    expect(optionalArgumentsParameter0.type.reflectedType, MyClass);
    expect(optionalArgumentsParameter1.isOptional, false);
    expect(optionalArgumentsParameter1.type.reflectedType, double);
    expect(optionalArgumentsParameter2.isOptional, true);
    expect(optionalArgumentsParameter2.isNamed, false);
    expect(optionalArgumentsParameter2.type.reflectedType, MyReflectable);
    expect(optionalArgumentsParameter3.isOptional, true);
    expect(optionalArgumentsParameter3.isNamed, false);
    expect(optionalArgumentsParameter3.type.reflectedType, dynamic);
    expect(optionalArgumentsParameter3.hasDefaultValue, true);
    expect(optionalArgumentsParameter3.defaultValue, 42);

    expect(namedArgumentsMirror.parameters.length, 3);
    ParameterMirror namedArgumentsParameter0 =
        namedArgumentsMirror.parameters[0];
    ParameterMirror namedArgumentsParameter1 =
        namedArgumentsMirror.parameters[1];
    ParameterMirror namedArgumentsParameter2 =
        namedArgumentsMirror.parameters[2];
    expect(namedArgumentsParameter0.isOptional, false);
    expect(namedArgumentsParameter0.type.reflectedType, String);
    expect(namedArgumentsParameter1.isOptional, false);
    expect(namedArgumentsParameter1.type.reflectedType, List);
    expect(namedArgumentsParameter2.isOptional, true);
    expect(namedArgumentsParameter2.isNamed, true);
    expect(namedArgumentsParameter2.type.reflectedType, String);
    expect(namedArgumentsParameter2.hasDefaultValue, true);
    expect(namedArgumentsParameter2.defaultValue, "42");
  });
}
