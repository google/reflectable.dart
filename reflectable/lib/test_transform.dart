// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Convenience functionality for testing the transformer.
library reflectable.test_transform;

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
class TestTransform implements Transform {
  final String fileName;
  final String fileContents;
  final String package;
  final List<Asset> outputs = <Asset>[];
  final Map<AssetId, Asset> assets = <AssetId, Asset>{};
  Asset _primaryAsset;
  AssetId _primaryAssetId;
  bool consumed = false;
  String packageRoot;

  final List<MessageRecord> messages = <MessageRecord>[];

  logFunction(AssetId id, LogLevel level, String message, SourceSpan span) {
    messages.add(new MessageRecord(id, level, message, span));
  }

  TestTransform(this.fileName, this.fileContents, this.package,
      [String packageRoot]) {
    this.packageRoot =
        packageRoot == null ? io.Platform.packageRoot : packageRoot;
    // The semantics of `io.Platform.packageRoot` suddenly changed from version
    // dart-sdk-1.14.0-dev.4.0 to .5.0: It used to be passed on from the
    // command line arguments directly, but starting from .5.0 it is being
    // interpreted: If it is a relative path then it is turned into an absolute
    // path, and an absolute path is in turn changed into a 'file://' uri.
    // If [packageRoot] is a 'file://' uri then we reduce it to a path.
    Uri uri;
    if (this.packageRoot == null) {
      logger.error("Cannot determine the package root, using './packages'.");
      this.packageRoot = "./packages";
    }
    try {
      uri = Uri.parse(this.packageRoot);
      this.packageRoot = uri.path;
    } on FormatException catch (_) {
      // No problem, now we just know that `packageRoot` is not a well-formed
      // uri; it should then be a path.
    }
    if (this.packageRoot.endsWith(io.Platform.pathSeparator)) {
      this.packageRoot =
          this.packageRoot.substring(0, this.packageRoot.length - 1);
    }
    _primaryAssetId = new AssetId.parse(fileName);
    _primaryAsset = new Asset.fromString(_primaryAssetId, fileContents);
    assets[_primaryAssetId] = _primaryAsset;
  }

  @override
  TransformLogger get logger => new TransformLogger(logFunction);

  /// The stream of primary inputs that will be processed by this transform.
  @override
  Asset get primaryInput => _primaryAsset;

  /// Gets the asset for an input [id].
  ///
  /// If an input with [id] cannot be found, it will throw an
  /// [AssetNotFoundException].
  @override
  Future<Asset> getInput(AssetId id) async {
    Asset content = assets[id];
    if (content != null) return content;
    String path;
    if (package == id.package) {
      path = id.path;
    } else {
      String pathWithoutLib =
          id.path.split('/').skip(1).join(io.Platform.pathSeparator);
      path = [packageRoot, id.package, pathWithoutLib]
          .join(io.Platform.pathSeparator);
    }
    io.File file = new io.File(path);
    if (!(await file.exists())) {
      throw new AssetNotFoundException(id);
    }
    return new Asset.fromFile(id, file);
  }

  @override
  Future<String> readInputAsString(AssetId id, {Encoding encoding}) async {
    return (await getInput(id)).readAsString(encoding: encoding);
  }

  @override
  Stream<List<int>> readInput(AssetId id) {
    throw new UnimplementedError();
  }

  @override
  Future<bool> hasInput(AssetId id) async =>
      new Future<bool>.value(fileName == id.path);

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

  void consumePrimary() {
    consumed = true;
  }
}

class TestDeclaringTransform implements DeclaringTransform {
  Set<String> outputs = new Set<String>();
  String asset;
  bool consumed = false;

  TestDeclaringTransform(this.asset);

  @override
  void consumePrimary() {
    consumed = true;
  }

  @override
  void declareOutput(AssetId id) {
    outputs.add(id.toString());
  }

  @override
  TransformLogger get logger => null;

  @override
  AssetId get primaryId => new AssetId.parse(asset);
}
