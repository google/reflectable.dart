// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.global_quantify_test;

@GlobalQuantifyCapability(
    r'^test_reflectable.test.global_quantify_test.(A|B)$', reflector)
@GlobalQuantifyMetaCapability(Mark, reflector)
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'global_quantify_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(typeCapability, const InstanceInvokeCapability('foo'));
}

const reflector = Reflector();

class Mark {
  const Mark();
}

class A {
  int foo() => 42;
}

class B {
  int foo() => 43;
}

class C {
  int foo() => 44;
}

@Mark()
class D {
  int foo() => 45;
}

Matcher throwsNoSuchCapabilityError =
    throwsA(const TypeMatcher<NoSuchCapabilityError>());

void main() {
  initializeReflectable();

  test('GlobalQuantifyCapability', () {
    expect(reflector.canReflectType(A), true);
    expect(reflector.canReflect(A()), true);
    expect(reflector.reflectType(A), const TypeMatcher<ClassMirror>());
    expect(reflector.reflect(A()).invoke('foo', []), 42);
    expect(reflector.canReflectType(B), true);
    expect(reflector.canReflect(B()), true);
    expect(reflector.reflectType(B), const TypeMatcher<ClassMirror>());
    expect(reflector.reflect(B()).invoke('foo', []), 43);
    expect(reflector.canReflectType(C), false);
    expect(reflector.canReflect(C()), false);
    expect(() => reflector.reflectType(C), throwsNoSuchCapabilityError);
    expect(() => reflector.reflect(C()), throwsNoSuchCapabilityError);
  });
  test('GlobalQuantifyMetaCapability', () {
    expect(reflector.canReflectType(D), true);
    expect(reflector.canReflect(D()), true);
    expect(reflector.reflect(D()).invoke('foo', []), 45);
  });
}
