// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses a getter/setter for a variable which is inherited
// from a non-covered class. Created for issue #51, based on
// input from Lasse Damgaard.

library test_reflectable.test.inherited_variable_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'inherited_variable_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(instanceInvokeCapability, declarationsCapability);
}

const reflector = Reflector();

class A {
  late int x;
}

class B extends A {}

@reflector
class C extends B {}

void main() {
  initializeReflectable();

  test('Variable inherited from non-covered class', () {
    expect(
        reflector.reflect(C()).type.instanceMembers['x']!.simpleName, 'x');
  });
}
