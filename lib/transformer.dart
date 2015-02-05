// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.transformer;

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:analyzer/src/generated/element.dart';

class ReflectableTransformer extends Transformer
                             implements DeclaringTransformer {
  /// TODO(eernst): Use _settings to interpret 'entry_points',
  /// based on third_party/observatory_pub_packages/polymer.
  BarbackSettings _settings;

  /// Creates new instance as required by Barback.
  ReflectableTransformer.asPlugin(this._settings);

  /// Declares by 'file extension' which files may be
  /// transformed by this transformer.
  String get allowedExtensions => ".dart";

  /// Announces output files.
  Future declareOutputs(DeclaringTransform transform) {
    return new Future.value(transform.primaryId);
  }

  /// Performs the transformation.
  /// TODO(eernst): This is still a no-op transform
  Future apply(Transform transform) {
    Asset input = transform.primaryInput;
    return input.readAsString().then((source) {
      transform.addOutput(new Asset.fromString(input.id, source));
    });
  }
}

