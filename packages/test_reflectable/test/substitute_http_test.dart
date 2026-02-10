// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test the special casing of declarations in 'dart:_http'.

library test_reflectable.test.substitute_http_test;

import 'dart:io';

@GlobalQuantifyCapability(r'\.Cookie$', reflector)
import 'package:reflectable/reflectable.dart';

import 'substitute_http_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
    : super(
        instanceInvokeCapability,
        declarationsCapability,
        superclassQuantifyCapability,
        typeAnnotationQuantifyCapability,
      );
}

const reflector = Reflector();

@reflector
class CookieHolder extends HttpException {
  CookieHolder(super._);
  final Cookie? cookie = null;
}

void main() {
  initializeReflectable();
  // Just checking that the program compiles, that is, it does not
  // attempt to import `dart:_http`.
}
