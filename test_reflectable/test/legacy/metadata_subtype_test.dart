// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

/// Tests that metadata used to select members is recognized when it is a
/// proper subtype of the metadata type specified in a [..MetaCapability].

library test_reflectable.test.metadata_subtype_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'metadata_subtype_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(const InstanceInvokeMetaCapability(D),
            const StaticInvokeMetaCapability(D), declarationsCapability);
}

const myReflectable = MyReflectable();

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
  int baz() => int.parse('2' '4');

  // Annotated by metadata instance of subclass.
  @E()
  static int staticFoo() => 24;

  // Annotated by metadata instance of subtype.
  @F()
  static int staticBar() => 24.0.ceil();

  // Does not have the required metadata.
  static int staticBaz() => int.parse(' 2' '4 '.substring(1, 2));
}

final Matcher throwsReflectableNoMethod =
    throwsA(const TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  initializeReflectable();

  ClassMirror classMirror = myReflectable.reflectType(C);
  Map<String, DeclarationMirror> declarations = classMirror.declarations;
  test('Proper subtypes as metadata, declarations', () {
    expect(declarations['foo'], isNotNull);
    expect(declarations['bar'], isNotNull);
    expect(declarations['baz'], isNull);
    expect(declarations['staticFoo'], isNotNull);
    expect(declarations['staticBar'], isNotNull);
    expect(declarations['staticBaz'], isNull);
  });
  InstanceMirror instanceMirror = myReflectable.reflect(C());
  test('Proper subtypes as metadata, invocation', () {
    expect(instanceMirror.invoke('foo', []), 24);
    expect(instanceMirror.invoke('bar', []), 24);
    expect(() => instanceMirror.invoke('baz', []), throwsReflectableNoMethod);
    expect(classMirror.invoke('staticFoo', []), 24);
    expect(classMirror.invoke('staticBar', []), 24);
    expect(
        () => classMirror.invoke('staticBaz', []), throwsReflectableNoMethod);
  });
}
