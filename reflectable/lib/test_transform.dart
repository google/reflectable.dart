// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Convenience functionality for testing the transformer.
library test_transform;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:barback/barback.dart';
import 'package:source_span/source_span.dart';

/// Collects logger-messages for inspection in tests.
class MessageRecord {
  AssetId id;
  LogLevel level;
  String message;
  SourceSpan span;
  MessageRecord(this.id, this.level, this.message, this.span);
}

/// A transform that gets its main inputs from a [Map] from path to [String].
/// If an input is not found there it will be looked up in [packageRoot].
/// [packageRoot] should use the system path-separator.
class TestAggregateTransform implements AggregateTransform {
  final Map<String, String> files;
  final List<Asset> outputs = <Asset>[];
  final Map<AssetId, Asset> assets = <AssetId, Asset>{};
  final Set<AssetId> consumed = new Set<AssetId>();
  String packageRoot;

  final List<MessageRecord> messages = <MessageRecord>[];

  logFunction(AssetId id, LogLevel level, String message, SourceSpan span) {
    messages.add(new MessageRecord(id, level, message, span));
  }

  TestAggregateTransform(this.files, [String packageRoot]) {
    this.packageRoot =
        packageRoot == null ? io.Platform.packageRoot : packageRoot;
    files.forEach((String description, String content) {
      AssetId assetId = new AssetId.parse(description);
      assets[assetId] = new Asset.fromString(assetId, content);
    });
  }

  TransformLogger get logger => new TransformLogger(logFunction);

  String get key => null;
  String get package => null;

  /// The stream of primary inputs that will be processed by this transform.
  Stream<Asset> get primaryInputs => new Stream.fromIterable(assets.values);

  /// Gets the asset for an input [id].
  ///
  /// If an input with [id] cannot be found, it will throw an
  /// [AssetNotFoundException].
  Future<Asset> getInput(AssetId id) async {
    Asset content = assets[id];
    if (content != null) return content;
    String pathWithoutLib =
        id.path.split('/').skip(1).join(io.Platform.pathSeparator);
    String path = [
      packageRoot,
      id.package,
      pathWithoutLib
    ].join(io.Platform.pathSeparator);
    io.File file = new io.File(path);
    if (!(await file.exists())) {
      throw new AssetNotFoundException(id);
    }
    return new Asset.fromFile(id, file);
  }

  Future<String> readInputAsString(AssetId id, {Encoding encoding}) async {
    return (await getInput(id)).readAsString(encoding: encoding);
  }

  Stream<List<int>> readInput(AssetId id) {
    throw new UnimplementedError();
  }

  Future<bool> hasInput(AssetId id) async {
    return files.containsKey(id.path);
  }

  /// Stores [output] as an output created by this transformation.
  ///
  /// A transformation can output as many assets as it wants.
  void addOutput(Asset output) {
    outputs.add(output);
  }

  Future<Map<String, String>> outputMap() async {
    Map<String, String> result = <String, String>{};
    for (Asset asset in outputs) {
      String content = await asset.readAsString();
      result["${asset.id.package}|${asset.id.path}"] = content;
    }
    return result;
  }

  void consumePrimary(AssetId id) {
    if (!assets.containsKey(id)) {
      throw new StateError(
          "$id can't be consumed because it's not a primary input.");
    }
    consumed.add(id);
  }
}

class TestDeclaringTransform implements DeclaringAggregateTransform {
  Set<String> outputs = new Set<String>();
  Set<String> assets = new Set<String>();
  Set<String> consumed = new Set<String>();

  TestDeclaringTransform(Map<String, String> files) {
    files.forEach((String description, String content) {
      assets.add(description);
    });
  }

  @override
  void consumePrimary(AssetId id) {
    consumed.add(id.toString());
  }

  @override
  void declareOutput(AssetId id) {
    outputs.add(id.toString());
  }

  @override
  String get key => null;

  @override
  TransformLogger get logger => null;

  @override
  String get package => null;

  @override
  Stream<AssetId> get primaryIds {
    return new Stream.fromIterable(
        assets.map((String a) => new AssetId.parse(a)));
  }
}
