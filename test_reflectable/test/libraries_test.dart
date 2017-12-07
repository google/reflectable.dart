// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses library mirrors and `invoke` on top level entities.

@reflector
library test_reflectable.test.libraries_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'libraries_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(
            libraryCapability,
            const TopLevelInvokeCapability(r"^myFunction$"),
            declarationsCapability);
}

class Reflector2 extends Reflectable {
  const Reflector2()
      : super(reflectedTypeCapability, const TopLevelInvokeMetaCapability(Test),
            declarationsCapability, libraryCapability, metadataCapability);
}

class Reflector3 extends Reflectable {
  const Reflector3() : super(typeCapability);
}

const reflector = const Reflector();
const reflector2 = const Reflector2();
const reflector3 = const Reflector3();

@reflector2
class C {}

@reflector3
class D {}

myFunction() => "hello";

class Test {
  const Test();
}

@Test()
var p = 10;

@Test()
const int q = 11;

@Test()
set setter(x) => p = x + 1;

@Test()
get getter => "10";

final Matcher throwsNoCapability =
    throwsA(const isInstanceOf<NoSuchCapabilityError>());

final Matcher throwsReflectableNoMethod =
    throwsA(const isInstanceOf<ReflectableNoSuchMethodError>());

main() {
  initializeReflectable();

  test('invoke function, getter', () {
    LibraryMirror libraryMirror =
        reflector.findLibrary('test_reflectable.test.libraries_test');
    expect(libraryMirror.simpleName, 'test_reflectable.test.libraries_test');
    expect(libraryMirror.invoke('myFunction', []), 'hello');
    expect(
        Function.apply(libraryMirror.invokeGetter('myFunction'), []), 'hello');
    expect(
        () => libraryMirror.invokeGetter("getter"), throwsReflectableNoMethod);
    MethodMirror myFunctionMirror = libraryMirror.declarations["myFunction"];
    expect(myFunctionMirror.owner, libraryMirror);
  });
  test('owner, setter, TopLevelMetaInvokeCapability', () {
    LibraryMirror libraryMirror = reflector2.reflectType(C).owner;
    expect(libraryMirror.qualifiedName, "test_reflectable.test.libraries_test");
    expect(libraryMirror.simpleName, "test_reflectable.test.libraries_test");
    expect(libraryMirror.invokeSetter('setter=', 11), 11);
    expect(p, 12);
    expect(libraryMirror.invokeGetter("getter"), "10");
    VariableMirror pMirror = libraryMirror.declarations["p"];
    VariableMirror qMirror = libraryMirror.declarations["q"];
    MethodMirror getterMirror = libraryMirror.declarations["getter"];
    MethodMirror setterMirror = libraryMirror.declarations["setter="];
    expect(pMirror.owner, libraryMirror);
    expect(pMirror.hasReflectedType, true);
    expect(pMirror.reflectedType, dynamic);
    expect(pMirror.metadata.length, 1);
    expect(pMirror.metadata[0], const Test());
    expect(pMirror.isConst, false);
    expect(qMirror.owner, libraryMirror);
    expect(qMirror.hasReflectedType, true);
    expect(qMirror.reflectedType, int);
    expect(qMirror.metadata.length, 1);
    expect(qMirror.metadata[0], const Test());
    expect(qMirror.isConst, true);
    expect(getterMirror.owner, libraryMirror);
    expect(setterMirror.owner, libraryMirror);
  });
  test("No libraryCapability", () {
    expect(() => reflector3.reflectType(D).owner, throwsNoCapability);
    expect(
        () => reflector3
            .findLibrary("test_reflectable.test.libraries_test")
            .owner,
        throwsNoCapability);
  });
}
