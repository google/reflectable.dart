// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Used from 'default_values_test.dart' in order to test the situation
// where a default value which is already imported is moved to a third
// file and must be imported from there.

const String globalConstant = '21';

class A {
  static const localConstant = 11;
}
