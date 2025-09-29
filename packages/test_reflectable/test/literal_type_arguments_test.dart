// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Tests that type arguments given to literal lists and maps are preserved
/// when such objects are delivered as `metadata`.

library test_reflectable.test.literal_type_arguments_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'literal_type_arguments_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(metadataCapability, instanceInvokeCapability,
            declarationsCapability);
}

const reflector = Reflector();

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
  @ListMetadata(<int>[1, 2])
  int get foo => 42;
  @MapMetadata(<int, Reflector>{3: reflector})
  int get bar => 43;
}

void main() {
  initializeReflectable();

  test('Type arguments on literal maps and lists', () {
    var cMirror = reflector.reflectType(C) as ClassMirror;
    Map<String, DeclarationMirror> cDeclarations = cMirror.declarations;
    DeclarationMirror fooMirror = cDeclarations['foo']!;
    var fooMetadata = fooMirror.metadata[0] as ListMetadata;
    DeclarationMirror barMirror = cDeclarations['bar']!;
    var barMetadata = barMirror.metadata[0] as MapMetadata;

    // These tests are forgiving, e.g., they ignore type arguments.
    expect(fooMetadata.theList, const <int>[1, 2]);
    expect(barMetadata.theMap, const <int, Reflector>{3: reflector});

    // These tests are strict.
    expect(fooMetadata.theList == const <int>[1, 2], isTrue);
    expect(barMetadata.theMap == const <int, Reflector>{3: reflector}, isTrue);
  });
}
