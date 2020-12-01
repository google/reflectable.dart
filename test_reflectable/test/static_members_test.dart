// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Uses `staticMembers` to access a static const variable.

library test_reflectable.test.static_members_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'static_members_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(staticInvokeCapability, declarationsCapability);
}

const myReflectable = MyReflectable();

@myReflectable
class A {
  static const List<String> foo = ['apple'];
}

void main() {
  initializeReflectable();

  ClassMirror classMirror = myReflectable.reflectType(A);
  test('Static members', () {
    expect(classMirror.staticMembers.length, 1);
    expect(classMirror.staticMembers['foo'], isNotNull);
  });
}
