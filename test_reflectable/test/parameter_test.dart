// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Accesses method parameters and their properties, such as
// existence, being optional, type annotations; includes checks
// concerning method return types.

// Note that this test gives rise to about 30 warnings, because the
// quantification requested includes a `reflectedType` for some types
// containing type variables. Apart from the fact that `reflectedType`
// for the parameter of `add` on a `List` will then return `dynamic`
// rather than the actual value of `E`, this does not prevent code
// generation from completing, and it does not invalidate any other
// feature. It may thus be an acceptable trade-off in some situations,
// if we need the reflectedType for a few thousand type annotations,
// and we don't want to enumerate them one by one.

library test_reflectable.test.parameter_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'parameter_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

// TODO(eernst) implement: Avoid testing the same things twice in this test and
// in 'parameter_mirrors_test.dart'.

class Reflector extends Reflectable {
  const Reflector()
      : super(
            typeAnnotationQuantifyCapability,
            invokingCapability,
            declarationsCapability,
            reflectedTypeCapability,
            typeRelationsCapability);
}

const reflector = Reflector();

class DeepReflector extends Reflectable {
  const DeepReflector()
      : super(
            typeAnnotationDeepQuantifyCapability,
            invokingCapability,
            declarationsCapability,
            reflectedTypeCapability,
            typeRelationsCapability);
}

const deepReflector = DeepReflector();

class C {}

@reflector
@deepReflector
class MyClass {
  int? arg0() => null;
  int arg1(int x) => 0;
  int? arg2to4(MyClass x, int y, [Reflector? z, w = 41.99999999]) => null;
  int argNamed(int x, y, {num? z}) => 0;

  int? operator +(int x) => null;
  int operator [](int x) => 0;
  void operator []=(int x, v) {}

  String get getset => '42';
  set getset(String string) {}

  static int? noArguments() => null;
  static int oneArgument(String x) => 0;
  static int? optionalArguments(MyClass x, double y,
          [Reflector? z, dynamic w = 42]) =>
      null;

  // ignore: prefer_adjacent_string_concatenation
  static int namedArguments(String x, List y, {String z = '4' + '2'}) => 0;

  static List<List<List<C>>> get staticGetset => [];
  static set staticGetset(List<List<List<C>>> list) {}
}

class UnrelatedClass {}

final throwsNoCapability = throwsA(const TypeMatcher<NoSuchCapabilityError>());

void performTests(String message, Reflectable reflector) {
  var myClassMirror = reflector.reflectType(MyClass) as ClassMirror;
  Map<String, DeclarationMirror> declarations = myClassMirror.declarations;

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
  var optionalArgumentsMirror = declarations['optionalArguments']
      as MethodMirror;
  var namedArgumentsMirror = declarations['namedArguments'] as MethodMirror;
  var staticGetsetMirror = declarations['staticGetset'] as MethodMirror;
  var staticGetsetEqualsMirror = declarations['staticGetset='] as MethodMirror;

  test('$message reflector: parameter list properties, instance methods', () {
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
    expect(arg2to4Parameter2.type.reflectedType, Reflector);
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

  test('$message reflector: parameter list properties, operators', () {
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

  test('$message reflector: parameter list properties, getters and setters',
      () {
    expect(getsetMirror.parameters.length, 0);
    expect(getsetEqualsMirror.parameters.length, 1);
    ParameterMirror getsetEqualsParameter0 = getsetEqualsMirror.parameters[0];
    expect(getsetEqualsParameter0.isOptional, false);
    expect(getsetEqualsParameter0.type.reflectedType, String);
  });

  test('$message reflector: parameter list properties, static methods', () {
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
    expect(optionalArgumentsParameter2.type.reflectedType, Reflector);
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
    TypeMirror namedArgumentsType1 = namedArgumentsParameter1.type;
    TypeMirror namedArgumentsClass1 = namedArgumentsType1.originalDeclaration;
    expect(namedArgumentsParameter0.isOptional, false);
    expect(namedArgumentsParameter0.type.reflectedType, String);
    expect(namedArgumentsParameter1.isOptional, false);
    expect(namedArgumentsType1.isOriginalDeclaration, false);
    expect(namedArgumentsType1.hasReflectedType, true);
    expect(namedArgumentsClass1.simpleName, 'List');
    expect(namedArgumentsParameter2.isOptional, true);
    expect(namedArgumentsParameter2.isNamed, true);
    expect(namedArgumentsParameter2.type.reflectedType, String);
    expect(namedArgumentsParameter2.hasDefaultValue, true);
    expect(namedArgumentsParameter2.defaultValue, '42');
  });

  test('$message reflector: parameter list properties, getters and setters',
      () {
    expect(staticGetsetMirror.parameters.length, 0);
    expect(staticGetsetEqualsMirror.parameters.length, 1);
    ParameterMirror staticGetsetEqualsParameter0 =
        staticGetsetEqualsMirror.parameters[0];
    TypeMirror staticGetsetEqualsType0 = staticGetsetEqualsParameter0.type;
    expect(staticGetsetEqualsParameter0.isOptional, false);
    expect(staticGetsetEqualsType0.isOriginalDeclaration, false);
    expect(staticGetsetEqualsType0.originalDeclaration.simpleName, 'List');
  });

  test('$message reflector: method return types', () {
    expect(arg0Mirror.returnType.reflectedType, int);
    expect(arg1Mirror.returnType.reflectedType, int);
    expect(arg2to4Mirror.returnType.reflectedType, int);
    expect(argNamedMirror.returnType.reflectedType, int);
    expect(opPlusMirror.returnType.reflectedType, int);
    expect(opBracketMirror.returnType.reflectedType, int);
    // TODO(eernst) implement: Find a better way to test for the `void`
    // type other than looking at its name!
    expect(opBracketEqualsMirror.returnType.simpleName, 'void');
    expect(getsetMirror.returnType.reflectedType, String);
    expect(getsetEqualsMirror.returnType.simpleName, 'void');
    expect(getsetEqualsMirror.returnType.hasReflectedType, false);
    expect(noArgumentsMirror.returnType.reflectedType, int);
    expect(oneArgumentMirror.returnType.reflectedType, int);
    expect(optionalArgumentsMirror.returnType.reflectedType, int);
    expect(namedArgumentsMirror.returnType.reflectedType, int);
    TypeMirror staticGetsetReturnType = staticGetsetMirror.returnType;
    expect(staticGetsetReturnType.isOriginalDeclaration, false);
    expect(staticGetsetReturnType.originalDeclaration.simpleName, 'List');
    expect(staticGetsetEqualsMirror.returnType.simpleName, 'void');
  });
}

void main() {
  initializeReflectable();

  performTests('Shallow', reflector);
  performTests('Deep', deepReflector);

  test('Type annotation coverage', () {
    // A class used as a type annotation in [MyClass] is supported.
    expect(reflector.reflectType(int), isNotNull);
    expect(deepReflector.reflectType(int), isNotNull);
    // A class used as a type annotation in a class used as a type annotation
    // in [MyClass] is covered iff the reflector is transitive.
    expect(() => reflector.reflectType(Pattern), throwsNoCapability);
    expect(deepReflector.reflectType(Pattern), isNotNull);
    // An unrelated class is unsupported.
    expect(() => reflector.reflectType(UnrelatedClass), throwsNoCapability);
    expect(() => deepReflector.reflectType(UnrelatedClass), throwsNoCapability);
  });
}
