// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// TODO(sigurdm) doc: Make NoSuchCapability messages streamlined (the same in
// both `reflectable_mirror_based.dart` and
// `reflectable_transformer_based.dart`, and explaining as well as possible
// which capability is missing.)

/// Implementation of the reflectable interface using dart mirrors.
library reflectable.src.reflectable_implementation;

import 'dart:mirrors' as dm;
import 'incompleteness.dart';
import 'reflectable_base.dart';
import 'fixed_point.dart';
import '../capability.dart';
import '../mirrors.dart' as rm;
import '../reflectable.dart';

bool get isTransformed => false;

/// Returns the set of reflectors in the current program.
Set<Reflectable> get reflectors {
  Set<Reflectable> result = new Set<Reflectable>();
  for (dm.LibraryMirror library in dm.currentMirrorSystem().libraries.values) {
    for (dm.LibraryDependencyMirror dependency in library.libraryDependencies) {
      if (dependency.isImport &&
          dependency.targetLibrary.qualifiedName == reflectableLibrarySymbol) {
        for (dm.InstanceMirror metadatumMirror in dependency.metadata) {
          Object metadatum = metadatumMirror.reflectee;
          if (metadatum is GlobalQuantifyCapability) {
            result.add(metadatum.reflector);
          }
          if (metadatum is GlobalQuantifyMetaCapability) {
            result.add(metadatum.reflector);
          }
        }
      }
    }
  }
  for (dm.LibraryMirror library in dm.currentMirrorSystem().libraries.values) {
    for (dm.DeclarationMirror declaration in library.declarations.values) {
      for (dm.InstanceMirror metadatum in declaration.metadata) {
        if (metadatum.reflectee is Reflectable) {
          result.add(metadatum.reflectee);
        }
      }
    }
  }
  return result;
}

/// The name of the reflectable library.
const Symbol reflectableLibrarySymbol = #reflectable.reflectable;

rm.ClassMirror wrapClassMirrorIfSupported(
    dm.ClassMirror classMirror, ReflectableImpl reflectable) {
  if (classMirror is dm.FunctionTypeMirror) {
    // TODO(sigurdm) clarify: Exactly what capabilities will allow reflecting on
    // a function is still not clear.
    return new _FunctionTypeMirrorImpl(classMirror, reflectable);
  } else {
    assert(classMirror is dm.ClassMirror);
    if (!reflectable._supportedClasses
        .contains(classMirror.originalDeclaration)) {
      throw new NoSuchCapabilityError(
          "Reflecting on class '$classMirror' without capability");
    }
    return new ClassMirrorImpl(classMirror, reflectable);
  }
}

rm.DeclarationMirror wrapDeclarationMirror(
    dm.DeclarationMirror declarationMirror, ReflectableImpl reflectable) {
  if (declarationMirror is dm.MethodMirror) {
    return new MethodMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.ParameterMirror) {
    return new _ParameterMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.VariableMirror) {
    return new VariableMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.TypeVariableMirror) {
    return new _TypeVariableMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.TypedefMirror) {
    return new _TypedefMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.ClassMirror) {
    // Covers FunctionTypeMirror and ClassMirror.
    return wrapClassMirrorIfSupported(declarationMirror, reflectable);
  } else {
    assert(declarationMirror is dm.LibraryMirror);
    return new _LibraryMirrorImpl(declarationMirror, reflectable);
  }
}

rm.InstanceMirror wrapInstanceMirror(
    dm.InstanceMirror instanceMirror, ReflectableImpl reflectable) {
  if (instanceMirror is dm.ClosureMirror) {
    return new _ClosureMirrorImpl(instanceMirror, reflectable);
  } else {
    assert(instanceMirror is dm.InstanceMirror);
    return new _InstanceMirrorImpl(instanceMirror, reflectable);
  }
}

rm.ObjectMirror wrapObjectMirror(
    dm.ObjectMirror m, ReflectableImpl reflectable) {
  if (m is dm.LibraryMirror) {
    return new _LibraryMirrorImpl(m, reflectable);
  } else if (m is dm.InstanceMirror) {
    return wrapInstanceMirror(m, reflectable);
  } else {
    assert(m is dm.ClassMirror);
    return wrapClassMirrorIfSupported(m, reflectable);
  }
}

rm.TypeMirror wrapTypeMirror(
    dm.TypeMirror typeMirror, ReflectableImpl reflectable) {
  if (typeMirror is dm.TypeVariableMirror) {
    return new _TypeVariableMirrorImpl(typeMirror, reflectable);
  } else if (typeMirror is dm.TypedefMirror) {
    return new _TypedefMirrorImpl(typeMirror, reflectable);
  } else if (typeMirror.hasReflectedType &&
      typeMirror.reflectedType == dynamic) {
    return new _SpecialTypeMirrorImpl(typeMirror, reflectable);
  } else {
    assert(typeMirror is dm.ClassMirror);
    return wrapClassMirrorIfSupported(typeMirror, reflectable);
  }
}

rm.CombinatorMirror wrapCombinatorMirror(dm.CombinatorMirror combinatorMirror) {
  return new _CombinatorMirrorImpl(combinatorMirror);
}

dm.ClassMirror unwrapClassMirror(rm.ClassMirror m) {
  if (m is ClassMirrorImpl) {
    // This also works for _FunctionTypeMirrorImpl
    return m._classMirror;
  } else {
    throw unreachableError("Unexpected subtype of ClassMirror");
  }
}

dm.TypeMirror unwrapTypeMirror(rm.TypeMirror TypeMirror) {
  if (TypeMirror is _TypeMirrorImpl) {
    return TypeMirror._typeMirror;
  } else {
    throw unreachableError("Unexpected subtype of TypeMirror");
  }
}

/// Returns true iff an element of the [metadata] is supported by the
/// [capability].
bool metadataSupported(
    List<dm.InstanceMirror> metadata, MetadataQuantifiedCapability capability) {
  return metadata.map((dm.InstanceMirror x) => x.type).any(
      (dm.ClassMirror classMirror) =>
          classMirror.isSubtypeOf(dm.reflectType(capability.metadataType)));
}

bool impliesDownwardsClosure(List<ReflectCapability> capabilities) {
  return capabilities
      .any((capability) => capability == subtypeQuantifyCapability);
}

bool impliesUpwardsClosure(List<ReflectCapability> capabilities) {
  return capabilities.any((ReflectCapability capability) =>
      capability is SuperclassQuantifyCapability);
}

bool impliesTypeAnnotations(List<ReflectCapability> capabilities) {
  return capabilities.any((ReflectCapability capability) =>
      capability is TypeAnnotationQuantifyCapability);
}

bool impliesTypeAnnotationClosure(List<ReflectCapability> capabilities) {
  return capabilities.any((ReflectCapability capability) =>
      capability is TypeAnnotationQuantifyCapability &&
          capability.transitive == true);
}

bool impliesMixins(List<ReflectCapability> capabilities) {
  return capabilities.any(
      (ReflectCapability capability) => capability is TypeRelationsCapability);
}

bool impliesReflectedType(List<ReflectCapability> capabilities) {
  return capabilities.any(
      (ReflectCapability capability) => capability == reflectedTypeCapability);
}

bool impliesCorrespondingSetter(List<ReflectCapability> capabilities) {
  return capabilities.any((ReflectCapability capability) =>
      capability == correspondingSetterQuantifyCapability);
}

Map<dm.ClassMirror, bool> extractUpwardsClosureBounds(
    List<ReflectCapability> capabilities) {
  Map<dm.ClassMirror, bool> result = <dm.ClassMirror, bool>{};
  capabilities.forEach((ReflectCapability capability) {
    if (capability is SuperclassQuantifyCapability) {
      dm.TypeMirror typeMirror = dm.reflectType(capability.upperBound);
      if (typeMirror is dm.ClassMirror) {
        result[typeMirror] = capability.excludeUpperBound;
      } else {
        throw new ArgumentError("Unexpected kind of upper bound specified "
            "for a `SuperclassQuantifyCapability`: $typeMirror.");
      }
    }
  });
  return result;
}

bool impliesDeclarations(List<ReflectCapability> capabilities) {
  return capabilities.contains(declarationsCapability);
}

bool impliesTypes(List<ReflectCapability> capabilities) {
  if (!impliesDeclarations(capabilities)) return false;
  return capabilities.any((ReflectCapability capability) {
    return capability is TypeCapability;
  });
}

/// Returns true if [predicate] returns true on the given [name]; otherwise, if
/// [reflectable] allows for corresponding setter quantification then it
/// returns the result of calling [predicate] on the corresponding getter name.
/// In other words, it makes an attempt to get "yes" from [predicate] directly
/// and then, if allowed, via the corresponding getter.
bool _checkWithGetter(
    ReflectableImpl reflectable, String name, bool predicate(String name)) {
  return predicate(name) ||
      (_isSetterName(name) &&
          impliesCorrespondingSetter(reflectable.capabilities) &&
          predicate(_setterNameToGetterName(name)));
}

/// Returns true if [classMirror] supports reflective invoke of the
/// instance-member named [name] according to the capabilities of [reflectable].
bool reflectableSupportsInstanceInvoke(
    ReflectableImpl reflectable, String name, dm.ClassMirror classMirror) {
  bool helper(String name) {
    Symbol nameSymbol = new Symbol(name);
    bool predicate(ApiReflectCapability capability) {
      if (capability == invokingCapability ||
          capability == instanceInvokeCapability) {
        return true;
      } else if (capability is InstanceInvokeCapability) {
        return new RegExp(capability.namePattern).hasMatch(name);
      } else if (capability is InstanceInvokeMetaCapability) {
        // We have to use 'declarations' here instead of instanceMembers,
        // because the synthetic field mirrors generated from fields do not
        // have metadata attached. This means we have to walk up all the
        // classes on the super chain as well.
        dm.ClassMirror currentClass = classMirror;
        while (currentClass != null) {
          dm.DeclarationMirror declarationMirror =
              currentClass.declarations[nameSymbol];
          if (declarationMirror != null &&
              metadataSupported(declarationMirror.metadata, capability)) {
            return true;
          }
          currentClass = currentClass.superclass;
        }
        return false;
      } else {
        return false;
      }
    }

    return reflectable.hasCapability(predicate);
  }

  return _checkWithGetter(reflectable, name, helper);
}

/// Returns true if [classMirror] supports looking up the declaration of the
/// instance-member named [name] according to the capabilities of [reflectable].
bool reflectableSupportsDeclaration(
    ReflectableImpl reflectable, String name, dm.ClassMirror classMirror) {
  bool helper(String name) {
    Symbol nameSymbol = new Symbol(name);
    bool predicate(ApiReflectCapability capability) {
      if (capability == invokingCapability ||
          capability == instanceInvokeCapability) {
        // We have the convention that declarations cover all members when
        // invocation has been requested for all members.
        return true;
      } else if (capability is InstanceInvokeCapability) {
        // We have the convention that declarations covers the members for which
        // there is a specific request for invocation support.
        return new RegExp(capability.namePattern).hasMatch(name);
      } else if (capability is InstanceInvokeMetaCapability) {
        dm.DeclarationMirror declarationMirror =
            classMirror.declarations[nameSymbol];
        return declarationMirror != null &&
            metadataSupported(declarationMirror.metadata, capability);
      } else {
        return false;
      }
    }

    return reflectable.hasCapability(predicate);
  }

  return _checkWithGetter(reflectable, name, helper);
}

/// Returns true if [reflectable] supports types.
bool reflectableSupportsType(ReflectableImpl reflectable) {
  bool predicate(ApiReflectCapability capability) =>
      capability is TypeCapability;
  return reflectable.hasCapability(predicate);
}

/// Used to delay the extraction of metadata that may be needed.
typedef List<dm.InstanceMirror> MetadataEvaluator(String name);

/// Returns true if [predicate] returns true on the given [name] and [metadata];
/// otherwise, if [reflectable] allows for corresponding setter quantification
/// then it returns the result of calling [predicate] on the corresponding
/// getter name via `getMetadata(..)`. In other words, it makes an attempt to
/// get "yes" from [predicate] directly and then, if allowed, via the
/// corresponding getter.
bool _checkWithGetterUsingMetadata(
    ReflectableImpl reflectable,
    String name,
    bool predicate(String name, List<dm.InstanceMirror> metadata),
    List<dm.InstanceMirror> metadata,
    MetadataEvaluator getMetadata) {
  if (predicate(name, metadata)) return true;
  if (getMetadata == null ||
      !_isSetterName(name) ||
      !impliesCorrespondingSetter(reflectable.capabilities)) {
    return false;
  }
  String getterName = _setterNameToGetterName(name);
  return predicate(getterName, getMetadata(getterName));
}

/// Returns true iff [reflectable] supports static invoke of [name].
/// The metadata of the declaration of [name] is provided as [metadata], and
/// the metadata of the declaration of the corresponding getter is provided
/// via [getMetadata]; the latter must be [null] in the cases where [name]
/// does not declare a setter or it does declare a setter but there is no
/// corresponding getter declaration.
bool reflectableSupportsStaticInvoke(
    ReflectableImpl reflectable, String name, List<dm.InstanceMirror> metadata,
    [MetadataEvaluator getMetadata]) {
  bool helper(String name, List<dm.InstanceMirror> metadata) {
    bool predicate(ApiReflectCapability capability) {
      if (capability == staticInvokeCapability) {
        return true;
      } else if (capability is StaticInvokeCapability) {
        return new RegExp(capability.namePattern).hasMatch(name);
      }
      if (capability is StaticInvokeMetaCapability) {
        return metadataSupported(metadata, capability);
      }
      return false;
    }
    return reflectable.hasCapability(predicate);
  }

  return _checkWithGetterUsingMetadata(
      reflectable, name, helper, metadata, getMetadata);
}

/// Returns true iff [reflectable] covers [libraryMirror], i.e., iff the
/// library modeled by [libraryMirror] contains a `library` directive that
/// carries [reflectable] as metadata, or there exists an import of
/// 'package:reflectable/reflectable.dart' in the program that carries a
/// global quantifier that connects [reflectable] to that library.
bool _supportsLibrary(
    ReflectableImpl reflectable, dm.LibraryMirror libraryMirror) {
  // TODO(eernst) implement: Apparently, we cannot check whether the library
  // modeled by [libraryMirror] even has a `library` directive, much less
  // whether that directive does or does not carry a particular object as
  // metadata. If that is true then there is no way we can detect whether
  // [reflector] covers [libraryMirror] due to metadata on the directive.
  // To avoid creating too many spurious [NoSuchCapabilityError]s, we let it
  // pass as "OK" for now.
  return true;
}

/// Cache for the status of each library relative to each reflector: Does
/// this reflector cover that library?
final Map<Reflectable,
        Map<dm.LibraryMirror, bool>> _reflectableLibraryCoverage =
    <Reflectable, Map<dm.LibraryMirror, bool>>{};

/// Returns true iff [reflectable] supports top-level invoke of [name].
/// The metadata of the declaration of [name] is provided as [metadata], and
/// the metadata of the declaration of the corresponding getter is provided
/// via [getMetadata]; the latter must be [null] in the cases where [name]
/// does not declare a setter or it does declare a setter but there is no
/// corresponding getter declaration.
bool reflectableSupportsTopLevelInvoke(
    ReflectableImpl reflectable,
    dm.LibraryMirror libraryMirror,
    String name,
    List<dm.InstanceMirror> metadata,
    MetadataEvaluator getMetadata) {
  // We don't have to check for `libraryCapability` because this method is only
  // ever called from the methods of a `LibraryMirrorImpl` and the existence of
  // an instance of a `LibraryMirrorImpl` implies the `libraryMirrorCapability`.
  // Also, we do not have to check for the capability as given to a subtype
  // because a library is never a subtype of anything.
  bool helper(String name, List<dm.InstanceMirror> metadata) {
    bool predicate(ApiReflectCapability capability) {
      return capability == topLevelInvokeCapability ||
          (capability is TopLevelInvokeCapability &&
              new RegExp(capability.namePattern).hasMatch(name)) ||
          (capability is TopLevelInvokeMetaCapability &&
              metadataSupported(metadata, capability));
    }
    return reflectable.hasCapability(predicate);
  }

  if (_reflectableLibraryCoverage[reflectable] == null) {
    // Initialize the coverage entry for [reflectable].
    _reflectableLibraryCoverage[reflectable] = <dm.LibraryMirror, bool>{};
  }
  Map<dm.LibraryMirror, bool> _libraryCoverage =
      _reflectableLibraryCoverage[reflectable];
  if (_libraryCoverage[libraryMirror] == null) {
    // Find the coverage value for [libraryMirror] in the coverage entry for
    // [reflectable].
    _libraryCoverage[libraryMirror] =
        _supportsLibrary(reflectable, libraryMirror);
  }
  if (!_libraryCoverage[libraryMirror]) return false;

  return _checkWithGetterUsingMetadata(
      reflectable, name, helper, metadata, getMetadata);
}

/// Returns true iff [reflectable] supports invoke of [name].
bool reflectableSupportsConstructorInvoke(
    ReflectableImpl reflectable, dm.ClassMirror classMirror, String name) {
  bool predicate(ApiReflectCapability capability) {
    if (capability == newInstanceCapability) {
      return true;
    } else if (capability is NewInstanceCapability) {
      return new RegExp(capability.namePattern).hasMatch(name);
    } else if (capability is NewInstanceMetaCapability) {
      dm.MethodMirror constructorMirror = classMirror.declarations.values
          .firstWhere((dm.DeclarationMirror declarationMirror) {
        Symbol nameSymbol = new Symbol(name);
        return declarationMirror is dm.MethodMirror &&
            declarationMirror.isConstructor &&
            declarationMirror.constructorName == nameSymbol;
      });
      if (constructorMirror == null ||
          !constructorMirror.isConstructor) return false;
      return metadataSupported(constructorMirror.metadata, capability);
    }
    return false;
  }

  return reflectable.hasCapability(predicate);
}

bool reflectableSupportsDeclarations(Reflectable reflectable) {
  bool predicate(ApiReflectCapability capability) =>
      capability is DeclarationsCapability;
  return reflectable.hasCapability(predicate);
}

bool reflectableSupportsTypeRelations(Reflectable reflectable) {
  bool predicate(ApiReflectCapability capability) =>
      capability is TypeRelationsCapability;
  return reflectable.hasCapability(predicate);
}

/// Returns [name] with final "=" removed.
/// If the it does not have a final "=" it is returned as is.
String _setterToGetter(String name) {
  return _isSetterName(name) ? _setterNameToGetterName(name) : name;
}

/// Returns [getterName] with a final "=" added.
/// If [getter] already ends with "=" an error is thrown.
String _getterToSetter(String getterName) {
  if (_isSetterName(getterName)) {
    throw new ArgumentError(
        "$getterName is a setter name (ends with `=`) already.");
  }
  return '$getterName=';
}

bool _supportsType(List<ReflectCapability> capabilities) {
  return capabilities
      .any((ReflectCapability capability) => capability is TypeCapability);
}

bool _supportsMetadata(List<ReflectCapability> capabilities) {
  return capabilities
      .any((ReflectCapability capability) => capability is MetadataCapability);
}

abstract class _ObjectMirrorImplMixin implements rm.ObjectMirror {
  ReflectableImpl get _reflectable;
}

MetadataEvaluator _getMetadataLibraryFactory(dm.LibraryMirror libraryMirror) {
  List<dm.InstanceMirror> helper(String name) {
    dm.DeclarationMirror declaration =
        libraryMirror.declarations[new Symbol(name)];
    return declaration?.metadata;
  }
  return helper;
}

class _LibraryMirrorImpl extends _DeclarationMirrorImpl
    with _ObjectMirrorImplMixin
    implements rm.LibraryMirror {
  dm.LibraryMirror get _libraryMirror => _declarationMirror;

  _LibraryMirrorImpl(dm.LibraryMirror m, ReflectableImpl reflectable)
      : super(m, reflectable) {}

  @override
  Uri get uri => _libraryMirror.uri;

  @override
  Map<String, rm.DeclarationMirror> get declarations {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get declarations without capability");
    }
    Map<String, rm.DeclarationMirror> result = <String, rm.DeclarationMirror>{};
    _libraryMirror.declarations
        .forEach((Symbol nameSymbol, dm.DeclarationMirror declarationMirror) {
      String name = dm.MirrorSystem.getName(nameSymbol);
      if (declarationMirror is dm.MethodMirror) {
        if (reflectableSupportsTopLevelInvoke(
            _reflectable,
            _libraryMirror,
            name,
            declarationMirror.metadata,
            _getMetadataLibraryFactory(_libraryMirror))) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else if (declarationMirror is dm.VariableMirror) {
        // For variableMirrors we test both for support of the name and the
        // derived setter name.
        if (reflectableSupportsTopLevelInvoke(_reflectable, _libraryMirror,
                name, declarationMirror.metadata, null) ||
            reflectableSupportsTopLevelInvoke(_reflectable, _libraryMirror,
                _getterToSetter(name), declarationMirror.metadata, null)) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else {
        // The additional subtypes of [dm.DeclarationMirror] are
        // [dm.LibraryMirror]: doees not occur inside another library,
        // [dm.ParameterMirror]: not declared in a library, [dm.TypeMirror],
        // and the 4 subtypes thereof; [dm.ClassMirror]: processed here,
        // [dm.TypedefMirror]: not yet supported, [dm.FunctionTypeMirror]: not
        // yet supported, and [dm.TypeVariableMirror]: not yet supported.
        if (declarationMirror is dm.ClassMirror) {
          if (_reflectable._supportedClasses.contains(declarationMirror)) {
            result[name] =
                wrapDeclarationMirror(declarationMirror, _reflectable);
          }
        } else {
          // TODO(eernst) implement: currently ignoring the unsupported cases.
        }
      }
    });
    return result;
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    dm.DeclarationMirror declaration =
        _libraryMirror.declarations[new Symbol(memberName)];
    if (!reflectableSupportsTopLevelInvoke(
        _reflectable,
        _libraryMirror,
        memberName,
        declaration.metadata,
        _getMetadataLibraryFactory(_libraryMirror))) {
      throw new NoSuchInvokeCapabilityError(
          _receiver, memberName, positionalArguments, namedArguments);
    }
    return _libraryMirror
        .invoke(new Symbol(memberName), positionalArguments, namedArguments)
        .reflectee;
  }

  @override
  Object invokeGetter(String getterName) {
    if (!reflectableSupportsTopLevelInvoke(
        _reflectable,
        _libraryMirror,
        getterName,
        _libraryMirror.declarations[new Symbol(getterName)].metadata,
        null)) {
      throw new NoSuchInvokeCapabilityError(_receiver, getterName, [], null);
    }
    Symbol getterNameSymbol = new Symbol(getterName);
    return _libraryMirror.getField(getterNameSymbol).reflectee;
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    dm.DeclarationMirror declaration =
        _libraryMirror.declarations[new Symbol(setterName)];
    String getterName = _setterToGetter(setterName);
    Symbol getterNameSymbol = new Symbol(getterName);
    if (!reflectableSupportsTopLevelInvoke(
        _reflectable,
        _libraryMirror,
        setterName,
        declaration.metadata,
        _getMetadataLibraryFactory(_libraryMirror))) {
      throw new NoSuchInvokeCapabilityError(
          _receiver, setterName, [value], null);
    }
    return _libraryMirror.setField(getterNameSymbol, value).reflectee;
  }

  @override
  bool operator ==(other) {
    return other is _LibraryMirrorImpl
        ? _libraryMirror == other._libraryMirror
        : false;
  }

  @override
  int get hashCode => _libraryMirror.hashCode;

  @override
  List<rm.LibraryDependencyMirror> get libraryDependencies {
    return _libraryMirror.libraryDependencies
        .map((dep) => new _LibraryDependencyMirrorImpl(dep, _reflectable))
        .toList();
  }

  get _receiver => "top-level";

  @override
  String toString() {
    return "_LibraryMirrorImpl('${_libraryMirror.toString()}')";
  }
}

class _LibraryDependencyMirrorImpl implements rm.LibraryDependencyMirror {
  final dm.LibraryDependencyMirror _libraryDependencyMirror;
  final ReflectableImpl _reflectable;

  _LibraryDependencyMirrorImpl(
      this._libraryDependencyMirror, this._reflectable);

  @override
  bool get isImport => _libraryDependencyMirror.isImport;

  @override
  bool get isExport => _libraryDependencyMirror.isExport;

  @override
  rm.LibraryMirror get sourceLibrary {
    return new _LibraryMirrorImpl(
        _libraryDependencyMirror.sourceLibrary, _reflectable);
  }

  @override
  rm.LibraryMirror get targetLibrary {
    return new _LibraryMirrorImpl(
        _libraryDependencyMirror.targetLibrary, _reflectable);
  }

  @override
  String get prefix => dm.MirrorSystem.getName(_libraryDependencyMirror.prefix);

  @override
  List<Object> get metadata {
    if (!_supportsMetadata(_reflectable.capabilities)) {
      throw new NoSuchCapabilityError(
          "Attempt to get metadata without `MetadataCapability`.");
    }
    return _libraryDependencyMirror.metadata.map((m) => m.reflectee).toList();
  }

  @override
  rm.SourceLocation get location {
    return new _SourceLocationImpl(_libraryDependencyMirror.location);
  }

  @override
  List<rm.CombinatorMirror> get combinators {
    return _libraryDependencyMirror.combinators
        .map(wrapCombinatorMirror)
        .toList();
  }

  @override
  bool get isDeferred => _libraryDependencyMirror.isDeferred;

  @override
  String toString() {
    return "_LibraryDependencyMirrorImpl('${_libraryDependencyMirror}')";
  }
}

class _InstanceMirrorImpl extends _ObjectMirrorImplMixin
    implements rm.InstanceMirror {
  final dm.InstanceMirror _instanceMirror;
  final ReflectableImpl _reflectable;

  _InstanceMirrorImpl(this._instanceMirror, this._reflectable);

  @override
  rm.TypeMirror get type {
    if (!reflectableSupportsType(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get `type` without capability");
    }
    return wrapTypeMirror(_instanceMirror.type, _reflectable);
  }

  @override
  bool get hasReflectee => _instanceMirror.hasReflectee;

  @override
  get reflectee => _instanceMirror.reflectee;

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, memberName, _instanceMirror.type)) {
      Symbol memberNameSymbol = new Symbol(memberName);
      return _instanceMirror
          .invoke(memberNameSymbol, positionalArguments, namedArguments)
          .reflectee;
    }
    throw new NoSuchInvokeCapabilityError(
        _receiver, memberName, positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String fieldName) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, fieldName, _instanceMirror.type)) {
      Symbol fieldNameSymbol = new Symbol(fieldName);
      return _instanceMirror.getField(fieldNameSymbol).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, fieldName, [], null);
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, setterName, _instanceMirror.type)) {
      String getterName = _setterToGetter(setterName);
      Symbol getterNameSymbol = new Symbol(getterName);
      return _instanceMirror.setField(getterNameSymbol, value).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, setterName, [value], null);
  }

  @override
  bool operator ==(other) => other is _InstanceMirrorImpl
      ? _instanceMirror == other._instanceMirror
      : false;

  @override
  int get hashCode => _instanceMirror.hashCode;

  @override
  delegate(Invocation invocation) => _instanceMirror.delegate(invocation);

  get _receiver => _instanceMirror.reflectee;

  @override
  String toString() => "_InstanceMirrorImpl('${_instanceMirror}')";
}

MetadataEvaluator _getMetadataClassFactory(dm.ClassMirror classMirror) {
  List<dm.InstanceMirror> helper(String name) {
    dm.DeclarationMirror declaration =
        classMirror.declarations[new Symbol(name)];
    return declaration?.metadata;
  }
  return helper;
}

class ClassMirrorImpl extends _TypeMirrorImpl
    with _ObjectMirrorImplMixin
    implements rm.ClassMirror {
  dm.ClassMirror get _classMirror => _declarationMirror;

  ClassMirrorImpl(dm.ClassMirror classMirror, ReflectableImpl reflectable)
      : super(classMirror, reflectable) {}

  @override
  bool get hasDynamicReflectedType => _classMirror.typeVariables.isEmpty;

  @override
  Type get dynamicReflectedType {
    if (!hasDynamicReflectedType) {
      /// We cannot hope to implement this based on 'dart:mirrors' for generic
      /// classes, because there is no support for obtaining one instantiation
      /// of a generic class based on a different one (we cannot obtain
      /// `List<dynamic>` from `List<int>` or any such thing); and when
      /// `isOriginalDeclaration` is true we do not have a `reflectedType` at
      /// all.
      throw new UnsupportedError(
          "Attempt to get dynamicReflectedType on $_classMirror");
    }
    return reflectedType;
  }

  @override
  bool get hasBestEffortReflectedType =>
      hasReflectedType || hasDynamicReflectedType;

  @override
  Type get bestEffortReflectedType =>
      hasReflectedType ? reflectedType : dynamicReflectedType;

  @override
  List<rm.TypeVariableMirror> get typeVariables {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get typeVariables without `declarationsCapability`");
    }
    return _classMirror.typeVariables.map((v) {
      return new _TypeVariableMirrorImpl(v, _reflectable);
    }).toList();
  }

  @override
  List<rm.TypeMirror> get typeArguments {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get typeArguments without `declarationsCapability`");
    }
    return _classMirror.typeArguments.map((a) {
      return wrapTypeMirror(a, _reflectable);
    }).toList();
  }

  @override
  rm.ClassMirror get superclass {
    if (!reflectableSupportsTypeRelations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get superinterfaces without `typeRelationsCapability`");
    }
    dm.ClassMirror sup = _classMirror.superclass;
    if (sup == null) return null; // For `Object`, do as `dm`.
    return wrapClassMirrorIfSupported(sup, _reflectable);
  }

  @override
  List<rm.ClassMirror> get superinterfaces {
    if (!reflectableSupportsTypeRelations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get superinterfaces without `typeRelationsCapability`");
    }
    List<dm.ClassMirror> superinterfaces = _classMirror.superinterfaces;
    return superinterfaces
        .where((dm.ClassMirror superinterface) => (_reflectable
            ._supportedClasses.contains(superinterface.originalDeclaration)))
        .map((dm.TypeMirror superinterface) {
      return wrapTypeMirror(superinterface, _reflectable);
    }).toList();
  }

  @override
  bool get isAbstract => _classMirror.isAbstract;

  @override
  bool get isEnum => _classMirror.isEnum;

  @override
  Map<String, rm.DeclarationMirror> get declarations {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get declarations without capability");
    }
    // TODO(sigurdm) future: Possibly cache this.
    Map<String, rm.DeclarationMirror> result = <String, rm.DeclarationMirror>{};
    _classMirror.declarations
        .forEach((Symbol nameSymbol, dm.DeclarationMirror declarationMirror) {
      String name = dm.MirrorSystem.getName(nameSymbol);
      if (declarationMirror is dm.MethodMirror) {
        if (_isMixin && declarationMirror.isStatic) return;
        bool included = false;
        if (declarationMirror.isConstructor) {
          // Factory constructors are static, others not, so this decision
          // is made independently of `isStatic`.
          included = included ||
              reflectableSupportsConstructorInvoke(
                  _reflectable, _classMirror, name);
        } else {
          // `declarationMirror` is a non-constructor.
          if (declarationMirror.isStatic) {
            // `declarationMirror` is a static method/getter/setter.
            included = included ||
                reflectableSupportsStaticInvoke(
                    _reflectable,
                    name,
                    declarationMirror.metadata,
                    _getMetadataClassFactory(_classMirror));
          } else {
            // `declarationMirror` is an instance method/getter/setter.
            included = included ||
                reflectableSupportsDeclaration(
                    _reflectable, name, _classMirror);
          }
        }
        if (included) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else if (declarationMirror is dm.VariableMirror) {
        if (_isMixin && declarationMirror.isStatic) return;
        // For variableMirrors we test both for support of the name and the
        // derived setter name.
        bool included = false;
        if (declarationMirror.isStatic) {
          included = included ||
              reflectableSupportsStaticInvoke(
                  _reflectable, name, declarationMirror.metadata) ||
              reflectableSupportsStaticInvoke(_reflectable,
                  _getterToSetter(name), declarationMirror.metadata);
        } else {
          included = included ||
              reflectableSupportsDeclaration(
                  _reflectable, name, _classMirror) ||
              reflectableSupportsDeclaration(
                  _reflectable, _getterToSetter(name), _classMirror);
        }
        if (included) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else {
        // TODO(sigurdm) implement: Consider capabilities for other
        // declarations; the additional subtypes of DeclarationMirror are
        // LibraryMirror (global), TypeMirror and the 4 subtypes thereof,
        // and ParameterMirror (declared in a method, not class), so the
        // only case that needs further clarification is TypeVariableMirror.
        // For now we just let it through.
        result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
      }
    });
    return result;
  }

  @override
  Map<String, rm.MethodMirror> get instanceMembers {
    // TODO(sigurdm) implement: Only expose members that are allowed
    // by the capabilities of the reflectable.
    Map<Symbol, dm.MethodMirror> members = _classMirror.instanceMembers;
    return new Map<String, rm.MethodMirror>.fromIterable(members.keys,
        key: (k) => dm.MirrorSystem.getName(k),
        value: (v) => new MethodMirrorImpl(members[v], _reflectable));
  }

  @override
  Map<String, rm.MethodMirror> get staticMembers {
    // TODO(sigurdm) implement: Only expose members that are allowed by the
    // capabilities of the reflectable.
    Map<Symbol, dm.MethodMirror> members = _classMirror.staticMembers;
    return new Map<String, rm.MethodMirror>.fromIterable(members.keys,
        key: (k) => dm.MirrorSystem.getName(k),
        value: (v) => new MethodMirrorImpl(members[v], _reflectable));
  }

  @override
  rm.ClassMirror get mixin {
    return wrapClassMirrorIfSupported(_classMirror.mixin, _reflectable);
  }

  @override
  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (!reflectableSupportsConstructorInvoke(
        _reflectable, _classMirror, constructorName)) {
      throw new NoSuchInvokeCapabilityError(
          _classMirror, constructorName, positionalArguments, namedArguments);
    }
    Symbol constructorNameSymbol = new Symbol(constructorName);
    return _classMirror
        .newInstance(constructorNameSymbol, positionalArguments, namedArguments)
        .reflectee;
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    dm.DeclarationMirror declaration =
        _classMirror.declarations[new Symbol(memberName)];
    List<Object> metadata = declaration == null ? null : declaration.metadata;
    if (reflectableSupportsStaticInvoke(_reflectable, memberName, metadata,
        _getMetadataClassFactory(_classMirror))) {
      Symbol memberNameSymbol = new Symbol(memberName);
      return _classMirror
          .invoke(memberNameSymbol, positionalArguments, namedArguments)
          .reflectee;
    }
    throw new NoSuchInvokeCapabilityError(
        _receiver, memberName, positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String name) {
    if (reflectableSupportsStaticInvoke(_reflectable, name,
        _classMirror.declarations[new Symbol(name)]?.metadata)) {
      Symbol getterNameSymbol = new Symbol(name);
      return _classMirror.getField(getterNameSymbol).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, name, [], null);
  }

  @override
  Object invokeSetter(String name, Object value) {
    List<dm.InstanceMirror> metadata =
        _classMirror.declarations[new Symbol(name)]?.metadata;
    if (reflectableSupportsStaticInvoke(
        _reflectable, name, metadata, _getMetadataClassFactory(_classMirror))) {
      String getterName = _setterToGetter(name);
      Symbol getterNameSymbol = new Symbol(getterName);
      return _classMirror.setField(getterNameSymbol, value).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, name, [value], null);
  }

  @override
  bool operator ==(other) {
    return other is ClassMirrorImpl
        ? _classMirror == other._classMirror
        : false;
  }

  @override
  int get hashCode => _classMirror.hashCode;

  @override
  bool isSubclassOf(rm.ClassMirror other) {
    return _classMirror.isSubclassOf(unwrapClassMirror(other));
  }

  get _receiver => _classMirror.reflectedType;

  @override
  String toString() => "ClassMirrorImpl('${_classMirror}')";

  @override
  Function invoker(String memberName) {
    Symbol memberNameSymbol = new Symbol(memberName);
    Function helper(Object o) {
      dm.InstanceMirror receiverMirror = dm.reflect(o);
      dm.InstanceMirror memberMirror =
          receiverMirror.getField(memberNameSymbol);
      return memberMirror.reflectee;
    }
    return helper;
  }

  @override
  rm.LibraryMirror get owner {
    if (_reflectable._supportsLibraries) return super.owner;
    throw new NoSuchCapabilityError(
        "Trying to get owner of class '$qualifiedName' "
        "without 'libraryCapability'");
  }

  bool get _isMixin => _classMirror.mixin != _classMirror;
}

class _FunctionTypeMirrorImpl extends ClassMirrorImpl
    implements rm.FunctionTypeMirror {
  dm.FunctionTypeMirror get _functionTypeMirror => _classMirror;

  _FunctionTypeMirrorImpl(
      dm.FunctionTypeMirror functionTypeMirror, ReflectableImpl reflectable)
      : super(functionTypeMirror, reflectable);

  @override
  bool get hasDynamicReflectedType => false;

  @override
  Type get dynamicReflectedType => throw unimplementedError(
      "Attempt to get dynamicReflectedType on a function type mirror");

  @override
  rm.MethodMirror get callMethod {
    return new MethodMirrorImpl(_functionTypeMirror.callMethod, _reflectable);
  }

  @override
  List<rm.ParameterMirror> get parameters {
    return _functionTypeMirror.parameters
        .map((dm.ParameterMirror parameterMirror) {
      return new _ParameterMirrorImpl(parameterMirror, _reflectable);
    });
  }

  @override
  rm.TypeMirror get returnType {
    // TODO(eernst) clarify: Is it really true that we cannot detect the
    // type void other than looking at its name?
    if (_functionTypeMirror.returnType.simpleName == "void") {
      return new _VoidMirrorImpl();
    }
    return wrapTypeMirror(_functionTypeMirror.returnType, _reflectable);
  }
}

abstract class _DeclarationMirrorImpl implements rm.DeclarationMirror {
  final dm.DeclarationMirror _declarationMirror;
  final ReflectableImpl _reflectable;

  _DeclarationMirrorImpl(this._declarationMirror, this._reflectable);

  @override
  String get simpleName =>
      dm.MirrorSystem.getName(_declarationMirror.simpleName);

  @override
  String get qualifiedName =>
      dm.MirrorSystem.getName(_declarationMirror.qualifiedName);

  @override
  rm.DeclarationMirror get owner {
    return wrapDeclarationMirror(_declarationMirror.owner, _reflectable);
  }

  @override
  bool get isPrivate => _declarationMirror.isPrivate;

  @override
  bool get isTopLevel => _declarationMirror.isTopLevel;

  @override
  List<Object> get metadata {
    if (!_supportsMetadata(_reflectable.capabilities)) {
      throw new NoSuchCapabilityError(
          "Attempt to get metadata without `MetadataCapability`.");
    }
    return _declarationMirror.metadata.map((m) => m.reflectee).toList();
  }

  @override
  rm.SourceLocation get location {
    return new _SourceLocationImpl(_declarationMirror.location);
  }

  @override
  String toString() {
    return "_DeclarationMirrorImpl('${_declarationMirror}')";
  }
}

class MethodMirrorImpl extends _DeclarationMirrorImpl
    implements rm.MethodMirror {
  dm.MethodMirror get _methodMirror => _declarationMirror;

  MethodMirrorImpl(dm.MethodMirror mm, ReflectableImpl reflectable)
      : super(mm, reflectable);

  @override
  rm.TypeMirror get returnType {
    // TODO(eernst) clarify: Is there really no other way to detect
    // the `void` type than looking at its name?
    if (_methodMirror.returnType.simpleName == const Symbol("void")) {
      return new _VoidMirrorImpl();
    }
    return wrapTypeMirror(_methodMirror.returnType, _reflectable);
  }

  @override
  bool get hasReflectedReturnType {
    if (impliesReflectedType(_reflectable.capabilities)) {
      return _methodMirror.returnType.hasReflectedType;
    }
    throw new NoSuchCapabilityError(
        "Attempt to evaluate hasReflectedReturnType without capability");
  }

  @override
  Type get reflectedReturnType {
    if (impliesReflectedType(_reflectable.capabilities)) {
      return _methodMirror.returnType.reflectedType;
    }
    throw new NoSuchCapabilityError(
        "Attempt to get reflectedReturnType without capability");
  }

  @override
  bool get hasDynamicReflectedReturnType {
    if (impliesReflectedType(_reflectable.capabilities)) {
      return _methodMirror.returnType.typeVariables.isEmpty &&
          _methodMirror.returnType.hasReflectedType;
    }
    throw new NoSuchCapabilityError("Attempt to get "
        "hasDynamicReflectedReturnType without `reflectedTypeCapability`");
  }

  @override
  Type get dynamicReflectedReturnType {
    if (impliesReflectedType(_reflectable.capabilities)) {
      if (_methodMirror.returnType.typeVariables.isEmpty) {
        return _methodMirror.returnType.reflectedType;
      } else {
        // The value returned by `hasDynamicReflectedReturnType` is false, so
        // even though this is unimplemented and may be implemented if we get
        // the required runtime support, it is currently an `UnsupportedError`.
        throw new UnsupportedError("Attempt to obtain the "
            "dynamicReflectedReturnType of a generic type "
            "${_methodMirror.returnType}");
      }
    }
    throw new NoSuchCapabilityError("Attempt to get dynamicReflectedReturnType "
        "without `reflectedTypeCapability`");
  }

  @override
  String get source => _methodMirror.source;

  @override
  List<rm.ParameterMirror> get parameters {
    return _methodMirror.parameters.map((p) {
      return new _ParameterMirrorImpl(p, _reflectable);
    }).toList();
  }

  @override
  bool get isStatic => _methodMirror.isStatic;

  @override
  bool get isAbstract => _methodMirror.isAbstract;

  @override
  bool get isSynthetic => _methodMirror.isSynthetic;

  @override
  bool get isRegularMethod => _methodMirror.isRegularMethod;

  @override
  bool get isOperator => _methodMirror.isOperator;

  @override
  bool get isGetter => _methodMirror.isGetter;

  @override
  bool get isSetter => _methodMirror.isSetter;

  @override
  bool get isConstructor => _methodMirror.isConstructor;

  @override
  String get constructorName =>
      dm.MirrorSystem.getName(_methodMirror.constructorName);

  @override
  bool get isConstConstructor => _methodMirror.isConstConstructor;

  @override
  bool get isGenerativeConstructor => _methodMirror.isGenerativeConstructor;

  @override
  bool get isRedirectingConstructor => _methodMirror.isRedirectingConstructor;

  @override
  bool get isFactoryConstructor => _methodMirror.isFactoryConstructor;

  @override
  bool operator ==(other) {
    return other is MethodMirrorImpl
        ? _methodMirror == other._methodMirror
        : false;
  }

  @override
  int get hashCode => _methodMirror.hashCode;

  @override
  String toString() => "_MethodMirrorImpl('${_methodMirror}')";
}

class _ClosureMirrorImpl extends _InstanceMirrorImpl
    implements rm.ClosureMirror {
  dm.ClosureMirror get _closureMirror => _instanceMirror;

  _ClosureMirrorImpl(
      dm.ClosureMirror closureMirror, ReflectableImpl reflectable)
      : super(closureMirror, reflectable);

  @override
  Object apply(List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    return _closureMirror.apply(positionalArguments, namedArguments).reflectee;
  }

  @override
  rm.MethodMirror get function {
    return new MethodMirrorImpl(_closureMirror.function, _reflectable);
  }

  @override
  String toString() => "_ClosureMirrorImpl('${_closureMirror}')";
}

class VariableMirrorImpl extends _DeclarationMirrorImpl
    implements rm.VariableMirror {
  dm.VariableMirror get _variableMirror => _declarationMirror;

  VariableMirrorImpl(dm.VariableMirror vm, ReflectableImpl reflectable)
      : super(vm, reflectable);

  @override
  rm.TypeMirror get type {
    if (_supportsType(_reflectable.capabilities)) {
      return wrapTypeMirror(_variableMirror.type, _reflectable);
    }
    throw new NoSuchCapabilityError(
        "Attempt to get type without `TypeCapability`");
  }

  @override
  bool get hasReflectedType =>
      impliesReflectedType(_reflectable.capabilities) &&
          _variableMirror.type.hasReflectedType;

  @override
  Type get reflectedType {
    if (impliesReflectedType(_reflectable.capabilities)) {
      return _variableMirror.type.reflectedType;
    }
    throw new NoSuchCapabilityError(
        "Attempt to get reflectedType without `reflectedTypeCapability`");
  }

  @override
  bool get hasDynamicReflectedType =>
      impliesReflectedType(_reflectable.capabilities) &&
          _variableMirror.type.typeVariables.isEmpty &&
          _variableMirror.type.hasReflectedType;

  @override
  Type get dynamicReflectedType {
    if (impliesReflectedType(_reflectable.capabilities)) {
      if (_variableMirror.type.typeVariables.isEmpty) {
        return _variableMirror.type.reflectedType;
      } else {
        // The value returned by `hasDynamicReflectedReturnType` is false, so
        // even though this is unimplemented and may be implemented if we get
        // the required runtime support, it is currently an `UnsupportedError`.
        throw new UnsupportedError("Attempt to obtain the dynamicReflectedType "
            "of a generic type ${_variableMirror.type}");
      }
    }
    throw new NoSuchCapabilityError("Attempt to get dynamicReflectedType "
        "without `reflectedTypeCapability`");
  }

  @override
  bool get isStatic => _variableMirror.isStatic;

  @override
  bool get isFinal => _variableMirror.isFinal;

  @override
  bool get isConst => _variableMirror.isConst;

  @override
  bool operator ==(other) => other is VariableMirrorImpl
      ? _variableMirror == other._variableMirror
      : false;

  @override
  int get hashCode => _variableMirror.hashCode;

  @override
  String toString() => "VariableMirrorImpl('${_variableMirror}')";
}

class _ParameterMirrorImpl extends VariableMirrorImpl
    implements rm.ParameterMirror {
  dm.ParameterMirror get _parameterMirror => _declarationMirror;

  _ParameterMirrorImpl(dm.ParameterMirror pm, ReflectableImpl reflectable)
      : super(pm, reflectable);

  @override
  bool get isOptional => _parameterMirror.isOptional;

  @override
  bool get isNamed => _parameterMirror.isNamed;

  @override
  bool get hasDefaultValue => _parameterMirror.hasDefaultValue;

  @override
  Object get defaultValue {
    if (_parameterMirror.hasDefaultValue) {
      return _parameterMirror.defaultValue.reflectee;
    }
    return null;
  }

  @override
  bool operator ==(other) => other is _ParameterMirrorImpl
      ? _parameterMirror == other._parameterMirror
      : false;

  @override
  int get hashCode => _parameterMirror.hashCode;

  @override
  String toString() => "_ParameterMirrorImpl('${_parameterMirror}')";
}

abstract class _TypeMirrorImpl extends _DeclarationMirrorImpl
    implements rm.TypeMirror {
  dm.TypeMirror get _typeMirror => _declarationMirror;

  _TypeMirrorImpl(dm.TypeMirror typeMirror, ReflectableImpl reflectable)
      : super(typeMirror, reflectable);

  @override
  bool get hasReflectedType => _typeMirror.hasReflectedType;

  @override
  bool isAssignableTo(rm.TypeMirror other) {
    return _typeMirror.isAssignableTo(unwrapTypeMirror(other));
  }

  @override
  bool get isOriginalDeclaration => _typeMirror.isOriginalDeclaration;

  @override
  bool isSubtypeOf(rm.TypeMirror other) {
    return _typeMirror.isSubtypeOf(unwrapTypeMirror(other));
  }

  @override
  rm.TypeMirror get originalDeclaration {
    return wrapTypeMirror(_typeMirror.originalDeclaration, _reflectable);
  }

  @override
  Type get reflectedType => _typeMirror.reflectedType;

  @override
  List<rm.TypeMirror> get typeArguments {
    return _typeMirror.typeArguments.map((dm.TypeMirror typeArgument) {
      return wrapTypeMirror(typeArgument, _reflectable);
    }).toList();
  }

  @override
  List<rm.TypeVariableMirror> get typeVariables {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get typeVariables without `declarationsCapability`");
    }
    return _typeMirror.typeVariables
        .map((dm.TypeVariableMirror typeVariableMirror) {
      return new _TypeVariableMirrorImpl(typeVariableMirror, _reflectable);
    }).toList();
  }
}

class _TypeVariableMirrorImpl extends _TypeMirrorImpl
    implements rm.TypeVariableMirror {
  dm.TypeVariableMirror get _typeVariableMirror => _typeMirror;

  _TypeVariableMirrorImpl(
      dm.TypeVariableMirror typeVariableMirror, ReflectableImpl reflectable)
      : super(typeVariableMirror, reflectable);

  @override
  bool get isStatic => _typeVariableMirror.isStatic;

  @override
  operator ==(other) {
    return other is _TypeVariableMirrorImpl &&
        other._typeVariableMirror == _typeVariableMirror;
  }

  @override
  int get hashCode => _typeVariableMirror.hashCode;

  @override
  rm.TypeMirror get upperBound {
    return wrapTypeMirror(_typeVariableMirror.upperBound, _reflectable);
  }

  @override
  String toString() {
    return "_TypeVariableMirrorImpl('${_typeVariableMirror}')";
  }
}

class _TypedefMirrorImpl extends _TypeMirrorImpl implements rm.TypedefMirror {
  dm.TypedefMirror get _typedefMirror => _typeMirror;

  _TypedefMirrorImpl(
      dm.TypedefMirror typedefMirror, ReflectableImpl reflectable)
      : super(typedefMirror, reflectable);

  @override
  rm.FunctionTypeMirror get referent {
    return new _FunctionTypeMirrorImpl(_typedefMirror.referent, _reflectable);
  }

  @override operator ==(other) {
    return other is _TypedefMirrorImpl &&
        other._typedefMirror == _typedefMirror;
  }

  @override
  int get hashCode => _typedefMirror.hashCode;

  @override
  String toString() {
    return "_TypedefMirrorImpl('${_typedefMirror}')";
  }
}

class _SpecialTypeMirrorImpl extends _TypeMirrorImpl {
  _SpecialTypeMirrorImpl(dm.TypeMirror typeMirror, ReflectableImpl reflectable)
      : super(typeMirror, reflectable);

  @override operator ==(other) {
    return other is _SpecialTypeMirrorImpl && other._typeMirror == _typeMirror;
  }

  @override
  int get hashCode => _typeMirror.hashCode;

  @override
  String toString() {
    return "_SpecialTypeMirrorImpl('${_typeMirror}')";
  }
}

class _CombinatorMirrorImpl implements rm.CombinatorMirror {
  dm.CombinatorMirror _combinatorMirror;

  _CombinatorMirrorImpl(this._combinatorMirror);

  @override
  List<String> get identifiers =>
      _combinatorMirror.identifiers.map(dm.MirrorSystem.getName);

  @override
  bool get isHide => _combinatorMirror.isHide;

  @override
  bool get isShow => _combinatorMirror.isShow;

  @override
  operator ==(other) {
    return other is _CombinatorMirrorImpl &&
        other._combinatorMirror == _combinatorMirror;
  }

  @override
  int get hashCode => _combinatorMirror.hashCode;

  @override
  String toString() {
    return "_CombinatorMirrorImpl('${_combinatorMirror}')";
  }
}

class _VoidMirrorImpl implements rm.TypeMirror {
  @override
  bool get hasReflectedType => false;

  @override
  Type get reflectedType => throw new NoSuchCapabilityError(
      "Attempt to get the reflected type of 'void'");

  @override
  List<TypeVariableMirror> get typeVariables => [];

  @override
  List<TypeMirror> get typeArguments => [];

  @override
  bool get isOriginalDeclaration => true;

  @override
  TypeMirror get originalDeclaration => this;

  @override
  bool isSubtypeOf(TypeMirror other) =>
      other.hasReflectedType && other.reflectedType == dynamic;

  @override
  bool isAssignableTo(TypeMirror other) => isSubtypeOf(other);

  @override
  String get simpleName => "void";

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  @override
  get owner => null;

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  // TODO(eernst) implement: we should fail if there is no capability.
  @override
  List<Object> get metadata => <Object>[];

  @override
  String get qualifiedName => simpleName;

  @override
  bool get isPrivate => false;

  // It is allowed to return null.
  @override
  get location => null;

  @override
  bool get isTopLevel => true;
}

class _SourceLocationImpl implements rm.SourceLocation {
  dm.SourceLocation _sourceLocation;

  _SourceLocationImpl(this._sourceLocation);

  @override
  int get line => _sourceLocation.line;

  @override
  int get column => _sourceLocation.column;

  @override
  Uri get sourceUri => _sourceLocation.sourceUri;

  @override operator ==(other) {
    return other is _SourceLocationImpl &&
        other._sourceLocation == _sourceLocation;
  }

  @override
  int get hashCode => _sourceLocation.hashCode;

  @override
  String toString() {
    return "_SourceLocationImpl('${_sourceLocation}')";
  }
}

/// An implementation of [ReflectableInterface] based on dart:mirrors.
class ReflectableImpl extends ReflectableBase implements ReflectableInterface {
  /// Const constructor, to enable usage as metadata, allowing for varargs
  /// style invocation with up to ten arguments.
  const ReflectableImpl(
      [ReflectCapability cap0 = null,
      ReflectCapability cap1 = null,
      ReflectCapability cap2 = null,
      ReflectCapability cap3 = null,
      ReflectCapability cap4 = null,
      ReflectCapability cap5 = null,
      ReflectCapability cap6 = null,
      ReflectCapability cap7 = null,
      ReflectCapability cap8 = null,
      ReflectCapability cap9 = null])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const ReflectableImpl.fromList(List<ReflectCapability> capabilities)
      : super.fromList(capabilities);

  bool _canReflect(dm.InstanceMirror mirror) {
    dm.ClassMirror classMirror = mirror.type.originalDeclaration;
    return !classMirror.isPrivate && _supportedClasses.contains(classMirror);
  }

  /// Determines whether reflection is supported for the given [o].
  @override
  bool canReflect(Object o) => _canReflect(dm.reflect(o));

  /// Returns a mirror of the given object [reflectee]
  @override
  rm.InstanceMirror reflect(Object o) {
    dm.InstanceMirror mirror = dm.reflect(o);
    if (_canReflect(mirror)) return wrapInstanceMirror(mirror, this);
    throw new NoSuchCapabilityError(
        "Attempt to reflect on class '${o.runtimeType}' without capability");
  }

  bool get _supportsType {
    return capabilities
        .any((ReflectCapability capability) => capability is TypeCapability);
  }

  bool _canReflectType(dm.ClassMirror mirror) {
    // We refuse support for class mirrors with type arguments, because they
    // are instantiated generic classes (that is, `!isOriginalDeclaration`)
    // and until we get support for detecting whether a given instantiated
    // generic class "C<T>" is an instance of a given generic class "C", we
    // cannot find the right class mirror in post-transform code. So for
    // consistency we must also reject doing it here.
    return _supportsType &&
        _supportedClasses.contains(mirror.originalDeclaration) &&
        mirror.typeArguments.isEmpty;
  }

  @override
  bool canReflectType(Type type) {
    dm.TypeMirror typeMirror = dm.reflectType(type);
    if (typeMirror is dm.ClassMirror) {
      return _canReflectType(typeMirror);
    } else {
      throw unimplementedError("Checking reflection support on a "
          "currently unsupported kind of type: $typeMirror");
    }
  }

  @override
  rm.TypeMirror reflectType(Type type) {
    if (!_supportsType) {
      throw new NoSuchCapabilityError(
          "Reflecting on type $type without capability");
    }
    dm.TypeMirror typeMirror = dm.reflectType(type);
    if (typeMirror is dm.ClassMirror) {
      return wrapClassMirrorIfSupported(typeMirror, this);
    } else {
      throw unimplementedError("Checking reflection support on a "
          "currently unsupported kind of type: $typeMirror");
    }
  }

  bool get _supportsLibraries {
    return capabilities
        .any((ReflectCapability capability) => capability is LibraryCapability);
  }

  @override
  rm.LibraryMirror findLibrary(String libraryName) {
    if (!_supportsLibraries) {
      throw new NoSuchCapabilityError(
          "Searching for library '$libraryName'. LibraryMirrors are not "
          "supported by this reflector. Try adding 'libraryCapability'");
    }
    Symbol librarySymbol = new Symbol(libraryName);
    return new _LibraryMirrorImpl(
        dm.currentMirrorSystem().findLibrary(librarySymbol), this);
  }

  @override
  Map<Uri, rm.LibraryMirror> get libraries {
    if (!_supportsLibraries) {
      throw new NoSuchCapabilityError(
          "Trying to obtain a library mirror without capability. Try adding "
          "`libraryCapability`");
    }
    Map<Uri, dm.LibraryMirror> libs = dm.currentMirrorSystem().libraries;
    return new Map<Uri, rm.LibraryMirror>.fromIterable(libs.keys,
        key: (k) => k, value: (k) => new _LibraryMirrorImpl(libs[k], this));
  }

  @override
  Iterable<rm.ClassMirror> get annotatedClasses {
    return _supportedClasses.map((dm.ClassMirror classMirror) {
      return wrapClassMirrorIfSupported(classMirror, this);
    });
  }

  /// Auxiliary method used by [_supportedClasses]. Finds all classes
  /// which are directly covered by this [ReflectableImpl], that is,
  /// classes which are annotated with this [ReflectableImpl] as metadata
  /// as well as classes that match a global quantifier.
  Set<dm.ClassMirror> _directlySupportedClasses() {
    Set<dm.ClassMirror> result = new Set<dm.ClassMirror>();
    List<RegExp> globalPatterns = <RegExp>[];
    Set<Type> globalMetadataClasses = new Set<Type>();

    for (dm.LibraryMirror library
        in dm.currentMirrorSystem().libraries.values) {
      for (dm.LibraryDependencyMirror dependency
          in library.libraryDependencies) {
        if (dependency.isImport &&
            dependency.targetLibrary.qualifiedName ==
                reflectableLibrarySymbol) {
          for (dm.InstanceMirror metadatumMirror in dependency.metadata) {
            Object metadatum = metadatumMirror.reflectee;
            if (metadatum is GlobalQuantifyCapability &&
                metadatum.reflector == this) {
              globalPatterns.add(new RegExp(metadatum.classNamePattern));
            }
            if (metadatum is GlobalQuantifyMetaCapability &&
                metadatum.reflector == this) {
              globalMetadataClasses.add(metadatum.metadataType);
            }
          }
        }
      }
    }

    for (dm.LibraryMirror library
        in dm.currentMirrorSystem().libraries.values) {
      declarationLoop: for (dm.DeclarationMirror declaration
          in library.declarations.values) {
        if (declaration is dm.ClassMirror) {
          for (dm.InstanceMirror metadatum in declaration.metadata) {
            if (metadatum.reflectee == this ||
                globalMetadataClasses
                    .contains(metadatum.reflectee.runtimeType)) {
              result.add(declaration.originalDeclaration);
              continue declarationLoop;
            }
          }
          String qualifiedName =
              dm.MirrorSystem.getName(declaration.qualifiedName);
          for (RegExp pattern in globalPatterns) {
            if (pattern.hasMatch(qualifiedName)) {
              result.add(declaration.originalDeclaration);
              continue declarationLoop;
            }
          }
        }
      }
    }
    return result;
  }

  /// Returns the set of [dm.ClassMirror]s corresponding to the classes
  /// (and associated instances thereof) which must receive the reflection
  /// support that this [ReflectableImpl] specifies (that is, the set of
  /// classes 'covered by' this [ReflectableImpl]).
  ///
  /// It includes the directly covered classes, i.e., the classes which
  /// carry an instance of this [ReflectableImpl] as metadata, plus the
  /// classes which are matched by a [GlobalQuantifyCapability] or a
  /// [GlobalQuantifyMetaCapability] carrying this [ReflectableImpl]. This
  /// set of directly covered classes is extended in a series of steps:
  ///
  /// 1. The set of covered classes is extended by downwards-closure (every
  /// subtype of each member of the set is added) if there is a
  /// `subtypeQuantifyCapability` in `capabilities`.
  ///
  /// 2. The set of covered classes is extended by upwards-closure (every
  /// direct and indirect superclass is added) if `capabilities` contains a
  /// `SuperclassQuantifyCapability`. A `SuperclassQuantifyCapability` has
  /// an upper bound (by default: [Object]); if [Object] is not among the
  /// upper bounds specified then the upwards-closure is subject to non-trivial
  /// filtering by the given bounds: With each candidate class `C`, it is only
  /// added if there is an upper bound `B` such that `B` is a direct or
  /// indirect superclass of `C`; moreover, if that upper bound was specified
  /// to `excludeUpperBound` then it must be a proper superclass, that is,
  /// `C` is only added if `C != B`.
  ///
  /// 3. The set of covered classes is extended with all classes used in
  /// covered type annotations (types of covered variables and parameters,
  /// and return types of covered methods) iff there is a `typeCapability`
  /// and a `TypeAnnotationQuantifyCapability`. When `transitive` of that
  /// `TypeAnnotationQuantifyCapability` is false, a single iteration over
  /// the currently covered classes is used; when `transitive` is true, a
  /// fixed point iteration is used.
  ///
  /// As a result, a given class mirror `m`, mirror of a class `C`, is
  /// supported by this [ReflectableImpl] iff
  /// `this._supportedClasses.contains(m.originalDeclaration)`.
  Set<dm.ClassMirror> get _supportedClasses {
    // TODO(sigurdm) implement: This cache will break with deferred loading.
    return _supportedClassesCache.putIfAbsent(this, () {
      Set<dm.ClassMirror> result = _directlySupportedClasses();

      if (impliesDownwardsClosure(capabilities)) {
        new _SubtypesFixedPoint().expand(result);
      }
      if (impliesUpwardsClosure(capabilities)) {
        new _SuperclassesFixedPoint(extractUpwardsClosureBounds(capabilities),
            impliesMixins(capabilities)).expand(result);
      } else {
        // Even without the upwards closure, we wish to support some
        // superclasses, namely mixin applications where the class
        // applied as a mixin is supported (it seems natural to support
        // applications of supported mixins, and there is no other way short
        // of a full upwards closure to request that support).
        result.addAll(_mixinApplicationsOfClasses(result));
      }
      if (impliesTypes(capabilities) && impliesTypeAnnotations(capabilities)) {
        _TypeAnnotationsFixedPoint fix = new _TypeAnnotationsFixedPoint();
        (impliesTypeAnnotationClosure(capabilities)
            ? fix.expand
            : fix.singleExpand)(result);
      }
      return result;
    });
  }

  static Map<ReflectableImpl, Set<dm.ClassMirror>> _supportedClassesCache =
      <ReflectableImpl, Set<dm.ClassMirror>>{};

  /// Returns `true` iff this [ReflectableImpl] contains an
  /// [ApiReflectCapability] which satisfies the given [predicate], i.e.,
  /// if the corresponding capability to do something has been granted
  /// for a class that carries this [ReflectableImpl] as metadata, and to
  /// the instances of such a class.
  bool hasCapability(bool predicate(ApiReflectCapability capability)) {
    return capabilities.any((ReflectCapability capability) =>
        capability is ApiReflectCapability && predicate(capability));
  }
}

/// Auxiliary class used by `_supportedClasses`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SubtypesFixedPoint extends FixedPoint<dm.ClassMirror> {
  /// The inverse relation of `superinterfaces`, globally.
  final Map<dm.ClassMirror, Set<dm.ClassMirror>> subtypes =
      <dm.ClassMirror, Set<dm.ClassMirror>>{};

  _SubtypesFixedPoint() {
    for (dm.LibraryMirror library
        in dm.currentMirrorSystem().libraries.values) {
      for (dm.DeclarationMirror declaration in library.declarations.values) {
        if (declaration is dm.ClassMirror) {
          // If `declaration` is a mixin application (`class C = B with M`)
          // then include that mixin (`M`) as a supertype.
          if (declaration.mixin != declaration) {
            _addSubtypeRelation(declaration.mixin, declaration);
          }
          // If `declaration` has a superclass then include it.
          dm.ClassMirror superclass = declaration.superclass;
          if (superclass != null) _addSubtypeRelation(superclass, declaration);
          // If `superclass` is a mixin application, traverse superclasses
          // as long as they are mixin applications and add them, with the
          // classes applied as mixins.
          while (superclass != null && superclass.mixin != superclass) {
            _addSubtypeRelation(superclass.mixin, superclass);
            // Every mixin application has a non-null superclass: no check.
            _addSubtypeRelation(superclass.superclass, superclass);
            superclass = superclass.superclass;
          }
          for (dm.ClassMirror superinterface in declaration.superinterfaces) {
            _addSubtypeRelation(superinterface, declaration);
          }
        }
      }
    }
  }

  _addSubtypeRelation(dm.ClassMirror supertype, dm.ClassMirror subtype) {
    Set<dm.ClassMirror> subtypesOfClassMirror = subtypes[supertype];
    if (subtypesOfClassMirror == null) {
      subtypesOfClassMirror = new Set<dm.ClassMirror>();
      subtypes[supertype] = subtypesOfClassMirror;
    }
    subtypesOfClassMirror.add(subtype);
  }

  /// Returns all the immediate subtypes of the given [classMirror].
  Iterable<dm.ClassMirror> successors(final dm.ClassMirror classMirror) {
    return subtypes[classMirror] ?? <dm.ClassMirror>[];
  }
}

/// Auxiliary method used by `_supportedClasses`. Returns the set of classes
/// which are mixin applications that occur as direct or indirect superclasses
/// (stopping at classes which are not mixin applications) of members of
/// [classes], and which are not themselves included in [classes], when the
/// class applied as a mixin is a member of [classes]. In other words, it
/// returns the reachable applications of supported mixins. To be 'reachable'
/// means that there is a mixin-application-only superclass chain from an
/// already reachable class. Mixin applications which are not reachable in
/// this sense are excluded because there is no way to denote them directly,
/// and no other way to reach them than via `superclass`.
Set<dm.ClassMirror> _mixinApplicationsOfClasses(Set<dm.ClassMirror> classes) {
  Set<dm.ClassMirror> mixinApplications = new Set<dm.ClassMirror>();

  void addClass(dm.TypeMirror typeMirror) {
    dm.TypeMirror original = typeMirror.originalDeclaration;
    if (original is dm.ClassMirror && !classes.contains(original)) {
      mixinApplications.add(original);
    }
  }

  for (dm.ClassMirror workingClass in classes) {
    dm.ClassMirror superclass = workingClass.superclass;
    while (superclass != null && superclass.mixin != superclass) {
      if (classes.contains(superclass.mixin.originalDeclaration)) {
        addClass(superclass);
      }
      superclass = superclass.superclass;
    }
  }
  return mixinApplications;
}

/// Auxiliary class used by `_supportedClasses`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SuperclassesFixedPoint extends FixedPoint<dm.ClassMirror> {
  Map<dm.ClassMirror, bool> upwardsClosureBounds;
  bool mixinsRequested;
  _SuperclassesFixedPoint(this.upwardsClosureBounds, this.mixinsRequested);

  /// Returns the successors to the given [classMirror], that is, its direct
  /// superclass (if [_includedByUpwardsClosure]) and (iff [mixinsRequested])
  /// the class which was used in a mixin application to create [classMirror],
  /// if any.
  Iterable<dm.ClassMirror> successors(dm.ClassMirror classMirror) sync* {
    dm.ClassMirror superclass = classMirror.superclass;
    if (superclass != null) {
      if (includedByUpwardsClosure(superclass)) {
        dm.ClassMirror successor = superclass.originalDeclaration;
        if (successor is dm.ClassMirror) yield successor;
        if (superclass.mixin != superclass && mixinsRequested) {
          dm.ClassMirror mixinSuccessor = superclass.mixin.originalDeclaration;
          if (mixinSuccessor is dm.ClassMirror) yield mixinSuccessor;
        }
      }
    }
  }

  /// Returns true iff [upwardsClosureBounds] is empty or there exists an
  /// upper bound of [classMirror] in [upwardsClosureBounds] which is
  /// either a proper superclass of [classMirror] or which does not have
  /// a true `excludeUpperBound`.
  bool includedByUpwardsClosure(dm.ClassMirror classMirror) {
    if (upwardsClosureBounds.isEmpty) return true;
    return upwardsClosureBounds.keys.any((dm.ClassMirror bound) {
      return classMirror.isSubclassOf(bound) &&
          (!upwardsClosureBounds[bound] || classMirror != bound);
    });
  }
}

class _TypeAnnotationsFixedPoint extends FixedPoint<dm.ClassMirror> {
  /// Returns the successors to the given [classMirror], that is, the mirrors
  /// of classes used as type annotations in covered variables and parameters
  /// of covered methods as well as their return types, in the class reflected
  /// by [classMirror].
  Iterable<dm.ClassMirror> successors(dm.ClassMirror classMirror) sync* {
    for (dm.DeclarationMirror declaration in classMirror.declarations.values) {
      if (declaration is dm.VariableMirror) {
        dm.TypeMirror typeMirror = declaration.type.originalDeclaration;
        if (typeMirror is dm.ClassMirror) yield typeMirror;
      } else if (declaration is dm.MethodMirror) {
        for (dm.ParameterMirror parameter in declaration.parameters) {
          dm.TypeMirror typeMirror = parameter.type.originalDeclaration;
          if (typeMirror is dm.ClassMirror) yield typeMirror;
        }
        dm.TypeMirror typeMirror = declaration.returnType;
        if (typeMirror is dm.ClassMirror) yield typeMirror;
      }
    }
    for (dm.TypeVariableMirror typeVariableMirror
        in classMirror.typeVariables) {
      dm.TypeMirror typeMirror = typeVariableMirror.upperBound;
      if (typeMirror is dm.ClassMirror) {
        yield typeMirror;
      }
    }
  }
}

bool _isSetterName(String name) => name.endsWith("=");

String _setterNameToGetterName(String name) {
  assert(_isSetterName(name));
  return name.substring(0, name.length - 1);
}
