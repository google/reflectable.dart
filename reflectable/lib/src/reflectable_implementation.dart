// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.reflectable_implementation;

import 'dart:mirrors' as dm;
import '../capability.dart';
import '../reflectable.dart' as r;

r.InstanceMirror reflect(o, r.Reflectable reflectable) {
  bool hasReflectable(dm.ClassMirror type) {
    if (type == null) return false;
    if (type.metadata
        .map((dm.InstanceMirror reflectable) => reflectable.reflectee)
        .contains(reflectable)) {
      return true;
    }
    return false;
  }

  dm.InstanceMirror mirror = dm.reflect(o);
  if (!hasReflectable(mirror.type)) {
    throw new NoSuchCapabilityError(
        "Reflecting on object of unannotated class.");
  }
  return wrapInstanceMirror(dm.reflect(o), reflectable);
}

r.ClassMirror reflectClass(Type t, r.Reflectable reflectable) {
  return wrapClassMirror(dm.reflectClass(t), reflectable);
}

r.LibraryMirror findLibrary(Symbol libraryName, r.Reflectable reflectable) {
  return new _LibraryMirrorImpl(
      dm.currentMirrorSystem().findLibrary(libraryName), reflectable);
}

Iterable<r.ClassMirror> annotatedClasses(r.Reflectable reflectable) {
  List<r.ClassMirror> result = new List<r.ClassMirror>();
  for (dm.LibraryMirror library in dm.currentMirrorSystem().libraries.values) {
    for (dm.DeclarationMirror declarationMirror
         in library.declarations.values) {
      // TODO(sigurdm, eernst): Update when we can annotate top-level functions.
      if (declarationMirror is! dm.ClassMirror) continue;
      if (!_isAnnotatedBy(declarationMirror, reflectable)) continue;
      result.add(wrapClassMirror(declarationMirror, reflectable));
    }
  }
  return result;
}

bool _isAnnotatedBy(dm.DeclarationMirror declarationMirror, Object annotation) {
  return declarationMirror.metadata.any((dm.InstanceMirror metadataMirror) {
    return metadataMirror.reflectee == annotation;
  });
}

Map<Uri, r.LibraryMirror> libraries(r.Reflectable reflectable) {
  Map<Uri, dm.LibraryMirror> libs = dm.currentMirrorSystem().libraries;
  return new Map<Uri, r.LibraryMirror>.fromIterable(libs.keys,
      key: (k) => k,
      value: (k) => new _LibraryMirrorImpl(libs[k], reflectable));
}

r.ClassMirror wrapClassMirror(
    dm.ClassMirror classMirror, r.Reflectable reflectable) {
  if (classMirror is dm.FunctionTypeMirror) {
    return new _FunctionTypeMirrorImpl(classMirror, reflectable);
  } else {
    assert(classMirror is dm.ClassMirror);
    return new _ClassMirrorImpl(classMirror, reflectable);
  }
}

r.DeclarationMirror wrapDeclarationMirror(
    dm.DeclarationMirror declarationMirror, r.Reflectable reflectable) {
  if (declarationMirror is dm.MethodMirror) {
    return new _MethodMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.ParameterMirror) {
    return new _ParameterMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.VariableMirror) {
    return new _VariableMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.TypeVariableMirror) {
    return new _TypeVariableMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.TypedefMirror) {
    return new _TypedefMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.ClassMirror) {
    // Covers FunctionTypeMirror and ClassMirror.
    return wrapClassMirror(declarationMirror, reflectable);
  } else {
    assert(declarationMirror is dm.LibraryMirror);
    return new _LibraryMirrorImpl(declarationMirror, reflectable);
  }
}

r.InstanceMirror wrapInstanceMirror(
    dm.InstanceMirror instanceMirror, r.Reflectable reflectable) {
  if (instanceMirror is dm.ClosureMirror) {
    return new _ClosureMirrorImpl(instanceMirror, reflectable);
  } else {
    assert(instanceMirror is dm.InstanceMirror);
    return new _InstanceMirrorImpl(instanceMirror, reflectable);
  }
}

r.ObjectMirror wrapObjectMirror(dm.ObjectMirror m, r.Reflectable reflectable) {
  if (m is dm.LibraryMirror) {
    return new _LibraryMirrorImpl(m, reflectable);
  } else if (m is dm.InstanceMirror) {
    return wrapInstanceMirror(m, reflectable);
  } else {
    assert(m is dm.ClassMirror);
    return wrapClassMirror(m, reflectable);
  }
}

r.TypeMirror wrapTypeMirror(
    dm.TypeMirror typeMirror, r.Reflectable reflectable) {
  if (typeMirror is dm.TypeVariableMirror) {
    return new _TypeVariableMirrorImpl(typeMirror, reflectable);
  } else if (typeMirror is dm.TypedefMirror) {
    return new _TypedefMirrorImpl(typeMirror, reflectable);
  } else {
    assert(typeMirror is dm.ClassMirror);
    return wrapClassMirror(typeMirror, reflectable);
  }
}

r.CombinatorMirror wrapCombinatorMirror(dm.CombinatorMirror combinatorMirror) {
  return new _CombinatorMirrorImpl(combinatorMirror);
}

dm.ClassMirror unwrapClassMirror(r.ClassMirror m) {
  if (m is _ClassMirrorImpl) {
    // This also works for _FunctionTypeMirrorImpl
    return m._classMirror;
  } else {
    throw new ArgumentError("Unexpected subtype of ClassMirror");
  }
}

dm.TypeMirror unwrapTypeMirror(r.TypeMirror TypeMirror) {
  if (TypeMirror is _TypeMirrorImpl) {
    return TypeMirror._typeMirror;
  } else {
    throw new ArgumentError("Unexpected subtype of TypeMirror");
  }
}

/// Returns true if [classMirror] supports reflective invoke of the
/// instance-member named [name] according to the
/// capabilities of [reflectable].
bool reflectableSupportsInstanceInvoke(
    r.Reflectable reflectable, Symbol name, dm.ClassMirror classMirror) {
  return reflectable.capabilities.any((ReflectCapability capability) {
    if (capability == invokeMembersCapability ||
        capability == invokeInstanceMembersCapability) {
      return true;
    } else if (capability is InvokeInstanceMemberCapability) {
      return capability.name == name;
    } else if (capability is InvokeMembersWithMetadataCapability) {
      dm.DeclarationMirror declarationMirror =
          classMirror.instanceMembers[name];
      return declarationMirror != null &&
          declarationMirror.metadata.contains(capability.metadata);
    } else if (capability is InvokeInstanceMembersUpToSuperCapability) {
      dm.ClassMirror currentClass = classMirror;
      while (currentClass != null &&
          currentClass.reflectedType != capability.superType) {
        if (currentClass.instanceMembers.containsKey(name)) {
          return true;
        }
        currentClass = currentClass.superclass;
      }
      return false;
    } else {
      return false;
    }
  });
}

/// Returns true iff [reflectable] supports static invoke of [name].
bool reflectableSupportsStaticInvoke(r.Reflectable reflectable, Symbol name) {
  return reflectable.capabilities.any((ReflectCapability capability) {
    if (capability is InvokeStaticMemberCapability) {
      return capability.name == name;
    }
    return false;
  });
}

/// Returns true iff [reflectable] supports invoke of [name].
bool reflectableSupportsConstructorInvoke(
    r.Reflectable reflectable,
    dm.ClassMirror classMirror,
    Symbol name) {
  return reflectable.capabilities.any((ReflectCapability capability) {
    if (capability == r.invokeConstructorsCapability) {
      return true;
    } else if (capability is r.InvokeConstructorCapability) {
      return capability.name == name;
    } else if (capability is r.InvokeConstructorsWithMetaDataCapability) {
      dm.MethodMirror constructorMirror = classMirror.declarations.values
          .firstWhere((dm.DeclarationMirror declarationMirror) {
        return declarationMirror is dm.MethodMirror &&
               declarationMirror.constructorName == name;
      });
      if (constructorMirror == null ||
          !constructorMirror.isConstructor) return false;
      return constructorMirror.metadata.contains(capability.metadata);
    }
    return false;
  });
}

/// Returns the symbol with final "=" removed.
/// If the symbol does not have a final "=" it is returned as is.
Symbol _setterToGetter(Symbol setter) {
  String setterName = dm.MirrorSystem.getName(setter);
  if (!setterName.endsWith("=")) {
    return setter;
  }
  return new Symbol(setterName.substring(0, setterName.length - 1));
}

/// Returns [getter] with a final "=" added.
/// If [getter] already ends with "=" an error is thrown.
Symbol _getterToSetter(Symbol getter) {
  String getterName = dm.MirrorSystem.getName(getter);
  if (getterName.endsWith("=")) {
    throw new ArgumentError("$getter is a setter symbol already");
  }
  return new Symbol('$getterName=');
}

abstract class _ObjectMirrorImplMixin implements r.ObjectMirror {
  r.Reflectable get _reflectable;

  Object getField(Symbol name) {
    throw new UnsupportedError("Use invokeGetter instead of getField");
  }

  void setField(Symbol name, Object value) {
    throw new UnsupportedError("Use invokeSetter instead of setField");
  }
}

class _LibraryMirrorImpl extends _DeclarationMirrorImpl
    with _ObjectMirrorImplMixin implements r.LibraryMirror {
  dm.LibraryMirror get _libraryMirror => _declarationMirror;

  _LibraryMirrorImpl(dm.LibraryMirror m, r.Reflectable reflectable)
      : super(m, reflectable) {}

  @override
  Uri get uri => _libraryMirror.uri;

  @override
  Map<Symbol, r.DeclarationMirror> get declarations {
    Map<Symbol, dm.DeclarationMirror> decls = _libraryMirror.declarations;
    Iterable<Symbol> relevantKeys = decls.keys.where((k) {
      List<dm.InstanceMirror> metadata = decls[k].metadata;
      for (var item in metadata) {
        if (item.hasReflectee && item.reflectee is r.Reflectable) return true;
      }
      return false;
    });
    return new Map<Symbol, r.DeclarationMirror>.fromIterable(relevantKeys,
        key: (k) => k,
        value: (v) => wrapDeclarationMirror(decls[v], _reflectable));
  }

  @override
  Object invoke(Symbol memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (!reflectableSupportsStaticInvoke(_reflectable, memberName)) {
      throw new NoSuchInvokeCapabilityError(
          _receiver, memberName, positionalArguments, namedArguments);
    }
    return _libraryMirror.invoke(
        memberName, positionalArguments, namedArguments).reflectee;
  }

  @override
  Object invokeGetter(Symbol getterName) {
    if (!reflectableSupportsStaticInvoke(_reflectable, getterName)) {
      throw new NoSuchInvokeCapabilityError(_receiver, getterName, [], null);
    }
    return _libraryMirror.getField(getterName).reflectee;
  }

  @override
  Object invokeSetter(Symbol setterName, Object value) {
    if (!reflectableSupportsStaticInvoke(_reflectable, setterName)) {
      throw new NoSuchInvokeCapabilityError(_receiver, setterName, [value], null);
    }
    return _libraryMirror.setField(_setterToGetter(setterName), value);
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
  List<r.LibraryDependencyMirror> get libraryDependencies {
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

class _LibraryDependencyMirrorImpl implements r.LibraryDependencyMirror {
  final dm.LibraryDependencyMirror _libraryDependencyMirror;
  final r.Reflectable _reflectable;

  _LibraryDependencyMirrorImpl(
      this._libraryDependencyMirror, this._reflectable);

  @override
  bool get isImport => _libraryDependencyMirror.isImport;

  @override
  bool get isExport => _libraryDependencyMirror.isExport;

  @override
  r.LibraryMirror get sourceLibrary {
    return new _LibraryMirrorImpl(
        _libraryDependencyMirror.sourceLibrary, _reflectable);
  }

  @override
  r.LibraryMirror get targetLibrary {
    return new _LibraryMirrorImpl(
        _libraryDependencyMirror.targetLibrary, _reflectable);
  }

  @override
  Symbol get prefix => _libraryDependencyMirror.prefix;

  @override
  List<Object> get metadata =>
      _libraryDependencyMirror.metadata.map((m) => m.reflectee).toList();

  @override
  r.SourceLocation get location {
    return new _SourceLocationImpl(_libraryDependencyMirror.location);
  }

  @override
  List<r.CombinatorMirror> get combinators {
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
    implements r.InstanceMirror {
  final dm.InstanceMirror _instanceMirror;
  final r.Reflectable _reflectable;

  _InstanceMirrorImpl(this._instanceMirror, this._reflectable);

  @override
  r.TypeMirror get type => wrapTypeMirror(_instanceMirror.type, _reflectable);

  @override
  bool get hasReflectee => _instanceMirror.hasReflectee;

  @override
  get reflectee => _instanceMirror.reflectee;

  @override
  Object invoke(Symbol memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, memberName, _instanceMirror.type)) {
      return _instanceMirror.invoke(
          memberName, positionalArguments, namedArguments).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(
        _receiver, memberName, positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(Symbol fieldName) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, fieldName, _instanceMirror.type)) {
      return _instanceMirror.getField(fieldName).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, fieldName, [], null);
  }

  @override
  Object invokeSetter(Symbol setterName, Object value) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, setterName, _instanceMirror.type)) {
      return _instanceMirror.setField(
          _setterToGetter(setterName), value).reflectee;
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

class _ClassMirrorImpl extends _TypeMirrorImpl with _ObjectMirrorImplMixin
    implements r.ClassMirror {
  dm.ClassMirror get _classMirror => _declarationMirror;

  _ClassMirrorImpl(dm.ClassMirror cm, r.Reflectable reflectable)
      : super(cm, reflectable) {}

  @override
  List<r.TypeVariableMirror> get typeVariables {
    return _classMirror.typeVariables.map((v) {
      return new _TypeVariableMirrorImpl(v, _reflectable);
    }).toList();
  }

  @override
  List<r.TypeMirror> get typeArguments => _classMirror.typeArguments.map((a) {
    return wrapTypeMirror(a, _reflectable);
  }).toList();

  @override
  r.TypeMirror get superclass {
    dm.ClassMirror sup = _classMirror.superclass;
    return wrapClassMirror(sup, _reflectable);
  }

  @override
  List<r.TypeMirror> get superinterfaces {
    List<dm.TypeMirror> superinterfaces = _classMirror.superinterfaces;
    return superinterfaces.map((dm.TypeMirror superInterface) {
      return wrapTypeMirror(superInterface, _reflectable);
    }).toList();
  }

  @override
  bool get isAbstract => _classMirror.isAbstract;

  @override
  Map<Symbol, r.DeclarationMirror> get declarations {
    // TODO(sigurdm): Possibly cache this.
    Map<Symbol, r.DeclarationMirror> result =
        new Map<Symbol, r.DeclarationMirror>();
    _classMirror.declarations
        .forEach((Symbol name, dm.DeclarationMirror declarationMirror) {
      if (declarationMirror is dm.MethodMirror) {
        if ((declarationMirror.isStatic &&
                reflectableSupportsStaticInvoke(_reflectable, name)) ||
            reflectableSupportsInstanceInvoke(
                _reflectable, name, _classMirror)) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else if (declarationMirror is dm.VariableMirror) {
        // For variableMirrors we test both for support of the name and the
        // derived setter name.
        if ((declarationMirror.isStatic &&
                (reflectableSupportsStaticInvoke(_reflectable, name) ||
                    reflectableSupportsStaticInvoke(
                        _reflectable, _getterToSetter(name)))) ||
            (reflectableSupportsInstanceInvoke(
                    _reflectable, name, _classMirror) ||
                reflectableSupportsInstanceInvoke(
                    _reflectable, _getterToSetter(name), _classMirror))) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else {
        // TODO(sigurdm): Support capabilities for other declarations
        result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
      }
    });
    return result;
  }

  @override
  Map<Symbol, r.MethodMirror> get instanceMembers {
    // TODO(sigurdm): Only expose members that are allowed by the capabilities
    // of the reflectable.
    Map<Symbol, dm.MethodMirror> members = _classMirror.instanceMembers;
    return new Map<Symbol, r.MethodMirror>.fromIterable(members.keys,
        key: (k) => k,
        value: (v) => new _MethodMirrorImpl(members[v], _reflectable));
  }

  @override
  Map<Symbol, r.MethodMirror> get staticMembers {
    // TODO(sigurdm): Only expose members that are allowed by the capabilities
    // of the reflectable.
    Map<Symbol, dm.MethodMirror> members = _classMirror.staticMembers;
    return new Map<Symbol, r.MethodMirror>.fromIterable(members.keys,
        key: (k) => k,
        value: (v) => new _MethodMirrorImpl(members[v], _reflectable));
  }

  @override
  r.TypeMirror get mixin => wrapTypeMirror(_classMirror.mixin, _reflectable);

  @override
  Object newInstance(Symbol constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (!reflectableSupportsConstructorInvoke(
        _reflectable, _classMirror, constructorName)) {
      throw new NoSuchInvokeCapabilityError(
          _classMirror , constructorName, positionalArguments, namedArguments);
    }
    return _classMirror.newInstance(
        constructorName, positionalArguments, namedArguments).reflectee;
  }

  @override
  Object invoke(Symbol memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (reflectableSupportsStaticInvoke(_reflectable, memberName)) {
      return _classMirror.invoke(
          memberName, positionalArguments, namedArguments).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(
        _receiver, memberName, positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(Symbol getterName) {
    if (reflectableSupportsStaticInvoke(_reflectable, getterName)) {
      return _classMirror.getField(getterName).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, getterName, [], null);
  }

  @override
  Object invokeSetter(Symbol setterName, Object value) {
    if (reflectableSupportsStaticInvoke(_reflectable, setterName)) {
      return _classMirror.setField(_setterToGetter(setterName), value).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, setterName, [value], null);
  }

  @override
  bool operator ==(other) {
    return other is _ClassMirrorImpl
        ? _classMirror == other._classMirror
        : false;
  }

  @override
  int get hashCode => _classMirror.hashCode;

  @override
  bool isSubclassOf(r.ClassMirror other) {
    return _classMirror.isSubclassOf(unwrapClassMirror(other));
  }

  get _receiver => _classMirror.reflectedType;

  @override
  String toString() => "_ClassMirrorImpl('${_classMirror}')";
}

class _FunctionTypeMirrorImpl extends _ClassMirrorImpl
    implements r.FunctionTypeMirror {
  dm.FunctionTypeMirror get _functionTypeMirror => _classMirror;

  _FunctionTypeMirrorImpl(
      dm.FunctionTypeMirror functionTypeMirror, r.Reflectable reflectable)
      : super(functionTypeMirror, reflectable);

  @override
  r.MethodMirror get callMethod {
    return new _MethodMirrorImpl(_functionTypeMirror.callMethod, _reflectable);
  }

  @override
  List<r.ParameterMirror> get parameters {
    return _functionTypeMirror.parameters
        .map((dm.ParameterMirror parameterMirror) {
      return new _ParameterMirrorImpl(parameterMirror, _reflectable);
    });
  }

  @override
  r.TypeMirror get returnType {
    return wrapTypeMirror(_functionTypeMirror.returnType, _reflectable);
  }
}

abstract class _DeclarationMirrorImpl implements r.DeclarationMirror {
  final dm.DeclarationMirror _declarationMirror;
  final r.Reflectable _reflectable;

  _DeclarationMirrorImpl(this._declarationMirror, this._reflectable);

  @override
  Symbol get simpleName => _declarationMirror.simpleName;

  @override
  Symbol get qualifiedName => _declarationMirror.qualifiedName;

  @override
  r.DeclarationMirror get owner {
    return wrapDeclarationMirror(_declarationMirror.owner, _reflectable);
  }

  @override
  bool get isPrivate => _declarationMirror.isPrivate;

  @override
  bool get isTopLevel => _declarationMirror.isTopLevel;

  @override
  List<Object> get metadata =>
      _declarationMirror.metadata.map((m) => m.reflectee).toList();

  @override
  r.SourceLocation get location {
    return new _SourceLocationImpl(_declarationMirror.location);
  }

  @override
  String toString() {
    return "_DeclarationMirrorImpl('${_declarationMirror}')";
  }
}

class _MethodMirrorImpl extends _DeclarationMirrorImpl
    implements r.MethodMirror {
  dm.MethodMirror get _methodMirror => _declarationMirror;

  _MethodMirrorImpl(dm.MethodMirror mm, r.Reflectable reflectable)
      : super(mm, reflectable);

  @override
  r.TypeMirror get returnType =>
      wrapTypeMirror(_methodMirror.returnType, _reflectable);

  @override
  String get source => _methodMirror.source;

  @override
  List<r.ParameterMirror> get parameters {
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
  Symbol get constructorName => _methodMirror.constructorName;

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
    return other is _MethodMirrorImpl
        ? _methodMirror == other._methodMirror
        : false;
  }

  @override
  int get hashCode => _methodMirror.hashCode;

  @override
  String toString() => "_MethodMirrorImpl('${_methodMirror}')";
}

class _ClosureMirrorImpl extends _InstanceMirrorImpl
    implements r.ClosureMirror {
  dm.ClosureMirror get _closureMirror => _instanceMirror;

  _ClosureMirrorImpl(dm.ClosureMirror closureMirror, r.Reflectable reflectable)
      : super(closureMirror, reflectable);

  @override
  Object apply(List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    return _closureMirror.apply(positionalArguments, namedArguments).reflectee;
  }

  @override
  r.MethodMirror get function {
    return new _MethodMirrorImpl(_closureMirror.function, _reflectable);
  }

  @override
  String toString() => "_ClosureMirrorImpl('${_closureMirror}')";
}

class _VariableMirrorImpl extends _DeclarationMirrorImpl
    implements r.VariableMirror {
  dm.VariableMirror get _variableMirror => _declarationMirror;

  _VariableMirrorImpl(dm.VariableMirror vm, r.Reflectable reflectable)
      : super(vm, reflectable);

  @override
  r.TypeMirror get type => wrapTypeMirror(_variableMirror.type, _reflectable);

  @override
  bool get isStatic => _variableMirror.isStatic;

  @override
  bool get isFinal => _variableMirror.isFinal;

  @override
  bool get isConst => _variableMirror.isConst;

  @override
  bool operator ==(other) => other is _VariableMirrorImpl
      ? _variableMirror == other._variableMirror
      : false;

  @override
  int get hashCode => _variableMirror.hashCode;

  @override
  String toString() => "_VariableMirrorImpl('${_variableMirror}')";
}

class _ParameterMirrorImpl extends _VariableMirrorImpl
    implements r.ParameterMirror {
  dm.ParameterMirror get _parameterMirror => _declarationMirror;

  _ParameterMirrorImpl(dm.ParameterMirror pm, r.Reflectable reflectable)
      : super(pm, reflectable);

  @override
  bool get isOptional => _parameterMirror.isOptional;

  @override
  bool get isNamed => _parameterMirror.isNamed;

  @override
  bool get hasDefaultValue => _parameterMirror.hasDefaultValue;

  @override
  Object get defaultValue => _parameterMirror.defaultValue.reflectee;

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
    implements r.TypeMirror {
  dm.TypeMirror get _typeMirror => _declarationMirror;

  _TypeMirrorImpl(dm.TypeMirror typeMirror, r.Reflectable reflectable)
      : super(typeMirror, reflectable);

  @override
  bool get hasReflectedType => _typeMirror.hasReflectedType;

  @override
  bool isAssignableTo(r.TypeMirror other) {
    return _typeMirror.isAssignableTo(unwrapTypeMirror(other));
  }

  @override
  bool get isOriginalDeclaration => _typeMirror.isOriginalDeclaration;

  @override
  bool isSubtypeOf(r.TypeMirror other) {
    return _typeMirror.isSubtypeOf(unwrapTypeMirror(other));
  }

  @override
  r.TypeMirror get originalDeclaration {
    return wrapTypeMirror(_typeMirror.originalDeclaration, _reflectable);
  }

  @override
  Type get reflectedType => _typeMirror.reflectedType;

  @override
  List<r.TypeMirror> get typeArguments {
    return _typeMirror.typeArguments.map((dm.TypeMirror typeArgument) {
      return wrapTypeMirror(typeArgument, _reflectable);
    }).toList();
  }

  @override
  List<r.TypeVariableMirror> get typeVariables {
    return _typeMirror.typeVariables
        .map((dm.TypeVariableMirror typeVariableMirror) {
      return new _TypeVariableMirrorImpl(typeVariableMirror, _reflectable);
    }).toList();
  }
}

class _TypeVariableMirrorImpl extends _TypeMirrorImpl
    implements r.TypeVariableMirror {
  dm.TypeVariableMirror get _typeVariableMirror => _typeMirror;

  _TypeVariableMirrorImpl(
      dm.TypeVariableMirror typeVariableMirror, r.Reflectable reflectable)
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
  r.TypeMirror get upperBound {
    return wrapTypeMirror(_typeVariableMirror.upperBound, _reflectable);
  }

  @override
  String toString() {
    return "_TypeVariableMirrorImpl('${_typeVariableMirror}')";
  }
}

class _TypedefMirrorImpl extends _TypeMirrorImpl implements r.TypedefMirror {
  dm.TypedefMirror get _typedefMirror => _typeMirror;

  _TypedefMirrorImpl(dm.TypedefMirror typedefMirror, r.Reflectable reflectable)
      : super(typedefMirror, reflectable);

  @override
  r.FunctionTypeMirror get referent {
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

class _CombinatorMirrorImpl implements r.CombinatorMirror {
  dm.CombinatorMirror _combinatorMirror;

  _CombinatorMirrorImpl(this._combinatorMirror);

  @override
  List<Symbol> get identifiers => _combinatorMirror.identifiers;

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

class _SourceLocationImpl implements r.SourceLocation {
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
