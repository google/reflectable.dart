// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and uses the
// class Reflectable as an annotation.

library reflectable.test.transformed.use_annotation;
import 'reflectable_dummy.dart';

@Reflectable(const [])
class A {}
