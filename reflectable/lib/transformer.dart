// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.transformer;

import 'dart:async';
import 'dart:io';
import 'package:barback/barback.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'src/transformer_implementation.dart' as implementation;

class ReflectableTransformer extends Transformer
    implements DeclaringTransformer {
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
    Set<String> entryPoints = new Set<String>();
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
    return entryPoints.toList();
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
          " the 'suppress_warnings' option.\n"
          "Accepted values: true, false, missing_entry_point, "
          "bad_superclass, bad_name_pattern, bad_metadata");
    }

    Iterable<implementation.WarningKind> helper(setting) sync* {
      // With no settings, no warnings are suppressed; same for `false`.
      if (setting == null || setting == false) return;
      // Setting `true` means suppress them all.
      if (setting == true) {
        yield* implementation.WarningKind.values;
      } else if (setting is String) {
        switch (setting) {
          case "missing_entry_point":
            yield implementation.WarningKind.missingEntryPoint;
            break;
          case "bad_superclass":
            yield implementation.WarningKind.badSuperclass;
            break;
          case "bad_name_pattern":
            yield implementation.WarningKind.badNamePattern;
            break;
          case "bad_metadata":
            yield implementation.WarningKind.badMetadata;
            break;
          case "bad_reflector_class":
            yield implementation.WarningKind.badReflectorClass;
            break;
          case "unrecognized_reflector":
            yield implementation.WarningKind.unrecognizedReflector;
            break;
          case "unused_reflector":
            yield implementation.WarningKind.unusedReflector;
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

  /// Performs the transformation.
  @override
  Future apply(Transform transform) {
    return new implementation.TransformerImplementation().apply(
        transform, _entryPoints, _formatted, _suppressWarnings);
  }

  @override
  declareOutputs(DeclaringTransform transform) async {
    AssetId id = await transform.primaryId;
    _entryPoints.forEach((String entryPoint) {
      Glob glob = new Glob(entryPoint);
      if (glob.matches(id.path)) {
        transform.declareOutput(id);
        AssetId dataId = id.changeExtension("_reflectable_original_main.dart");
        transform.declareOutput(dataId);
      }
      // Otherwise there is no such entry point; however, we do not need to
      // emit any diagnostic messages, this is done by `apply` in
      // `TransformerImplementation`.
    });
  }
}
