// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.reflector;

import 'package:unittest/unittest.dart';  // Get 'expect' etc.
import 'reflectee1_s.dart';  // Get target classes.
import 'reflectee2_s.dart';  // Get target classes.
import 'my_reflectable_s.dart';  // Get metadata.

// Imports used in library mirror related test case.
import 'a_s.dart';
import 'b_s.dart';
import 'c_s.dart';

import 'package:reflectable/capability.dart';
import 'package:reflectable/mirror.dart';

part 'reflectable_reflector.dart';
part 'reflector.dart';
