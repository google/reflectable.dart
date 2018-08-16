// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.reflectable_builder;

import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_config/build_config.dart';
import 'package:build_runner/build_runner.dart';
import 'src/builder_implementation.dart';

class ReflectableBuilder implements Builder {
  BuilderOptions builderOptions;

  ReflectableBuilder(this.builderOptions);

  @override
  Future build(BuildStep buildStep) async {
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
    return await build(
        [applyToRoot(builder, generateFor: new InputSet(include: arguments))],
        deleteFilesByDefault: true);
  }
}
