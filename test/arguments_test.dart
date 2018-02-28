// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable.test.mock_tests.arguments_test;

/// Check that attempts to have a non-empty argument list in a reflector
/// constructor is detected and diagnosed as an error.

import 'package:barback/barback.dart';
import "package:reflectable/test_transform.dart";
import "package:reflectable/transformer.dart";
import "package:unittest/unittest.dart";

var sources = {
  "a|main.dart": """
import 'package:reflectable/reflectable.dart';

class Reflector extends Reflectable {
  const Reflector(ReflectableCapability capability): super(capability);
}

@Reflector()
class A {}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
}
"""
};

const String package = "a";

main() async {
  BarbackSettings settings = new BarbackSettings({
    "entry_points": ["main.dart"]
  }, BarbackMode.RELEASE);

  test("Verify error at reflector class constructor argument", () async {
    for (String inputName in sources.keys) {
      String inputContents = sources[inputName];
      TestTransform transform =
          new TestTransform(inputName, inputContents, package);
      Transformer transformer = new ReflectableTransformer.asPlugin(settings);
      await transformer.apply(transform);
      await transform.outputMap();
      expect(transform.messages.isNotEmpty, true);
      MessageRecord message = transform.messages[0];
      expect(message.level, LogLevel.ERROR);
      expect(message.message.contains("constructor"), true);
      expect(message.message.contains("argument"), true);
    }
  });
}
