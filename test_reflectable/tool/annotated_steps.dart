// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io";

Uri baseUri = Platform.script.resolve("../../../../../");

/// Run `pub` commands to set up .packages, generate code, and run tests.
/// Will change current working directory of this process to the root of
/// the copy of package 'test_reflectable' where the tests are executed.
Future<int> runBuildRunnerInDirectory(String directory) async {
  Map<String, String> environment =
      new Map<String, String>.from(Platform.environment);
  Directory.current = directory;
  print("^^^ Current working directory: ${Directory.current}");

  // Run `pub get`, bail out and report exit code if failing.
  Process process1 =
      await Process.start('pub', ['get'], environment: environment);
  stdout.addStream(process1.stdout);
  stderr.addStream(process1.stderr);
  int exitCode = await process1.exitCode;
  if (exitCode != 0) return process1.exitCode;

  // Run `pub run build_runner test` and report exit code.
  Process process2 = await Process.start('pub', ['run', 'build_runner', 'test'],
      environment: environment);
  stdout.addStream(process2.stdout);
  stderr.addStream(process2.stderr);
  return process2.exitCode;
}

/// Expects to be called with the path to the package root.
/// See .test_config.
void main(List<String> arguments) async {
  String packagePath = arguments[0];
  print("^^^ Run 'annotated_steps.dart' in $packagePath");
  int exitCode = await runBuildRunnerInDirectory(packagePath);
  print("^^^ Done 'annotated_steps.dart'");
  if (exitCode != 0) exit(1);
}
