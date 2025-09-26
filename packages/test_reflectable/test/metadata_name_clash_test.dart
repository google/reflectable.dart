// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.metadata_name_clash_test;

import 'metadata_name_clash_lib.dart' as o;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'metadata_name_clash_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(metadataCapability);
}

class Bar {
  const Bar();
}

const Reflectable reflector = Reflector();

@reflector
@Bar()
class C {}

void main() {
  initializeReflectable();

  test('Metadata with name-clash', () {
    expect(reflector.reflectType(C).metadata, [reflector, const Bar()]);
    expect(
        o.reflector2.reflectType(o.D).metadata, [o.reflector2, const o.Bar()]);
  });
}
