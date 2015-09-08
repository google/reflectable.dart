// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.mirrors_unimpl;

import 'dart:collection' show UnmodifiableMapView, UnmodifiableListView;

import '../capability.dart';
import '../mirrors.dart';
import '../reflectable.dart';
import 'encoding_constants.dart' as constants;
import 'encoding_constants.dart' show NO_CAPABILITY_INDEX;
import 'reflectable_base.dart';

bool get isTransformed => true;

// Mirror classes with default implementations of all methods, to be used as
// superclasses of transformer generated static mirror classes.  They serve to
// ensure that the static mirror classes always implement all methods, such that
// they throw an exception at runtime, rather than causing an error at compile
// time, which is the required behavior for static mirrors when they are used
// in ways that are not covered by the specified capabilities.
//
// Each of these classes implements the corresponding class in
// `package:reflectable/mirrors.dart`, and they replicate the internal
// implements `structure in package:reflectable/mirrors.dart` using `extends`
// and `with` clauses, such that the (un)implementation is inherited rather than
// replicated wherever possible.

_unsupported() => throw new UnimplementedError();

/// Invokes a getter on an object.
typedef Object _InvokerOfGetter(Object instance);

/// Invokes a setter on an object.
typedef Object _InvokerOfSetter(Object instance, Object value);

/// Invokes a static getter.
typedef Object _StaticGetter();

/// Invokes a setter on an object.
typedef Object _StaticSetter(Object value);

/// The data backing a reflector.
class ReflectorData {
  /// List of class mirrors, one class mirror for each class that is
  /// supported by reflection as specified by the reflector backed up
  /// by this [ReflectorData].
  final List<ClassMirror> classMirrors;

  /// List of library mirrors, one library mirror for each library that is
  /// supported by reflection as specified by the reflector backed up
  /// by this [ReflectorData].
  final List<LibraryMirror> libraryMirrors;

  /// Repository of method mirrors used (via indices into this list) by
  /// the [classMirrors] to describe the behavior of the mirrored
  /// class and its instances, and of variable mirrors used to describe
  /// their state. From the behavioral point of view there are no fields,
  /// but each of them gives rise to a getter and possibly a setter (whose
  /// `isSynthetic` is true). The implicit getters/setters are not stored
  /// in this list, but they can be reconstructed based on the variable
  /// mirrors describing the fields. From the program structure point of
  /// view (used for `declarations`), the method mirrors and the field
  /// mirrors must both be included directly. Hence, both points of view
  /// require a little bit of processing, but in return we avoid some
  /// redundancy in the stored information.
  final List<DeclarationMirror> memberMirrors;

  /// Repository of parameter mirrors used (via indices into this list) by
  /// the [memberMirrors] to describe the parameters of methods
  final List<ParameterMirror> parameterMirrors;

  /// List of [Type]s used to select class mirrors: If M is a class
  /// mirror in [classMirrors] at index `i`, the mirrored class (and
  /// hence the runtime type of the mirrored instances) is found in
  /// `types[i]`.
  final List<Type> types;

  /// Map from getter names to closures accepting an instance and returning
  /// the result of invoking the getter with that name on that instance.
  final Map<String, _InvokerOfGetter> getters;

  /// Map from setter names to closures accepting an instance and a new value,
  /// invoking the setter of that name on that instance, and returning its
  /// return value.
  final Map<String, _InvokerOfSetter> setters;

  Map<Type, ClassMirror> _typeToClassMirrorCache;

  ReflectorData(this.classMirrors, this.memberMirrors, this.parameterMirrors,
      this.types, this.getters, this.setters, this.libraryMirrors);

  /// Returns a class-mirror for the given [type].
  ///
  /// Returns `null` if the given class is not marked for reflection.
  ClassMirror classMirrorForType(Type type) {
    if (_typeToClassMirrorCache == null) {
      _typeToClassMirrorCache = new Map.fromIterables(types, classMirrors);
    }
    return _typeToClassMirrorCache[type];
  }
}

/// This mapping contains the mirror-data for each reflector.
/// It will be initialized in the generated code.
Map<Reflectable, ReflectorData> data =
    throw new StateError("Reflectable has not been initialized. "
        "Did you forget to add the main file to the "
        "reflectable transformer's entry_points in pubspec.yaml?");

abstract class _DataCaching {
  // TODO(eernst) clarify: When we have some substantial pieces of code using
  // reflectable, perform some experiments to detect how useful it is to have
  // this kind of caching.

  ReflectorData _dataCache;
  ReflectableImpl get _reflector;

  ReflectorData get _data {
    if (_dataCache == null) {
      _dataCache = data[_reflector];
    }
    return _dataCache;
  }
}

class _InstanceMirrorImpl extends _DataCaching implements InstanceMirror {
  final ReflectableImpl _reflector;
  final Object reflectee;

  _InstanceMirrorImpl(this.reflectee, this._reflector) {
    _type = _data.classMirrorForType(reflectee.runtimeType);
    if (_type == null) {
      throw new NoSuchCapabilityError(
          "Reflecting on un-marked type '${reflectee.runtimeType}'");
    }
  }

  ClassMirror _type;

  ClassMirror get type => _type;

  Object invoke(String methodName, List<Object> positionalArguments,
      [Map<Symbol, Object> namedArguments]) {
    Function methodTearer = _data.getters[methodName];
    if (methodTearer != null) {
      return Function.apply(
          methodTearer(reflectee), positionalArguments, namedArguments);
    }
    // TODO(eernst) clarify: Do we want to invoke noSuchMethod here when
    // we have a capability matching the name, but there really is no such
    // method. And how will we construct the symbol for the Invoke instance
    // we pass to `noSuchMethod`?
    throw new NoSuchInvokeCapabilityError(
        reflectee, methodName, positionalArguments, namedArguments);
  }

  bool get hasReflectee => true;

  bool operator ==(other) {
    return other is _InstanceMirrorImpl &&
        other._reflector == _reflector &&
        other.reflectee == reflectee;
  }

  int get hashCode => reflectee.hashCode ^ _reflector.hashCode;

  delegate(Invocation invocation) => _unsupported();

  @override
  Object invokeGetter(String getterName) {
    Function getter = _data.getters[getterName];
    if (getter != null) {
      return getter(reflectee);
    }
    throw new NoSuchInvokeCapabilityError(reflectee, getterName, [], {});
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (setterName.substring(setterName.length - 1) != "=") {
      setterName += "=";
    }
    Function setter = _data.setters[setterName];
    if (setter != null) {
      return setter(reflectee, value);
    }
    throw new NoSuchInvokeCapabilityError(reflectee, setterName, [value], {});
  }
}

class ClassMirrorImpl extends _DataCaching implements ClassMirror {
  /// The reflector which represents the mirror system that this
  /// mirror belongs to.
  final ReflectableImpl _reflector;

  /// The index of this mirror in the [ReflectorData.classMirrors] table.
  /// Also this is the index of the Type of the reflected class in
  /// [ReflectorData.types].
  final int _classIndex;

  /// The index of the owner library in the [ReflectorData.libraryMirrors]
  /// table.
  final int _ownerIndex;

  /// The index of the mirror of the superclass in the
  /// [ReflectorData.classMirrors] table.
  final int _superclassIndex;

  /// The index of the mixin of this class in the
  /// [ReflectorData.classMirrors] table.
  ///
  /// For classes that are not mixin-applications this is the same as the class
  /// itself.
  final int _mixinIndex;

  // TODO(sigurdm) implement: Implement superInterfaces.
  List<ClassMirror> get superinterfaces {
    return _superinterfaceIndices.map((int i) => _data.classMirrors[i]).toList();
  }

  // TODO(sigurdm) implement: Implement typeArguments.
  @override
  List<TypeMirror> get typeArguments => _unsupported();

  // TODO(sigurdm) implement: Implement typeVariables.
  @override
  List<TypeVariableMirror> get typeVariables => _unsupported();

  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// declarations of the reflected class. This includes method mirrors
  /// and variable mirrors and it directly corresponds to `declarations`.
  /// Exception: When the given `_reflector.capabilities` do not support
  /// the operation `declarations`, this will be `<int>[NO_CAPABILITY_INDEX]`.
  /// It is enough to check that the list is non-empty and first element is
  /// NO_CAPABILITY_INDEX to detect this situation, because
  /// NO_CAPABILITY_INDEX` will otherwise never occur.
  final List<int> _declarationIndices;

  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// instance members of the reflected class, except that it includes
  /// variable mirrors describing fields which must be converted to
  /// implicit getters and possibly implicit setters in order to
  /// obtain the correct result for `instanceMembers`.
  final List<int> _instanceMemberIndices;

  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// static members of the reflected class, except that it includes
  /// variable mirrors describing static fields nwhich must be converted
  /// to implicit getters and possibly implicit setters in order to
  /// obtain the correct result for `staticMembers`.
  final List<int> _staticMemberIndices;

  /// A list of the indices in [ReflectorData.classMirrors] of the
  /// superinterfaces of the reflected class.
  final List<int> _superinterfaceIndices;

  final String simpleName;
  final String qualifiedName;
  final List<Object> _metadata;
  final Map<String, _StaticGetter> _getters;
  final Map<String, _StaticSetter> _setters;
  final Map<String, Function> _constructors;

  ClassMirrorImpl(
      this.simpleName,
      this.qualifiedName,
      this._classIndex,
      this._reflector,
      this._declarationIndices,
      this._instanceMemberIndices,
      this._staticMemberIndices,
      this._superclassIndex,
      this._getters,
      this._setters,
      this._constructors,
      this._ownerIndex,
      this._mixinIndex,
      this._superinterfaceIndices,
      List<Object> metadata)
      : _metadata =
            (metadata == null) ? null : new UnmodifiableListView(metadata);

  bool get isAbstract => _unsupported();

  Map<String, DeclarationMirror> _declarations;

  Map<String, DeclarationMirror> get declarations {
    if (_declarations == null) {
      Map<String, DeclarationMirror> result =
          new Map<String, DeclarationMirror>();
      for (int declarationIndex in _declarationIndices) {
        // We encode a missing `declarations` capability as an index with
        // the value NO_CAPABILITY_INDEX. Note that `_declarations` will not be
        // initialized and hence we will come here repeatedly if that is the
        // case; however, performing operations for which there is no capability
        // need not have stellar performance, it is almost always a bug to do
        // that.
        if (declarationIndex == NO_CAPABILITY_INDEX) {
          throw new NoSuchCapabilityError(
              "Requesting declarations of '$qualifiedName' without capability");
        }
        DeclarationMirror declarationMirror =
            _data.memberMirrors[declarationIndex];
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _declarations =
          new UnmodifiableMapView<String, DeclarationMirror>(result);
    }
    return _declarations;
  }

  Map<String, MethodMirror> _instanceMembers;

  Map<String, MethodMirror> get instanceMembers {
    if (_instanceMembers == null) {
      Map<String, MethodMirror> result = new Map<String, MethodMirror>();
      for (int instanceMemberIndex in _instanceMemberIndices) {
        DeclarationMirror declarationMirror =
            _data.memberMirrors[instanceMemberIndex];
        assert(declarationMirror is MethodMirror);
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _instanceMembers = new UnmodifiableMapView<String, MethodMirror>(result);
    }
    return _instanceMembers;
  }

  Map<String, MethodMirror> _staticMembers;

  Map<String, MethodMirror> get staticMembers {
    if (_staticMembers == null) {
      Map<String, MethodMirror> result = new Map<String, MethodMirror>();
      for (int staticMemberIndex in _staticMemberIndices) {
        DeclarationMirror declarationMirror =
            _data.memberMirrors[staticMemberIndex];
        assert(declarationMirror is MethodMirror);
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _staticMembers = new UnmodifiableMapView<String, MethodMirror>(result);
    }
    return _staticMembers;
  }

  ClassMirror get mixin {
    if (_mixinIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Attempt to get mixin from '$simpleName' without capability");
    }
    return _data.classMirrors[_mixinIndex];
  }

  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    return Function.apply(
        _constructors["$constructorName"], positionalArguments, namedArguments);
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    _StaticGetter getter = _getters[memberName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(
          reflectedType, memberName, positionalArguments, namedArguments);
    }
    return Function.apply(
        _getters[memberName](), positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String getterName) {
    _StaticGetter getter = _getters[getterName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(reflectedType, getterName, [], {});
    }
    return getter();
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    _StaticSetter setter = _setters[setterName];
    if (setter == null) {
      throw new NoSuchInvokeCapabilityError(
          reflectedType, setterName, [value], {});
    }
    return setter(value);
  }

  // TODO(eernst) feature: Implement `isOriginalDeclaration`.
  @override
  bool get isOriginalDeclaration => _unsupported();

  // For now we only support reflection on public classes.
  @override
  bool get isPrivate => false;

  // Classes are always toplevel.
  @override
  bool get isTopLevel => true;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of '$reflectedType' without capability");
    }
    return _metadata;
  }

  @override
  Function invoker(String memberName) {
    Function getter = _data.getters[memberName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(reflectedType, memberName, [], {});
    }
    return getter;
  }

  @override
  bool get hasReflectedType => true;

  // TODO(eernst) feature: Implement `isAssignableTo`.
  @override
  bool isAssignableTo(TypeMirror other) => _unsupported();

  // TODO(eernst) feature: Implement `isSubTypeOf`.
  @override
  bool isSubtypeOf(TypeMirror other) => _unsupported();

  bool isSubclassOf(ClassMirror other) {
    if (other is FunctionTypeMirror) {
      return false;
    }
    if (other is ClassMirror && other.reflectedType == reflectedType) {
      return true;
    } else if (superclass == null) {
      return false;
    } else {
      return superclass.isSubclassOf(other);
    }
  }

  @override
  TypeMirror get originalDeclaration => _unsupported();

  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Trying to get owner of class '$qualifiedName' "
          "without 'LibraryCapability'");
    }
    return _data.libraryMirrors[_ownerIndex];
  }

  @override
  Type get reflectedType => _data.types[_classIndex];

  ClassMirror get superclass {
    if (_superclassIndex == null) return null;
    if (_superclassIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Requesting mirror on un-marked class, superclass of '$simpleName'");
    }
    return _data.classMirrors[_superclassIndex];
  }

  String toString() => "ClassMirrorImpl($qualifiedName)";

  // Because we take care to only ever create one instance for each
  // type/reflector-combination we can rely on the default `hashCode` and `==`
  // operations.
}

class LibraryMirrorImpl implements LibraryMirror {
  LibraryMirrorImpl(this.simpleName, this.uri, this.getters, this.setters,
      List<Object> metadata)
      : _metadata =
            metadata == null ? null : new UnmodifiableListView(metadata);

  final Uri uri;

  Map<String, DeclarationMirror> get declarations => _unsupported();

  @override
  final String simpleName;

  final Map<String, _StaticGetter> getters;
  final Map<String, _StaticSetter> setters;

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    _StaticGetter getter = getters[memberName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(
          null, memberName, positionalArguments, namedArguments);
    }
    return Function.apply(
        getters[memberName](), positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String getterName) {
    _StaticGetter getter = getters[getterName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(null, getterName, [], {});
    }
    return getter();
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    _StaticSetter setter = setters[setterName];
    if (setter == null) {
      throw new NoSuchInvokeCapabilityError(null, setterName, [value], {});
    }
    return setter(value);
  }

  @override
  bool get isPrivate => false;

  @override
  bool get isTopLevel => false;

  @override
  SourceLocation get location => null;

  final List<Object> _metadata;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of library '$simpleName' without capability");
    }
    return _metadata;
  }

  @override
  DeclarationMirror get owner => null;

  @override
  String get qualifiedName => simpleName;

  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();

  // TODO(sigurdm) implement: Need to implement this. Probably only when a given
  // capability is enabled.
  List<LibraryDependencyMirror> get libraryDependencies => _unsupported();
}

class MethodMirrorImpl extends _DataCaching implements MethodMirror {
  /// An encoding of the attributes and kind of this mirror.
  final int _descriptor;

  /// The name of this method. Setters names will end in '='.
  final String _name;

  /// The index of the [ClassMirror] of the owner of this method,
  final int _ownerIndex;

  /// The index of the return type of this method.
  final int _returnTypeIndex;

  /// The indices of the [ParameterMirror]s describing the formal parameters
  /// of this method.
  final List<int> _parameterIndices;

  /// The [Reflectable] associated with this mirror.
  final ReflectableImpl _reflector;

  /// A cache of the metadata of the mirrored method. The empty list means
  /// no metadata, null means that [_reflector] does not have
  /// [metadataCapability].
  final List<Object> _metadata;

  MethodMirrorImpl(
      this._name,
      this._descriptor,
      this._ownerIndex,
      this._returnTypeIndex,
      this._parameterIndices,
      this._reflector,
      List<Object> metadata)
      : _metadata =
            (metadata == null) ? null : new UnmodifiableListView(metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  ClassMirror get owner => _data.classMirrors[_ownerIndex];

  @override
  String get constructorName => isConstructor ? _name : "";

  @override
  bool get isAbstract => (_descriptor & constants.abstractAttribute != 0);

  @override
  bool get isConstConstructor => (_descriptor & constants.constAttribute != 0);

  @override
  bool get isConstructor => isFactoryConstructor || isGenerativeConstructor;

  @override
  bool get isFactoryConstructor => kind == constants.factoryConstructor;

  @override
  bool get isGenerativeConstructor => kind == constants.generativeConstructor;

  @override
  bool get isGetter => kind == constants.getter;

  @override
  bool get isOperator => isRegularMethod &&
      ["+", "-", "*", "/", "[", "<", ">", "=", "~", "%"].contains(_name[0]);

  @override
  bool get isPrivate => (_descriptor & constants.privateAttribute != 0);

  @override
  bool get isRedirectingConstructor =>
      (_descriptor & constants.redirectingConstructorAttribute != 0);

  @override
  bool get isRegularMethod => kind == constants.method;

  @override
  bool get isSetter => kind == constants.setter;

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isSynthetic => (_descriptor & constants.syntheticAttribute != 0);

  @override
  bool get isTopLevel => owner is LibraryMirror;

  bool get _hasDynamicReturnType =>
      (_descriptor & constants.dynamicReturnTypeAttribute != 0);

  bool get _hasClassReturnType =>
      (_descriptor & constants.classReturnTypeAttribute != 0);

  bool get _hasVoidReturnType =>
      (_descriptor & constants.voidReturnTypeAttribute != 0);

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of method '$simpleName' without capability");
    }
    return _metadata;
  }

  @override
  List<ParameterMirror> get parameters {
    return _parameterIndices
        .map((int parameterIndex) => _data.parameterMirrors[parameterIndex])
        .toList();
  }

  @override
  String get qualifiedName => "${owner.qualifiedName}.$_name";

  @override
  TypeMirror get returnType {
    if (_returnTypeIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Requesting returnType of method '$simpleName' without capability");
    }
    if (_hasDynamicReturnType) return new DynamicMirrorImpl();
    if (_hasVoidReturnType) return new VoidMirrorImpl();
    if (_hasClassReturnType) return _data.classMirrors[_returnTypeIndex];
    // TODO(eernst) implement: Support remaining kinds of types.
    return _unsupported();
  }

  @override
  String get simpleName => isConstructor
      ? (_name == '' ? "${owner.simpleName}" : "${owner.simpleName}.$_name")
      : _name;

  @override
  String get source => null;

  @override
  String toString() => "MethodMirrorImpl($qualifiedName)";
}

abstract class ImplicitAccessorMirrorImpl extends _DataCaching
    implements MethodMirror {
  final ReflectableImpl _reflector;
  final int _variableMirrorIndex;

  /// Index of this [ImplicitAccessorMirrorImpl] in `_data.memberMirrors`.
  final int _selfIndex;

  VariableMirrorImpl get _variableMirror =>
      _data.memberMirrors[_variableMirrorIndex];

  ImplicitAccessorMirrorImpl(
      this._reflector, this._variableMirrorIndex, this._selfIndex);

  int get kind => constants.kindFromEncoding(_variableMirror._descriptor);

  ClassMirror get owner => _variableMirror.owner;

  @override
  String get constructorName => "";

  @override
  bool get isAbstract => false;

  @override
  bool get isConstConstructor => false;

  @override
  bool get isConstructor => false;

  @override
  bool get isFactoryConstructor => false;

  @override
  bool get isGenerativeConstructor => false;

  @override
  bool get isOperator => false;

  @override
  bool get isPrivate => _variableMirror.isPrivate;

  @override
  bool get isRedirectingConstructor => false;

  @override
  bool get isRegularMethod => false;

  @override
  bool get isStatic => _variableMirror.isStatic;

  @override
  bool get isSynthetic => true;

  @override
  bool get isTopLevel => false;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata => <Object>[];

  @override
  TypeMirror get returnType => _variableMirror.type;

  @override
  String get source => null;
}

class ImplicitGetterMirrorImpl extends ImplicitAccessorMirrorImpl {
  ImplicitGetterMirrorImpl(
      ReflectableImpl reflector, int variableMirrorIndex, int selfIndex)
      : super(reflector, variableMirrorIndex, selfIndex);

  @override
  bool get isGetter => true;

  @override
  bool get isSetter => false;

  @override
  List<ParameterMirror> get parameters => <ParameterMirror>[];

  @override
  String get qualifiedName => _variableMirror.qualifiedName;

  @override
  String get simpleName => _variableMirror.simpleName;

  @override
  String toString() => "ImplicitGetterMirrorImpl($qualifiedName)";
}

class ImplicitSetterMirrorImpl extends ImplicitAccessorMirrorImpl {
  ImplicitSetterMirrorImpl(
      ReflectableImpl reflector, int variableMirrorIndex, int selfIndex)
      : super(reflector, variableMirrorIndex, selfIndex);

  @override
  bool get isGetter => false;

  @override
  bool get isSetter => true;

  int get _parameterDescriptor {
    int descriptor = constants.parameter;
    if (_variableMirror.isStatic) descriptor |= constants.staticAttribute;
    if (_variableMirror.isPrivate) descriptor |= constants.privateAttribute;
    descriptor |= constants.syntheticAttribute;
    if (_variableMirror._isDynamic) descriptor |= constants.dynamicAttribute;
    if (_variableMirror._isClassType) descriptor |=
        constants.classTypeAttribute;
    return descriptor;
  }

  @override
  List<ParameterMirror> get parameters {
    return <ParameterMirror>[
      new ParameterMirrorImpl(
          _variableMirror.simpleName,
          _parameterDescriptor,
          _selfIndex,
          _variableMirror._reflector,
          _variableMirror._classMirrorIndex,
          <Object>[],
          null)
    ];
  }

  @override
  String get qualifiedName => "${_variableMirror.qualifiedName}=";

  @override
  String get simpleName => "${_variableMirror.simpleName}=";

  @override
  String toString() => "ImplicitSetterMirrorImpl($qualifiedName)";
}

abstract class VariableMirrorBase extends _DataCaching
    implements VariableMirror {
  final String _name;
  final int _descriptor;
  final int _ownerIndex;
  final ReflectableImpl _reflector;
  final _classMirrorIndex;
  final List<Object> _metadata;

  VariableMirrorBase(this._name, this._descriptor, this._ownerIndex,
      this._reflector, this._classMirrorIndex, List<Object> metadata)
      : _metadata =
            (metadata == null) ? null : new UnmodifiableListView(metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  @override
  bool get isPrivate => (_descriptor & constants.privateAttribute != 0);

  @override
  bool get isTopLevel => owner is LibraryMirror;

  @override
  bool get isFinal => (_descriptor & constants.finalAttribute != 0);

  bool get _isDynamic => (_descriptor & constants.dynamicAttribute != 0);

  bool get _isClassType => (_descriptor & constants.classTypeAttribute != 0);

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of field '$simpleName' without capability");
    }
    return _metadata;
  }

  @override
  bool operator ==(other) => _unsupported();

  @override
  int get hashCode => _unsupported();

  @override
  String get simpleName => _name;

  @override
  String get qualifiedName => "${owner.qualifiedName}.$_name";

  @override
  TypeMirror get type {
    if (_classMirrorIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Attempt to get class mirror for un-marked class (type of '$_name')");
    }
    if (_isDynamic) return new DynamicMirrorImpl();
    if (_isClassType) {
      return _data.classMirrors[_classMirrorIndex];
    }
    // TODO(eernst) implement: Support remaining kinds of types.
    return _unsupported();
  }
}

class VariableMirrorImpl extends VariableMirrorBase {
  @override
  ClassMirror get owner => _data.classMirrors[_ownerIndex];

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isConst => (_descriptor & constants.constAttribute != 0);

  VariableMirrorImpl(String name, int descriptor, int ownerIndex,
      ReflectableImpl reflectable, int classMirrorIndex, List<Object> metadata)
      : super(name, descriptor, ownerIndex, reflectable, classMirrorIndex,
            metadata);
}

class ParameterMirrorImpl extends VariableMirrorBase
    implements ParameterMirror {
  @override
  final defaultValue;

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isConst => (_descriptor & constants.constAttribute != 0);

  @override
  bool get hasDefaultValue =>
      (_descriptor & constants.hasDefaultValueAttribute != 0);

  @override
  bool get isOptional => (_descriptor & constants.optionalAttribute != 0);

  @override
  bool get isNamed => (_descriptor & constants.namedAttribute != 0);

  @override
  MethodMirror get owner => _data.memberMirrors[_ownerIndex];

  ParameterMirrorImpl(
      String name,
      int descriptor,
      int ownerIndex,
      ReflectableImpl reflectable,
      classMirrorIndex,
      List<Object> metadata,
      this.defaultValue)
      : super(name, descriptor, ownerIndex, reflectable, classMirrorIndex,
            metadata);
}

class DynamicMirrorImpl implements TypeMirror {
  @override
  bool get isPrivate => false;

  @override
  bool get isTopLevel => true;

  // TODO(eernst) implement: test what 'dart:mirrors' does, then do the same.
  @override
  bool get isOriginalDeclaration => true;

  @override
  bool get hasReflectedType => true;

  @override
  Type get reflectedType => dynamic;

  @override
  String get simpleName => "dynamic";

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  List<TypeVariableMirror> get typeVariables => <TypeVariableMirror>[];

  @override
  List<TypeMirror> get typeArguments => <TypeMirror>[];

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  TypeMirror get originalDeclaration => null;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  bool isSubtypeOf(TypeMirror other) => true;

  @override
  bool isAssignableTo(TypeMirror other) => true;

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  @override
  DeclarationMirror get owner => null;

  @override
  String get qualifiedName => simpleName;

  @override
  List<Object> get metadata => <Object>[];
}

class VoidMirrorImpl implements TypeMirror {
  @override
  bool get isPrivate => false;

  @override
  bool get isTopLevel => true;

  // TODO(eernst) implement: test what 'dart:mirrors' does, then do the same.
  @override
  bool get isOriginalDeclaration => true;

  @override
  bool get hasReflectedType => false;

  @override
  Type get reflectedType => throw new NoSuchCapabilityError(
      "Attempt to get the reflected type of 'void'");

  @override
  String get simpleName => "void";

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  List<TypeVariableMirror> get typeVariables => <TypeVariableMirror>[];

  @override
  List<TypeMirror> get typeArguments => <TypeMirror>[];

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  TypeMirror get originalDeclaration => null;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  // TODO(eernst) clarify: check the spec!
  @override
  bool isSubtypeOf(TypeMirror other) => other is DynamicMirrorImpl;

  // TODO(eernst) clarify: check the spec!
  @override
  bool isAssignableTo(TypeMirror other) => other is DynamicMirrorImpl;

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  @override
  DeclarationMirror get owner => null;

  @override
  String get qualifiedName => simpleName;

  @override
  List<Object> get metadata => <Object>[];
}

abstract class ReflectableImpl extends ReflectableBase
    implements ReflectableInterface {
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

  @override
  InstanceMirror reflect(Object reflectee) {
    return new _InstanceMirrorImpl(reflectee, this);
  }

  @override
  bool canReflect(Object reflectee) {
    return data[this].classMirrorForType(reflectee.runtimeType) != null;
  }

  @override
  ClassMirror reflectType(Type type) {
    ClassMirror result = data[this].classMirrorForType(type);
    if (result == null) {
      throw new NoSuchCapabilityError(
          "Reflecting on type '$type' without capability");
    }
    return result;
  }

  @override
  bool canReflectType(Type type) {
    return data[this].classMirrorForType(type) != null;
  }

  @override
  LibraryMirror findLibrary(String libraryName) {
    if (data[this].libraryMirrors == null) {
      throw new NoSuchCapabilityError(
          "Using 'findLibrary' without capability. "
          "Try adding 'libraryCapability'.");
    }
    return data[this].libraryMirrors.singleWhere(
        (LibraryMirror mirror) => mirror.qualifiedName == libraryName);
  }

  @override
  Map<Uri, LibraryMirror> get libraries => _unsupported();

  @override
  Iterable<ClassMirror> get annotatedClasses {
    return new UnmodifiableListView<ClassMirror>(data[this].classMirrors);
  }
}

// For mixin-applications we need to construct objects that represents their
// type.
class FakeType implements Type {
  const FakeType(this.description);

  final String description;

  String toString() => "Type($description)";
}
