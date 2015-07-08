// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable.check_literal_transform_test;

/// Test the literal output of the transformation for a few simple cases.

import "package:reflectable/src/transformer_implementation.dart";
import "package:reflectable/test_transform.dart";
import "package:unittest/unittest.dart";

var useReflect = [{"a|main.dart": """
import 'package:reflectable/reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(newInstanceCapability);
}

@MyReflectable()
class A {}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
}

"""}, {"a|main.dart": """
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

void main() {
  initializeReflectable();
  _main();
}""", "a|main_reflection_data.dart": """
library main_reflection_data.dart;
import "package:reflectable/src/mirrors_unimpl.dart" as r;
import 'main.dart';

initializeReflectable() {
  r.data = {const MyReflectable(): new r.ReflectorData([new r.ClassMirrorImpl("A", ".A", 0, const MyReflectable(), [0], [], -1, {}, {}, {"": () => new A()}, null)], [new r.MethodMirrorImpl("", 64, 0, const MyReflectable())], [A], {}, {})};
}
"""}];

checkTransform(List maps) async {
  Map<String, String> inputs = maps[0];
  Map<String, String> expectedOutputs = maps[1];
  TestAggregateTransform transform =
      new TestAggregateTransform(inputs);
  await new TransformerImplementation().apply(transform, ["main.dart"]);
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
