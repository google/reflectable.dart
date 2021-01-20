// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// File being transformed by the reflectable transformer.
// Uses 'reflect' across file and directory boundaries.  This is an
// additional library declaring a class with a Reflectable annotation.

library test_reflectable.test.three_files_dir.three_files_aux;

import '../three_files_meta.dart';

@myReflectable
class B {}
