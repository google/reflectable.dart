// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses a getter/setter for a variable which is inherited
// from a non-covered class. Created for issue #51, based on
// input from Lasse Damgaard.

library test_reflectable.test.inherited_variable_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'inherited_variable_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(instanceInvokeCapability, declarationsCapability);
}

const reflector = const Reflector();

class A {
  int x;
}

class B extends A {}

@reflector
class C extends B {}

main() {
  initializeReflectable();

  test('Variable inherited from non-covered class', () {
    expect(
        reflector.reflect(new C()).type.instanceMembers['x'].simpleName, 'x');
  });
}
