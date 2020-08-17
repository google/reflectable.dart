// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'package:build_runner/build_runner.dart';
import 'package:glob/glob.dart';
import 'package:reflectable/reflectable_builder.dart' as builder;

main(List<String> arguments) async {
  List<String> globbedArguments = <String>[];
  for (String argument in arguments) {
    Glob fileGlob = new Glob(argument);
    await for (var entity in fileGlob.list()) {
      String fileSpec = entity.path;
      if (fileSpec.startsWith("./")) fileSpec = fileSpec.substring(2);
      globbedArguments.add(fileSpec);
    }
  }
  return (await builder.reflectableBuild(globbedArguments)).status ==
      BuildStatus.success;
}
