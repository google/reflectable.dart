// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File being transformed by the reflectable transformer.
/// Part of the entry point 'meta_reflectors_test.dart'.
///
/// Independence: The "domain classes" `M1`..`M3`, `A`..`D`, `P` are assumed to
/// be specific to the particular entry point 'meta_reflectors_test.dart' and
/// its transitive closure, but there is no dependency from them to any of the
/// libraries introducing or using reflectable reflection.
library test_reflectable.test.meta_reflectors_share;

class P {
  const P();
}

@P()
class M1 {
  foo() {}
  var field;
  static staticFoo(x) {}
}

class M2 {}

class M3 {}

class A {
  foo() {}
  var field;
  static staticFoo(x) {}
  static staticBar() {}
}

class B extends A with M1 {}

class C extends B with M2, M3 {}

class D = A with M1;
