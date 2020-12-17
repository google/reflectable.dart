// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

/// File used to test reflectable code generation.
/// Part of the entry point 'meta_reflectors_test.dart'.
///
/// Independence: This library defines reflectors only, and it does not depend
/// on domain classes (`M1..3, A..D, P`) nor on the usage of reflection, i.e.,
/// these reflectors could have been defined in a third-party package .
library test_reflectable.test.meta_reflectors_definer;

import 'package:reflectable/reflectable.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, declarationsCapability,
            typeRelationsCapability, libraryCapability);
}

class Reflector2 extends Reflectable {
  const Reflector2()
      : super(invokingCapability, typeRelationsCapability, metadataCapability,
            libraryCapability);
}

class ReflectorUpwardsClosed extends Reflectable {
  const ReflectorUpwardsClosed()
      : super(superclassQuantifyCapability, invokingCapability,
            declarationsCapability, typeRelationsCapability);
}
