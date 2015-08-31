// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests some basic functionality of instance mirrors and class mirrors.

library test_reflectable.test.basic_test;

import 'package:unittest/unittest.dart';
import 'package:reflectable/reflectable.dart' as r;
import 'package:reflectable/capability.dart';

class MyReflectable extends r.Reflectable {
  const MyReflectable()
      : super(instanceInvokeCapability, newInstanceCapability,
            declarationsCapability);
}

@MyReflectable()
class A {
  var foo;
  instanceMethod(x) => 'A:instanceMethod($x)';
  get accessor => 'A:get accessor';
  set accessor(x) {
    accessorBackingStorageA = x;
  }

  aMethod() => 'aMethod';
}

@MyReflectable()
class B extends A {
  get foo => 'B:get field';
  instanceMethod(x) => 'B:instanceMethod($x)';
  get accessor => 'B:get accessor';
  set accessor(x) {
    accessorBackingStorageB = x;
  }

  bMethod() => 'bMethod';
}

@MyReflectable()
class C extends B {
  set foo(x) {
    fooBackingStorageC = x;
  }

  instanceMethod(x) => 'C:instanceMethod($x)';
  get accessor => 'C:get accessor';
  set accessor(x) {
    accessorBackingStorageC = x;
  }

  cMethod() => 'cMethod';
}

List<r.DeclarationMirror> filteredDeclarationsOf(r.ClassMirror cm, predicate) {
  var result = new List();
  cm.declarations.forEach((k, v) {
    if (predicate(v)) {
      result.add(v);
    }
  });
  return result;
}

// These fields are used to test that setters work properly.
// As all instances share the same backing they can only be used for testing
// one instance.
var accessorBackingStorageA;
var accessorBackingStorageB;
var accessorBackingStorageC;
var fooBackingStorageC;

List<r.VariableMirror> variablesOf(r.ClassMirror cm) {
  return filteredDeclarationsOf(cm, (v) => v is r.VariableMirror);
}

List<r.MethodMirror> gettersOf(r.ClassMirror cm) {
  return filteredDeclarationsOf(cm, (v) => v is r.MethodMirror && v.isGetter);
}

List<r.MethodMirror> settersOf(r.ClassMirror cm) {
  return filteredDeclarationsOf(cm, (v) => v is r.MethodMirror && v.isSetter);
}

List<r.MethodMirror> methodsOf(r.ClassMirror cm) {
  return filteredDeclarationsOf(
      cm, (v) => v is r.MethodMirror && v.isRegularMethod);
}

Matcher throwsNoSuchCapabilityError = throwsA(isNoSuchCapabilityError);
Matcher throwsNoSuchMethodError = throwsA(isNoSuchMethodError);
Matcher isNoSuchCapabilityError = new isInstanceOf<NoSuchCapabilityError>();
Matcher isNoSuchMethodError = new isInstanceOf<NoSuchMethodError>();

main() {
  var unnamed = '';
  var foo = 'foo';
  var fooSetter = 'foo=';
  var instanceMethod = 'instanceMethod';
  var accessor = 'accessor';
  var accessorSetter = 'accessor=';
  var aMethod = 'aMethod';
  var bMethod = 'bMethod';
  var cMethod = 'cMethod';

  r.Reflectable reflectable = const MyReflectable();

  r.ClassMirror aClass = reflectable.reflectType(A);
  r.ClassMirror bClass = reflectable.reflectType(B);
  r.ClassMirror cClass = reflectable.reflectType(C);

  r.InstanceMirror aM = reflectable.reflect(aClass.newInstance(unnamed, []));
  r.InstanceMirror bM = reflectable.reflect(bClass.newInstance(unnamed, []));
  r.InstanceMirror cM = reflectable.reflect(cClass.newInstance(unnamed, []));

  test('get field', () {
    expect(aM.invokeGetter(foo), isNull);
    expect(bM.invokeGetter(foo), 'B:get field');
    expect(cM.invokeGetter(foo), 'B:get field');
  });

  test('set field', () {
    aM.invokeSetter(fooSetter, 42);
    bM.invokeSetter(fooSetter, 87);
    cM.invokeSetter(fooSetter, 89);
    expect(aM.invokeGetter(foo), 42);
    expect(bM.invokeGetter(foo), 'B:get field');
    expect(cM.invokeGetter(foo), 'B:get field');
    expect(fooBackingStorageC, 89);
  });

  test('field variables', () {
    expect(variablesOf(aClass).map((x) => x.simpleName), ["foo"]);
    expect(variablesOf(bClass), []);
    expect(variablesOf(cClass), []);
  });

  test('invoke instance method', () {
    expect(aM.invoke(instanceMethod, [7]), 'A:instanceMethod(7)');
    expect(bM.invoke(instanceMethod, [9]), 'B:instanceMethod(9)');
    expect(cM.invoke(instanceMethod, [13]), 'C:instanceMethod(13)');
  });

  test('getters', () {
    expect(aM.invokeGetter(accessor), 'A:get accessor');
    expect(bM.invokeGetter(accessor), 'B:get accessor');
    expect(bM.invokeGetter(accessor), 'B:get accessor');
  });

  test('setters', () {
    expect(aM.invokeSetter(accessorSetter, "foo"), 'foo');
    expect(bM.invokeSetter(accessorSetter, "bar"), 'bar');
    expect(cM.invokeSetter(accessorSetter, "baz"), 'baz');

    expect(accessorBackingStorageA, 'foo');
    expect(accessorBackingStorageB, 'bar');
    expect(accessorBackingStorageC, 'baz');
  });

  test('aMethod', () {
    expect(aM.invoke(aMethod, []), "aMethod");
    expect(bM.invoke(aMethod, []), "aMethod");
    expect(cM.invoke(aMethod, []), "aMethod");
  });

  test('bMethod', () {
    expect(() => aM.invoke(bMethod, []), throwsNoSuchMethodError);
    expect(bM.invoke(bMethod, []), "bMethod");
    expect(cM.invoke(bMethod, []), "bMethod");
  });

  test('cMethod', () {
    expect(() => aM.invoke(cMethod, []), throwsNoSuchMethodError);
    expect(() => bM.invoke(cMethod, []), throwsNoSuchMethodError);
    expect(cM.invoke(cMethod, []), "cMethod");
  });

  test('getters and setters', () {
    expect(gettersOf(aClass).map((x) => x.simpleName), ["accessor"]);
    expect(gettersOf(bClass).map((x) => x.simpleName),
        ["accessor", "foo"].toSet());
    expect(gettersOf(cClass).map((x) => x.simpleName), ["accessor"]);
    expect(settersOf(aClass).map((x) => x.simpleName), ["accessor="]);
    expect(settersOf(bClass).map((x) => x.simpleName), ["accessor="].toSet());
    expect(settersOf(cClass).map((x) => x.simpleName),
        ["accessor=", "foo="].toSet());
    expect(methodsOf(aClass).map((x) => x.simpleName),
        ["instanceMethod", "aMethod"].toSet());
    expect(methodsOf(bClass).map((x) => x.simpleName),
        ["instanceMethod", "bMethod"].toSet());
    expect(methodsOf(cClass).map((x) => x.simpleName),
        ["instanceMethod", "cMethod"].toSet());
  });
}
