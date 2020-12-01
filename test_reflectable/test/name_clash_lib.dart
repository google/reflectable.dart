// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

library test_reflectable.test.name_clash_lib;

import 'package:reflectable/reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

const reflector = Reflector();

@reflector
class C {}
