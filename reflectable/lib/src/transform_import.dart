// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transform_import;

import 'dart:async';

import 'package:barback/barback.dart';

class ImportTransformer extends Transformer implements DeclaringTransformer {

  ImportTransformer.asPlugin();

  Future<bool> isPrimary(AssetId path) async {
    // This is for internal use, and should only ever be applied to
    // lib/reflectable.
    if (path.path != "lib/reflectable.dart") {
      throw new ArgumentError(
          "This transformer can only operate on lib/reflectable.dart");
    }
    return true;
  }

  Future apply(Transform transform) async {
    // TODO(eernst) future: Add an option to disable the transformer
    // from the command-line.
    if (const bool.fromEnvironment("reflectable.print.entry.point")) {
      print("Starting transform_import on '${transform.primaryInput.id}'.");
    }
    String content = await transform.primaryInput.readAsString();
    AssetId id = transform.primaryInput.id;
    String newContent = content.replaceAll(
        "'src/reflectable_mirror_based.dart'",
        "'src/reflectable_transformer_based.dart'");
    transform.addOutput(new Asset.fromString(id, newContent));
  }

  @override
  declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId);
  }
}
