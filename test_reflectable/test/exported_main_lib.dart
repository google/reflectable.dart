// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart=2.9

// This file illustrates a peculiar situation: The `main` function which
// defines the behavior of the program 'exported_main_test.dart' is not
// declared in 'exported_main_test.dart', it is defined in this library.
// When this situation arises, i.e., when `main` is imported by the root
// library rather than being declared in the root library, the modifications
// which are otherwise needed in the root library must be applied to the
// library where the relevant `main` function is declared, i.e., this
// library.
//
// So we add an import of 'reflectable.dart' and of the generated code in
// 'exported_main_test.reflectable.dart', and add `initializeReflectable()`
// at the beginning of the body of `main`.
//
// Note the asymmetry: This library depends on the name of the root library
// of the program ('exported_main_test'), because the code generator stores
// the generated code in a file whose name is determined by the name of the
// file containing the root library.
//
// This again means that it is not possible to use this library as part of
// several different programs, all of which are using this library in order
// to "reuse the same `main`" (this file would then have to import a different
// '*.reflectable.dart' for each of those root libraries, but a library cannot
// contain different text "as seen from" different importing libraries).
//
// We recommend that such a design is simply avoided by adding a `main`
// function in each of those root libraries, renaming the `main` below to
// something else, say `myMain`, and then calling `myMain` from the newly
// added `main` functions (it doesn't even have to be renamed, but the name
// `main` may be confusing when it's never used as the entry point of a
// program):
//
//   import 'sameNameAsThisFile.reflectable.dart';
//   ...
//   main(String[] args) {
//     initializeReflectable();
//     myMain(args);
//   }
//
// In other words, this program shows that it is possible to import `main`,
// but it is not recommended, doesn't scale, and is easy to avoid. This is
// also the reason why README.md and other documentation does not discuss
// that situation.

library test_reflectable.test.exported_main_lib;

import 'package:test/test.dart';
import 'package:reflectable/reflectable.dart';
import 'exported_main_test.reflectable.dart';

class Reflector extends Reflectable {
  const Reflector() : super(typeCapability);
}

@Reflector()
class C {}

void main() {
  initializeReflectable();

  test('exported main', () {
    expect(const Reflector().canReflectType(C), true);
  });
}
