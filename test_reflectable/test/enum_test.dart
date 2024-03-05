// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflectable code generation.
/// Based on https://github.com/dart-lang/reflectable/issues/80.
library test_reflectable.test.enum_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'enum_test.reflectable.dart';

/// This annotation specifies the object can be serialized
class Serializable extends Reflectable {
  const Serializable()
      : super(
            typeAnnotationQuantifyCapability,
            superclassQuantifyCapability,
            invokingCapability,
            declarationsCapability,
            metadataCapability,
            newInstanceCapability,
            typeRelationsCapability,
            typeCapability);
}

const serializable = Serializable();

enum Color { blue, red, green }

class JsonObjectStub {
  late Color color;
  JsonObjectStub(String jsonStr) {
    if (jsonStr.contains('0')) {
      color = Color.blue;
    } else if (jsonStr.contains('1')) {
      color = Color.red;
    } else if (jsonStr.contains('2')) {
      color = Color.green;
    }
  }
}

dynamic fromJson(String jsonStr, Type clazz) {
  if (jsonStr.startsWith('{')) return JsonObjectStub(jsonStr);
  return Color.blue;
}

@serializable
class ObjectWithEnum {
  late Color color;
}

void main() {
  initializeReflectable();

  test('deserialize enum', () {
    expect(fromJson('0', Color), Color.blue);
  });
  test('deserialize object with enum', () {
    expect(fromJson('{"color":0}', ObjectWithEnum).color, Color.blue);
    expect(fromJson('{"color":1}', ObjectWithEnum).color, Color.red);
    expect(fromJson('{"color":2}', ObjectWithEnum).color, Color.green);
  });
}
