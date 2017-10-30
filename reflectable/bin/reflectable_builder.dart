// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Performs the reflectable code generation as a 'package:build' builder.
///
/// Expects the package name as the first argument, followed by the entry
/// points to transform.

library reflectable.bin.reflectable_builder;

import 'package:barback/src/transformer/barback_settings.dart';
import 'package:build_barback/build_barback.dart';
import 'package:build_runner/build_runner.dart';
import 'package:reflectable/transformer.dart';

main(List<String> arguments) async {
  if (arguments.length < 1) {
    print("reflectable_builder: Expects name of package as first "
        "argument; exiting.");
  } else {
    String packageName = arguments[0];
    List<String> filePaths = arguments.sublist(1);
    // TODO(eernst): Sort out which settings to use here.
    BarbackSettings settings = new BarbackSettings({
      "entry_points": [filePaths],
      "formatted": true,
    }, BarbackMode.DEBUG);
    final reflectableTransformerBuilder = new TransformerBuilder(
        new ReflectableTransformer.asPlugin(settings),
        const <String, List<String>>{
          '.dart': const ['.reflectable.dart']
        });
    await build(<BuildAction>[
      new BuildAction(reflectableTransformerBuilder, packageName,
          inputs: filePaths)
    ]);
  }
}
