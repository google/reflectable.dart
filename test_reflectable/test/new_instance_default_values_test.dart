// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses default values on optional arguments.

library test_reflectable.test.new_instance_default_values_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'new_instance_default_values_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(newInstanceCapability);
}

const myReflectable = MyReflectable();

const String globalConstant = '20';

@myReflectable
class A {
  static const localConstant = 10;
  A.optional([int x = localConstant, String y = globalConstant])
      : f = x,
        g = y;
  A.namedOptional({int x = localConstant, String y = globalConstant})
      : f = x,
        g = y;
  A.initializingFormal([this.f = localConstant, this.g = globalConstant]);
  A.namedInitializingFormal({this.f = localConstant, this.g = globalConstant});
  int f = 0;
  String g;
}

void main() {
  initializeReflectable();

  ClassMirror classMirror = myReflectable.reflectType(A);
  A a;

  test('positional argument default, local constant', () {
    a = classMirror.newInstance('optional', [], {});
    expect(a.f, 10);
  });
  test('positional argument default, global constant', () {
    a = classMirror.newInstance('optional', [], {});
    expect(a.g, '20');
  });

  test('named argument default, local constant', () {
    a = classMirror.newInstance('namedOptional', [], {});
    expect(a.f, 10);
  });
  test('named argument default, global constant', () {
    a = classMirror.newInstance('namedOptional', [], {});
    expect(a.g, '20');
  });

  test('initializing formal default, local constant', () {
    a = classMirror.newInstance('initializingFormal', [], {});
    expect(a.f, 10);
  });
  test('initializing formal default, global constant', () {
    a = classMirror.newInstance('initializingFormal', [], {});
    expect(a.g, '20');
  });

  test('named initializing formal default, local constant', () {
    a = classMirror.newInstance('namedInitializingFormal', [], {});
    expect(a.f, 10);
  });
  test('named initializing formal default, global constant', () {
    a = classMirror.newInstance('namedInitializingFormal', [], {});
    expect(a.g, '20');
  });
}
