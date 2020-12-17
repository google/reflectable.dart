// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses `newInstance`.

library test_reflectable.test.new_instance_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'new_instance_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(newInstanceCapability);
}

const reflector = Reflector();

class MetaReflector extends Reflectable {
  const MetaReflector() : super(const NewInstanceMetaCapability(C));
}

const metaReflector = MetaReflector();

class C {
  const C();
}

@reflector
@metaReflector
class A {
  @C()
  A() : f = 42;

  @C()
  A.positional(int x) : f = x - 42;

  @C()
  A.optional(int x, int y, [int z = 1, w]): f = x + y + z * 42 + ((w ?? 10) as int);

  @C()
  A.argNamed(int x, int y, {int z = 42, int? p}): f = x + y - z - (p ?? 10);

  // Note that the parameter name `b` is used here in order to test the
  // handling of name clashes for `isCheckCode`, so please do not change it.
  A.noMeta(int b) : f = b + 42;

  @C()
  factory A.aFactory() => A();

  int f = 0;
}

void performTests(String message, Reflectable reflector) {
  initializeReflectable();

  var classMirror = reflector.reflectType(A) as ClassMirror;
  test('$message: newInstance unnamed constructor, no arguments', () {
    expect((classMirror.newInstance('', []) as A).f, 42);
  });
  test('$message: newInstance named constructor, simple argument list, '
      'one argument',
      () {
    expect((classMirror.newInstance('positional', [84]) as A).f, 42);
  });
  test('$message: newInstance optional arguments, all used', () {
    expect((classMirror.newInstance('optional', [1, 2, 3, 4]) as A).f, 133);
  });
  test('$message: newInstance optional arguments, none used', () {
    expect((classMirror.newInstance('optional', [1, 2]) as A).f, 55);
  });
  test('$message: newInstance optional arguments, some used', () {
    expect((classMirror.newInstance('optional', [1, 2, 3]) as A).f, 139);
  });
  test('$message: newInstance named arguments, all used', () {
    expect((classMirror.newInstance('argNamed', [1, 2], {#z: 3, #p: 0}) as A).f,
        0);
  });
  test('$message: newInstance named arguments, some used', () {
    expect((classMirror.newInstance('argNamed', [1, 2], {#z: 3}) as A).f, -10);
    expect((classMirror.newInstance('argNamed', [1, 2], {#p: 3}) as A).f, -42);
  });
  test('$message: newInstance named arguments, unused', () {
    expect((classMirror.newInstance('argNamed', [1, 2]) as A).f, -49);
    expect((classMirror.newInstance('argNamed', [1, 2], {}) as A).f, -49);
  });
  test('$message: newInstance on factory', () {
    expect((classMirror.newInstance('aFactory', []) as A).f, 42);
  });
}

final throwsReflectableNoMethod =
    throwsA(const TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  performTests('reflector', reflector);
  performTests('metaReflector', metaReflector);

  test('newInstance named constructor, no metadata, none required', () {
    var classMirror = reflector.reflectType(A) as ClassMirror;
    expect((classMirror.newInstance('noMeta', [0]) as A).f, 42);
  });
  test('newInstance named constructor, no metadata, rejected', () {
    var classMirror = metaReflector.reflectType(A) as ClassMirror;
    expect(() => classMirror.newInstance('noMeta', [0]),
        throwsReflectableNoMethod);
  });
}
