// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.mixin_application_static_member_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'mixin_application_static_member_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, declarationsCapability, libraryCapability,
            typeRelationsCapability);
}

@Reflector()
class M {
  static dynamic staticFoo(x) => x + 1;
}

@Reflector()
class A {
  static dynamic staticFoo(x) => x + 2;
}

@Reflector()
class B extends A with M {}

Matcher throwsReflectableNoMethod =
    throwsA(const TypeMatcher<ReflectableNoSuchMethodError>());

void main() {
  initializeReflectable();

  test('Mixin-application invoke', () {
    TypeMirror typeMirror = const Reflector().reflectType(B)!;
    expect(typeMirror is ClassMirror, true);
    var classMirror = typeMirror as ClassMirror;
    expect(() => classMirror.invoke('staticFoo', [10]),
        throwsReflectableNoMethod);
  });
  test('Mixin-application static member', () {
    TypeMirror typeMirror = const Reflector().reflectType(B)!;
    expect(typeMirror is ClassMirror, true);
    var classMirror = typeMirror as ClassMirror;
    expect(classMirror.superclass!.declarations['staticFoo'], null);
  });
}
