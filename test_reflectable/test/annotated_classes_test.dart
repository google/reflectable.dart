// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test_reflectable.test.annotated_classes_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'annotated_classes_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(typeCapability);
}

class MyReflectable2 extends Reflectable {
  const MyReflectable2(): super(typeCapability);
}

@MyReflectable()
class A {}

@MyReflectable()
class B extends A {}

class C extends B {}

class D implements B {}

@MyReflectable2()
class E {}

@MyReflectable2()
class F implements A {}

@MyReflectable()
@MyReflectable2()
class G {}

void main() {
  initializeReflectable();

  test('Annotated classes', () {
    expect(const MyReflectable().annotatedClasses
            .map((ClassMirror classMirror) => classMirror.simpleName),
            {'A', 'B', 'G'});
    expect(const MyReflectable2().annotatedClasses
            .map((ClassMirror classMirror) => classMirror.simpleName),
            {'E', 'F', 'G'});
  });
}
