// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses type relations without a `typeRelations` capability.

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'no_type_relations_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(declarationsCapability, superclassQuantifyCapability);
}

const reflector = const Reflector();

@reflector
class Foo {}

@reflector
class Bar extends Foo {}

final Matcher throwsNoCapability =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());

void expectCapabilityMessage(f()) {
  expect(() => f(), throwsNoCapability);
  try {
    f();
  } on NoSuchCapabilityError catch (exc) {
    // Test in lower case to eliminate the distinction between the class and
    // object name.
    expect("$exc".toLowerCase().contains('typerelationscapability'), isTrue);
  }
}

main() {
  initializeReflectable();

  ClassMirror classMirror = reflector.reflectType(Bar);
  test('Detect missing type relations capability', () {
    expectCapabilityMessage(() => classMirror.superclass);
    expectCapabilityMessage(() => classMirror.typeVariables);
    expectCapabilityMessage(() => classMirror.typeArguments);
    expectCapabilityMessage(() => classMirror.originalDeclaration);
    expectCapabilityMessage(() => classMirror.isSubtypeOf(classMirror));
    expectCapabilityMessage(() => classMirror.isAssignableTo(classMirror));
    expectCapabilityMessage(() => classMirror.superinterfaces);
    expectCapabilityMessage(() => classMirror.mixin);
    expectCapabilityMessage(() => classMirror.isSubclassOf(classMirror));
  });
  // TODO(eernst) implement: add missing cases for `typeRelationsCapability`:
  // upperBound and referent.
}
