// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Uses 'reflect', with a constraint to invocation based on
// 'InvokeInstanceMemberCapability'.

library test_reflectable.test.member_capability_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'member_capability_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(invokingCapability);
}

class MyReflectable2 extends Reflectable {
  const MyReflectable2() : super(const InstanceInvokeCapability(r'^(x|b|b=)$'));
}

class MyReflectable3 extends Reflectable {
  const MyReflectable3() : super(const InstanceInvokeMetaCapability(Bar));
}

const myReflectable = MyReflectable();
const myReflectable2 = MyReflectable2();
const myReflectable3 = MyReflectable3();

class Bar {
  const Bar();
}

@myReflectable
class Foo {
  var a = 1;
  var b = 2;
  int x() => 42;
  String y(int n) => 'Hello $n';
}

@myReflectable2
class Foo2 {
  var a = 1;
  var b = 2;
  int x() => 42;
  String y(int n) => 'Hello $n';
  Object? z;
}

class Foo3Base {
  @Bar()
  var c = 3;
}

@myReflectable3
class Foo3 extends Foo3Base {
  var a = 1;
  @Bar()
  var b = 2;
  int x() => 42;
  @Bar()
  String y(int n) => 'Hello $n';
  // ignore:prefer_typing_uninitialized_variables
  var z;
}

final Matcher throwsReflectableNoMethod =
    throwsA(const TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  initializeReflectable();

  test('invokingCapability', () {
    var foo = Foo();
    var fooMirror = myReflectable.reflect(foo);
    expect(fooMirror.invokeGetter('a'), 1);
    expect(fooMirror.invokeSetter('a', 11), 11);
    expect(fooMirror.invokeGetter('a'), 11);
    expect(fooMirror.invokeGetter('b'), 2);
    expect(fooMirror.invokeSetter('b', 12), 12);
    expect(fooMirror.invokeGetter('b'), 12);
    expect(fooMirror.invoke('y', [1]), 'Hello 1');

    expect(fooMirror.invoke('x', []), 42);
    expect(fooMirror.invoke('y', [1]), 'Hello 1');
  });

  test("InstanceInvokeCapability('x')", () {
    var foo = Foo2();
    var fooMirror = myReflectable2.reflect(foo);
    expect(() => fooMirror.invokeGetter('a'), throwsReflectableNoMethod);
    expect(() => fooMirror.invokeSetter('a', 11), throwsReflectableNoMethod);
    expect(fooMirror.invokeGetter('b'), 2);
    expect(fooMirror.invokeSetter('b', 12), 12);
    expect(fooMirror.invokeGetter('b'), 12);

    expect(myReflectable2.reflect(Foo2()).invoke('x', []), 42);
    expect(() => myReflectable2.reflect(Foo2()).invoke('y', [3]),
        throwsReflectableNoMethod);
  });

  test('InstanceInvokeMetaCapability(Bar)', () {
    var foo = Foo3();
    var fooMirror = myReflectable3.reflect(foo);
    expect(() => fooMirror.invokeGetter('a'), throwsReflectableNoMethod);
    expect(() => fooMirror.invokeSetter('a', 11), throwsReflectableNoMethod);
    expect(fooMirror.invokeGetter('b'), 2);
    expect(fooMirror.invokeSetter('b', 12), 12);
    expect(fooMirror.invokeGetter('b'), 12);
    expect(fooMirror.invokeGetter('c'), 3);
    expect(fooMirror.invokeSetter('c', 13), 13);
    expect(fooMirror.invokeGetter('c'), 13);

    expect(() => myReflectable3.reflect(Foo3()).invoke('x', []),
        throwsReflectableNoMethod);
    expect(myReflectable3.reflect(Foo3()).invoke('y', [3]), 'Hello 3');
  });
}
