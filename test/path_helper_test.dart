// (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.path_helper_test;

import 'package:reflectable/src/path_helper.dart';
import 'package:unittest/unittest.dart';

void check(String s1, String s2, String result) =>
    expect(relativePath(s1, s2), result);

void main([args]) {
  test('relativePath', () {
    check('a.dart', 'b.dart', 'a.dart');
    check('a.dart', 'a.dart', 'a.dart');
    check('/a.dart', '/b.dart', 'a.dart');
    check('/x/a.dart', '/x/b.dart', 'a.dart');
    check('x/a.dart', 'x/b.dart', 'a.dart');
    check('x/a.dart', 'y/b.dart', '../x/a.dart');
    check('x/y/a.dart', 'x/z/b.dart', '../y/a.dart');
    check('x/y/z/a.dart', 'x/y/b.dart', 'z/a.dart');
    check('x/y/a.dart', 'x/y/z/b.dart', '../a.dart');
    check('x/y/z/a.dart', 'x/w/z/b.dart', '../../y/z/a.dart');
  });
}
