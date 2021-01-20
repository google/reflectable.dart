// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.name_clash_test;

import 'name_clash_lib.dart' as o;
import 'package:test/test.dart';
import 'name_clash_test.reflectable.dart';

@o.reflector
class C {}

void main() {
  initializeReflectable();

  test('Name-clash in annotated classes', () {
    expect(o.reflector.reflectType(C), isNot(o.reflector.reflectType(o.C)));
  });
}
