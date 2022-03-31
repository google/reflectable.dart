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
  'nn05': 'X',
  'nn06': 'FutureOr<Never>',
  'nn07': 'FutureOr<Function>',
  'nn08': 'FutureOr<void Function()>',
  'nn09': 'FutureOr<int>',
  'nn10': 'FutureOr<List<int>>',
  'nn11': 'FutureOr<X>',
  'nn12': 'FutureOr<FutureOr<Never>>',
  'n01': 'void',
  'n02': 'dynamic',
  'n03': 'Null',
  'n04': 'Never?',
  'n05': 'Function?',
  'n06': 'void Function()?',
  'n07': 'int?',
  'n08': 'List<int>?',
  'n09': 'X?',
  'n10': 'FutureOr<Never>?',
  'n11': 'FutureOr<Function>?',
  'n12': 'FutureOr<void Function()>?',
  'n13': 'FutureOr<int>?',
  'n14': 'FutureOr<List<int>>?',
  'n15': 'FutureOr<X>?',
  'n16': 'FutureOr<void>',
  'n17': 'FutureOr<dynamic>',
  'n18': 'FutureOr<Null>',
  'n19': 'FutureOr<Never?>',
  'n20': 'FutureOr<Function?>',
  'n21': 'FutureOr<void Function()?>',
  'n22': 'FutureOr<int?>',
  'n23': 'FutureOr<List<int>?>',
  'n24': 'FutureOr<X?>',
  'n25': 'FutureOr<FutureOr<void>>',
  'x01': 'Y',
  'x02': 'FutureOr<Y>',
  'x03': 'FutureOr<FutureOr<Y>>',
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
  late void Function()? n06;
  late int? n07;
  late List<int>? n08;
  late X? n09;
  late FutureOr<Never>? n10;
  late FutureOr<Function>? n11;
  late FutureOr<void Function()>? n12;
  late FutureOr<int>? n13;
  late FutureOr<List<int>>? n14;
  late FutureOr<X>? n15;
  late FutureOr<void> n16;
  late FutureOr<dynamic> n17;
  late FutureOr<Null> n18;
  late FutureOr<Never?> n19;
  late FutureOr<Function?> n20;
  late FutureOr<void Function()?> n21;
  late FutureOr<int?> n22;
  late FutureOr<List<int>?> n23;
  late FutureOr<X?> n24;
  late FutureOr<FutureOr<void>> n25;

  // Types which are not nullable and not nonNullable.
  late Y x01;
  late FutureOr<Y> x02;
  late FutureOr<FutureOr<Y>> x03;
}

void testNonNullable(String name, TypeMirror typeMirror) {
  test('${fieldType[name]} isNonNullable', () {});
}

void testNullable(String name, TypeMirror typeMirror) {}

void testNeither(String name, TypeMirror typeMirror) {}

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
  for (var i = 1; i <= 25; ++i) {
    var name = 'n${i < 10 ? '0' : ''}$i';
    testNullable(name, type(name));
  }
  for (var i = 1; i <= 3; ++i) {
    var name = 'x0$i';
    testNeither(name, type(name));
  }
}
