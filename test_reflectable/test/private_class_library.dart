// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File being transformed by the reflectable transformer.
/// Part of the entry point 'private_class_test.dart'.
library test_reflectable.test.private_class_library;

class PublicClass {
  int publicMethod() => 42;
}

class _PrivateClass1 extends PublicClass {
  int supposedlyPrivate() => -42;
}

class PublicSubclass1 extends _PrivateClass1 {}

class _PrivateClass2 implements PublicClass {
  int publicMethod() => 43;
  int supposedlyPrivateToo() => -43;
}

class PublicSubclass2 extends _PrivateClass2 {}

PublicClass func1() => new _PrivateClass1();

PublicClass func2() => new _PrivateClass2();

PublicClass func3() => new PublicSubclass1();

PublicClass func4() => new PublicSubclass2();
