// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Creates a symlink to the reflectable package next to this package.

import "dart:io";

void main(List<String> args) {
  Uri projectRoot = new Uri.file(args[0]);
  // If projectRoot is relative we want to make it absolute, so the link
  // will be to an absolute location.
  Uri currentPathUri = new Uri.file(Directory.current.path +
                                    Platform.pathSeparator);
  Uri projectRootUri = currentPathUri.resolveUri(projectRoot);
  Uri reflectableLocation = projectRootUri.resolve(
      "../../../../../dart/third_party/pkg/reflectable/reflectable");
  Uri destination = projectRootUri.resolve("../reflectable/reflectable");
  print("Making a link to ${reflectableLocation.toFilePath()} "
        "at ${destination.toFilePath()}");
  bool exists = new Directory(reflectableLocation.toFilePath()).existsSync();
  print("Target exists: $exists");
  new Link.fromUri(destination).create(reflectableLocation.toFilePath());
}
