// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Tests that metadata is preserved when the metadataCapability is present.
// TODO(sigurdm): Support for metadata-annotations of members.
// TODO(sigurdm): Support for metadata-anmntations of arguments.
library reflectable.test.to_be_transformed.metadata_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(metadataCapability);
}

const myReflectable = const MyReflectable();

class MyReflectable2 extends Reflectable {
  const MyReflectable2() : super();
}

const myReflectable2 = const MyReflectable2();

const b = 13;
const c = const [const Bar(const {"a": 14})];

@myReflectable
@Bar(const {})
@b
@c
class Foo {}

@myReflectable2
@Bar(const {})
@b
@c
class Foo2 {}

class Bar {
  final Map<String, int> m;
  const Bar(this.m);
}

main() {
  test("metadata on class", () {
    expect(myReflectable.reflectType(Foo).metadata, [
      const MyReflectable(),
      const Bar(const {}),
      13,
      const [const Bar(const {"a": 14})]
    ]);
  });
  test("metadata without capability", () {
    expect(() => myReflectable2.reflectType(Foo2).metadata,
        throwsA(const isInstanceOf<NoSuchCapabilityError>()));
  });
}
