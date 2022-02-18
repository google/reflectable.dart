// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses a function type in type annotations.

@reflector
library test_reflectable.test.function_type_annotation_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'function_type_annotation_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(instanceInvokeCapability, topLevelInvokeCapability,
            declarationsCapability, reflectedTypeCapability, libraryCapability);
}

const reflector = Reflector();

typedef Int2IntFunc = int Function(int);

Int2IntFunc int2int = (int x) => x;

@reflector
class C {
  Int2IntFunc get getter => int2int;
  set setter(Int2IntFunc int2int) {}
  void method(int Function(int) noNameType, {required Int2IntFunc int2int}) {}

  void inlineTypes(
    int Function() f1,
    int Function(int) f2,
    int Function(int, int) f3,
    int Function(int, [int]) f4,
    int Function([int, int]) f5,
    int Function(int, [int, int]) f6,
    int Function(int, {int a}) f7,
    int Function({int a, int b}) f8,
    int Function(int, {int a, int b}) f9,
    X Function<X>(X) f10,
    X Function<X>(X, X) f11,
    X Function<X>(X, [X]) f12,
    X Function<X>([X, X]) f13,
    X Function<X>(X, [X, X]) f14,
    X Function<X>(X, {X a}) f15,
    X Function<X>({X a, X b}) f16,
    X Function<X>(X, {X a, X b}) f17,
  ) {}
}

typedef TypeF10 = X Function<X>(X);
typedef TypeF11 = X Function<X>(X, X);
typedef TypeF12 = X Function<X>(X, [X]);
typedef TypeF13 = X Function<X>([X, X]);
typedef TypeF14 = X Function<X>(X, [X, X]);
typedef TypeF15 = X Function<X>(X, {X a});
typedef TypeF16 = X Function<X>({X a, X b});
typedef TypeF17 = X Function<X>(X, {X a, X b});

void main() {
  initializeReflectable();

  LibraryMirror libraryMirror = reflector
      .findLibrary('test_reflectable.test.function_type_annotation_test');
  var variableMirror = libraryMirror.declarations['int2int'] as VariableMirror;
  var classMirror = reflector.reflectType(C) as ClassMirror;
  var getterMirror = classMirror.declarations['getter'] as MethodMirror;
  var setterMirror = classMirror.declarations['setter='] as MethodMirror;
  var methodMirror = classMirror.declarations['method'] as MethodMirror;
  var setterArgumentMirror = setterMirror.parameters[0];
  var methodArgument0Mirror = methodMirror.parameters[0];
  var methodArgument1Mirror = methodMirror.parameters[1];
  Type int2intType = const TypeValue<int Function(int)>().type;

  test('Using a function type as an annotation', () {
    expect(variableMirror.hasReflectedType, true);
    expect(variableMirror.reflectedType, int2intType);
    expect(getterMirror.hasReflectedReturnType, true);
    expect(getterMirror.reflectedReturnType, int2intType);
    expect(setterArgumentMirror.hasReflectedType, true);
    expect(setterArgumentMirror.reflectedType, int2intType);
    expect(methodArgument0Mirror.hasReflectedType, true);
    expect(methodArgument0Mirror.reflectedType, int2intType);
    expect(methodArgument1Mirror.hasReflectedType, true);
    expect(methodArgument1Mirror.reflectedType, int2intType);

    expect(variableMirror.hasDynamicReflectedType, true);
    expect(variableMirror.dynamicReflectedType, int2intType);
    expect(getterMirror.hasDynamicReflectedReturnType, true);
    expect(getterMirror.dynamicReflectedReturnType, int2intType);
    expect(setterArgumentMirror.hasDynamicReflectedType, true);
    expect(setterArgumentMirror.dynamicReflectedType, int2intType);
    expect(methodArgument0Mirror.hasDynamicReflectedType, true);
    expect(methodArgument0Mirror.dynamicReflectedType, int2intType);
    expect(methodArgument1Mirror.hasDynamicReflectedType, true);
    expect(methodArgument1Mirror.dynamicReflectedType, int2intType);
  });

  var inlineTypesMirror =
      classMirror.declarations['inlineTypes'] as MethodMirror;
  List<ParameterMirror> parameterMirrors = inlineTypesMirror.parameters;
  List<Type> expectedTypes = [
    TypeValue<int Function()>().type,
    TypeValue<int Function(int)>().type,
    TypeValue<int Function(int, int)>().type,
    TypeValue<int Function(int, [int])>().type,
    TypeValue<int Function([int, int])>().type,
    TypeValue<int Function(int, [int, int])>().type,
    TypeValue<int Function(int, {int a})>().type,
    TypeValue<int Function({int a, int b})>().type,
    TypeValue<int Function(int, {int a, int b})>().type,
    // The following types cannot be recognized (SDK issue #32625):
    // TypeF10, TypeF11, TypeF12, TypeF13, TypeF14, TypeF15, TypeF16, TypeF17
  ];

  test('Using different kinds of function types', () {
    for (ParameterMirror parameterMirror in parameterMirrors) {
      expect(parameterMirror.hasReflectedType, true);
    }
    for (int index = 0; index < expectedTypes.length; index++) {
      expect(parameterMirrors[index].reflectedType, expectedTypes[index]);
    }
  });
}
