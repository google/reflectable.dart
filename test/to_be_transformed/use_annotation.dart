// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and uses the
// class Reflectable as an annotation.

library reflectable.test.to_be_transformed.use_annotation;
import 'package:reflectable/reflectable.dart';

@Reflectable(const [])
class A {}
