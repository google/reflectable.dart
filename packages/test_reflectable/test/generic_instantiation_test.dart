// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test metadata with a generic instantiation like `someFunction<Service>`.
// Used as a regression test to verify that bug #300 has been resolved.

library test_reflectable.test.generic_instantiation_test;

@GlobalQuantifyMetaCapability(Component, reflector)
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'generic_instantiation_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(
            newInstanceCapability,
            declarationsCapability,
            invokingCapability,
            typeCapability,
            typeRelationsCapability,
            libraryCapability,
            metadataCapability);
}

const reflector = Reflector();

class Component {
  final Object value;
  const Component({required this.value});
}

abstract class Service {}

class ConcreteService implements Service {}

X someFunction<X>() => ConcreteService() as X;

@Component(value: someFunction<Service>)
class A {}

void main() {
  initializeReflectable();

  var classMirror = reflector.reflectType(A) as ClassMirror;
  var metadata = classMirror.metadata[0] as Component;
  var function = metadata.value as Service Function();

  test('The function from metadata has the expected type and is callable', () {
    expect(function().runtimeType, ConcreteService);
  });
}
