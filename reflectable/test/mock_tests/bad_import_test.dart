// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Run the test_transform on a simple example.

library reflectable.trivial_mock_test;

import "package:reflectable/src/transformer_implementation.dart";
import "package:unittest/unittest.dart";
import "package:reflectable/src/transformer_errors.dart" as errors;
import "package:reflectable/test_transform.dart";

// File being transformed by the reflectable transformer.
// Imports the core file of this package and declares that
// it should `show` some names (and hide the rest).  The
// use of `show` on this import is not supported, and it
// must give rise to an error during transformation.
Map<String, String> usingShow = {"a|main.dart": """
import 'package:reflectable/reflectable.dart'
    show Reflectable, ReflectCapability;

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
}

@MyReflectable()
class A {}
"""};

// File being transformed by the reflectable transformer.
// Imports the core file of this package and declares that
// it should `hide` some names (and show the rest).  The
// use of `hide` on this import is not supported, and it
// must give rise to an error during transformation.
Map<String, String> usingHide = {"a|main.dart": """
import 'package:reflectable/reflectable.dart'
    hide InvokeStaticMemberCapability;

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
}

@MyReflectable()
class A {}
"""};

// File being transformed by the reflectable transformer.
// Imports the core file of this package and declares that
// it is `deferred`.  The use of a `deferred` modifier on
// this import is not supported, and it must give rise to
// an error during transformation.
Map<String, String> deferredImport = {"a|main.dart": """
import 'package:reflectable/reflectable.dart' deferred as r;
"""};

testError(Map<String, String> fileMap, String expectedError) async {
  TestAggregateTransform transform =
  new TestAggregateTransform(fileMap);
  await new TransformerImplementation().apply(transform, ["main.dart"]);
  Map<String, String> result = await transform.outputMap();
  result['unused key'] = 'ignored value';  // Avoid 'unused variable' hint.
  expect(transform.messages[0].message, expectedError);
}

main() async {
  await testError(usingShow,
                  errors.LIBRARY_UNSUPPORTED_SHOW);
  await testError(usingHide,
                  errors.LIBRARY_UNSUPPORTED_HIDE);
  await testError(deferredImport,
                  errors.LIBRARY_UNSUPPORTED_DEFERRED);
}