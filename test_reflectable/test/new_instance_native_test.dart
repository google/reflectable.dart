// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Based on https://github.com/dart-lang/sdk/issues/18541; ported to fit in
// reflectable: Changed symbols to strings; added reflector and quantifier;
// removed usages of `reflectee` to bypass the mirror (that reflectable
// already avoids creating). Uses type annotations like all other parts of
// reflectable. This variant was again created as a variant of
// 'new_instance_html_test.dart' which does not depend on 'dart:html'.

@GlobalQuantifyCapability(r'^dart.core.List', reflector)
import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'new_instance_native_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Reflector extends Reflectable {
  const Reflector(): super(newInstanceCapability, declarationsCapability,
      libraryCapability);
}

const Reflector reflector = Reflector();

void main() {
  initializeReflectable();

  LibraryMirror lib = reflector.findLibrary('dart.core')!;
  var fooClass = lib.declarations['List'] as ClassMirror;
  var fooInstance = fooClass.newInstance('', []) as List;
  test('Creating instance of native class', () {
      expect(fooInstance.toString(), '[]');
  });
}
