// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test `reflectedTypeArguments` and `typeArguments` on statically known
// type annotations.

library test_reflectable.test.static_type_arguments_test;

import 'package:unittest/unittest.dart';
import 'package:reflectable/reflectable.dart';
import 'static_type_arguments_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(instanceInvokeCapability, declarationsCapability,
      typeCapability, typeRelationsCapability, reflectedTypeCapability);
}

const Reflector reflector = const Reflector();

@reflector
class SecurityService {}

@reflector
class Provider<X> {}

@reflector
class MyService {
  Provider<SecurityService> securityService;
}

@reflector
class MyGenericService<X extends SecurityService> {
  Provider<X> genericSecurityService;
}

Matcher throwsUnimplemented = throwsA(isUnimplementedError);
Matcher isUnimplementedError = new isInstanceOf<UnimplementedError>();

main() {
  initializeReflectable();

  test('get type arguments', () {
    ClassMirror myServiceMirror = reflector.reflectType(MyService);
    Map<String, DeclarationMirror> declarations = myServiceMirror.declarations;
    VariableMirror securityServiceMirror = declarations['securityService'];
    ClassMirror typeAnnotationMirror = securityServiceMirror.type;
    expect(typeAnnotationMirror.reflectedTypeArguments[0], SecurityService);
    expect(typeAnnotationMirror.typeArguments[0].reflectedType,
        SecurityService);
  });

  test('get type arguments in unimplemented case', () {
    ClassMirror myServiceMirror = reflector.reflectType(MyGenericService);
    Map<String, DeclarationMirror> declarations = myServiceMirror.declarations;
    VariableMirror securityServiceMirror =
        declarations['genericSecurityService'];
    ClassMirror typeAnnotationMirror = securityServiceMirror.type;
    expect(() => typeAnnotationMirror.reflectedTypeArguments,
        throwsUnimplemented);
    expect(() => typeAnnotationMirror.typeArguments, throwsUnimplemented);
  });
}
