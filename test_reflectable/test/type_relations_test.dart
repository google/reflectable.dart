// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `typeRelations` capability.

library test_reflectable.test.type_relations_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(typeRelationsCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class MyClass {}

main() {
  var typeMirror = myReflectable.reflectType(MyClass);
  ClassMirror classObjectMirror = typeMirror.superclass;
  test('superclass targetting un-annotated class', () {
    expect(classObjectMirror.simpleName, "Object");
  });
  print(classObjectMirror.superclass); // DEBUG
  test('non-existing superclass', () {
    expect(classObjectMirror.superclass, null);
  });
  // TODO(eernst): add missing cases covered by `typeRelationsCapability`:
  // typeVariables, typeArguments, originalDeclaration, isSubtypeOf,
  // isAssignableTo, superClass, superInterfaces, mixin, isSubclassOf,
  // upperBound, and referent.
}
