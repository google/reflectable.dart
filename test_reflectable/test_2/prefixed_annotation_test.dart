// Copyright (c) 2018, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File used to test reflectable code generation.
// Uses an annotation that denotes a reflector via a prefix.

library test_reflectable.test.prefixed_annotation_test;

import 'package:test/test.dart';
import 'prefixed_annotation_lib.dart' as prefix;
import 'prefixed_annotation_test.reflectable.dart';

@prefix.reflector
class C {
  int m() => 42;
}

void main() {
  initializeReflectable();
  
  test('Using an import prefix with a reflector', () {
    var instanceMirror = prefix.reflector.reflect(C());
    var result = instanceMirror.invoke('m', []);
    expect(result, 42);
  });
}
