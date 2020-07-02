// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.superinterfaces_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'superinterfaces_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, declarationsCapability,
            typeRelationsCapability, libraryCapability);
}

@Reflector()
class A {}

@Reflector()
class B implements A {}

@Reflector()
class C implements G {
  String get expires => 'never';
}

@Reflector()
class D {}

class E {}

@Reflector()
class F extends C implements B, D, E {}

@Reflector()
class G {}

const reflector = Reflector();

void main() {
  initializeReflectable();

  ClassMirror bm = reflector.reflectType(B);
  ClassMirror dm = reflector.reflectType(D);
  ClassMirror fm = reflector.reflectType(F);
  test('superinterfaces', () {
    // Test that only the supported classes from the superinterface
    // list in the class-declaration are included.
    expect(fm.superinterfaces, [bm, dm]);
  });
}
