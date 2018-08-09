// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.reflectable_builder;

import 'dart:async';
import 'package:build/build.dart';
import 'package:build_config/build_config.dart';
import 'package:build_runner/build_runner.dart';

class ReflectableBuilder implements Builder {
  BuilderOptions builderOptions;

  ReflectableBuilder(this.builderOptions);

  @override
  Future build(BuildStep buildStep) async {
    var resolver = buildStep.resolver;
    var inputId = buildStep.inputId;

    var copy = inputId.changeExtension('.reflectable.dart');
    var contents = await buildStep.readAsString(inputId);

    buildStep.writeAsString(copy, contents);

    // Get the `LibraryElement` for the primary input.
    var entryLib = await buildStep.inputLibrary;

    // Resolves all libraries reachable from the primary input.
    var visibleLibraries = await resolver.libraries.length;

    var info = buildStep.inputId.addExtension('.info');

    await buildStep.writeAsString(info, '''
         Input ID: ${buildStep.inputId}
     Member count: ${entryLib.unit.declarations.length}
Visible libraries: $visibleLibraries
''');
  }


  Map<String, List<String>> get buildExtensions => 
      const <String, List<String>>{'.dart': ['.reflectable.dart', '.dart.info']};
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
    // Plus: new ReflectableTransformer.asPlugin(settings),
    return await build(
        [applyToRoot(builder, generateFor: new InputSet(include: arguments))],
        deleteFilesByDefault: true);
  }
}
