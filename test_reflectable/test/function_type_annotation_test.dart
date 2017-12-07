// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses a function type in type annotations.

@reflector
library test_reflectable.test.function_type_annotation_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'function_type_annotation_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(instanceInvokeCapability, topLevelInvokeCapability,
            declarationsCapability, reflectedTypeCapability, libraryCapability);
}

const reflector = const Reflector();

typedef int Int2IntFunc(int _);

Int2IntFunc int2int = (int x) => x;

@reflector
class C {
  Int2IntFunc get getter => int2int;
  void set setter(Int2IntFunc int2int) {}
  void method(int noNameType(int _), {Int2IntFunc int2int: null}) {}
}

main() {
  initializeReflectable();

  LibraryMirror libraryMirror = reflector
      .findLibrary("test_reflectable.test.function_type_annotation_test");
  VariableMirror variableMirror = libraryMirror.declarations["int2int"];
  ClassMirror classMirror = reflector.reflectType(C);
  MethodMirror getterMirror = classMirror.declarations["getter"];
  MethodMirror setterMirror = classMirror.declarations["setter="];
  MethodMirror methodMirror = classMirror.declarations["method"];
  ParameterMirror setterArgumentMirror = setterMirror.parameters[0];
  ParameterMirror methodArgument0Mirror = methodMirror.parameters[0];
  ParameterMirror methodArgument1Mirror = methodMirror.parameters[1];

  test('Function type as annotation', () {
    expect(variableMirror.hasReflectedType, true);
    expect(variableMirror.reflectedType, Int2IntFunc);
    expect(getterMirror.hasReflectedReturnType, true);
    expect(getterMirror.reflectedReturnType, Int2IntFunc);
    expect(setterArgumentMirror.hasReflectedType, true);
    expect(setterArgumentMirror.reflectedType, Int2IntFunc);
    expect(methodArgument1Mirror.hasReflectedType, true);
    expect(methodArgument1Mirror.reflectedType, Int2IntFunc);
    expect(variableMirror.hasDynamicReflectedType, true);
    expect(variableMirror.dynamicReflectedType, Int2IntFunc);
    expect(getterMirror.hasDynamicReflectedReturnType, true);
    expect(getterMirror.dynamicReflectedReturnType, Int2IntFunc);
    expect(setterArgumentMirror.hasDynamicReflectedType, true);
    expect(setterArgumentMirror.dynamicReflectedType, Int2IntFunc);
    expect(methodArgument1Mirror.hasDynamicReflectedType, true);
    expect(methodArgument1Mirror.dynamicReflectedType, Int2IntFunc);

    // A nameless function type currently does not have a reflected type:
    // Even though we could generate such a thing it would only be known to
    // be different from other types --- programmers cannot denote it, so they
    // cannot perform a test whereby it is recognized as equal to anything.
    // Hence, a function type should have a `typedef` in order to have a
    // reflected type.
    expect(methodArgument0Mirror.hasReflectedType, false);
    expect(methodArgument0Mirror.hasDynamicReflectedType, false);
  });
}
