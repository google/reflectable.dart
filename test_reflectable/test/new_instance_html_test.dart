// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Based on https://github.com/dart-lang/sdk/issues/18541; ported to fit in
// reflectable: Changed symbols to strings, added reflector and quantifier;
// removed usages of `reflectee` to bypass the mirror (that reflectable
// already avoids creating). Uses type annotations like all other parts of
// reflectable.

import 'dart:html';

@GlobalQuantifyCapability(r"^dart.dom.html.HttpRequest$", reflector)
import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class Reflector extends Reflectable {
  const Reflector()
      : super(newInstanceCapability, declarationsCapability, libraryCapability);
}

const Reflector reflector = const Reflector();

void main() {
  LibraryMirror lib = reflector.findLibrary('dart.dom.html');
  ClassMirror fooClass = lib.declarations['HttpRequest'];
  HttpRequest fooInstance = fooClass.newInstance('', []);
  test('Creating instance of native class', () {
    expect(fooInstance is HttpRequest, true);
  });
}
