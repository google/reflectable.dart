// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.reflectable_builder;

import 'dart:async';
import 'package:barback/src/transformer/barback_settings.dart';
import 'package:build_barback/build_barback.dart';
import 'package:build_runner/build_runner.dart';
import 'package:reflectable/transformer.dart';

Future<BuildResult> reflectableBuild(List<String> arguments) async {
  if (arguments.length < 1) {
    // Globbing may produce an empty argument list, and it might be ok,
    // but we should give at least notify the caller.
    print("reflectable_builder: No arguments given, exiting.");
    return new BuildResult(BuildStatus.success, []);
  } else {
    PackageGraph graph = new PackageGraph.forThisPackage();
    String packageName = graph.root.name;
    // TODO(eernst) feature: We should support some customization of
    // the settings, e.g., specifying options like `suppress_warnings`.
    BarbackSettings settings = new BarbackSettings(
      <String, Object>{"entry_points": arguments, "formatted": true},
      BarbackMode.DEBUG,
    );
    final builder = new TransformerBuilder(
      new ReflectableTransformer.asPlugin(settings),
      const <String, List<String>>{'.dart': const ['.reflectable.dart']},
    );
    return await build(
        [new BuildAction(builder, packageName, inputs: arguments)],
        deleteFilesByDefault: true);
  }
}
