// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses a generic mixin.

@reflector
library test_reflectable.test.no_such_method_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(typeCapability, invokingCapability, libraryCapability);
}

const reflector = const Reflector();

@reflector
@proxy // To silence the analyzer.
class A {
  int arg0() => 100;
  int arg1(int x) => 101;
  int arg2to4(A x, int y, [Reflector z, w]) => 102;
  int argNamed(int x, y, {num z}) => 103;
  int operator [](int x) => 104;
  void operator []=(int x, v) {}
}

Matcher throwsNoSuchMethod =
    throwsA(const isInstanceOf<ReflectableNoSuchMethodError>());

main() {
  InstanceMirror aMirror = reflector.reflect(new A());
  LibraryMirror libraryMirror =
      reflector.findLibrary("test_reflectable.test.no_such_method_test");

  test('No such method', () {
    expect(() => aMirror.invoke("doesNotExist", []), throwsNoSuchMethod);
    expect(() => aMirror.invoke("doesNotExist", [0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("doesNotExist", [0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg0", [0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg0", [], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg0", [0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg1", []), throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg1", [], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg1", [0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg1", [0, 0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg1", [0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg2to4", [0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg2to4", [0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg2to4", [0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg2to4", [0, 0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg2to4", [0, 0, 0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(
        () => aMirror.invoke("arg2to4", [0, 0, 0, 0, 0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("arg2to4", [0, 0, 0, 0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("+", []), throwsNoSuchMethod);
    expect(
        () => aMirror.invoke("+", [], {#doesNotExist: 0}), throwsNoSuchMethod);
    expect(
        () => aMirror.invoke("+", [0], {#doesNotExist: 0}), throwsNoSuchMethod);
    expect(() => aMirror.invoke("+", [0, 0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("+", [0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("[]", []), throwsNoSuchMethod);
    expect(
        () => aMirror.invoke("[]", [], {#doesNotExist: 0}), throwsNoSuchMethod);
    expect(() => aMirror.invoke("[]", [0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => aMirror.invoke("[]", [0, 0]), throwsNoSuchMethod);
    expect(() => aMirror.invoke("[]", [0, 0], {#doesNotExist: 0}),
        throwsNoSuchMethod);

    expect(() => aMirror.invokeGetter("doesNotExist"), throwsNoSuchMethod);
    expect(() => aMirror.invokeSetter("doesNotExist", 0), throwsNoSuchMethod);

    expect(() => libraryMirror.invoke("doesNotExist", []), throwsNoSuchMethod);
    expect(() => libraryMirror.invoke("doesNotExist", [], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(() => libraryMirror.invoke("doesNotExist", [0]), throwsNoSuchMethod);
    expect(() => libraryMirror.invoke("doesNotExist", [0], {#doesNotExist: 0}),
        throwsNoSuchMethod);
    expect(
        () => libraryMirror.invokeGetter("doesNotExist"), throwsNoSuchMethod);
    expect(() => libraryMirror.invokeSetter("doesNotExist", 0),
        throwsNoSuchMethod);
  });
}
