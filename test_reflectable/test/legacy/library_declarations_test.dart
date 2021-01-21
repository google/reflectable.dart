// Copyright (c) 2019, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

// File used to test reflectable code generation.
// Looks up the top-level declarations in a library.

@reflector
library test_reflectable.test.library_declarations_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'library_declarations_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(instanceInvokeCapability, topLevelInvokeCapability,
            declarationsCapability, reflectedTypeCapability, libraryCapability);
}

const reflector = Reflector();

@reflector
abstract class A {}

@reflector
class B extends A {}

@reflector
typedef F = void Function(int);

@reflector
typedef G<X> = double Function(X);

@reflector
typedef H = String Function<X>(X);

void main() {
  initializeReflectable();

  var libraryMirror =
      reflector.findLibrary('test_reflectable.test.library_declarations_test');
  var declarations = libraryMirror.declarations;

  // Commented out below: Cf. reflectable issue #165.

  test('library declarations', () {
    expect(declarations['reflector'].simpleName, 'reflector');
    expect(declarations['A'].simpleName, 'A');
    expect(declarations['B'].simpleName, 'B');
    // expect(declarations['F'].simpleName, 'F');
    // expect(declarations['G'].simpleName, 'G');
    // expect(declarations['H'].simpleName, 'H');
    expect(declarations['main'].simpleName, 'main');

    expect(declarations['reflector'] is VariableMirror, isTrue);
    expect(declarations['A'] is ClassMirror, isTrue);
    expect(declarations['B'] is ClassMirror, isTrue);
    // expect(declarations['F'] is TypedefMirror, isTrue);
    // expect(declarations['G'] is TypedefMirror, isTrue);
    // expect(declarations['H'] is TypedefMirror, isTrue);
    expect(declarations['main'] is MethodMirror, isTrue);

    ClassMirror aMirror = declarations['A'];
    ClassMirror bMirror = declarations['B'];
    // TypedefMirror fMirror = declarations['F'];
    // TypedefMirror gMirror = declarations['G'];
    // TypedefMirror hMirror = declarations['H'];

    expect(aMirror.hasReflectedType, isTrue);
    expect(bMirror.hasReflectedType, isTrue);
    // expect(fMirror.hasReflectedType, isTrue);
    // expect(gMirror.hasReflectedType, isTrue); // I2b?
    // expect(hMirror.hasReflectedType, isTrue);

    expect(aMirror.reflectedType, A);
    expect(bMirror.reflectedType, B);
    // expect(fMirror.reflectedType, F);
    // expect(gMirror.reflectedType, G); // G<dynamic>?
    // expect(hMirror.reflectedType, H);
  });
}
