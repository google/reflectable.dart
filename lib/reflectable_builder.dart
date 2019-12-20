// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.reflectable_builder;

import 'dart:async';
import 'package:build/build.dart';
import 'package:build_config/build_config.dart';
import 'package:build_runner_core/build_runner_core.dart';
import 'src/builder_implementation.dart';

class ReflectableBuilder implements Builder {
  BuilderOptions builderOptions;

  ReflectableBuilder(this.builderOptions);

  @override
  Future<void> build(BuildStep buildStep) async {
    var inputLibrary = await buildStep.inputLibrary;
    var resolver = buildStep.resolver;
    var inputId = buildStep.inputId;
    var outputId = inputId.changeExtension('.reflectable.dart');
    var visibleLibraries = await resolver.libraries.toList();
    var generatedSource = await BuilderImplementation().buildMirrorLibrary(
        resolver, inputId, outputId, inputLibrary, visibleLibraries, true, []);
    await buildStep.writeAsString(outputId, generatedSource);
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.reflectable.dart']
      };
}

ReflectableBuilder reflectableBuilder(BuilderOptions options) {
  var config = Map<String, Object>.from(options.config);
  config.putIfAbsent('entry_points', () => ['**.dart']);
  return ReflectableBuilder(options);
}

Future<BuildResult> reflectableBuild(List<String> arguments) async {
  if (arguments.isEmpty) {
    // Globbing may produce an empty argument list, and it might be ok,
    // but we should give at least notify the caller.
    print('reflectable_builder: No arguments given, exiting.');
    return BuildResult(BuildStatus.success, []);
  } else {
    // TODO(eernst) feature: We should support some customization of
    // the settings, e.g., specifying options like `suppress_warnings`.
    var options = BuilderOptions(
        <String, dynamic>{'entry_points': arguments, 'formatted': true},
        isRoot: true);
    final builder = ReflectableBuilder(options);
    var builders = <BuilderApplication>[
      applyToRoot(builder, generateFor: InputSet(include: arguments))
    ];
    var packageGraph = PackageGraph.forThisPackage();
    var environment = OverrideableEnvironment(IOEnvironment(packageGraph));
    var buildOptions = await BuildOptions.create(
      LogSubscription(environment),
      deleteFilesByDefault: true,
      packageGraph: packageGraph,
    );
    try {
      var build = await BuildRunner.create(
          buildOptions, environment, builders, const {},
          isReleaseBuild: false);
      var result = await build.run(const {});
      await build?.beforeExit();
      return result;
    } finally {
      await buildOptions.logListener.cancel();
    }
  }
}
