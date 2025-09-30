// Copyright (c) 2025, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// Show minimal usage of this package.

import 'package:reflectable/reflectable.dart';
import 'example.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(invokingCapability);
}

void main() {
  // The program execution must start run this initialization before
  // any reflective features can be used.
  initializeReflectable();

  print('''
This illustrates minimal usage of the package `reflectable`. Any actual
usage will include code generation. Please refer to the example in package
`reflectable_builder` to see how to do that.''');
}
