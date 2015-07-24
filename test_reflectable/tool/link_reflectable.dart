// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Creates a symlink to the reflectable package next to this package.

import "dart:io";
import "package:path/path.dart" as path;

void main(List<String> args) {
  // All paths are platform specific, e.g., `args[0]` and
  // [projectRoot] may contain a drive letter and backslashes
  // on Windows. The given command line argument is the
  // project root, but it may be relative so we need to ensure
  // that we have the absolute path relative to the current
  // working directory.
  String projectRoot = path.absolute(args[0]);
  String relativeReflectableLocation =
      path.join(path.join("..", "..", "..", "..", "..", "..", "dart"),
          path.join("third_party", "pkg", "reflectable", "reflectable"));
  String relativeLinkLocation =
      path.join("..", "..", "reflectable", "reflectable");
  String reflectableLocation =
      path.normalize(path.join(projectRoot, relativeReflectableLocation));
  String destinationPath =
      path.normalize(path.join(projectRoot, relativeLinkLocation));
  print("Creating a link to $reflectableLocation at $destinationPath");
  bool exists = new Directory(reflectableLocation).existsSync();
  print("Target exists: $exists");
  new Link(destinationPath).create(reflectableLocation);
}
