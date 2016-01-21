// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Defines a reflector that is never used as a reflector; causes a transformer
// warning, but not an error.

library test_reflectable.test.invoke_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector() : super(invokingCapability);
}

const reflector = const Reflector();

Matcher throwsNoCapability =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());

main() {
  test('Unused reflector', () {
    expect(() => reflector.libraries, throwsNoCapability);
    expect(reflector.annotatedClasses, <ClassMirror>[]);
  });
}
