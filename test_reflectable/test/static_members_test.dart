// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `staticMembers` to access a static const variable.

library test_reflectable.test.static_members_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'static_members_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(staticInvokeCapability, declarationsCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
class A {
  static const List<String> foo = const ["apple"];
}

main() {
  initializeReflectable();

  ClassMirror classMirror = myReflectable.reflectType(A);
  test('Static members', () {
    expect(classMirror.staticMembers.length, 1);
    expect(classMirror.staticMembers['foo'], isNotNull);
  });
}
