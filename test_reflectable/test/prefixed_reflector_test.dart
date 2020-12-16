// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses a reflector which is accessed via a prefixed identifier.

library test_reflectable.test.prefixed_reflector_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'prefixed_reflector_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(instanceInvokeCapability, topLevelInvokeCapability,
            declarationsCapability, reflectedTypeCapability, libraryCapability);
}

class C {
  static const reflector = Reflector();
}

@C.reflector
class D {
  int get getter => 24;
  set setter(int owtytrof) {}
}

void main() {
  initializeReflectable();

  ClassMirror classMirror = C.reflector.reflectType(D);
  test('Prefixed reflector type', () {
    expect(classMirror.reflectedType, D);
  });
}
