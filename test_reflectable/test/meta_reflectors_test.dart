// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File being transformed by the reflectable transformer.
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

@GlobalQuantifyCapability(r"\.(M1|M2|M3|A|B|C|D)$", const Reflector())
@GlobalQuantifyCapability(r"\.(M1|M2|M3|B|C|D)$", const Reflector2())
@GlobalQuantifyCapability(r"\.(C|D)$", const ReflectorUpwardsClosed())
@GlobalQuantifyCapability(r"\.(C|D)$", const ReflectorUpwardsClosedToA())
@GlobalQuantifyCapability(r"\.(C|D)$", const ReflectorUpwardsClosedUntilA())
import "package:reflectable/reflectable.dart";
import "meta_reflectors_domain_definer.dart";
import "meta_reflectors_definer.dart";
import "meta_reflectors_meta.dart";
import "meta_reflectors_user.dart";

Map<String, Iterable<Reflectable>> scopeMap = <String, Iterable<Reflectable>>{
  "polymer": <Reflectable>[const Reflector(), const ReflectorUpwardsClosed()],
  "observe": <Reflectable>[const Reflector2(), const ReflectorUpwardsClosed()]
};

@ScopeMetaReflector()
Iterable<Reflectable> reflectablesOfScope(String scope) => scopeMap[scope];

main() {
  runTests();
}
