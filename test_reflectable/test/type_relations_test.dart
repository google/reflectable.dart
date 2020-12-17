// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses `typeRelations` capability.

library test_reflectable.test.type_relations_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'type_relations_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(superclassQuantifyCapability, typeRelationsCapability);
}

const myReflectable = MyReflectable();

@myReflectable
class MyClass {}

void main() {
  initializeReflectable();

  var myClassMirror = myReflectable.reflectType(MyClass) as ClassMirror;
  ClassMirror classObjectMirror = myClassMirror.superclass;
  test('superclass targetting un-annotated class', () {
    expect(classObjectMirror.simpleName, 'Object');
  });
  test('non-existing superclass', () {
    expect(classObjectMirror.superclass, null);
  });
  // TODO(eernst) implement: add missing cases for `typeRelationsCapability`:
  // typeVariables, typeArguments, originalDeclaration, isSubtypeOf,
  // isAssignableTo, superClass, superInterfaces, mixin, isSubclassOf,
  // upperBound, and referent.
}
