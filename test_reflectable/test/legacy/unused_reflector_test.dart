// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Defines a reflector that is never used as a reflector; causes a
// warning, but not an error.

library test_reflectable.test.unused_reflector_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'unused_reflector_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(invokingCapability);
}

const reflector = Reflector();

Matcher throwsNoCapability =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());

void main() {
  initializeReflectable();

  test('Unused reflector', () {
    expect(() => reflector.libraries, throwsNoCapability);
    expect(reflector.annotatedClasses, <ClassMirror>[]);
  });
}
