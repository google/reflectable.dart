// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.transformer;

import 'dart:async';
import 'dart:io';
import 'package:barback/barback.dart';
import 'package:logging/logging.dart';
import 'src/transformer_implementation.dart' as implementation;

class ReflectableTransformer extends AggregateTransformer
    implements DeclaringAggregateTransformer {
  BarbackSettings _settings;
  List<String> _entryPoints = <String>[];
  bool _formatted;
  List<implementation.WarningKind> _suppressWarnings =
      <implementation.WarningKind>[];

  /// Reports an error in a situation where we do not yet have
  /// a [Logger].
  void _reportEarlyError(String message) {
    print("Error(Reflectable): $message.");
    exit(-1);
  }

  /// Reports an info message in a situation where we do not yet have
  /// a [Logger].
  void _reportEarlyInfo(String message) {
    print("Info(Reflectable): $message.");
    exit(0);
  }

  /// Checks and interprets the given list of entry points,
  /// given via [_settings].
  List<String> _findEntryPoints(entryPointSettings) {
    List<String> entryPoints = <String>[];
    if (entryPointSettings == null) {
      _reportEarlyInfo("No entry points, nothing to do.");
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

  bool _findFormatted(formattedSettings) {
    if (formattedSettings == null) {
      return false;
    } else if (formattedSettings is! bool) {
      _reportEarlyError("Encountered non-bool value for 'formatted' option.");
      return false;
    } else {
      return formattedSettings;
    }
  }

  List<implementation.WarningKind> _findSuppressWarnings(
      suppressWarningsSettings) {
    void fail(setting) {
      _reportEarlyError("Encountered unknown value '$setting' for"
          " the 'suppressWarnings' option.\n"
          "Accepted values: true, false, missingEntryPoint, "
          "badSuperclass, badNamePattern, badMetadata");
    }

    Iterable<implementation.WarningKind> helper(setting) sync* {
      // With no settings, no warnings are suppressed; same for `false`.
      if (setting == null || setting == false) return;
      // Setting `true` means suppress them all.
      if (setting == true) {
        yield* implementation.WarningKind.values;
      } else if (setting is String) {
        switch (setting) {
          case "missingEntryPoint":
            yield implementation.WarningKind.missingEntryPoint;
            break;
          case "badSuperclass":
            yield implementation.WarningKind.badSuperclass;
            break;
          case "badNamePattern":
            yield implementation.WarningKind.badNamePattern;
            break;
          case "badMetadata":
            yield implementation.WarningKind.badMetadata;
            break;
          default:
            fail(setting);
            return;
        }
      } else {
        fail(setting);
        return;
      }
    }

    List<implementation.WarningKind> result = <implementation.WarningKind>[];
    if (suppressWarningsSettings is Iterable) {
      suppressWarningsSettings
          .forEach((setting) => helper(setting).forEach(result.add));
    } else {
      result.addAll(helper(suppressWarningsSettings));
    }
    return new List<implementation.WarningKind>.unmodifiable(result);
  }

  /// Creates new instance as required by Barback.
  ReflectableTransformer.asPlugin(this._settings) {
    _entryPoints = _findEntryPoints(_settings.configuration['entry_points']);
    _formatted = _findFormatted(_settings.configuration['formatted']);
    _suppressWarnings =
        _findSuppressWarnings(_settings.configuration['suppressWarnings']);
  }

  /// Return a [String] or [Future<String>] valued key for each
  /// primary asset that this transformer wishes to process, and
  /// null for assets that it wishes to ignore.  Primary assets
  /// with the same key are delivered to [apply] as a group.  In
  /// this transformer we handle the grouping later, so everything
  /// is in the same group.
  String classifyPrimary(AssetId id) {
    return _entryPoints.any((entryPoint) => id.path.endsWith(entryPoint))
        ? "ReflectableTransformed"
        : null;
  }

  /// Performs the transformation.
  @override
  Future apply(AggregateTransform transform) {
    return new implementation.TransformerImplementation()
        .apply(transform, _entryPoints, _formatted, _suppressWarnings);
  }

  @override
  declareOutputs(DeclaringAggregateTransform transform) async {
    List<AssetId> ids = await transform.primaryIds.toList();
    _entryPoints.forEach((String entryPoint) {
      AssetId id = ids.firstWhere((AssetId id) => id.path.endsWith(entryPoint),
          orElse: () => null);
      if (id == null) {
        // There is no such entry point; however, we do not need to emit
        // any diagnostic messages, this is done by `apply` in
        // `TransformerImplementation`.
        return;
      }
      transform.declareOutput(id);
      AssetId dataId = id.changeExtension("_reflectable_original_main.dart");
      transform.declareOutput(dataId);
    });
  }
}
