// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Uses `delegate`.

library test_reflectable.test.delegate_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'delegate_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(delegateCapability, instanceInvokeCapability);
}

class NameReflector extends Reflectable {
  const NameReflector()
      : super(delegateCapability, const InstanceInvokeCapability('arg0'));
}

class MetaReflector extends Reflectable {
  const MetaReflector()
      : super(delegateCapability, const InstanceInvokeMetaCapability(D));
}

const reflector = Reflector();
const nameReflector = NameReflector();
const metaReflector = MetaReflector();

class D {
  const D();
}

@reflector
@nameReflector
@metaReflector
class A {
  int arg0() => 100;

  @D()
  int arg1(int x) => 101;

  int arg2to4(A x, int y, [Reflector z, w]) => 102;

  @D()
  int argNamed(int x, y, {num z}) => 103;

  int operator +(int x) => 104;

  @D()
  int operator [](int x) => indexTarget;

  void operator []=(int x, v) {
    indexTarget = v;
  }

  int indexTarget = 105;

  @D()
  int get getset => getsetTarget;

  set getset(int x) {
    getsetTarget = x;
  }

  int getsetTarget = 107;
}

class B implements A {
  final InstanceMirror _instanceMirror;
  B(this._instanceMirror);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return _instanceMirror.delegate(invocation);
  }
}

Matcher throwsReflectableNoMethod =
    throwsA(const TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  initializeReflectable();

  var a = A();
  var b = B(reflector.reflect(a));
  var bName = B(nameReflector.reflect(a));
  var bMeta = B(metaReflector.reflect(a));

  test('Delegate method, no arguments', () {
    expect(b.arg0(), a.arg0());
    expect(bName.arg0(), a.arg0());
    expect(() => bMeta.arg0(), throwsReflectableNoMethod);
  });
  test('Delegate method, positional arguments', () {
    expect(b.arg1(42), a.arg1(42));
    expect(b.arg2to4(a, 43), a.arg2to4(a, 43));
    expect(b.arg2to4(a, 44, reflector), a.arg2to4(a, 44, reflector));
    expect(b.arg2to4(a, 45, reflector, 0), a.arg2to4(a, 45, reflector, 0));
    expect(() => bName.arg1(46), throwsReflectableNoMethod);
    expect(() => bName.arg2to4(a, 47), throwsReflectableNoMethod);
    expect(() => bName.arg2to4(a, 48, reflector), throwsReflectableNoMethod);
    expect(() => bName.arg2to4(a, 49, reflector, 0), throwsReflectableNoMethod);
    expect(bMeta.arg1(50), a.arg1(50));
    expect(() => bMeta.arg2to4(a, 51), throwsReflectableNoMethod);
    expect(() => bMeta.arg2to4(a, 52, reflector), throwsReflectableNoMethod);
    expect(() => bMeta.arg2to4(a, 53, reflector, 0), throwsReflectableNoMethod);
  });
  test('Delegate method, positional and named arguments', () {
    expect(b.argNamed(54, b), a.argNamed(54, b));
    expect(b.argNamed(55, b, z: 3.1415926), a.argNamed(55, b, z: 3.1415926));
    expect(() => bName.argNamed(56, b), throwsReflectableNoMethod);
    expect(
        () => bName.argNamed(57, b, z: 3.1415926), throwsReflectableNoMethod);
    expect(bMeta.argNamed(58, b), a.argNamed(58, b));
    expect(
        bMeta.argNamed(59, b, z: 3.1415926), a.argNamed(59, b, z: 3.1415926));
  });
  test('Delegate operator', () {
    expect(b + 60, a + 60);
    expect(b[61], a[61]);
    b[62] = 63;
    expect(b[62], 63);
    expect(a[62], 63);
    expect(() => bName + 64, throwsReflectableNoMethod);
    expect(() => bName[62], throwsReflectableNoMethod);
    expect(() => bName[65] = 66, throwsReflectableNoMethod);
    expect(a[65], 63);
    expect(() => bMeta + 66, throwsReflectableNoMethod);
    expect(bMeta[65], a[65]);
    expect(() => bMeta[66] = 67, throwsReflectableNoMethod);
    expect(a[66], 63);
  });
  test('Delegate getter and setter', () {
    expect(b.getset, a.getset);
    b.getset = 61;
    expect(b.getset, 61);
    expect(a.getset, 61);
    expect(bMeta.getset, a.getset);
    expect(() => bMeta.getset = 62, throwsReflectableNoMethod);
    expect(a.getset, 61);
  });
}
