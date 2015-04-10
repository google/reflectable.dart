// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and declares that
// it should `hide` some names (and show the rest).  The
// use of `hide` on this import is not supported, and it
// must give rise to an error during transformation.

library reflectable.test.to_be_transformed.bad_import_2_test;
import 'package:reflectable/reflectable.dart'
    hide InvokeStaticMemberCapability;

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
}

@MyReflectable()
class A {}
