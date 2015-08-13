// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable.check_literal_transform_test;

/// Test the literal output of the transformation for a few simple cases.

import "package:reflectable/test_transform.dart";
import "package:reflectable/transformer.dart";
import "package:unittest/unittest.dart";
import 'package:barback/src/transformer/barback_settings.dart';

var useReflect = [
  {
    "a|main.dart": """
import 'package:reflectable/reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(newInstanceCapability);
}

@MyReflectable()
class A {}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
}

"""
  },
  {
    "a|main.dart": """
// This file has been transformed by reflectable.
import 'package:reflectable/reflectable.dart';
import "main_reflection_data.dart" show initializeReflectable;

class MyReflectable extends Reflectable {
  const MyReflectable(): super(newInstanceCapability);
}

@MyReflectable()
class A {}

_main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
}

main() {
  initializeReflectable();
  return _main();
}""",
    "a|main_reflection_data.dart": """
library main_reflection_data.dart;
import "package:reflectable/src/mirrors_unimpl.dart" as r;
import "package:reflectable/reflectable.dart" show isTransformed;
import "dart:core";
import 'main.dart' as prefix0;

initializeReflectable() {
  if (!isTransformed) {
    throw new UnsupportedError(
        "The transformed code is running with the untransformed "
        "reflectable package. Remember to set your package-root to "
        "'build/.../packages'.");
  }
  r.data = {const prefix0.MyReflectable(): new r.ReflectorData([new r.ClassMirrorImpl(r"A", r".A", 0, const prefix0.MyReflectable(), [0], [], -1, {}, {}, {r"": () => new prefix0.A()}, null)], [new r.MethodMirrorImpl(r"", 64, 0, const prefix0.MyReflectable(), null)], [prefix0.A], {}, {})};
}
"""
  }
];


checkTransform(List maps) async {
  Map<String, String> inputs = maps[0];
  Map<String, String> expectedOutputs = maps[1];
  TestAggregateTransform transform = new TestAggregateTransform(inputs);
  ReflectableTransformer transformer = new ReflectableTransformer.asPlugin(
      new BarbackSettings(
          {"entry_points": ["main.dart"]}, BarbackMode.RELEASE));

  // Test `declareOutputs`.
  TestDeclaringTransform declaringTransform = new TestDeclaringTransform(inputs);
  await transformer.declareOutputs(declaringTransform);
  expect(declaringTransform.outputs, new Set.from(expectedOutputs.keys));
  expect(declaringTransform.consumed, new Set.from([]));

  // Test `apply`.
  await transformer.apply(transform);
  Map<String, String> outputs = await transform.outputMap();
  expect(transform.messages.isEmpty, true);
  expect(outputs.length, expectedOutputs.length);
  outputs.forEach((key, value) {
    // The error message is nicer when the strings are compared separately
    // instead of comparing Maps.
    expect(value, expectedOutputs[key]);
  });
}

main() async {
  test("Check transforms", () async {
    await checkTransform(useReflect);
  });
}
