// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflectable code generation.
/// Part of the entry point 'meta_reflectors_test.dart'.
///
/// Independence: This library defines reflectors only, and it does not depend
/// on the usage of reflection. It does depend on the domain classes, because
/// it uses `A` as an upper bound in a superclass quantifier.
library test_reflectable.test.meta_reflectors_domain_definer;

import 'package:reflectable/reflectable.dart';
import 'meta_reflectors_domain.dart';

class ReflectorUpwardsClosedToA extends Reflectable {
  const ReflectorUpwardsClosedToA()
      : super(const SuperclassQuantifyCapability(A), invokingCapability,
            declarationsCapability, typeRelationsCapability);
}

class ReflectorUpwardsClosedUntilA extends Reflectable {
  const ReflectorUpwardsClosedUntilA()
      : super(const SuperclassQuantifyCapability(A, excludeUpperBound: true),
            invokingCapability, declarationsCapability);
}
