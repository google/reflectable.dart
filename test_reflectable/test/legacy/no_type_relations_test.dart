// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

// File used to test reflectable code generation.
// Uses type relations without a `typeRelations` capability.

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'no_type_relations_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(declarationsCapability, superclassQuantifyCapability);
}

const reflector = Reflector();

@reflector
class Foo {}

@reflector
class Bar extends Foo {}

final Matcher throwsNoCapability =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());

void expectCapabilityMessage(Function() f) {
  expect(() => f(), throwsNoCapability);
  try {
    f();
  } on NoSuchCapabilityError catch (exc) {
    // Test in lower case to eliminate the distinction between the class and
    // object name.
    expect('$exc'.toLowerCase().contains('typerelationscapability'), isTrue);
  }
}

void main() {
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
