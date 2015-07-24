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
import 'package:analyzer/src/generated/constant.dart';

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

class StaticInvokeCapability extends NamePatternCapability {
  const StaticInvokeCapability(String namePattern) : super(namePattern);
}

const staticInvokeCapability = const StaticInvokeCapability("");

class StaticInvokeMetaCapability extends MetadataQuantifiedCapability {
  const StaticInvokeMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

class NewInstanceCapability extends NamePatternCapability {
  const NewInstanceCapability(String namePattern) : super(namePattern);
}

const newInstanceCapability = const NewInstanceCapability("");

class NewInstanceMetaCapability extends MetadataQuantifiedCapability {
  const NewInstanceMetaCapability(ClassElement metadataType)
      : super(metadataType);
}

const nameCapability = const _NameCapability();

const classifyCapability = const _ClassifyCapability();

const metadataCapability = const _MetadataCapability();

class TypeCapability implements ApiReflectCapability {
  final Element upperBound;
  const TypeCapability(this.upperBound);
}

// TODO(eernst): Obtain an Element representing the class Object.
const typeCapability = const TypeCapability(null /* should ~ Object! */);

const localTypeCapability = const TypeCapability(null);

const typeRelationsCapability = const _TypeRelationsCapability();

const ownerCapability = const _OwnerCapability();

const declarationsCapability = const _DeclarationsCapability();

const uriCapability = const _UriCapability();

const libraryDependenciesCapability = const _LibraryDependenciesCapability();

class InvokingCapability extends NamePatternCapability
    implements InstanceInvokeCapability, StaticInvokeCapability,
    NewInstanceCapability {
  const InvokingCapability(String namePattern) : super(namePattern);
}

const invokingCapability = const InvokingCapability("");

class InvokingMetaCapability extends MetadataQuantifiedCapability
    implements InstanceInvokeMetaCapability, StaticInvokeMetaCapability,
    NewInstanceMetaCapability {
  const InvokingMetaCapability(ClassElement metadataType) : super(metadataType);
}

class TypingCapability extends TypeCapability
    implements _NameCapability, _ClassifyCapability, _MetadataCapability,
    _TypeRelationsCapability, _OwnerCapability, _DeclarationsCapability,
    _UriCapability, _LibraryDependenciesCapability {
  const TypingCapability(Element upperBound) : super(upperBound);
}

abstract class ReflecteeQuantifyCapability implements ReflectCapability {
  final bool _capabilitiesGivenAsList;
  final ApiReflectCapability _cap0, _cap1, _cap2, _cap3, _cap4;
  final ApiReflectCapability _cap5, _cap6, _cap7, _cap8, _cap9;
  final List<ApiReflectCapability> _capabilities;

  List<ApiReflectCapability> get capabilities {
    if (_capabilitiesGivenAsList) return _capabilities;
    List<ApiReflectCapability> result = <ApiReflectCapability>[];

    void add(ApiReflectCapability cap) {
      if (cap != null) result.add(cap);
    }

    add(_cap0);
    add(_cap1);
    add(_cap2);
    add(_cap3);
    add(_cap4);
    add(_cap5);
    add(_cap6);
    add(_cap7);
    add(_cap8);
    add(_cap9);
    return result;
  }

  const ReflecteeQuantifyCapability([this._cap0 = null, this._cap1 = null,
      this._cap2 = null, this._cap3 = null, this._cap4 = null,
      this._cap5 = null, this._cap6 = null, this._cap7 = null,
      this._cap8 = null, this._cap9 = null])
      : _capabilitiesGivenAsList = false,
        _capabilities = null;

  const ReflecteeQuantifyCapability.fromList(this._capabilities)
      : _capabilitiesGivenAsList = true,
        _cap0 = null,
        _cap1 = null,
        _cap2 = null,
        _cap3 = null,
        _cap4 = null,
        _cap5 = null,
        _cap6 = null,
        _cap7 = null,
        _cap8 = null,
        _cap9 = null;
}

class SubtypeQuantifyCapability extends ReflecteeQuantifyCapability {
  const SubtypeQuantifyCapability([ApiReflectCapability cap0,
      ApiReflectCapability cap1, ApiReflectCapability cap2,
      ApiReflectCapability cap3, ApiReflectCapability cap4,
      ApiReflectCapability cap5, ApiReflectCapability cap6,
      ApiReflectCapability cap7, ApiReflectCapability cap8,
      ApiReflectCapability cap9])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const SubtypeQuantifyCapability.fromList(
      List<ApiReflectCapability> capabilities)
      : super.fromList(capabilities);
}

class AdmitSubtypeCapability extends ReflecteeQuantifyCapability {
  const AdmitSubtypeCapability([ApiReflectCapability cap0,
      ApiReflectCapability cap1, ApiReflectCapability cap2,
      ApiReflectCapability cap3, ApiReflectCapability cap4,
      ApiReflectCapability cap5, ApiReflectCapability cap6,
      ApiReflectCapability cap7, ApiReflectCapability cap8,
      ApiReflectCapability cap9])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const AdmitSubtypeCapability.fromList(List<ApiReflectCapability> capabilities)
      : super.fromList(capabilities);
}

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

class _NameCapability implements ApiReflectCapability {
  const _NameCapability();
}

class _ClassifyCapability implements ApiReflectCapability {
  const _ClassifyCapability();
}

class _MetadataCapability implements ApiReflectCapability {
  const _MetadataCapability();
}

class _TypeRelationsCapability implements ApiReflectCapability {
  const _TypeRelationsCapability();
}

class _OwnerCapability implements ApiReflectCapability {
  const _OwnerCapability();
}

class _DeclarationsCapability implements ApiReflectCapability {
  const _DeclarationsCapability();
}

class _UriCapability implements ApiReflectCapability {
  const _UriCapability();
}

class _LibraryDependenciesCapability implements ApiReflectCapability {
  const _LibraryDependenciesCapability();
}
