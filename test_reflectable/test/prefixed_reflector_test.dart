// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses a reflector which is accessed via a prefixed identifier.

library test_reflectable.test.prefixed_reflector_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(instanceInvokeCapability, topLevelInvokeCapability,
            declarationsCapability, reflectedTypeCapability, libraryCapability);
}

class C {
  static const reflector = const Reflector();
}

@C.reflector
class D {
  int get getter => 24;
  void set setter(int owtytrof) {}
}

main() {
  ClassMirror classMirror = C.reflector.reflectType(D);
  test('Prefixed reflector type', () {
    expect(classMirror.reflectedType, D);
  });
}
