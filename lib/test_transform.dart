// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Convenience functionality for testing the transformer.
library reflectable.test_transform;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:barback/barback.dart';
import 'package:package_resolver/package_resolver.dart';
import "package:package_config/packages_file.dart" as packages_file;
import 'package:source_span/source_span.dart';

Uri dotPackages = io.Platform.script;

/// Collects logger-messages for inspection in tests.
class MessageRecord {
  AssetId id;
  LogLevel level;
  String message;
  SourceSpan span;
  MessageRecord(this.id, this.level, this.message, this.span);
}

/// A transform that gets its main inputs from a [Map] from path to [String].
/// If an input is not found there it will be looked up in '.packages'.
class TestTransform implements Transform {
  final String fileName;
  final String fileContents;
  final String package;
  final List<Asset> outputs = <Asset>[];
  final Map<AssetId, Asset> assets = <AssetId, Asset>{};
  Asset _primaryAsset;
  AssetId _primaryAssetId;
  bool consumed = false;
  Uri dotPackages;
  PackageResolver packageResolver;

  final List<MessageRecord> messages = <MessageRecord>[];

  logFunction(AssetId id, LogLevel level, String message, SourceSpan span) {
    messages.add(new MessageRecord(id, level, message, span));
  }

  TestTransform(
      this.fileName, this.fileContents, this.package) {
    _primaryAssetId = new AssetId.parse(fileName);
    _primaryAsset = new Asset.fromString(_primaryAssetId, fileContents);
    assets[_primaryAssetId] = _primaryAsset;
    Uri scriptUri = io.Platform.script;
    String uriDataScriptString = scriptUri.data?.contentAsString();
    if (uriDataScriptString != null) {
      // `uriDataScriptString` actually contains the entire program, which
      // imports the test file using a `file:///` uri.
      int startIndex = uriDataScriptString.indexOf("file:///");
      if (startIndex == 0) {
        logger.error("Unexpected Platform.script: $uriDataScriptString");
      }
      int endIndex = uriDataScriptString.indexOf("\" as test;");
      scriptUri =
          Uri.parse(uriDataScriptString.substring(startIndex, endIndex));
    }
    if (scriptUri.hasScheme && scriptUri.scheme == 'http') {
      logger.error("Platform.script has scheme 'http': Not supported");
    }
    dotPackages = scriptUri.resolve("../.packages");
  }

  @override
  TransformLogger get logger => new TransformLogger(logFunction);

  /// The stream of primary inputs that will be processed by this transform.
  @override
  Asset get primaryInput => _primaryAsset;

  Future _setupPackageResolver() async {
    String path = dotPackages.toFilePath();
    io.File file = new io.File(path);
    if (!(await file.exists())) {
      logger.error("Package specification not found: $path");
    }
    String contents = await file.readAsString();
    Map<String, Uri> map = packages_file.parse(contents.codeUnits, dotPackages);
    packageResolver = new PackageResolver.config(map, uri: dotPackages);
  }

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
      if (packageResolver == null) await _setupPackageResolver();
      String pathWithoutLib =
          id.path.split('/').skip(1).join(io.Platform.pathSeparator);
      path = (await packageResolver.urlFor(id.package, pathWithoutLib))
          .toFilePath();
    }
    io.File file = new io.File(path);
    if (!(await file.exists())) throw new AssetNotFoundException(id);
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
