// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.transformer;

import 'dart:async';
import 'package:barback/barback.dart';
import 'package:logging/logging.dart';
import 'src/transformer_implementation.dart' as implementation;

class ReflectableTransformer extends AggregateTransformer {
  // TODO(eernst): Consider doing `implements DeclaringAggregateTransformer`,
  // which might help improving the performance of barback graph management.
  BarbackSettings _settings;
  List<String> _entryPoints = <String>[];

  /// Reports an error in a situation where we do not yet have
  /// a [Logger].
  void _reportEarlyError(String message) {
    print("Error: $message.");
    // TODO(eernst): then exit?
  }

  /// Checks and interprets the given list of entry points,
  /// given via [_settings].
  List<String> _findEntryPoints(Map<String, dynamic> entryPointSettings) {
    List<String> entryPoints = <String>[];
    if (entryPointSettings == null) {
      // No entry points given: Every file with a top-level function named
      // `main` is an entry point.
      // TODO(eernst): find a way to do this.
      throw new UnimplementedError();
    }

    void addToEntryPoints(entryPoint) {
      if (entryPoint is String) {
        entryPoints.add(entryPoint);
      } else if (entryPoint is List) {
        entryPoint.forEach((value) => addToEntryPoints(value));
      } else {
        _reportEarlyError(
            "Encountered non-String $entryPoint in 'entry_points'.");
      }
    }

    addToEntryPoints(entryPointSettings);
    return entryPoints;
  }

  /// Creates new instance as required by Barback.
  ReflectableTransformer.asPlugin(this._settings) {
    _entryPoints = _findEntryPoints(_settings.configuration['entry_points']);
  }

  /// Declares by 'file extension' which files may be
  /// transformed by this transformer.
  String get allowedExtensions => ".dart";

  /// Announces output files.
  /// TODO(eernst): implement this if needed..
  // Future declareOutputs(DeclaringAggregateTransform transform) =>
  //     new Future.value(transform.primaryId);

  /// Return a [String] or [Future<String>] valued key for each
  /// primary asset that this transformer wishes to process, and
  /// null for assets that it wishes to ignore.  Primary assets
  /// with the same key are delivered to [apply] as a group.  In
  /// this transformer we handle the grouping later, so everything
  /// is in the same group.
  String classifyPrimary(AssetId id) {
    if (!id.path.endsWith('.dart')) return null;
    return "ReflectableTransformed";
  }

  /// Performs the transformation.
  Future apply(AggregateTransform transform) {
    return new implementation.TransformerImplementation()
        .apply(transform, _entryPoints);
  }
}
