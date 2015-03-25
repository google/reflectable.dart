// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect' across file boundaries.  Additional library
// declaring a class with a Reflectable annotation.

library reflectable.test.to_be_transformed.three_files_aux;

import 'three_files_meta.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';


@myReflectable
class B {}

// Generated: Rest of file

class Static_B_ClassMirror extends ClassMirrorUnimpl {
}

class Static_B_InstanceMirror extends InstanceMirrorUnimpl {
  final B reflectee;
  Static_B_InstanceMirror(this.reflectee);
}
