// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect' across file boundaries.  Provider of the
// metadata class.

library reflectable.test.to_be_transformed.three_files_meta;

import 'package:reflectable/reflectable.dart';
import 'three_files_test.dart';
import 'three_files_aux.dart';

class MyReflectable extends Reflectable {
  const MyReflectable(): super(const <ReflectCapability>[]);
}

const myReflectable = const MyReflectable();
