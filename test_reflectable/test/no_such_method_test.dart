// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// File used to test reflectable code generation.
// Uses a generic mixin.

@reflector
library test_reflectable.test.no_such_method_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'no_such_method_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(typeCapability, invokingCapability, libraryCapability);
}

const reflector = Reflector();

@reflector
class A {
  int arg0() => 100;
  int arg1(int x) => 101;
  int arg2to4(A x, int y, [Reflector? z, w]) => 102;
  int argNamed(int x, y, {num? z}) => 103;
  int operator [](int x) => 104;
  void operator []=(int x, v) {}

  // Not a movie title.
  int deepThrow(o) => deepThrowImpl(o);
  int deepThrowImpl(o) => o.thisGetterDoesNotExist;
}

Matcher throwsReflectableNoSuchMethod =
    throwsA(const TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  initializeReflectable();

  var aMirror = reflector.reflect(A());
  var libraryMirror =
      reflector.findLibrary('test_reflectable.test.no_such_method_test');

  // Check that reflectable invocations of non-existing methods causes
  // a `ReflectableNoSuchMethodError`.
  test('No such method', () {
    expect(() => aMirror.invoke('doesNotExist', []),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('doesNotExist', [0]),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('doesNotExist', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg0', [0]), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg0', [], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg0', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg1', []), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg1', [], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg1', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg1', [0, 0]), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg1', [0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0]), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0, 0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0, 0, 0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0, 0, 0, 0, 0]),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('arg2to4', [0, 0, 0, 0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('+', []), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('+', [], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('+', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('+', [0, 0]), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('+', [0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('[]', []), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('[]', [], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('[]', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('[]', [0, 0]), throwsReflectableNoSuchMethod);
    expect(() => aMirror.invoke('[]', [0, 0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);

    expect(() => aMirror.invokeGetter('doesNotExist'),
        throwsReflectableNoSuchMethod);
    expect(() => aMirror.invokeSetter('doesNotExist', 0),
        throwsReflectableNoSuchMethod);

    expect(() => libraryMirror.invoke('doesNotExist', []),
        throwsReflectableNoSuchMethod);
    expect(() => libraryMirror.invoke('doesNotExist', [], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => libraryMirror.invoke('doesNotExist', [0]),
        throwsReflectableNoSuchMethod);
    expect(() => libraryMirror.invoke('doesNotExist', [0], {#doesNotExist: 0}),
        throwsReflectableNoSuchMethod);
    expect(() => libraryMirror.invokeGetter('doesNotExist'),
        throwsReflectableNoSuchMethod);
    expect(() => libraryMirror.invokeSetter('doesNotExist', 0),
        throwsReflectableNoSuchMethod);
  });

  // Check that we can distinguish a reflectable invocation failure from a
  // `NoSuchMethodError` thrown by a normal, non-reflectable invocation.
  test('No such method, natively', () {
    expect(() => A().deepThrow(Object()), throwsNoSuchMethodError);
    expect(
        () => aMirror.invoke('deepThrow', [Object()]), throwsNoSuchMethodError);
  });
}
