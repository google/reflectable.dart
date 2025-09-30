// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses `reflectedType` to access a `Type` value for the type annotation
// of various declarations.

library test_reflectable.test.reflected_type_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'reflected_type_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
    : super(
        reflectedTypeCapability,
        invokingCapability,
        declarationsCapability,
      );
}

const reflector = Reflector();

@reflector
class A {
  int arg0() => 0;
  int? arg1(int x) => null;
  int arg2to4(A x, int y, [Reflector? z, w = 41.99999999]) => 0;
  int? argNamed(int x, y, {num? z}) => null;

  int operator +(int x) => 0;
  int? operator [](int x) => null;
  void operator []=(int x, v) {}

  String get getset => '42';
  set getset(String string) {}

  static int noArguments() => 0;
  static int? oneArgument(String x) => null;
  static int optionalArguments(A x, double y, [Reflector? z, dynamic w = 42]) =>
      0;

  // ignore: prefer_adjacent_string_concatenation
  static int? namedArguments(String x, List y, {String z = '4' + '2'}) => null;

  static List<String> get staticGetset => ['42'];
  static set staticGetset(List<String> list) {}
}

final throwsNoCapability = throwsA(const TypeMatcher<NoSuchCapabilityError>());

void main() {
  initializeReflectable();

  var aMirror = reflector.reflectType(A) as ClassMirror;
  Map<String, DeclarationMirror> declarations = aMirror.declarations;

  var arg0Mirror = declarations['arg0'] as MethodMirror;
  var arg1Mirror = declarations['arg1'] as MethodMirror;
  var arg2to4Mirror = declarations['arg2to4'] as MethodMirror;
  var argNamedMirror = declarations['argNamed'] as MethodMirror;
  var opPlusMirror = declarations['+'] as MethodMirror;
  var opBracketMirror = declarations['[]'] as MethodMirror;
  var opBracketEqualsMirror = declarations['[]='] as MethodMirror;
  var getsetMirror = declarations['getset'] as MethodMirror;
  var getsetEqualsMirror = declarations['getset='] as MethodMirror;
  var noArgumentsMirror = declarations['noArguments'] as MethodMirror;
  var oneArgumentMirror = declarations['oneArgument'] as MethodMirror;
  var optionalArgumentsMirror =
      declarations['optionalArguments'] as MethodMirror;
  var namedArgumentsMirror = declarations['namedArguments'] as MethodMirror;
  var staticGetsetMirror = declarations['staticGetset'] as MethodMirror;
  var staticGetsetEqualsMirror = declarations['staticGetset='] as MethodMirror;

  test('parameter reflected types, instance methods', () {
    expect(arg0Mirror.parameters.length, 0);

    expect(arg1Mirror.parameters.length, 1);
    expect(arg1Mirror.parameters[0].reflectedType, int);

    expect(arg2to4Mirror.parameters.length, 4);
    expect(arg2to4Mirror.parameters[0].reflectedType, A);
    expect(arg2to4Mirror.parameters[1].reflectedType, int);
    expect(arg2to4Mirror.parameters[2].reflectedType, Reflector);
    expect(arg2to4Mirror.parameters[3].reflectedType, dynamic);

    expect(argNamedMirror.parameters.length, 3);
    expect(argNamedMirror.parameters[0].reflectedType, int);
    expect(argNamedMirror.parameters[1].reflectedType, dynamic);
    expect(argNamedMirror.parameters[2].reflectedType, num);
  });

  test('parameter reflected types, operators', () {
    expect(opPlusMirror.parameters.length, 1);
    expect(opPlusMirror.parameters[0].reflectedType, int);

    expect(opBracketMirror.parameters.length, 1);
    expect(opBracketMirror.parameters[0].reflectedType, int);

    expect(opBracketEqualsMirror.parameters.length, 2);
    var opBracketEqualsParameter0 = opBracketEqualsMirror.parameters[0];
    var opBracketEqualsParameter1 = opBracketEqualsMirror.parameters[1];
    expect(opBracketEqualsParameter0.reflectedType, int);
    expect(opBracketEqualsParameter1.reflectedType, dynamic);
  });

  test('parameter reflected types, getters and setters', () {
    expect(getsetMirror.parameters.length, 0);
    expect(getsetEqualsMirror.parameters.length, 1);
    var getsetEqualsParameter0 = getsetEqualsMirror.parameters[0];
    expect(getsetEqualsParameter0.reflectedType, String);
  });

  test('parameter reflected types, static methods', () {
    expect(noArgumentsMirror.parameters.length, 0);

    expect(oneArgumentMirror.parameters.length, 1);
    expect(oneArgumentMirror.parameters[0].reflectedType, String);

    expect(optionalArgumentsMirror.parameters.length, 4);
    var optionalArgumentsParameter0 = optionalArgumentsMirror.parameters[0];
    var optionalArgumentsParameter1 = optionalArgumentsMirror.parameters[1];
    var optionalArgumentsParameter2 = optionalArgumentsMirror.parameters[2];
    var optionalArgumentsParameter3 = optionalArgumentsMirror.parameters[3];
    expect(optionalArgumentsParameter0.reflectedType, A);
    expect(optionalArgumentsParameter1.reflectedType, double);
    expect(optionalArgumentsParameter2.reflectedType, Reflector);
    expect(optionalArgumentsParameter3.reflectedType, dynamic);

    expect(namedArgumentsMirror.parameters.length, 3);
    var namedArgumentsParameter0 = namedArgumentsMirror.parameters[0];
    var namedArgumentsParameter1 = namedArgumentsMirror.parameters[1];
    var namedArgumentsParameter2 = namedArgumentsMirror.parameters[2];
    expect(namedArgumentsParameter0.reflectedType, String);
    expect(namedArgumentsParameter1.reflectedType, List);
    expect(namedArgumentsParameter2.reflectedType, String);
  });

  test('parameter reflected types, static getters and setters', () {
    expect(staticGetsetMirror.parameters.length, 0);
    expect(staticGetsetEqualsMirror.parameters.length, 1);
    var staticGetsetEqualsParameter0 = staticGetsetEqualsMirror.parameters[0];
    expect(
      staticGetsetEqualsParameter0.reflectedType,
      const TypeValue<List<String>>().type,
    );
  });

  test('reflected return types, methods', () {
    expect(arg0Mirror.hasReflectedReturnType, true);
    expect(arg0Mirror.reflectedReturnType, int);
    expect(arg1Mirror.hasReflectedReturnType, true);
    expect(arg1Mirror.reflectedReturnType, int);
    expect(arg2to4Mirror.hasReflectedReturnType, true);
    expect(arg2to4Mirror.reflectedReturnType, int);
    expect(argNamedMirror.hasReflectedReturnType, true);
    expect(argNamedMirror.reflectedReturnType, int);
    expect(opPlusMirror.hasReflectedReturnType, true);
    expect(opPlusMirror.reflectedReturnType, int);
    expect(opBracketMirror.hasReflectedReturnType, true);
    expect(opBracketMirror.reflectedReturnType, int);
    expect(opBracketEqualsMirror.hasReflectedReturnType, true);
    expect(
      opBracketEqualsMirror.reflectedReturnType,
      const TypeValue<void>().type,
    );
    expect(getsetMirror.hasReflectedReturnType, true);
    expect(getsetMirror.reflectedReturnType, String);
    expect(getsetEqualsMirror.hasReflectedReturnType, true);
    expect(
      getsetEqualsMirror.reflectedReturnType,
      const TypeValue<void>().type,
    );
    expect(noArgumentsMirror.hasReflectedReturnType, true);
    expect(noArgumentsMirror.reflectedReturnType, int);
    expect(oneArgumentMirror.hasReflectedReturnType, true);
    expect(oneArgumentMirror.reflectedReturnType, int);
    expect(optionalArgumentsMirror.hasReflectedReturnType, true);
    expect(optionalArgumentsMirror.reflectedReturnType, int);
    expect(namedArgumentsMirror.hasReflectedReturnType, true);
    expect(namedArgumentsMirror.reflectedReturnType, int);
    expect(staticGetsetMirror.hasReflectedReturnType, true);
    expect(
      staticGetsetMirror.reflectedReturnType,
      const TypeValue<List<String>>().type,
    );
    expect(staticGetsetEqualsMirror.hasReflectedReturnType, true);
    expect(
      staticGetsetEqualsMirror.reflectedReturnType,
      const TypeValue<void>().type,
    );
  });
}
