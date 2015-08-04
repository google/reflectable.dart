// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Tests that metadata is preserved when the metadataCapability is present.
// TODO(sigurdm): Support for metadata-annotations of arguments.

library test_reflectable.test.metadata_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(
          metadataCapability, instanceInvokeCapability, staticInvokeCapability);
}

const myReflectable = const MyReflectable();

class MyReflectable2 extends Reflectable {
  const MyReflectable2()
      : super(instanceInvokeCapability, staticInvokeCapability);
}

const myReflectable2 = const MyReflectable2();

const b = 13;
const c = const [const Bar(const {"a": 14})];
const d = true;

class K {
  static const p = 2;
}

@myReflectable
@Bar(const {
  b: deprecated,
  c: const Deprecated("tomorrow"),
  1 + 2: (d ? 3 : 4),
  identical(1, 2): "s",
  K.p: 6
})
@b
@c
class Foo {
  @Bar(const {})
  @b
  @c
  foo() {}

  @b
  var x = 10;
}

@myReflectable2
@Bar(const {})
@b
@c
class Foo2 {
  @Bar(const {})
  @b
  @c
  foo() {}
}

class Bar {
  final Map<String, int> m;
  const Bar(this.m);
  toString() => "Bar($m)";
}

main() {
  test("metadata on class", () {
    expect(myReflectable.reflectType(Foo).metadata, [
      const MyReflectable(),
      const Bar(const {
        b: deprecated,
        c: const Deprecated("tomorrow"),
        3: 3,
        false: "s",
        2: 6
      }),
      13,
      const [const Bar(const {"a": 14})]
    ]);

    expect(myReflectable.reflectType(Foo).declarations["foo"].metadata, [
      const Bar(const {}),
      13,
      const [const Bar(const {"a": 14})]
    ]);

    expect(myReflectable.reflectType(Foo).declarations["x"].metadata, [b]);

    // The synthetic accessors do not have metadata.
    expect(myReflectable.reflectType(Foo).instanceMembers["x"].metadata, []);
    expect(myReflectable.reflectType(Foo).instanceMembers["x="].metadata, []);
  });
  test("metadata without capability", () {
    expect(() => myReflectable2.reflectType(Foo2).metadata,
        throwsA(const isInstanceOf<NoSuchCapabilityError>()));

    expect(() => myReflectable2.reflectType(Foo2).declarations["foo"].metadata,
        throwsA(const isInstanceOf<NoSuchCapabilityError>()));
  });
}
