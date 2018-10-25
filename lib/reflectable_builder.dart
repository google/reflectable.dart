// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.reflectable_builder;

import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_config/build_config.dart';
import 'package:build_runner_core/build_runner_core.dart';
import 'package:build_runner/src/logging/std_io_logging.dart';
import 'package:build_runner/src/package_graph/build_config_overrides.dart';
import 'package:build_runner/src/generate/terminator.dart';
import 'src/builder_implementation.dart';

Future<BuildResult> _build(List<BuilderApplication> builders,
    {bool deleteFilesByDefault,
    bool assumeTty,
    String configKey,
    PackageGraph packageGraph,
    RunnerAssetReader reader,
    RunnerAssetWriter writer,
    Resolvers resolvers,
    Stream terminateEventStream,
    bool enableLowResourcesMode,
    Map<String, String> outputMap,
    bool outputSymlinksOnly,
    bool trackPerformance,
    bool skipBuildScriptCheck,
    bool verbose,
    bool isReleaseBuild,
    Map<String, Map<String, dynamic>> builderConfigOverrides,
    List<String> buildDirs,
    String logPerformanceDir}) async {
  builderConfigOverrides ??= const {};
  packageGraph ??= PackageGraph.forThisPackage();
  var environment = OverrideableEnvironment(
      IOEnvironment(
        packageGraph,
        assumeTty: assumeTty,
        outputMap: outputMap,
        outputSymlinksOnly: outputSymlinksOnly,
      ),
      reader: reader,
      writer: writer,
      onLog: stdIOLogListener(assumeTty: assumeTty, verbose: verbose));
  var logSubscription =
      LogSubscription(environment, verbose: verbose);
  var options = await BuildOptions.create(
    logSubscription,
    deleteFilesByDefault: deleteFilesByDefault,
    packageGraph: packageGraph,
    skipBuildScriptCheck: skipBuildScriptCheck,
    overrideBuildConfig:
        await findBuildConfigOverrides(packageGraph, configKey),
    enableLowResourcesMode: enableLowResourcesMode,
    trackPerformance: trackPerformance,
    buildDirs: buildDirs,
    logPerformanceDir: logPerformanceDir,
    resolvers: resolvers,
  );
  var terminator = Terminator(terminateEventStream);
  try {
    var build = await BuildRunner.create(
      options,
      environment,
      builders,
      builderConfigOverrides,
      isReleaseBuild: isReleaseBuild ?? false,
    );
    var result = await build.run({});
    await build?.beforeExit();
    return result;
  } finally {
    await terminator.cancel();
    await options.logListener.cancel();
  }
}

class ReflectableBuilder implements Builder {
  BuilderOptions builderOptions;

  ReflectableBuilder(this.builderOptions);

  @override
  Future<void> build(BuildStep buildStep) async {
    var resolver = buildStep.resolver;
    var inputId = buildStep.inputId;
    var outputId = inputId.changeExtension('.reflectable.dart');
    var inputLibrary = await buildStep.inputLibrary;
    List<LibraryElement> visibleLibraries = await resolver.libraries.toList();

    await buildStep.writeAsString(
        outputId,
        new BuilderImplementation().buildMirrorLibrary(resolver, inputId,
            outputId, inputLibrary, visibleLibraries, true, []));
  }

  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.reflectable.dart']
      };
}

ReflectableBuilder reflectableBuilder(BuilderOptions options) {
  var config = new Map<String, Object>.from(options.config);
  config.putIfAbsent('entry_points', () => ['**.dart']);
  return new ReflectableBuilder(options);
}

Future<BuildResult> reflectableBuild(List<String> arguments) async {
  if (arguments.length < 1) {
    // Globbing may produce an empty argument list, and it might be ok,
    // but we should give at least notify the caller.
    print("reflectable_builder: No arguments given, exiting.");
    return new BuildResult(BuildStatus.success, []);
  } else {
    // TODO(eernst) feature: We should support some customization of
    // the settings, e.g., specifying options like `suppress_warnings`.
    BuilderOptions options = new BuilderOptions(
        <String, dynamic>{"entry_points": arguments, "formatted": true},
        isRoot: true);
    final builder = new ReflectableBuilder(options);
    return await _build(
        [applyToRoot(builder, generateFor: new InputSet(include: arguments))],
        deleteFilesByDefault: true);
  }
}
