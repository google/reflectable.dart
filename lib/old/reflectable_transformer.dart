// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.reflectable_transformer;

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:analyzer/src/generated/element.dart';

import 'reflectable.dart';
export 'reflectable.dart';

class ReflectableTransformer extends Transformer 
                             implements DeclaringTransformer {
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
  /// TODO(eernst): Currently the APIs of mirrors and many other things are
  /// being debated and adjusted, and generation of the static version of
  /// lib/reflectable.dart for a specific usage has not yet been implemented.  
  /// The transformation is currently just a stub (using output into some files
  /// named '*.clslist' for pure debugging purposes).  Until implementation
  /// of the transformation itself is commenced, the code below will only
  /// serve to enable the transformer to run, it will not do useful work.
  Future apply(Transform transform) {
    Asset input = transform.primaryInput;
    List<ClassElement> classes;
    Resolvers resolvers = new Resolvers(dartSdkDirectory);
    return resolvers.get(transform).then((resolver) {
      classes = ReflectableX.classes(resolver);
      return input.readAsString();
    }).then((source) {
      AssetId id = input.id.changeExtension(".clslist");
      StringBuffer listing = new StringBuffer();
      for (var clazz in classes) {
        listing.writeln("$clazz");
      }
      transform.addOutput(new Asset.fromString(id, "$listing"));
    });
  }
}

_error() => throw new StateError("ReflectableTransformer failed");
