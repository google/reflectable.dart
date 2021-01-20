// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test `reflectedTypeArguments` and `typeArguments` on statically known
// type annotations.

library test_reflectable.test.static_type_arguments_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'static_type_arguments_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector() : super(instanceInvokeCapability, declarationsCapability,
      typeCapability, typeRelationsCapability, reflectedTypeCapability);
}

const Reflector reflector = Reflector();

@reflector
class SecurityService {}

@reflector
class Provider<X> {}

@reflector
class MyService {
  late Provider<SecurityService> securityService;
}

@reflector
class MyGenericService<X extends SecurityService> {
  late Provider<X> genericSecurityService;
}

Matcher throwsUnimplemented = throwsA(isUnimplementedError);
Matcher isUnimplementedError = TypeMatcher<UnimplementedError>();

void main() {
  initializeReflectable();

  test('get type arguments', () {
    var myServiceMirror = reflector.reflectType(MyService) as ClassMirror;
    Map<String, DeclarationMirror> declarations = myServiceMirror.declarations;
    var securityServiceMirror = declarations['securityService']
        as VariableMirror;
    var typeAnnotationMirror = securityServiceMirror.type as ClassMirror;
    expect(typeAnnotationMirror.reflectedTypeArguments[0], SecurityService);
    expect(typeAnnotationMirror.typeArguments[0].reflectedType,
        SecurityService);
  });

  test('get type arguments in unimplemented case', () {
    var myServiceMirror = reflector.reflectType(MyGenericService)
        as ClassMirror;
    Map<String, DeclarationMirror> declarations = myServiceMirror.declarations;
    var securityServiceMirror =
        declarations['genericSecurityService'] as VariableMirror;
    var typeAnnotationMirror = securityServiceMirror.type as ClassMirror;
    expect(() => typeAnnotationMirror.reflectedTypeArguments,
        throwsUnimplemented);
    expect(() => typeAnnotationMirror.typeArguments, throwsUnimplemented);
  });
}
