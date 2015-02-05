#!/usr/bin/env dart
// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test that each file in 'expected' is identical to the corresponding
// file in ../build/test/transformed, thus ensuring that unexpected output
// from the transformer will be noticed.  Then iterate over all files in
// ../build/test/transformed to check that everything in there is indeed
// 'expected'.  Will fail if any files cannot be opened for reading,
// which includes the case where a [buildDir] file is missing and the
// case where permissions are to strict, in addition to the cases where
// the contents of corresponding files are different, and the case where
// some files in [buildDir] are missing in [expectDir].

// Note the following relevant generalizations:  We do not traverse
// subdirectories; if test cases arise where this is required the
// approach should be generalized, and care should be taken to avoid
// visiting irrelevant files such as 'packages'.  Similarly, we expect
// all directory entries to be actual files, symlinks are ignored.

import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:convert';

/// Returns the path of the file in [newBasePath] with the name from
/// the given [originalPath]; will fail if [originalPath] is empty.
String correspondingPath(String originalPath, String newBasePath) =>
    path.join(newBasePath, path.split(originalPath).last);

/// Checks for the given [entity] that if it is a file then there is
/// a corresponding file with the same name in the directory at
/// [newBasePath], with identical contents.
void checkContents(FileSystemEntity entity, String newBasePath) {
  if (entity is File) {
    String expectContents = entity.readAsStringSync();
    File buildFile = new File(correspondingPath(entity.path, newBasePath));
    String buildContents = buildFile.readAsStringSync();
    if (expectContents != buildContents) {
      throw "File contents not identical for ${entity.path}.";
    }
  } else {
    // [entity] may be a [Directory] which we will skip because we
    // do not traverse subdirectories, or it may be a [Link] which
    // we will skip because all tested entities must be files.
  }
}

/// Checks that for each file in the directory at [expectDir],
/// not including subdirectories, there is a file with the same name
/// and identical contents in the directary at [buildDirPath].
void checkAllContents(Directory expectDir, String buildDirPath) {
  expectDir
      .list(recursive: false, followLinks: false)
      .listen((entity) => checkContents(entity, buildDirPath));
}

/// Checks that for each file in [buildDir], not including
/// subdirectories, there exists a file with the same name in
/// [expectedDirPath].
void checkCompleteness(Directory buildDir, String expectDirPath) {
  buildDir.list(recursive: false, followLinks: false).listen(
      (entity) {
        if (entity is File) {
          String expectPath = correspondingPath(entity.path, expectDirPath);
          File expectFile = new File(expectPath);
          if (! expectFile.existsSync()) {
            throw "Unpexpected file found: ${entity.path}";
          }
        } else {
          // [entity] may be a [Directory] which we will skip because we
          // do not traverse subdirectories, or it may be a [Link] which
          // we will skip because all tested entities must be files.
        }
      });
}

void main ([String args]) {
  final String scriptDir = path.dirname(path.fromUri(Platform.script));
  final String rootDir = path.dirname(scriptDir);
  final String rootPath = rootDir.toString();
  final String expectedDirPath = path.join(rootDir, "test", "expected");
  final String buildDirPath = 
      path.join(rootDir, "build", "test", "transformed");
  final Directory expectDir = new Directory(expectedDirPath);
  final Directory buildDir = new Directory(buildDirPath);
  checkAllContents(expectDir, buildDirPath);
  checkCompleteness(buildDir, expectedDirPath);
}

