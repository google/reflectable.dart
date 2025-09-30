// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Accesses the types of instance fields and static fields.

library test_reflectable.test.field_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'field_test.reflectable.dart';

class FieldReflector extends Reflectable {
  const FieldReflector()
    : super(
        typeAnnotationQuantifyCapability,
        invokingCapability,
        declarationsCapability,
        typeRelationsCapability,
        metadataCapability,
      );
}

const fieldReflector = FieldReflector();

class NoFieldReflector extends Reflectable {
  const NoFieldReflector() : super(invokingCapability, metadataCapability);
}

const noFieldReflector = NoFieldReflector();

@fieldReflector
@noFieldReflector
class A {
  int f1 = 0;
  final String f2 = 'f2';
  static A? f3;
  static final List<num> f4 = <num>[1];
  static const f5 = '42!';
}

void main() {
  initializeReflectable();

  var classMirror = fieldReflector.reflectType(A) as ClassMirror;
  test('instance field properties', () {
    var f1Mirror = classMirror.declarations['f1'] as VariableMirror;
    expect(f1Mirror.simpleName, 'f1');
    expect(f1Mirror.qualifiedName, 'test_reflectable.test.field_test.A.f1');
    expect(f1Mirror.owner, classMirror);
    expect(f1Mirror.isPrivate, isFalse);
    expect(f1Mirror.isTopLevel, isFalse);
    expect(f1Mirror.metadata, <Object>[]);
    expect(f1Mirror.isStatic, isFalse);
    expect(f1Mirror.isFinal, isFalse);
    expect(f1Mirror.isConst, isFalse);
    expect(f1Mirror.type.reflectedType, int);

    var f2Mirror = classMirror.declarations['f2'] as VariableMirror;
    expect(f2Mirror.simpleName, 'f2');
    expect(f2Mirror.qualifiedName, 'test_reflectable.test.field_test.A.f2');
    expect(f2Mirror.owner, classMirror);
    expect(f2Mirror.isPrivate, isFalse);
    expect(f2Mirror.isTopLevel, isFalse);
    expect(f2Mirror.metadata, <Object>[]);
    expect(f2Mirror.isStatic, isFalse);
    expect(f2Mirror.isFinal, isTrue);
    expect(f2Mirror.isConst, isFalse);
    expect(f2Mirror.type.reflectedType, String);
  });

  test('static field properties', () {
    var f3Mirror = classMirror.declarations['f3'] as VariableMirror;
    expect(f3Mirror.simpleName, 'f3');
    expect(f3Mirror.qualifiedName, 'test_reflectable.test.field_test.A.f3');
    expect(f3Mirror.owner, classMirror);
    expect(f3Mirror.isPrivate, isFalse);
    expect(f3Mirror.isTopLevel, isFalse);
    expect(f3Mirror.metadata, <Object>[]);
    expect(f3Mirror.isStatic, isTrue);
    expect(f3Mirror.isFinal, isFalse);
    expect(f3Mirror.isConst, isFalse);
    expect(f3Mirror.type.reflectedType, A);

    var f4Mirror = classMirror.declarations['f4'] as VariableMirror;
    expect(f4Mirror.simpleName, 'f4');
    expect(f4Mirror.qualifiedName, 'test_reflectable.test.field_test.A.f4');
    expect(f4Mirror.owner, classMirror);
    expect(f4Mirror.isPrivate, isFalse);
    expect(f4Mirror.isTopLevel, isFalse);
    expect(f4Mirror.metadata, <Object>[]);
    expect(f4Mirror.isStatic, isTrue);
    expect(f4Mirror.isFinal, isTrue);
    expect(f4Mirror.isConst, isFalse);
    expect(f4Mirror.type.isOriginalDeclaration, false);
    expect(f4Mirror.type.originalDeclaration.simpleName, 'List');

    var f5Mirror = classMirror.declarations['f5'] as VariableMirror;
    expect(f5Mirror.simpleName, 'f5');
    expect(f5Mirror.qualifiedName, 'test_reflectable.test.field_test.A.f5');
    expect(f5Mirror.owner, classMirror);
    expect(f5Mirror.isPrivate, isFalse);
    expect(f5Mirror.isTopLevel, isFalse);
    expect(f5Mirror.metadata, <Object>[]);
    expect(f5Mirror.isStatic, isTrue);
    expect(f5Mirror.isFinal, isTrue); // Yes, a const member `isFinal`, too.
    expect(f5Mirror.isConst, isTrue);
    expect(f5Mirror.type.reflectedType, String);
  });

  test('no field capability', () {
    var classMirror = noFieldReflector.reflectType(A) as ClassMirror;
    expect(
      () => classMirror.declarations,
      throwsA(const TypeMatcher<NoSuchCapabilityError>()),
    );
  });
}
