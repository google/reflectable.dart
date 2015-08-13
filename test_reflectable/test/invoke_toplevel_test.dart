// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `invoke` on top level entities.

library test_reflectable.test.invoke_toplevel_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(invokingCapability);
}

const myReflectable = const MyReflectable();

@myReflectable
myFunction() => "hello";

main() {
  LibraryMirror lm =
      myReflectable.findLibrary('test_reflectable.test.invoke_toplevel_test');
  test('invoke function', () {
    expect(lm.invoke('myFunction', []), equals('hello'));
    expect(Function.apply(lm.invokeGetter('myFunction'), []), equals('hello'));
  });
}
