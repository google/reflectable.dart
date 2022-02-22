// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// @dart = 2.9

// Dealing with sdk issue #19635, 'Mirrors: newInstance on constructor with
// optional parameters result in crash when running as JavaScript'.

// Testing different parameter declarations, hence:
// ignore_for_file:prefer_initializing_formals

library test_reflectable.test.new_instance_optional_arguments_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'new_instance_optional_arguments_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(newInstanceCapability);
}

const Reflector reflector = Reflector();

@reflector
class A {
  Object req1, opt1, opt2;
  A.a0([opt1]) : opt1 = opt1;
  A.b0([opt1, opt2])
      : opt1 = opt1,
        opt2 = opt2;
  A.c0([opt1 = 499]) : opt1 = opt1;
  A.d0([opt1 = 499, opt2 = 42])
      : opt1 = opt1,
        opt2 = opt2;
  A.a1(req1, [opt1])
      : req1 = req1,
        opt1 = opt1;
  A.b1(req1, [opt1, opt2])
      : req1 = req1,
        opt1 = opt1,
        opt2 = opt2;
  A.c1(req1, [opt1 = 499])
      : req1 = req1,
        opt1 = opt1;
  A.d1(req1, [opt1 = 499, opt2 = 42])
      : req1 = req1,
        opt1 = opt1,
        opt2 = opt2;
}

@reflector
class ClazzA {
  ClazzA([dynamic property]);
}

void main() {
  initializeReflectable();

  // Problem reproduction code as described in the issue, adjusted to make it a
  // test and ported to make it work with reflectable.

  test('Issue as reported', () {
    ClassMirror classMirror = reflector.reflectType(ClazzA);
    ClazzA clazzA = classMirror.newInstance('', []);
    expect(clazzA, isNotNull);
  });

  // Test as introduced by https://codereview.chromium.org/417693002,
  // ported to work with reflectable: Uses unittest rather than expect because
  // all reflectable tests do that; changes symbols to strings; calls
  // `reflector.reflectType` rather than a plain `reflectClass`; otherwise
  // unchanged.

  ClassMirror cm = reflector.reflectType(A);
  // ignore:prefer_typing_uninitialized_variables
  var o;

  test('No arguments given', () {
    o = cm.newInstance('a0', []);
    expect(null, o.req1);
    expect(null, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('b0', []);
    expect(null, o.req1);
    expect(null, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('c0', []);
    expect(null, o.req1);
    expect(499, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('d0', []);
    expect(null, o.req1);
    expect(499, o.opt1);
    expect(42, o.opt2);
  });

  test('Giving one optional argument', () {
    o = cm.newInstance('a0', [77]);
    expect(null, o.req1);
    expect(77, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('b0', [77]);
    expect(null, o.req1);
    expect(77, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('c0', [77]);
    expect(null, o.req1);
    expect(77, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('d0', [77]);
    expect(null, o.req1);
    expect(77, o.opt1);
    expect(42, o.opt2);
  });

  test('Giving two optional arguments', () {
    o = cm.newInstance('b0', [77, 11]);
    expect(null, o.req1);
    expect(77, o.opt1);
    expect(11, o.opt2);
    o = cm.newInstance('d0', [77, 11]);
    expect(null, o.req1);
    expect(77, o.opt1);
    expect(11, o.opt2);
  });

  test('Giving one required argument', () {
    o = cm.newInstance('a1', [123]);
    expect(123, o.req1);
    expect(null, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('b1', [123]);
    expect(123, o.req1);
    expect(null, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('c1', [123]);
    expect(123, o.req1);
    expect(499, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('d1', [123]);
    expect(123, o.req1);
    expect(499, o.opt1);
    expect(42, o.opt2);
  });

  test('Giving one required and one optional argument', () {
    o = cm.newInstance('a1', [123, 77]);
    expect(123, o.req1);
    expect(77, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('b1', [123, 77]);
    expect(123, o.req1);
    expect(77, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('c1', [123, 77]);
    expect(123, o.req1);
    expect(77, o.opt1);
    expect(null, o.opt2);
    o = cm.newInstance('d1', [123, 77]);
    expect(123, o.req1);
    expect(77, o.opt1);
    expect(42, o.opt2);
  });

  test('Giving one required and two optional arguments', () {
    o = cm.newInstance('b1', [123, 77, 11]);
    expect(123, o.req1);
    expect(77, o.opt1);
    expect(11, o.opt2);
    o = cm.newInstance('d1', [123, 77, 11]);
    expect(123, o.req1);
    expect(77, o.opt1);
    expect(11, o.opt2);
  });
}
