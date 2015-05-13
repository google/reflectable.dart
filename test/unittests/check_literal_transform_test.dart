// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable.check_literal_transform_test;

/// Test the literal output of the transformation for a few simple cases.

import "package:reflectable/src/transformer_implementation.dart";
import "package:reflectable/test_transform.dart";
import "package:unittest/unittest.dart";

var noReflectable = [{"a|main.dart": """
main() {}
"""}, {}];

var importReflectable = [{"a|main.dart": """
import 'package:reflectable/reflectable.dart';
"""}, {"a|main.dart": """
// This file has been transformed by reflectable.
// Import modified by reflectable:
import 'package:reflectable/static_reflectable.dart';
"""}];

var useAnnotation = [{"a|main.dart": """
import 'package:reflectable/reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
}

@MyReflectable()
class A {}
"""}, {"a|main.dart": """
// This file has been transformed by reflectable.
// Import modified by reflectable:
import 'package:reflectable/static_reflectable.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
  // Generated: Rest of class
  InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == A) {
      return new Static_A_InstanceMirror(reflectee);
    }
    throw new UnimplementedError("`reflect` on unexpected object '\$reflectee'");
  }
}

@MyReflectable()
class A {}

// Generated: Rest of file

class Static_A_ClassMirror extends ClassMirrorUnimpl {
}

class Static_A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  Static_A_InstanceMirror(this.reflectee);
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
  }
}
"""}];

var useReflect = [{"a|main.dart": """
import 'package:reflectable/reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
}
"""}, {"a|main.dart": """
// This file has been transformed by reflectable.
// Import modified by reflectable:
import 'package:reflectable/static_reflectable.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
  // Generated: Rest of class
  InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == A) {
      return new Static_A_InstanceMirror(reflectee);
    }
    throw new UnimplementedError("`reflect` on unexpected object '\$reflectee'");
  }
}

const myReflectable = const MyReflectable();

@myReflectable
class A {}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
}

// Generated: Rest of file

class Static_A_ClassMirror extends ClassMirrorUnimpl {
}

class Static_A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  Static_A_InstanceMirror(this.reflectee);
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
  }
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
  checkTransform(noReflectable);
  checkTransform(importReflectable);
  checkTransform(useAnnotation);
  checkTransform(useReflect);
}