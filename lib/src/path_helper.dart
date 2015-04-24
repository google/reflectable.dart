// (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.path_helper;

import 'package:path/path.dart' as path;

/// Compute a relative path such that it denotes the file at
/// [destinationPath] when used from the location of the file
/// [sourcePath].
String relativePath(String destinationPath, String sourcePath) {
  List<String> destinationSplit = path.split(destinationPath);
  List<String> sourceSplit = path.split(sourcePath);
  while (destinationSplit.length > 1 && sourceSplit.length > 1 &&
         destinationSplit[0] == sourceSplit[0]) {
    destinationSplit = destinationSplit.sublist(1);
    sourceSplit = sourceSplit.sublist(1);
  }
  while (sourceSplit.length > 1) {
    sourceSplit = sourceSplit.sublist(1);
    destinationSplit.insert(0, "..");
  }
  return path.joinAll(destinationSplit);
}
