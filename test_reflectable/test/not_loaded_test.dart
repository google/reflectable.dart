// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Tests that `targetLibrary` of a library dependency is
// null when that library has not been loaded.

@reflector
library test_reflectable.test.not_loaded_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'not_loaded_lib.dart' deferred as not_loaded;

class Reflector extends Reflectable {
  const Reflector() : super(libraryCapability);
}

const reflector = const Reflector();

main() {
  test('get non-loaded library', () {
    LibraryMirror libraryMirror =
        reflector.findLibrary('test_reflectable.test.not_loaded_test');
    bool foundIt = false;
    for (LibraryDependencyMirror dependency in
             libraryMirror.libraryDependencies) {
      if (dependency.prefix == 'not_loaded') {
        foundIt = true;
        expect(dependency.targetLibrary, null);
        break;
      }
    }
    expect(foundIt, true);
  });
}
