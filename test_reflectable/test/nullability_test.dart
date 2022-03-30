// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests the `isNullable` and `isNonNullable` getters of a `TypeMirror`.

@reflector
library test_reflectable.test.nullability_test;

import 'package:test/test.dart';
import 'package:reflectable/reflectable.dart';
import 'nullability_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector():
      super(instanceInvokeCapability, declarationsCapability);
}

const reflector = Reflector();

@reflector
class A<X extends Object, Y> {
  // NonNullable types.
  late Never nn01;
  late Function nn02;
  late void Function() nn03;
  late int nn04;
  late List<int> nn05;
  late X nn06;
  late FutureOr<Never> nn07;
  late FutureOr<Function> nn08;
  late FutureOr<void Function()> nn09;
  late FutureOr<int> nn10;
  late FutureOr<List<int>> nn11;
  late FutureOr<X> nn12;
  late FutureOr<FutureOr<Never>> nn13;

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
  late FutureOr<List<int>?> n13;
  late FutureOr<X?> n24;
  late FutureOr<FutureOr<void>> n25;

  // Types which are not nullable and not nonNullable.
  late Y x01;
  late FutureOr<Y> x02;
  late FutureOr<FutureOr<Y>> x03;
}


void main() {
  initializeReflectable();

  var voidType
}
