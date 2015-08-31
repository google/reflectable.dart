// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test_reflectable.test.capabilities_test;

import 'package:unittest/unittest.dart';
import 'package:reflectable/reflectable.dart' as r;
import 'package:reflectable/capability.dart' as c;

// Tests that reflection is constrained according to capabilities.
// TODO(sigurdm) implement: Write tests that covers all capabilities.
// TODO(sigurdm) implement: Write tests that covers top-level invocations.

class MyReflectableStatic extends r.Reflectable {
  const MyReflectableStatic() : super(const c.StaticInvokeCapability("foo"),
          const c.StaticInvokeCapability("getFoo"),
          const c.StaticInvokeCapability("setFoo="),
          const c.StaticInvokeCapability("nonExisting"),
          const c.StaticInvokeMetaCapability(C),
          c.declarationsCapability);
}

@MyReflectableStatic()
class A {
  static int foo() => 42;
  static int bar() => 43;
  static int get getFoo => 44;
  static int get getBar => 45;
  static set setFoo(int x) => field = x;
  static set setBar(int x) => field = x;
  static int field = 46;
  @C()
  static int boo() => 47;
}

class C {
  const C();
}

class MyReflectableInstance extends r.Reflectable {
  const MyReflectableInstance() : super(const c.InstanceInvokeCapability("foo"),
          const c.InstanceInvokeCapability("getFoo"),
          const c.InstanceInvokeCapability("setFoo="),
          const c.InstanceInvokeCapability("nonExisting"),
          const c.InstanceInvokeMetaCapability(C),
          c.declarationsCapability);
}

@MyReflectableInstance()
class B {
  int foo() => 42;
  int bar() => 43;
  int get getFoo => 44;
  int get getBar => 45;
  set setFoo(int x) => field = x;
  set setBar(int x) => field = x;
  int field = 46;
  @C()
  int boo() => 47;
}

class BSubclass extends B {}

class BImplementer implements B {
  int foo() => 42;
  int bar() => 43;
  int get getFoo => 44;
  int get getBar => 45;
  set setFoo(int x) => field = x;
  set setBar(int x) => field = x;
  int field = 46;
  int boo() => 47;
}

Matcher throwsNoSuchCapabilityError = throwsA(isNoSuchCapabilityError);
Matcher isNoSuchCapabilityError = new isInstanceOf<c.NoSuchCapabilityError>();

class MyReflectableWithMetaCap extends r.Reflectable {
  const MyReflectableWithMetaCap() : super(c.metadataCapability, c.invokingCapability);
}

const myReflectableWithMetaCap = const MyReflectableWithMetaCap();

class AnnotationClass {
  const AnnotationClass();
}

@myReflectableWithMetaCap
class AnnotatedWithoutConstructor {
  @AnnotationClass()
  String someField;
}


void testDynamic(B o, String description) {
  test("Dynamic invocation $description", () {
    expect(const MyReflectableInstance().canReflect(o), true);
    expect(const MyReflectableInstance().canReflectType(o.runtimeType), true);
    r.InstanceMirror instanceMirror = const MyReflectableInstance().reflect(o);
    expect(instanceMirror.invoke("foo", []), 42);
    expect(instanceMirror.invoke("boo", []), 47);
    expect(() {
      instanceMirror.invoke("bar", []);
    }, throwsNoSuchCapabilityError);
    expect(instanceMirror.invokeGetter("getFoo"), 44);
    expect(() {
      instanceMirror.invokeGetter("getBar");
    }, throwsNoSuchCapabilityError);
    expect(o.field, 46);
    expect(instanceMirror.invokeSetter("setFoo=", 100), 100);
    expect(o.field, 100);
    expect(() {
      instanceMirror.invokeSetter("setBar=", 100);
    }, throwsNoSuchCapabilityError);

  });
}

void main() {
  test("Static invocation", () {
    r.ClassMirror classMirror = const MyReflectableStatic().reflectType(A);
    expect(classMirror.invoke("foo", []), 42);
    expect(() {
      classMirror.invoke("bar", []);
    }, throwsNoSuchCapabilityError);
    expect(classMirror.invokeGetter("getFoo"), 44);
    expect(() {
      classMirror.invokeGetter("getBar");
    }, throwsNoSuchCapabilityError);
    expect(A.field, 46);
    expect(classMirror.invokeSetter("setFoo=", 100), 100);
    expect(A.field, 100);
    expect(() {
      classMirror.invokeSetter("setBar=", 100);
    }, throwsNoSuchCapabilityError);
    expect(classMirror.declarations.keys,
        ["foo", "setFoo=", "getFoo", "boo"].toSet());
    expect(classMirror.invoke("boo", []), 47);
  });
  testDynamic(new B(), "Annotated");
  test("Declarations", () {
    expect(
        const MyReflectableInstance().reflect(new B()).type.declarations.keys,
        ["foo", "setFoo=", "getFoo", "boo"].toSet());
  });

  test("Can't reflect subclass of annotated", () {
    expect(const MyReflectableInstance().canReflect(new BSubclass()), false);
    expect(const MyReflectableInstance().canReflectType(BSubclass), false);
    expect(() {
      const MyReflectableInstance().reflect(new BSubclass());
    }, throwsNoSuchCapabilityError);
  });

  test("Can't reflect subtype of annotated", () {
    expect(const MyReflectableInstance().canReflect(new BImplementer()), false);
    expect(const MyReflectableInstance().canReflectType(BImplementer), false);
    expect(() {
      const MyReflectableInstance().reflect(new BImplementer());
    }, throwsNoSuchCapabilityError);
  });

  test("Can't reflect unnanotated", () {
    expect(() {
      expect(const MyReflectableInstance().canReflect(new Object()), false);
      expect(const MyReflectableInstance().canReflectType(Object), false);
      const MyReflectableInstance().reflect(new Object());
    }, throwsNoSuchCapabilityError);
  });

  test("Annotated Capability", () {
    var awcMirror = myReflectableWithMetaCap.reflectType(AnnotatedWithoutConstructor);
    expect(awcMirror.declarations['someField'].metadata, equals([const AnnotationClass()]));
  });
}
