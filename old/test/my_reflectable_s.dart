// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.my_reflectable;

import 'reflector_static.dart';

class MyReflectable extends ReflectableX {
  const MyReflectable(): super(const []);
}

const myReflectable = const MyReflectable();
