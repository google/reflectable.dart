// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Tests that type arguments given to literal lists and maps are preserved
/// when such objects are delivered as `metadata`.

library test_reflectable.test.literal_type_arguments_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'literal_type_arguments_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(metadataCapability, instanceInvokeCapability,
            declarationsCapability);
}

const reflector = const Reflector();

class ListMetadata {
  final List<int> theList;
  const ListMetadata(this.theList);
}

class MapMetadata {
  final Map<int, Reflector> theMap;
  const MapMetadata(this.theMap);
}

@reflector
class C {
  @ListMetadata(const <int>[1, 2])
  int get foo => 42;
  @MapMetadata(const <int, Reflector>{3: reflector})
  int get bar => 43;
}

main() {
  initializeReflectable();

  test('Type arguments on literal maps and lists', () {
    ClassMirror cMirror = reflector.reflectType(C);
    Map<String, DeclarationMirror> cDeclarations = cMirror.declarations;
    DeclarationMirror fooMirror = cDeclarations['foo'];
    ListMetadata fooMetadata = fooMirror.metadata[0];
    DeclarationMirror barMirror = cDeclarations['bar'];
    MapMetadata barMetadata = barMirror.metadata[0];

    // These tests are forgiving, e.g., they ignore type arguments.
    expect(fooMetadata.theList, const <int>[1, 2]);
    expect(barMetadata.theMap, const <int, Reflector>{3: reflector});

    // These tests are strict.
    expect(fooMetadata.theList == const <int>[1, 2], isTrue);
    expect(barMetadata.theMap == const <int, Reflector>{3: reflector}, isTrue);
  });
}
