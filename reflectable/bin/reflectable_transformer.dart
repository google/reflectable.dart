// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Performs the reflectable transformation as a stand-alone tool.
///
/// Expects the package name as the first argument, followed by the entry
/// points to transform. The 'pubspec.yaml' file will be ignored, which means
/// that it is possible to transform a single entry point from 'pubspec.yaml'
/// or any subset, or even something which is not mentioned in 'pubspec.yaml'
/// at all.
///
/// Note that this transformer will produce transformed output, but it will not
/// copy files that do not get transformed, and it will not create the
/// 'packages' directory needed for execution. It will therefore work, e.g.,
/// when a `pub build ..` command has been executed, such that 'packages' has
/// created and non-transformed files have been copied, but otherwise those
/// things must be done separately.

library reflectable.bin.reflectable_transformer;

import 'dart:io';
import 'package:barback/barback.dart';
import 'package:reflectable/test_transform.dart';
import 'package:reflectable/transformer.dart';
import 'package:barback/src/transformer/barback_settings.dart';

String buildPathFromAssetId(String assetIdString) {
  // TODO(eernst) implement: Error handling.
  int pipeIndex = assetIdString.indexOf(r'|');
  return "build/${assetIdString.substring(pipeIndex + 1)}";
}

transform(String package, String entryPoint, Map<String, String> inputs) async {
  for (String inputName in inputs.keys) {
    String inputContents = inputs[inputName];
    List<String> packageRootElements = entryPoint.split('/');
    String packageRootPrefix = packageRootElements
        .take(packageRootElements.length - 1)
        .join(Platform.pathSeparator);
    String packageRoot = "$packageRootPrefix${Platform.pathSeparator}packages";
    TestTransform transform =
        new TestTransform(inputName, inputContents, package, packageRoot);
    BarbackSettings barbackSettings = new BarbackSettings({
      "entry_points": [entryPoint],
      "formatted": true,
    }, BarbackMode.RELEASE);
    ReflectableTransformer transformer =
        new ReflectableTransformer.asPlugin(barbackSettings);

    TestDeclaringTransform declaringTransform =
        new TestDeclaringTransform(inputName);
    await transformer.declareOutputs(declaringTransform);

    await transformer.apply(transform);
    Map<String, String> outputs = await transform.outputMap();
    for (MessageRecord messageRecord in transform.messages) {
      String level = null;
      switch (messageRecord.level) {
        case LogLevel.INFO:
          level = "Info";
          break;
        case LogLevel.FINE:
          level = "Fine";
          break;
        case LogLevel.WARNING:
          level = "Warning";
          break;
        case LogLevel.ERROR:
          level = "Error";
          break;
      }
      assert(level != null);
      print("[$level from reflectable_transformer]:\n"
          "${messageRecord.message}");
    }
    for (String id in outputs.keys) {
      String contents = outputs[id];
      String buildPath = buildPathFromAssetId(id);
      File file = new File(buildPath);
      file.createSync(recursive: true);
      file.writeAsString(contents);
    }
  }
}

main(List<String> arguments) async {
  if (arguments.length < 1) {
    print("reflectable_transformer: Expects name of package as first "
        "argument; exiting.");
  } else {
    String packageName = arguments[0];
    List<String> filePaths = arguments.sublist(1);
    for (String filePath in filePaths) {
      Map<String, String> inputs = <String, String>{};
      File file = new File(filePath);
      String contents = await file.readAsString();
      String assetIdString = "$packageName|$filePath";
      inputs[assetIdString] = contents;
      await transform(packageName, filePath, inputs);
    }
  }
}
