// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library;

import 'dart:async';
import 'dart:io';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
// import 'package:build_config/build_config.dart';
// import 'package:build_runner_core/build_runner_core.dart';
import 'src/builder_implementation.dart';

final mapEnvironmentToWarningKind = <String, Set<WarningKind>>{
  "REFLECTABLE_SUPPRESS_MISSING_ENTRY_POINT": {WarningKind.missingEntryPoint},
  "REFLECTABLE_SUPPRESS_BAD_SUPERCLASS": {WarningKind.badSuperclass},
  "REFLECTABLE_SUPPRESS_BAD_NAME_PATTERN": {WarningKind.badNamePattern},
  "REFLECTABLE_SUPPRESS_BAD_METADATA": {WarningKind.badMetadata},
  "REFLECTABLE_SUPPRESS_BAD_REFLECTOR_CLASS": {WarningKind.badReflectorClass},
  "REFLECTABLE_SUPPRESS_UNRECOGNIZED_REFLECTOR": {
    WarningKind.unrecognizedReflector
  },
  "REFLECTABLE_SUPPRESS_UNUSED_REFLECTOR": {WarningKind.unusedReflector},
  "REFLECTABLE_SUPPRESS_ALL_WARNINGS": WarningKind.values.toSet(),
};

List<WarningKind> _computeSuppressedWarnings() {
  final suppressedWarnings = <WarningKind>{};
  final environmentMap = Platform.environment;
  for (final variable in mapEnvironmentToWarningKind.keys) {
    if (environmentMap[variable]?.isNotEmpty == true) {
      suppressedWarnings.addAll(mapEnvironmentToWarningKind[variable]!);
    }
  }
  return suppressedWarnings.toList();
}

class ReflectableBuilder implements Builder {
  BuilderOptions builderOptions;

  ReflectableBuilder(this.builderOptions);

  @override
  Future<void> build(BuildStep buildStep) async {
    var targetId = buildStep.inputId.toString();
    if (targetId.contains('.vm_test.') ||
        targetId.contains('.node_test.') ||
        targetId.contains('.browser_test.')) {
      return;
    }
    LibraryElement inputLibrary = await buildStep.inputLibrary;
    Resolver resolver = buildStep.resolver;
    AssetId inputId = buildStep.inputId;
    AssetId outputId = inputId.changeExtension('.reflectable.dart');
    List<LibraryElement> visibleLibraries = await resolver.libraries.toList();
    List<WarningKind> suppressedWarnings = _computeSuppressedWarnings();
    String generatedSource = await BuilderImplementation().buildMirrorLibrary(
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
