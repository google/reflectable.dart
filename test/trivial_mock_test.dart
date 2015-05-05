// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Run the test_transform on a simple example.

library trivial_mock_test;

import "dart:async";
import "package:reflectable/src/transformer_implementation.dart"
    as implementation;
import "package:unittest/unittest.dart";
import "package:reflectable/test_transform.dart";

Map<String, String> fileMap = {"a|main.dart": """
library main;
import "lib.dart" as lib;
@lib.MyReflectable
class C {}
main() {
  new C();
}
""", "a|lib.dart": """
library "lib";
import "package:reflectable/reflectable.dart";
class MyReflectable extends Reflectable {
  MyReflectable() : super([]);
}
"""};

main() async {
  TestAggregateTransform transform =
      new TestAggregateTransform(fileMap);
  await implementation.apply(transform, ["main.dart"]);
  Map<String, String> result = await transform.outputMap();
  expect(result.length, 2);
  expect(result["a|main.dart"],
         matches(r"// This file has been transformed by reflectable."));
  expect(result["a|main.dart"], matches(r"class Static_C_InstanceMirror"));
  expect(result["a|main.dart"], matches(r"class Static_C_ClassMirror"));
  expect(result["a|lib.dart"],
         matches(r"// This file has been transformed by reflectable."));
  expect(result["a|lib.dart"],
         matches(r"import 'package:reflectable/static_reflectable.dart';"));
  expect(transform.messages.isEmpty, true);
}