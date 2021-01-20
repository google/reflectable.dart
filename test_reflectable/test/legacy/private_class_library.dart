// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

/// File used to test reflectable code generation.
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
  @override
  int publicMethod() => 43;

  int supposedlyPrivateToo() => -43;
}

class PublicSubclass2 extends _PrivateClass2 {}

PublicClass func1() => _PrivateClass1();

PublicClass func2() => _PrivateClass2();

PublicClass func3() => PublicSubclass1();

PublicClass func4() => PublicSubclass2();
