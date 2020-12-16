// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// @dart=2.9

// Testing the basic set of features that are needed for polymer.

library test_reflectable.test.polymer_basic_needs_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'polymer_basic_needs_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

/// This class was used to separate Jacob Macdonald's Polymer example from
/// the package `smoke`, such that it was made possible to create a variant
/// of his example building on both `reflectable` and `smoke`, making the
/// choice simply by changing an `import`. We keep it here in order to make
/// it possible to see the common elements among the Polymer related tests.
class ThinDeclarationMirror {
  final String name;
  final bool isField;
  final bool isProperty;
  final bool isFinal;
  final bool isMethod;
  ThinDeclarationMirror(
      this.name, this.isField, this.isProperty, this.isFinal, this.isMethod);
}

bool _hasSetter(ClassMirror cls, MethodMirror getter) {
  var mirror = cls.declarations[_setterName(getter.simpleName)];
  return mirror is MethodMirror && mirror.isSetter;
}

String _setterName(String getter) => '$getter=';

ThinDeclarationMirror makeThin(DeclarationMirror declaration) {
  bool isField() => declaration is VariableMirror;

  bool isProperty() =>
      declaration is MethodMirror && !declaration.isRegularMethod;

  bool isFinal() => (declaration is VariableMirror && declaration.isFinal) ||
      (declaration is MethodMirror &&
          declaration.isGetter &&
          !_hasSetter(declaration.owner, declaration));

  bool isMethod() => !isField() && !isProperty();

  return ThinDeclarationMirror(declaration.simpleName,
      declaration is VariableMirror, isProperty(), isFinal(), isMethod());
}

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(instanceInvokeCapability, declarationsCapability);
}

const myReflectable = MyReflectable();

List<DeclarationMirror> _query(Type dartType) {
  ClassMirror mirror = myReflectable.reflectType(dartType);
  return mirror.declarations.values.toList();
}

List<ThinDeclarationMirror> buildMirrors(Type dartType) {
  return _query(dartType).map(makeThin).toList();
}

Object read(Object instance, String name) {
  var mirror = myReflectable.reflect(instance);
  return mirror.invokeGetter(name);
}

void write(Object instance, String name, Object value) {
  var mirror = myReflectable.reflect(instance);
  mirror.invokeSetter(name, value);
}

Object invoke(Object instance, String name, List<Object> newArgs) {
  var mirror = myReflectable.reflect(instance);
  // TODO(eernst) future: fix up the `newArgs` to emulate `adjust: true`.
  return mirror.invoke(name, newArgs);
}

@myReflectable
class A {
  int i = 0;
  String foo() => i == 42 ? 'OK!' : 'Error!';
  void bar(int i) {
    this.i = i;
  }
}

void main() {
  initializeReflectable();

  test('Polymer basic needs', () {
    List<ThinDeclarationMirror> thinDeclarations = buildMirrors(A);

    // Check in a few ways that the thin declarations are as expected.
    expect(thinDeclarations.length, 3);
    for (ThinDeclarationMirror thinDeclaration in thinDeclarations) {
      if (thinDeclaration.name == 'i') {
        expect(thinDeclaration.isField, isTrue);
        expect(thinDeclaration.isFinal, isFalse);
      } else if (thinDeclaration.name == 'foo') {
        expect(thinDeclaration.isMethod, isTrue);
        expect(thinDeclaration.isFinal, isFalse);
        expect(thinDeclaration.isField, isFalse);
      } else {
        String name = thinDeclaration.name;
        expect(name == 'bar' || name == 'A', isTrue);
      }
    }

    // Check other methods from `polymer_basic_needs_lib`.
    A a = A();
    write(a, 'i', 7);
    expect(read(a, 'i'), 7);
    invoke(a, 'bar', [42]);
    expect(invoke(a, 'foo', []), 'OK!');
  });
}
