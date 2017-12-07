// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.reflect_type_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

const reflector = const Reflector();

class BroadReflector extends Reflectable {
  const BroadReflector()
      : super.fromList(const <ReflectCapability>[typingCapability]);
}

const broadReflector = const BroadReflector();

@reflector
@broadReflector
class A {}

class B {}

final Matcher throwsNoCapability =
    throwsA(new isInstanceOf<NoSuchCapabilityError>());

void performTests(String message, reflector) {
  test("$message: reflectType", () {
    ClassMirror cm = reflector.reflectType(A);
    expect(cm, new isInstanceOf<ClassMirror>());
    expect(cm.simpleName, "A");
    expect(() => reflector.reflectType(B), throwsNoCapability);
  });
  test("$message: InstanceMirror.type", () {
    ClassMirror cm = reflector.reflectType(A);
    ClassMirror cm2 = reflector.reflect(new A()).type;
    expect(cm.qualifiedName, cm2.qualifiedName);
  });
}

main() {
  performTests('With typeCapability', reflector);
  performTests('With typingCapability', broadReflector);
  test('Seeing that typing is broader than type', () {
    expect(
        () => reflector.findLibrary('test_reflectable.test.reflect_type_test'),
        throwsNoCapability);
    LibraryMirror libraryMirror =
        broadReflector.findLibrary('test_reflectable.test.reflect_type_test');
    expect(libraryMirror, isNotNull);
    expect(libraryMirror.uri.toString().contains('reflect_type_test'), true);
  });
}
