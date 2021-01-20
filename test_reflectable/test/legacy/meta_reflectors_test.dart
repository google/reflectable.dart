// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

/// File used to test reflectable code generation.
/// Creates a `MetaReflector` which may be used to reflect on the set of
/// reflectors themselves.
///
/// Independence: This is the only library in this program where both the
/// reflector classes and the domain classes are seen together. The program
/// as a whole illustrates a number of ways in which it is possible to make
/// reflection, usage of reflection, and application specific classes (here
/// known as 'domain classes') independent of each other, statically and
/// dynamically.
library test_reflectable.test.meta_reflectors_test;

@GlobalQuantifyCapability(r'\.(M1|M2|M3|A|B|C|D)$', Reflector())
@GlobalQuantifyCapability(r'\.(M1|M2|M3|B|C|D)$', Reflector2())
@GlobalQuantifyCapability(r'\.(C|D)$', ReflectorUpwardsClosed())
@GlobalQuantifyCapability(r'\.(C|D)$', ReflectorUpwardsClosedToA())
@GlobalQuantifyCapability(r'\.(C|D)$', ReflectorUpwardsClosedUntilA())
import 'package:reflectable/reflectable.dart';
import 'meta_reflectors_domain_definer.dart';
import 'meta_reflectors_definer.dart';
import 'meta_reflectors_meta.dart';
import 'meta_reflectors_test.reflectable.dart';
import 'meta_reflectors_user.dart';

const Map<String, Iterable<Reflectable>> scopeMap = {
  'polymer': <Reflectable>[Reflector(), ReflectorUpwardsClosed()],
  'observe': <Reflectable>[Reflector2(), ReflectorUpwardsClosed()]
};

@ScopeMetaReflector()
Iterable<Reflectable> reflectablesOfScope(String scope) => scopeMap[scope];

void main() {
  initializeReflectable();

  runTests();
}
