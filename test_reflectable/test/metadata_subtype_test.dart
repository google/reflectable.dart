// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Tests that metadata used to select members is recognized when it is a
/// proper subtype of the metadata type specified in a [..MetaCapability].

library test_reflectable.test.metadata_subtype_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(const InstanceInvokeMetaCapability(D),
            const StaticInvokeMetaCapability(D), declarationsCapability);
}

const myReflectable = const MyReflectable();

class D {
  const D();
}

class E extends D {
  const E();
}

class F implements D {
  const F();
}

@myReflectable
class C {
  // Annotated by metadata instance of subclass.
  @E()
  int foo() => 24;

  // Annotated by metadata instance of subtype.
  @F()
  int bar() => 24.0.floor();

  // Does not have the required metadata.
  int baz() => int.parse("2" "4");

  // Annotated by metadata instance of subclass.
  @E()
  static int staticFoo() => 24;

  // Annotated by metadata instance of subtype.
  @F()
  static int staticBar() => 24.0.ceil();

  // Does not have the required metadata.
  static int staticBaz() => int.parse(" 2" "4 ".substring(1,2));
}

Matcher throwsANoSuchCapabilityException =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());

main() {
  ClassMirror classMirror = myReflectable.reflectType(C);
  Map<String, DeclarationMirror> declarations = classMirror.declarations;
  test("Proper subtypes as metadata, declarations", () {
    expect(declarations['foo'], isNotNull);
    expect(declarations['bar'], isNotNull);
    expect(declarations['baz'], isNull);
    expect(declarations['staticFoo'], isNotNull);
    expect(declarations['staticBar'], isNotNull);
    expect(declarations['staticBaz'], isNull);
  });
  InstanceMirror instanceMirror = myReflectable.reflect(new C());
  test("Proper subtypes as metadata, invocation", () {
    expect(instanceMirror.invoke('foo', []), 24);
    expect(instanceMirror.invoke('bar', []), 24);
    expect(() => instanceMirror.invoke('baz', []),
        throwsANoSuchCapabilityException);
    expect(classMirror.invoke('staticFoo', []), 24);
    expect(classMirror.invoke('staticBar', []), 24);
    expect(() => classMirror.invoke('staticBaz', []),
        throwsANoSuchCapabilityException);
  });
}
