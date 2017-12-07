// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `typeRelations` capability.

library test_reflectable.test.type_relations_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'type_relations_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(superclassQuantifyCapability, typeRelationsCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class MyClass {}

main() {
  initializeReflectable();

  ClassMirror myClassMirror = myReflectable.reflectType(MyClass);
  ClassMirror classObjectMirror = myClassMirror.superclass;
  test('superclass targetting un-annotated class', () {
    expect(classObjectMirror.simpleName, "Object");
  });
  test('non-existing superclass', () {
    expect(classObjectMirror.superclass, null);
  });
  // TODO(eernst) implement: add missing cases for `typeRelationsCapability`:
  // typeVariables, typeArguments, originalDeclaration, isSubtypeOf,
  // isAssignableTo, superClass, superInterfaces, mixin, isSubclassOf,
  // upperBound, and referent.
}
