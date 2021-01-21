// Copyright (c) 2018, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflectable.test.prefixed_annotation_lib;

import 'package:reflectable/reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(instanceInvokeCapability, metadataCapability);
}

const Reflector reflector = Reflector();
