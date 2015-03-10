#!/usr/bin/env dart
// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart' as path;

void main (List<String> args) {
  String rootDir = args[0];
  String testDir = path.join(rootDir, "build", "test");
  String src = path.join(testDir, "to_be_transformed", "packages");
  String target = path.join(testDir, "packages");
  Link link = new Link(src);
  link.createSync(target);
}

