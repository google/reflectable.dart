// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.element_capability;

// This library provides a variant of the `ReflectCapability` class
// hierarchy from `../capability.dart` which is suitable for holding
// information about entities in a target program at analysis time,
// rather than holding runtime entities. This is necessary because
// the transformer needs to deal with analysis time descriptions of
// objects and types that cannot exist in the transformer itself,
// because the transformer does not contain or import the same
// libraries as the target program does.
//
// For documentation of each of these classes and const values, please
// search the declaration with the same name in `../capability.dart`.
//
// NB! It is crucial that all changes in '../capabilities.dart' are
// performed in the corresponding manner here, and vice versa.

import 'package:analyzer/src/generated/element.dart';

abstract class ReflectCapability {
  const ReflectCapability();
}

abstract class ApiReflectCapability implements ReflectCapability {
  const ApiReflectCapability();
}

abstract class NamePatternCapability implements ApiReflectCapability {
  final String namePattern;
  const NamePatternCapability(this.namePattern);
}

abstract class MetadataQuantifiedCapability implements ApiReflectCapability {
  final ClassElement metadataType;
  const MetadataQuantifiedCapability(this.metadataType);
}

class InstanceInvokeCapability extends NamePatternCapability {
  const InstanceInvokeCapability(String namePattern) : super(namePattern);
}

const instanceInvokeCapability = const InstanceInvokeCapability("");

class InstanceInvokeMetaCapability extends MetadataQuantifiedCapability {
  const InstanceInvokeMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

class StaticInvokeCapability extends NamePatternCapability
    implements TypeCapability {
  const StaticInvokeCapability(String namePattern) : super(namePattern);
}

const staticInvokeCapability = const StaticInvokeCapability("");

class StaticInvokeMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const StaticInvokeMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

class TopLevelInvokeCapability extends NamePatternCapability {
  const TopLevelInvokeCapability(String namePattern) : super(namePattern);
}

class TopLevelInvokeMetaCapability extends MetadataQuantifiedCapability {
  const TopLevelInvokeMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

class NewInstanceCapability extends NamePatternCapability
    implements TypeCapability {
  const NewInstanceCapability(String namePattern) : super(namePattern);
}

const newInstanceCapability = const NewInstanceCapability("");

class NewInstanceMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const NewInstanceMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

const nameCapability = const _NameCapability();

const classifyCapability = const _ClassifyCapability();

const metadataCapability = const _MetadataCapability();

class TypeCapability implements ApiReflectCapability {
  const TypeCapability();
}

const typeCapability = const TypeCapability();

const typeRelationsCapability = const _TypeRelationsCapability();

const reflectedTypeCapability = const _ReflectedTypeCapability();

const libraryCapability = const _LibraryCapability();

const declarationsCapability = const _DeclarationsCapability();

const uriCapability = const _UriCapability();

const libraryDependenciesCapability = const _LibraryDependenciesCapability();

class InvokingCapability extends NamePatternCapability
    implements
        InstanceInvokeCapability,
        StaticInvokeCapability,
        NewInstanceCapability {
  const InvokingCapability(String namePattern) : super(namePattern);
}

const invokingCapability = const InvokingCapability("");

class InvokingMetaCapability extends MetadataQuantifiedCapability
    implements
        InstanceInvokeMetaCapability,
        StaticInvokeMetaCapability,
        NewInstanceMetaCapability {
  const InvokingMetaCapability(ClassElement metadataType) : super(metadataType);
}

class TypingCapability
    implements
        TypeCapability, // Redundant, just included for readability.
        _NameCapability,
        _ClassifyCapability,
        _MetadataCapability,
        _TypeRelationsCapability,
        _DeclarationsCapability,
        _UriCapability,
        _LibraryDependenciesCapability {
  const TypingCapability();
}

abstract class ReflecteeQuantifyCapability implements ReflectCapability {
  const ReflecteeQuantifyCapability();
}

const subtypeQuantifyCapability = const _SubtypeQuantifyCapability();

class SuperclassQuantifyCapability implements ReflecteeQuantifyCapability {
  final Element upperBound;
  final bool excludeUpperBound;
  const SuperclassQuantifyCapability(this.upperBound,
      {bool excludeUpperBound: false})
      : excludeUpperBound = excludeUpperBound;
}

// Note that `null` represents the [ClassElement] for `Object`.
const superclassQuantifyCapability = const SuperclassQuantifyCapability(null);

class TypeAnnotationQuantifyCapability implements ReflecteeQuantifyCapability {
  final bool transitive;
  const TypeAnnotationQuantifyCapability({bool transitive: false})
      : transitive = transitive;
}

const typeAnnotationQuantifyCapability =
    const TypeAnnotationQuantifyCapability();

const typeAnnotationDeepQuantifyCapability =
    const TypeAnnotationQuantifyCapability(transitive: true);

const correspondingSetterQuantifyCapability =
    const _CorrespondingSetterQuantifyCapability();

const admitSubtypeCapability = const _AdmitSubtypeCapability();

class ImportAttachedCapability {
  final Element reflector;
  const ImportAttachedCapability(this.reflector);
}

class GlobalQuantifyCapability extends ImportAttachedCapability {
  final String classNamePattern;
  const GlobalQuantifyCapability(this.classNamePattern, Element reflector)
      : super(reflector);
}

class GlobalQuantifyMetaCapability extends ImportAttachedCapability {
  final Element metadataType;
  const GlobalQuantifyMetaCapability(this.metadataType, Element reflector)
      : super(reflector);
}

class _NameCapability implements TypeCapability {
  const _NameCapability();
}

class _ClassifyCapability implements TypeCapability {
  const _ClassifyCapability();
}

class _MetadataCapability implements TypeCapability {
  const _MetadataCapability();
}

class _TypeRelationsCapability implements TypeCapability {
  const _TypeRelationsCapability();
}

class _ReflectedTypeCapability implements _DeclarationsCapability {
  const _ReflectedTypeCapability();
}

class _LibraryCapability implements ApiReflectCapability {
  const _LibraryCapability();
}

class _DeclarationsCapability implements TypeCapability {
  const _DeclarationsCapability();
}

class _UriCapability implements ApiReflectCapability {
  const _UriCapability();
}

class _LibraryDependenciesCapability implements ApiReflectCapability {
  const _LibraryDependenciesCapability();
}

class _SubtypeQuantifyCapability implements ReflecteeQuantifyCapability {
  const _SubtypeQuantifyCapability();
}

class _CorrespondingSetterQuantifyCapability
    implements ReflecteeQuantifyCapability {
  const _CorrespondingSetterQuantifyCapability();
}

class _AdmitSubtypeCapability implements ReflecteeQuantifyCapability {
  const _AdmitSubtypeCapability();
}
