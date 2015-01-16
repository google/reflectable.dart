// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.reflector;

import 'package:unittest/unittest.dart';  // Get 'expect' etc.
import 'reflectee1.dart';  // Get target classes.
import 'reflectee2.dart';  // Get target classes.
import 'my_reflectable.dart';  // Get metadata.

// Imports used in library mirror related test case.
import 'a.dart';
import 'b.dart';
import 'c.dart';

part 'reflector.dart';  // Embed test cases in dynamic context.
