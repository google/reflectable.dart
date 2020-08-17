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

import 'package:analyzer/dart/element/element.dart';

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

const instanceInvokeCapability = InstanceInvokeCapability('');

class InstanceInvokeMetaCapability extends MetadataQuantifiedCapability {
  const InstanceInvokeMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

class StaticInvokeCapability extends NamePatternCapability
    implements TypeCapability {
  const StaticInvokeCapability(String namePattern) : super(namePattern);
}

const staticInvokeCapability = StaticInvokeCapability('');

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

const newInstanceCapability = NewInstanceCapability('');

class NewInstanceMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const NewInstanceMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

/// To be eliminated when `NameCapability` in 'capability.dart' is eliminated.
/// We do not mark it as deprecated at this time because it will be needed in
/// order to handle usages of the deprecated `NameCapability` class or
/// `nameCapability` value in client code.
class NameCapability implements TypeCapability {
  const NameCapability();
}

/// To be eliminated when `nameCapability` in 'capability.dart' is eliminated.
/// We do not mark it as deprecated at this time because it will be needed in
/// order to handle usages of the deprecated `NameCapability` class or
/// `nameCapability` value in client code.
const nameCapability = NameCapability();

/// To be eliminated when `ClassifyCapability` in 'capability.dart' is
/// eliminated. We do not mark it as deprecated at this time because it will be
/// needed in order to handle usages of the deprecated `ClassifyCapability`
/// class or `classifyCapability` value in client code.
class ClassifyCapability implements TypeCapability {
  const ClassifyCapability();
}

/// To be eliminated when `classifyCapability` in 'capability.dart' is
/// eliminated. We do not mark it as deprecated at this time because it will be
/// needed in order to handle usages of the deprecated `ClassifyCapability`
/// class or `classifyCapability` value in client code.
const classifyCapability = ClassifyCapability();

class MetadataCapability implements TypeCapability {
  const MetadataCapability();
}

const metadataCapability = MetadataCapability();

class TypeCapability implements ApiReflectCapability {
  const TypeCapability();
}

const typeCapability = TypeCapability();

class TypeRelationsCapability implements TypeCapability {
  const TypeRelationsCapability();
}

const typeRelationsCapability = TypeRelationsCapability();

const reflectedTypeCapability = _ReflectedTypeCapability();

class LibraryCapability implements ApiReflectCapability {
  const LibraryCapability();
}

const libraryCapability = LibraryCapability();

class DeclarationsCapability implements TypeCapability {
  const DeclarationsCapability();
}

const declarationsCapability = DeclarationsCapability();

class UriCapability implements LibraryCapability {
  const UriCapability();
}

const uriCapability = UriCapability();

class LibraryDependenciesCapability implements LibraryCapability {
  const LibraryDependenciesCapability();
}

const libraryDependenciesCapability = LibraryDependenciesCapability();

class InvokingCapability extends NamePatternCapability
    implements
        InstanceInvokeCapability,
        StaticInvokeCapability,
        NewInstanceCapability {
  const InvokingCapability(String namePattern) : super(namePattern);
}

const invokingCapability = InvokingCapability('');

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
        NameCapability,
        ClassifyCapability,
        MetadataCapability,
        TypeRelationsCapability,
        DeclarationsCapability,
        UriCapability,
        LibraryDependenciesCapability {
  const TypingCapability();
}

const typingCapability = TypingCapability();

const delegateCapability = _DelegateCapability();

abstract class ReflecteeQuantifyCapability implements ReflectCapability {
  const ReflecteeQuantifyCapability();
}

const subtypeQuantifyCapability = _SubtypeQuantifyCapability();

class SuperclassQuantifyCapability implements ReflecteeQuantifyCapability {
  final Element upperBound;
  final bool excludeUpperBound;
  const SuperclassQuantifyCapability(this.upperBound,
      {bool excludeUpperBound = false})
      : excludeUpperBound = excludeUpperBound;
}

// Note that `null` represents the [ClassElement] for `Object`.
const superclassQuantifyCapability = SuperclassQuantifyCapability(null);

class TypeAnnotationQuantifyCapability implements ReflecteeQuantifyCapability {
  final bool transitive;
  const TypeAnnotationQuantifyCapability({bool transitive = false})
      : transitive = transitive;
}

const typeAnnotationQuantifyCapability = TypeAnnotationQuantifyCapability();

const typeAnnotationDeepQuantifyCapability =
    TypeAnnotationQuantifyCapability(transitive: true);

const correspondingSetterQuantifyCapability =
    _CorrespondingSetterQuantifyCapability();

const admitSubtypeCapability = _AdmitSubtypeCapability();

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

class _ReflectedTypeCapability implements DeclarationsCapability {
  const _ReflectedTypeCapability();
}

class _DelegateCapability implements ApiReflectCapability {
  const _DelegateCapability();
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
