// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'package:glob/glob.dart';
import 'package:reflectable/reflectable_builder.dart' as builder;

main(List<String> arguments) async {
  List<String> globbedArguments = <String>[];
  for (String argument in arguments) {
    String fileSpec = new Glob(argument);
    await for (FileSystemEntity entity in fileSpec.list()) {
      globbedArguments.add(entity.path);
    }
  }
  await builder.reflectableBuild(globbedArguments);
}
