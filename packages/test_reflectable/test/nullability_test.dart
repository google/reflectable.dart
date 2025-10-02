// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests the `isNullable` and `isNonNullable` getters of a `TypeMirror`.

@reflector
library test_reflectable.test.nullability_test;

// ignore_for_file:prefer_void_to_null

import 'dart:async';
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'nullability_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
    : super(
        instanceInvokeCapability,
        declarationsCapability,
        typeAnnotationQuantifyCapability,
      );
}

const reflector = Reflector();

const fieldType = {
  'nn01': 'Never',
  'nn02': 'Function',
  'nn03': 'int',
  'nn04': 'List<int>',
  'nn05': 'FutureOr<Never>',
  'nn06': 'FutureOr<Function>',
  'nn07': 'FutureOr<void Function()>',
  'nn08': 'FutureOr<int>',
  'nn09': 'FutureOr<List<int>>',
  'nn10': 'FutureOr<X>',
  'nn11': 'FutureOr<FutureOr<Never>>',
  'n01': 'void',
  'n02': 'dynamic',
  'n03': 'Null',
  'n04': 'Never?',
  'n05': 'Function?',
  'n06': 'int?',
  'n07': 'List<int>?',
  'n08': 'FutureOr<Never>?',
  'n09': 'FutureOr<Function>?',
  'n10': 'FutureOr<void Function()>?',
  'n11': 'FutureOr<int>?',
  'n12': 'FutureOr<List<int>>?',
  'n13': 'FutureOr<X>?',
  'n14': 'FutureOr<void>',
  'n15': 'FutureOr<dynamic>',
  'n16': 'FutureOr<Null>',
  'n17': 'FutureOr<Never?>',
  'n18': 'FutureOr<Function?>',
  'n19': 'FutureOr<void Function()?>',
  'n20': 'FutureOr<int?>',
  'n21': 'FutureOr<List<int>?>',
  'n22': 'FutureOr<X?>',
  'n23': 'FutureOr<FutureOr<void>>',
  'x01': 'FutureOr<Y>',
  'x02': 'FutureOr<FutureOr<Y>>',
};

@reflector
class A<X extends Object, Y> {
  // NonNullable types.
  late Never nn01;
  late Function nn02;
  // Missing support for function types: omit `late void Function() nn;`.
  late int nn03;
  late List<int> nn04;
  // Missing support for type variables: omit `late X nn;`.
  late FutureOr<Never> nn05;
  late FutureOr<Function> nn06;
  late FutureOr<void Function()> nn07;
  late FutureOr<int> nn08;
  late FutureOr<List<int>> nn09;
  late FutureOr<X> nn10;
  late FutureOr<FutureOr<Never>> nn11;

  // Nullable types.
  late void n01;
  late dynamic n02;
  late Null n03;
  late Never? n04;
  late Function? n05;
  // Missing support: omit `late void Function()? n;`.
  late int? n06;
  late List<int>? n07;
  // Missing support: omit `late X? n;`.
  late FutureOr<Never>? n08;
  late FutureOr<Function>? n09;
  late FutureOr<void Function()>? n10;
  late FutureOr<int>? n11;
  late FutureOr<List<int>>? n12;
  late FutureOr<X>? n13;
  late FutureOr<void> n14;
  late FutureOr<dynamic> n15;
  late FutureOr<Null> n16;
  late FutureOr<Never?> n17;
  late FutureOr<Function?> n18;
  late FutureOr<void Function()?> n19;
  late FutureOr<int?> n20;
  late FutureOr<List<int>?> n21;
  late FutureOr<X?> n22;
  late FutureOr<FutureOr<void>> n23;

  // Types which are not nullable and not nonNullable.
  // Missing support: omit `late Y x;`.
  late FutureOr<Y> x01;
  late FutureOr<FutureOr<Y>> x02;
}

void testNonNullable(String name, TypeMirror typeMirror) {
  test('${fieldType[name]} isNonNullable', () {
    expect(typeMirror.isNonNullable, true);
    expect(typeMirror.isNullable, false);
  });
}

void testNullable(String name, TypeMirror typeMirror) {
  test('${fieldType[name]} isNullable', () {
    expect(typeMirror.isNonNullable, false);
    expect(typeMirror.isNullable, true);
  });
}

void testNeither(String name, TypeMirror typeMirror) {
  test('${fieldType[name]} both false', () {
    expect(typeMirror.isNonNullable, false);
    expect(typeMirror.isNullable, false);
  });
}

void main() {
  initializeReflectable();

  var classMirror = reflector.reflectType(A) as ClassMirror;
  var declarations = classMirror.declarations;

  TypeMirror type(String name) {
    var variableMirror = declarations[name] as VariableMirror;
    return variableMirror.type;
  }

  for (var i = 1; i <= 11; ++i) {
    var name = 'nn${i < 10 ? '0' : ''}$i';
    testNonNullable(name, type(name));
  }
  for (var i = 1; i <= 23; ++i) {
    var name = 'n${i < 10 ? '0' : ''}$i';
    testNullable(name, type(name));
  }
  for (var i = 1; i <= 2; ++i) {
    var name = 'x0$i';
    testNeither(name, type(name));
  }
}
