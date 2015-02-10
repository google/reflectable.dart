// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.transformer;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'src/transformer_implementation.dart' as implementation;

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
  Future declareOutputs(DeclaringTransform transform) =>
      new Future.value(transform.primaryId);

  /// Performs the transformation.
  Future apply(Transform transform) => implementation.apply(transform);
}
