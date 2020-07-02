// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.reflectable_builder_based;

import 'dart:collection' show UnmodifiableMapView;

import '../capability.dart';
import '../mirrors.dart';
import '../reflectable.dart';
import 'encoding_constants.dart' as constants;
import 'encoding_constants.dart' show NO_CAPABILITY_INDEX;
import 'incompleteness.dart';
import 'reflectable_base.dart';

// ignore_for_file: omit_local_variable_types

/// Returns the set of reflectors in the current program. Note that it only
/// returns reflectors matching something---a reflector that does not match
/// anything is not even given a mapping in `data`. This makes sense because
/// a reflector that does not match anything is rather useless.
Set<Reflectable> get reflectors => data.keys.toSet();

// Mirror classes with default implementations of all methods, to be used as
// superclasses of builder generated static mirror classes.  They serve to
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

/// Invokes a getter on an object.
typedef _InvokerOfGetter = Object Function(Object instance);

/// Invokes a setter on an object.
typedef _InvokerOfSetter = Object Function(Object instance, Object value);

/// Invokes a static getter.
typedef _StaticGetter = Object Function();

/// Invokes a setter on an object.
typedef _StaticSetter = Object Function(Object value);

/// The data backing a reflector.
class ReflectorData {
  /// List of type mirrors, one [ClassMirror] for each class that is
  /// supported by reflection as specified by the reflector backed up
  /// by this [ReflectorData], and one [TypeVariableMirror] for each
  /// type variable declared by those classes.
  final List<TypeMirror> typeMirrors;

  /// List of library mirrors, one library mirror for each library that is
  /// supported by reflection as specified by the reflector backed up
  /// by this [ReflectorData].
  final List<LibraryMirror> libraryMirrors;

  /// Repository of method mirrors used (via indices into this list) by the
  /// class mirrors in [typeMirrors] to describe the behavior of the mirrored
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

  /// List of [Type]s divided into two parts. At the low indices until
  /// [supportedClassCount], it is a list of [Type]s used to select class
  /// mirrors: If M is a class mirror in [typeMirrors] at index `i`, the
  /// mirrored class (and hence the runtime type of the mirrored instances)
  /// is found in `types[i]`. At indices greater than or equal to
  /// [supportedClassCount], it is a list of [Type]s used to provide a value
  /// for `dynamicReflectedType` and `dynamicReflectedReturnType`.
  final List<Type> types;

  /// Number of entries in [types] describing supported classes
  final int supportedClassCount;

  /// Map from getter names to closures accepting an instance and returning
  /// the result of invoking the getter with that name on that instance.
  final Map<String, _InvokerOfGetter> getters;

  /// Map from setter names to closures accepting an instance and a new value,
  /// invoking the setter of that name on that instance, and returning its
  /// return value.
  final Map<String, _InvokerOfSetter> setters;

  /// List of parameter list shapes. Each entry is a list containing data on
  /// one shape of parameter list. The same shape is shared, e.g., by methods
  /// like `void foo(int a, [String b])` and `List bar(x, [y])` because the
  /// shape is independent of type annotations and names, and only describes
  /// the number and kind of parameters. It is represented as a list containing
  /// three elements: An `int` specifying the number of positional parameters,
  /// an `int` describing the number of optional positional parameters, and a
  /// `List` containing `Symbol` values for the names of named parameters.
  final List<List> parameterListShapes;

  Map<Type, ClassMirror> _typeToClassMirrorCache;

  ReflectorData(
      this.typeMirrors,
      this.memberMirrors,
      this.parameterMirrors,
      this.types,
      this.supportedClassCount,
      this.getters,
      this.setters,
      this.libraryMirrors,
      this.parameterListShapes);

  /// Returns a class-mirror for the given [type].
  ///
  /// Returns `null` if the given class is not marked for reflection.
  ClassMirror classMirrorForType(Type type) {
    if (_typeToClassMirrorCache == null) {
      if (typeMirrors.isEmpty) {
        // This is the case when the capabilities do not include a
        // `TypeCapability`; it is also the case when there are no
        // supported classes. In both cases the empty map is correct.
        _typeToClassMirrorCache = <Type, ClassMirror>{};
      } else {
        // Note that [types] corresponds to the prefix of [typeMirrors] which
        // are class mirrors; [typeMirrors] continues with type variable
        // mirrors, and they are irrelevant here.
        Iterable<ClassMirror> classMirrors() sync* {
          for (TypeMirror typeMirror
              in typeMirrors.sublist(0, supportedClassCount)) {
            yield typeMirror;
          }
        }

        _typeToClassMirrorCache = Map<Type, ClassMirror>.fromIterables(
            types.sublist(0, supportedClassCount), classMirrors());
      }
    }
    return _typeToClassMirrorCache[type];
  }

  ClassMirror classMirrorForInstance(Object instance) {
    ClassMirror result = classMirrorForType(instance.runtimeType);
    if (result != null) return result;
    // Check if we have a generic class that matches.
    for (ClassMirror classMirror in _typeToClassMirrorCache.values) {
      if (classMirror is GenericClassMirrorImpl) {
        if (classMirror._isGenericRuntimeTypeOf(instance)) {
          return _createInstantiatedGenericClass(
              classMirror, instance.runtimeType, null);
        }
      }
    }
    // Inform the caller that this object has no coverage.
    return null;
  }
}

const String pleaseInitializeMessage = 'Reflectable has not been initialized.\n'
    'Please make sure that the first action taken by your program\n'
    'in `main` is to call `initializeReflectable()`.';

/// This mapping contains the mirror-data for each reflector.
/// It will be initialized in the generated code.
Map<Reflectable, ReflectorData> data =
    throw StateError(pleaseInitializeMessage);

/// This mapping translates symbols to strings for the covered members.
/// It will be initialized in the generated code.
Map<Symbol, String> memberSymbolMap = throw StateError(pleaseInitializeMessage);

abstract class _DataCaching {
  // TODO(eernst) clarify: When we have some substantial pieces of code using
  // reflectable, perform some experiments to detect how useful it is to have
  // this kind of caching.

  ReflectorData _dataCache;
  ReflectableImpl get _reflector;

  ReflectorData get _data {
    if (_dataCache == null) {
      _dataCache = data[_reflector];
      // We should never call this method except from a mirror, and we should
      // never have a mirror unless it has a reflector, so it should never be
      // null.
      assert(_dataCache != null);
    }
    return _dataCache;
  }
}

class _InstanceMirrorImpl extends _DataCaching implements InstanceMirror {
  @override
  final ReflectableImpl _reflector;

  @override
  final Object reflectee;

  _InstanceMirrorImpl(this.reflectee, this._reflector) {
    _type = _data.classMirrorForInstance(reflectee);
    if (_type == null) {
      // If there is no `TypeCapability` and also no `InstanceInvokeCapability`
      // then can do almost nothing. Nevertheless, we can still offer a
      // mirror; at least, it can return its [reflectee], which is also the
      // only thing the given capabilities will justify. However, we should
      // not offer an instance mirror (even such a very weak one) for a
      // completely unsupported class, so we still insist that the runtime
      // type of the reflectee is known.
      if (!_data.types.contains(reflectee.runtimeType)) {
        throw NoSuchCapabilityError(
            'Reflecting on un-marked type "${reflectee.runtimeType}"');
      }
    }
  }

  bool get _supportsType => _reflector._hasTypeCapability;

  ClassMirrorBase _type;

  @override
  ClassMirror get type {
    if (!_supportsType) {
      throw NoSuchCapabilityError(
          'Attempt to get `type` without `TypeCapability`.');
    }
    return _type;
  }

  @override
  Object invoke(String methodName, List<Object> positionalArguments,
      [Map<Symbol, Object> namedArguments]) {
    void fail() {
      // It could be a method that exists but the given capabilities rejected
      // it, it could be a method that does not exist at all, or it could be
      // a non-conforming argument list shape. In all cases we consider the
      // invocation to be a capability violation.
      throw reflectableNoSuchMethodError(
          reflectee, methodName, positionalArguments, namedArguments);
    }

    // Obtain the tear-off closure for the method that we will invoke.
    Function methodTearer = _data.getters[methodName];
    // If not found then we definitely have a no-such-method event.
    if (methodTearer == null) fail();
    // The tear-off exists, but we may still call it incorrectly, so we need
    // to check its parameter list shape.
    if (_type == null) {
      // There is no information about the parameter list shape, so we should
      // never generate code that brings us to this location: Every kind of
      // invocation capability should force at least some level of class mirror
      // support.
      throw unreachableError('Attempt to `invoke` without class mirrors');
    }
    if (!_type._checkInstanceParameterListShape(
        methodName, positionalArguments.length, namedArguments?.keys)) {
      fail();
    }
    return Function.apply(
        methodTearer(reflectee), positionalArguments, namedArguments);
  }

  @override
  bool get hasReflectee => true;

  @override
  bool operator ==(other) {
    return other is _InstanceMirrorImpl &&
        other._reflector == _reflector &&
        other.reflectee == reflectee;
  }

  @override
  int get hashCode => _reflector.hashCode ^ reflectee.hashCode;

  @override
  dynamic delegate(Invocation invocation) {
    void fail() {
      StringInvocationKind kind = invocation.isGetter
          ? StringInvocationKind.getter
          : (invocation.isSetter
              ? StringInvocationKind.setter
              : StringInvocationKind.method);
      // TODO(eernst) implement: Pass the de-minified `memberName` string, if
      // get support for translating arbitrary symbols to strings (the caller
      // could use `new Symbol(..)` so we cannot assume that this symbol is
      // known).
      throw reflectableNoSuchInvokableError(
          reflectee,
          '${invocation.memberName}',
          invocation.positionalArguments,
          invocation.namedArguments,
          kind);
    }

    if (memberSymbolMap == null) {
      throw NoSuchCapabilityError(
          'Attempt to `delegate` without `delegateCapability`');
    }
    String memberName = memberSymbolMap[invocation.memberName];
    if (memberName == null) {
      // No such `memberName`. It could be a method that exists but the given
      // capabilities rejected it, or it could be a method that does not exist
      // at all. In both cases we consider the invocation to be a capability
      // violation.
      fail();
    }
    if (invocation.isGetter) {
      if (invocation.positionalArguments.isNotEmpty ||
          invocation.namedArguments.isNotEmpty) {
        fail();
      }
      return invokeGetter(memberName);
    } else if (invocation.isSetter) {
      if (invocation.positionalArguments.length != 1 ||
          invocation.namedArguments.isNotEmpty) {
        fail();
      }
      return invokeSetter(memberName, invocation.positionalArguments[0]);
    } else {
      return invoke(memberName, invocation.positionalArguments,
          invocation.namedArguments);
    }
  }

  @override
  Object invokeGetter(String getterName) {
    Function getter = _data.getters[getterName];
    if (getter != null) {
      return getter(reflectee);
    }
    // No such `getter`. It could be a method that exists but the given
    // capabilities rejected it, or it could be a method that does not exist
    // at all. In both cases we consider the invocation to be a capability
    // violation.
    throw reflectableNoSuchGetterError(reflectee, getterName, [], {});
  }

  @override
  Object invokeSetter(String name, Object value) {
    String setterName =
        _isSetterName(name) ? name : _getterNameToSetterName(name);
    Function setter = _data.setters[setterName];
    if (setter != null) {
      return setter(reflectee, value);
    }
    // No such `setter`. It could be a method that exists but the given
    // capabilities rejected it, or it could be a method that does not exist
    // at all. In both cases we consider the invocation to be a capability
    // violation.
    throw reflectableNoSuchSetterError(reflectee, setterName, [value], {});
  }
}

typedef MethodMirrorProvider = MethodMirror Function(String methodName);

abstract class ClassMirrorBase extends _DataCaching implements ClassMirror {
  /// The reflector which represents the mirror system that this
  /// mirror belongs to.
  @override
  final ReflectableImpl _reflector;

  /// An encoding of the attributes and kind of this class mirror.
  final int _descriptor;

  /// The index of this mirror in [ReflectorData.typeMirrors]. This is also
  /// the index of the Type of the reflected class in [ReflectorData.types].
  final int _classIndex;

  /// The index of the owner library in the [ReflectorData.libraryMirrors]
  /// table.
  final int _ownerIndex;

  /// The index of the mirror of the superclass in [ReflectorData.typeMirrors].
  final int _superclassIndex;

  /// The index of the mixin of this class in [ReflectorData.typeMirrors].
  ///
  /// For classes that are not mixin-applications this is the same as the class
  /// itself.
  final int _mixinIndex;

  @override
  List<ClassMirror> get superinterfaces {
    if (_superinterfaceIndices.length == 1 &&
        _superinterfaceIndices[0] == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError(
          'Requesting `superinterfaces` of `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return _superinterfaceIndices.map<ClassMirror>((int i) {
      if (i == NO_CAPABILITY_INDEX) {
        // When we have a list of superinterfaces which is not a list
        // containing just the single element [NO_CAPABILITY_INDEX] then
        // we do have the `typeRelationsCapability`, but we may still
        // encounter a single unsupported superinterface.
        throw NoSuchCapabilityError(
            'Requesting a superinterface of `$qualifiedName` '
            'without capability');
      }
      return _data.typeMirrors[i];
    }).toList();
  }

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

  /// A list of the indices in [ReflectorData.typeMirrors] of the
  /// superinterfaces of the reflected class.
  final List<int> _superinterfaceIndices;

  @override
  final String simpleName;

  @override
  final String qualifiedName;

  final List<Object> _metadata;
  final Map<String, _StaticGetter> _getters;
  final Map<String, _StaticSetter> _setters;
  final Map<String, Function> _constructors;
  final Map<String, int> _parameterListShapes;

  ClassMirrorBase(
      this.simpleName,
      this.qualifiedName,
      this._descriptor,
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
      this._metadata,
      this._parameterListShapes);

  @override
  bool get isAbstract => (_descriptor & constants.abstractAttribute != 0);

  Map<String, DeclarationMirror> _declarations;

  @override
  Map<String, DeclarationMirror> get declarations {
    if (_declarations == null) {
      Map<String, DeclarationMirror> result = <String, DeclarationMirror>{};
      for (int declarationIndex in _declarationIndices) {
        // We encode a missing `declarations` capability as an index with
        // the value NO_CAPABILITY_INDEX. Note that `_declarations` will not be
        // initialized and hence we will come here repeatedly if that is the
        // case; however, performing operations for which there is no capability
        // need not have stellar performance, it is almost always a bug to do
        // that.
        if (declarationIndex == NO_CAPABILITY_INDEX) {
          throw NoSuchCapabilityError(
              'Requesting declarations of "$qualifiedName" without capability');
        }
        DeclarationMirror declarationMirror =
            _data.memberMirrors[declarationIndex];
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _declarations = UnmodifiableMapView<String, DeclarationMirror>(result);
    }
    return _declarations;
  }

  Map<String, MethodMirror> _instanceMembers;

  @override
  Map<String, MethodMirror> get instanceMembers {
    if (_instanceMembers == null) {
      if (_instanceMemberIndices == null) {
        throw NoSuchCapabilityError(
            'Requesting instanceMembers without `declarationsCapability`.');
      }
      Map<String, MethodMirror> result = <String, MethodMirror>{};
      for (int instanceMemberIndex in _instanceMemberIndices) {
        DeclarationMirror declarationMirror =
            _data.memberMirrors[instanceMemberIndex];
        assert(declarationMirror is MethodMirror);
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _instanceMembers = UnmodifiableMapView<String, MethodMirror>(result);
    }
    return _instanceMembers;
  }

  Map<String, MethodMirror> _staticMembers;

  @override
  Map<String, MethodMirror> get staticMembers {
    if (_staticMembers == null) {
      if (_staticMemberIndices == null) {
        throw NoSuchCapabilityError(
            'Requesting instanceMembers without `declarationsCapability`.');
      }
      Map<String, MethodMirror> result = <String, MethodMirror>{};
      for (int staticMemberIndex in _staticMemberIndices) {
        DeclarationMirror declarationMirror =
            _data.memberMirrors[staticMemberIndex];
        assert(declarationMirror is MethodMirror);
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _staticMembers = UnmodifiableMapView<String, MethodMirror>(result);
    }
    return _staticMembers;
  }

  @override
  ClassMirror get mixin {
    if (_mixinIndex == NO_CAPABILITY_INDEX) {
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to get `mixin` for `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError(
          'Attempt to get mixin from "$simpleName" without capability');
    }
    return _data.typeMirrors[_mixinIndex];
  }

  bool _checkParameterListShape(
      String methodName,
      int numberOfPositionalArguments,
      Iterable<Symbol> namedArgumentNames,
      MethodMirrorProvider methodMirrorProvider) {
    bool checkUsingShape(List parameterListShape,
        int numberOfPositionalArguments, Iterable<Symbol> namedArgumentNames) {
      assert(parameterListShape.length == 3);
      int numberOfPositionalParameters = parameterListShape[0];
      int numberOfOptionalPositionalParameters = parameterListShape[1];
      List namesOfNamedParameters = parameterListShape[2];
      // The length of the positional part of the argument list must be
      // within bounds.
      if (numberOfPositionalArguments <
              numberOfPositionalParameters -
                  numberOfOptionalPositionalParameters ||
          numberOfPositionalArguments > numberOfPositionalParameters) {
        return false;
      }
      // It is always OK to make a call without named arguments.
      if (namedArgumentNames == null || namedArgumentNames.isEmpty) return true;
      // We do have named arguments; check that they are all known.
      return namesOfNamedParameters == null
          ? false
          : namedArgumentNames
              .every((Symbol name) => namesOfNamedParameters.contains(name));
    }

    if (_parameterListShapes != null) {
      // We have the ready-to-use parameter list shape information; we check
      // for that first because it is preferred over the slower computation
      // based on declaration mirror traversal. Check whether [methodName]
      // is known.
      int shapeIndex = _parameterListShapes[methodName];
      // If [methodName] is unknown then there exists such a method in the
      // program, but not in the receiver class/instance; hence, the check has
      // failed.
      if (shapeIndex == null) return false;
      // There exists a method of the specified name, now check whether the
      // invocation received an argument list that it supports. It is a bug if
      // `shapeIndex` is out of range for `parameterListShapes`, but if that
      // happens the built-in range check will catch it.
      return checkUsingShape(_data.parameterListShapes[shapeIndex],
          numberOfPositionalArguments, namedArgumentNames);
    } else {
      // Without ready-to-use parameter list shape information we must compute
      // the shape from declaration mirrors.
      MethodMirror methodMirror = methodMirrorProvider(methodName);
      // If [methodName] is unknown to the [methodProvider] then there exists
      // such a method in the program, but not in the receiver class/instance;
      // hence, the check has failed.
      if (methodMirror == null) return false;
      if (methodMirror is ImplicitGetterMirrorImpl) {
        return numberOfPositionalArguments == 0 &&
            (namedArgumentNames == null || namedArgumentNames.isEmpty);
      } else if (methodMirror is ImplicitSetterMirrorImpl) {
        return numberOfPositionalArguments == 1 &&
            (namedArgumentNames == null || namedArgumentNames.isEmpty);
      }
      // We do not expect other kinds of method mirrors than the accessors and
      // `MethodMirrorImpl`
      MethodMirrorImpl methodMirrorImpl = methodMirror;
      // Let the [methodMirrorImpl] check it based on declaration mirrors.
      return methodMirrorImpl._isArgumentListShapeAppropriate(
          numberOfPositionalArguments, namedArgumentNames);
    }
  }

  bool _checkInstanceParameterListShape(String methodName,
      int numberOfPositionalArguments, Iterable<Symbol> namedArgumentNames) {
    return _checkParameterListShape(methodName, numberOfPositionalArguments,
        namedArgumentNames, (String name) => instanceMembers[name]);
  }

  bool _checkStaticParameterListShape(String methodName,
      int numberOfPositionalArguments, Iterable<Symbol> namedArgumentNames) {
    return _checkParameterListShape(methodName, numberOfPositionalArguments,
        namedArgumentNames, (String name) => staticMembers[name]);
  }

  @override
  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    void fail() {
      Type type = hasReflectedType ? reflectedType : null;
      throw reflectableNoSuchConstructorError(
          type, constructorName, positionalArguments, namedArguments);
    }

    Function constructor = _constructors['$constructorName'];
    if (constructor == null) fail();
    try {
      Function.apply(constructor(false), positionalArguments, namedArguments);
    } on NoSuchMethodError {
      fail();
    }
    return Function.apply(
        constructor(true), positionalArguments, namedArguments);
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    void fail() {
      throw reflectableNoSuchMethodError(
          reflectedType, memberName, positionalArguments, namedArguments);
    }

    _StaticGetter getter = _getters[memberName];
    if (getter == null) fail();
    if (!_checkStaticParameterListShape(
        memberName, positionalArguments.length, namedArguments?.keys)) {
      fail();
    }
    return Function.apply(getter(), positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String getterName) {
    _StaticGetter getter = _getters[getterName];
    if (getter == null) {
      throw reflectableNoSuchGetterError(reflectedType, getterName, [], {});
    }
    return getter();
  }

  @override
  Object invokeSetter(String name, Object value) {
    String setterName =
        _isSetterName(name) ? name : _getterNameToSetterName(name);
    _StaticSetter setter = _setters[setterName];
    if (setter == null) {
      throw reflectableNoSuchSetterError(
          reflectedType, setterName, [value], {});
    }
    return setter(value);
  }

  @override
  bool get isEnum => (_descriptor & constants.enumAttribute != 0);

  @override
  bool get isPrivate => (_descriptor & constants.privateAttribute != 0);

  // Classes are always toplevel.
  @override
  bool get isTopLevel => true;

  @override
  SourceLocation get location => throw UnsupportedError('location');

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      String description =
          hasReflectedType ? reflectedType.toString() : qualifiedName;
      throw NoSuchCapabilityError(
          'Requesting metadata of "$description" without capability');
    }
    return _metadata;
  }

  @override
  Function invoker(String memberName) {
    Function getter = _data.getters[memberName];
    if (getter == null) {
      throw reflectableNoSuchGetterError(reflectedType, memberName, [], {});
    }
    return getter;
  }

  @override
  bool isAssignableTo(TypeMirror other) {
    if (_superclassIndex == NO_CAPABILITY_INDEX) {
      // There are two possible reasons for this: (1) If we have no type
      // relations capability then the index will always be NO_CAPABILITY_INDEX.
      // (2) Even if we have the type relations capability then the superclass
      // may be un-covered. So we cannot tell the two apart based on index.
      // Note that the check for superclass access also applies to the access
      // to superinterfaces, that is, it is not necessary (nor useful) to check
      // for access to superinterfaces here.
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to evaluate `isAssignableTo` for `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError(
          'Attempt to evaluate `isAssignableTo` for `$qualifiedName` '
          'without capability.');
    }
    return _isSubtypeOf(other) ||
        (other is ClassMirrorBase && other._isSubtypeOf(this));
  }

  @override
  bool isSubtypeOf(TypeMirror other) {
    if (_superclassIndex == NO_CAPABILITY_INDEX) {
      // There are two possible reasons for this: (1) If we have no type
      // relations capability then the index will always be NO_CAPABILITY_INDEX.
      // (2) Even if we have the type relations capability then the superclass
      // may be un-covered. So we cannot tell the two apart based on index.
      // Note that the check for superclass access also applies to the access
      // to superinterfaces, that is, it is not necessary (nor useful) to check
      // for access to superinterfaces here.
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to evaluate `isSubtypeOf` for `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError(
          'Attempt to evaluate `isSubtypeOf` for `$qualifiedName` '
          'without capability.');
    }
    return _isSubtypeOf(other);
  }

  bool _isSubtypeOf(TypeMirror other) {
    // Decision reached due to reflexivity?
    if (other == this) return true;
    // Decision reached because hierarchy has been exhausted?
    if (superclass == null) return false;
    // Decision reached because it is the mixin which is a supertype.
    if (mixin != this) {
      // This class was created by application of `mixin` to a superclass.
      if (other == mixin) return true;
    }
    // Recursively test hierarchy over `superclass`.
    if (superclass._isSubtypeOf(other)) return true;
    // Recursively test hierarchy over remaining direct supertypes.
    return superinterfaces.any((ClassMirror classMirror) =>
        classMirror is ClassMirrorBase && classMirror._isSubtypeOf(other));
  }

  @override
  bool isSubclassOf(ClassMirror other) {
    if (_superclassIndex == NO_CAPABILITY_INDEX) {
      // There are two possible reasons for this: (1) If we have no type
      // relations capability then the index will always be NO_CAPABILITY_INDEX.
      // (2) Even if we have the type relations capability then the superclass
      // may be un-covered. So we cannot tell the two apart based on index.
      // Note that the check for superclass access also applies to the access
      // to superinterfaces, that is, it is not necessary (nor useful) to check
      // for access to superinterfaces here.
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to evaluate `isSubclassOf` for `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError(
          'Attempt to evaluate `isSubclassOf` for $qualifiedName '
          'without capability.');
    }
    return _isSubclassOf(other);
  }

  bool _isSubclassOf(ClassMirror other) {
    if (other is FunctionTypeMirror) {
      return false;
    }
    if (other is ClassMirror && this == other) {
      return true;
    } else if (superclass == null) {
      return false;
    } else {
      return superclass._isSubclassOf(other);
    }
  }

  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to get `owner` of `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError(
          'Trying to get owner of class `$qualifiedName` '
          'without `libraryCapability`');
    }
    return _data.libraryMirrors[_ownerIndex];
  }

  @override
  ClassMirrorBase get superclass {
    if (_superclassIndex == NO_CAPABILITY_INDEX) {
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to get `superclass` of `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError('Requesting mirror on un-marked class, '
          '`superclass` of `$qualifiedName`');
    }
    if (_superclassIndex == null) return null; // Superclass of [Object].
    return _data.typeMirrors[_superclassIndex];
  }

  @deprecated
  @override
  bool get hasBestEffortReflectedType =>
      hasReflectedType || hasDynamicReflectedType;

  @deprecated
  @override
  Type get bestEffortReflectedType =>
      hasReflectedType ? reflectedType : dynamicReflectedType;
}

class NonGenericClassMirrorImpl extends ClassMirrorBase {
  NonGenericClassMirrorImpl(
      String simpleName,
      String qualifiedName,
      int descriptor,
      int classIndex,
      ReflectableImpl reflector,
      List<int> declarationIndices,
      List<int> instanceMemberIndices,
      List<int> staticMemberIndices,
      int superclassIndex,
      Map<String, _StaticGetter> getters,
      Map<String, _StaticSetter> setters,
      Map<String, Function> constructors,
      int ownerIndex,
      int mixinIndex,
      List<int> superinterfaceIndices,
      List<Object> metadata,
      Map<String, int> parameterListShapes)
      : super(
            simpleName,
            qualifiedName,
            descriptor,
            classIndex,
            reflector,
            declarationIndices,
            instanceMemberIndices,
            staticMemberIndices,
            superclassIndex,
            getters,
            setters,
            constructors,
            ownerIndex,
            mixinIndex,
            superinterfaceIndices,
            metadata,
            parameterListShapes);

  @override
  List<TypeMirror> get typeArguments {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `typeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return const <TypeMirror>[];
  }

  @override
  List<Type> get reflectedTypeArguments {
    if (!_supportsTypeRelations(_reflector) ||
        !_supportsReflectedType(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `typeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability` or `reflectedTypeCapability`');
    }
    return const <Type>[];
  }

  @override
  List<TypeVariableMirror> get typeVariables {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to evaluate `typeVariables` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return const <TypeVariableMirror>[];
  }

  @override
  bool get isOriginalDeclaration => true;

  @override
  TypeMirror get originalDeclaration {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `originalDeclaration` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return this;
  }

  @override
  bool get hasReflectedType => true;

  @override
  Type get reflectedType => _data.types[_classIndex];

  @override
  bool get hasDynamicReflectedType => true;

  @override
  Type get dynamicReflectedType => reflectedType;

  // Because we take care to only ever create one instance for each
  // type/reflector-combination we can rely on the default `hashCode` and `==`
  // operations.

  @override
  String toString() => 'NonGenericClassMirrorImpl($qualifiedName)';
}

typedef InstanceChecker = bool Function(Object);

class GenericClassMirrorImpl extends ClassMirrorBase {
  /// Used to enable instance checks. Let O be an instance and let C denote the
  /// generic class modeled by this mirror. The check is then such that the
  /// result is true iff there exists a list of type arguments X1..Xk such that
  /// O is an instance of C<X1..Xk>. We can perform this check by checking that
  /// O is an instance of C<dynamic .. dynamic>, and O is not an instance
  /// of any of Dj<dynamic .. dynamic> for j in {1..n}, where D1..Dn is the
  /// complete set of classes in the current program which are direct,
  /// non-abstract subinterfaces of C (i.e., classes which directly `extends`
  /// or `implements` C, or their subtypes again in case they are abstract).
  /// The check is implemented by this function.
  final InstanceChecker _isGenericRuntimeTypeOf;

  final List<int> _typeVariableIndices;

  final int _dynamicReflectedTypeIndex;

  GenericClassMirrorImpl(
      String simpleName,
      String qualifiedName,
      int descriptor,
      int classIndex,
      ReflectableImpl reflector,
      List<int> declarationIndices,
      List<int> instanceMemberIndices,
      List<int> staticMemberIndices,
      int superclassIndex,
      Map<String, _StaticGetter> getters,
      Map<String, _StaticSetter> setters,
      Map<String, Function> constructors,
      int ownerIndex,
      int mixinIndex,
      List<int> superinterfaceIndices,
      List<Object> metadata,
      Map<String, int> parameterListShapes,
      this._isGenericRuntimeTypeOf,
      this._typeVariableIndices,
      this._dynamicReflectedTypeIndex)
      : super(
            simpleName,
            qualifiedName,
            descriptor,
            classIndex,
            reflector,
            declarationIndices,
            instanceMemberIndices,
            staticMemberIndices,
            superclassIndex,
            getters,
            setters,
            constructors,
            ownerIndex,
            mixinIndex,
            superinterfaceIndices,
            metadata,
            parameterListShapes);

  @override
  List<TypeMirror> get typeArguments {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `typeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    // This mirror represents the original declaration, so no actual type
    // arguments have been passed. By convention we represent this situation
    // by returning the empty list, as documented in mirrors.dart.
    return const <TypeMirror>[];
  }

  @override
  List<Type> get reflectedTypeArguments {
    if (!_supportsTypeRelations(_reflector) ||
        !_supportsReflectedType(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `reflectedTypeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability` or `reflectedTypeCapability`');
    }
    // This mirror represents the original declaration, so no actual type
    // arguments have been passed. By convention we represent this situation
    // by returning the empty list, as documented in mirrors.dart.
    return const <Type>[];
  }

  // The type variables declared by this generic class, in declaration order.
  // The value `null` means no capability. The empty list would mean no type
  // parameters, but the empty list does not occur: [this] mirror would then
  // model a non-generic class.
  @override
  List<TypeVariableMirror> get typeVariables {
    if (_typeVariableIndices == null) {
      if (!_supportsTypeRelations(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to evaluate `typeVariables` for `$qualifiedName` '
            'without `typeRelationsCapability`');
      }
      throw NoSuchCapabilityError(
          'Requesting type variables of `$qualifiedName` without capability');
    }
    List<TypeVariableMirror> result = <TypeVariableMirror>[];
    for (int typeVariableIndex in _typeVariableIndices) {
      TypeVariableMirror typeVariableMirror =
          _data.typeMirrors[typeVariableIndex];
      assert(typeVariableMirror is TypeVariableMirror);
      result.add(typeVariableMirror);
    }
    return List<TypeVariableMirror>.unmodifiable(result);
  }

  @override
  bool get isOriginalDeclaration => true;

  @override
  TypeMirror get originalDeclaration {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `originalDeclaration` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return this;
  }

  @override
  bool get hasReflectedType => false;

  @override
  Type get reflectedType {
    throw UnsupportedError('Attempt to obtain `reflectedType` '
        'from generic class `$qualifiedName`.');
  }

  @override
  bool get hasDynamicReflectedType => true;

  @override
  Type get dynamicReflectedType {
    if (_dynamicReflectedTypeIndex == NO_CAPABILITY_INDEX) {
      if (!_supportsReflectedType(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to evaluate `dynamicReflectedType` for `$qualifiedName` '
            'without `reflectedTypeCapability`');
      }
      throw NoSuchCapabilityError(
          'Attempt to get `dynamicReflectedType` for `$qualifiedName` '
          'without capability');
    }
    return _data.types[_dynamicReflectedTypeIndex];
  }

  // Because we take care to only ever create one instance for each
  // type/reflector-combination we can rely on the default `hashCode` and `==`
  // operations.

  @override
  String toString() => 'GenericClassMirrorImpl($qualifiedName)';
}

class InstantiatedGenericClassMirrorImpl extends ClassMirrorBase {
  final GenericClassMirrorImpl _originalDeclaration;
  final Type _reflectedType;

  // `_reflectedTypeArgumentIndices == null` means that the given situation is
  // not yet supported for method `reflectedTypeArguments`.
  final List<int> _reflectedTypeArgumentIndices;

  InstantiatedGenericClassMirrorImpl(
      String simpleName,
      String qualifiedName,
      int descriptor,
      int classIndex,
      ReflectableImpl reflector,
      List<int> declarationIndices,
      List<int> instanceMemberIndices,
      List<int> staticMemberIndices,
      int superclassIndex,
      Map<String, _StaticGetter> getters,
      Map<String, _StaticSetter> setters,
      Map<String, Function> constructors,
      int ownerIndex,
      int mixinIndex,
      List<int> superinterfaceIndices,
      List<Object> metadata,
      Map<String, int> parameterListShapes,
      this._originalDeclaration,
      this._reflectedType,
      this._reflectedTypeArgumentIndices)
      : super(
            simpleName,
            qualifiedName,
            descriptor,
            classIndex,
            reflector,
            declarationIndices,
            instanceMemberIndices,
            staticMemberIndices,
            superclassIndex,
            getters,
            setters,
            constructors,
            ownerIndex,
            mixinIndex,
            superinterfaceIndices,
            metadata,
            parameterListShapes);

  @override
  List<TypeMirror> get typeArguments {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `typeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return reflectedTypeArguments
        .map((Type type) => _reflector.reflectType(type))
        .toList();
  }

  @override
  List<Type> get reflectedTypeArguments {
    if (!_supportsTypeRelations(_reflector) ||
        !_supportsReflectedType(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `reflectedTypeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability` or `reflectedTypeCapability`');
    }
    if (_reflectedTypeArgumentIndices == null) {
      throw unimplementedError('reflectedTypeArguments');
    }
    return _reflectedTypeArgumentIndices
        .map((int index) => _data.types[index])
        .toList();
  }

  @override
  List<TypeVariableMirror> get typeVariables =>
      originalDeclaration.typeVariables;

  @override
  bool get isOriginalDeclaration => false;

  @override
  TypeMirror get originalDeclaration {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `originalDeclaration` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return _originalDeclaration;
  }

  @override
  bool get hasReflectedType => _reflectedType != null;

  @override
  Type get reflectedType {
    if (_reflectedType != null) {
      return _reflectedType;
    }
    throw UnsupportedError('Cannot provide `reflectedType` of '
        'instance of generic type `$simpleName`.');
  }

  @override
  bool get hasDynamicReflectedType =>
      _originalDeclaration.hasDynamicReflectedType;

  @override
  Type get dynamicReflectedType => _originalDeclaration.dynamicReflectedType;

  @override
  bool operator ==(other) {
    // The same object twice: Were obtained in the same context, must model the
    // same type, are equal.
    if (identical(other, this)) return true;
    // Other than the reflexive case, we only consider my own class.
    if (other is InstantiatedGenericClassMirrorImpl) {
      if (originalDeclaration != other.originalDeclaration) return false;
      if (_reflectedType != null && other._reflectedType != null) {
        return _reflectedType == other._reflectedType;
      } else {
        // There is no `_reflectedType` for one, the other, or both, so at
        // least one of class mirrors is existential (in the sense that we
        // know that it stands for an instantiated generic class, but we
        // have no way to obtain its actual type arguments). This means that
        // they may or may not stand for the same type.
        // TODO(eernst) clarify: What is the correct semantics actually here?
        // We could return `false`, indicating that the equality is not known
        // to hold (this is similar to what static analysis does for types:
        // "the value of this expression may not be of type T" so it does not
        // get type T in the subsequent analysis steps). We could also insist
        // that both `true` and `false` must be precise, and "maybe" must give
        // rise to an exception. We choose to return `false` because knowledge
        // that two types are equal may be relied upon when doing something
        // specific, whereas knowledge that two types are (maybe) unequal is
        // much more likely to cause some strategy to be dropped and turning
        // to the next possible strategy.
        return false;
      }
    } else {
      // This object is never equal to an instance which is not an
      // [InstantiatedGenericClassMirrorImpl].
      return false;
    }
  }

  // Note that this will equip some instances with the same [hashCode] even
  // though they are not equal according to `operator ==`, namely the ones
  // where both have no `_reflectedType`. This does not compromise correctness.
  @override
  int get hashCode => originalDeclaration.hashCode ^ _reflectedType.hashCode;

  @override
  String toString() => 'InstantiatedGenericClassMirrorImpl($qualifiedName)';
}

InstantiatedGenericClassMirrorImpl _createInstantiatedGenericClass(
    GenericClassMirrorImpl genericClassMirror,
    Type reflectedType,
    List<int> reflectedTypeArguments) {
  // TODO(eernst) implement: Pass a representation of type arguments to this
  // method, and create an instantiated generic class which includes that
  // information.
  return InstantiatedGenericClassMirrorImpl(
      genericClassMirror.simpleName,
      genericClassMirror.qualifiedName,
      genericClassMirror._descriptor,
      genericClassMirror._classIndex,
      genericClassMirror._reflector,
      genericClassMirror._declarationIndices,
      genericClassMirror._instanceMemberIndices,
      genericClassMirror._staticMemberIndices,
      genericClassMirror._superclassIndex,
      genericClassMirror._getters,
      genericClassMirror._setters,
      genericClassMirror._constructors,
      genericClassMirror._ownerIndex,
      genericClassMirror._mixinIndex,
      genericClassMirror._superinterfaceIndices,
      genericClassMirror._metadata,
      genericClassMirror._parameterListShapes,
      genericClassMirror,
      reflectedType,
      reflectedTypeArguments);
}

class TypeVariableMirrorImpl extends _DataCaching
    implements TypeVariableMirror {
  /// The simple name of this type variable.
  @override
  final String simpleName;

  /// The qualified name of this type variable, i.e., the qualified name of
  /// the declaring class followed by its simple name.
  @override
  final String qualifiedName;

  /// The reflector which represents the mirror system that this
  /// mirror belongs to.
  @override
  final ReflectableImpl _reflector;

  /// The index into [typeMirrors] of the upper bound of this type variable.
  /// The value [null] encodes that the upper bound is [dynamic].
  final int _upperBoundIndex;

  /// The index into [typeMirrors] of the class that declares this type
  /// variable.
  final int _ownerIndex;

  /// The metadata that is associated with this type variable. The empty list
  /// means no metadata, null means no capability.
  final List<Object> _metadata;

  TypeVariableMirrorImpl(this.simpleName, this.qualifiedName, this._reflector,
      this._upperBoundIndex, this._ownerIndex, this._metadata);

  @override
  bool get isStatic => false;

  @override
  TypeMirror get upperBound {
    if (_upperBoundIndex == null) return DynamicMirrorImpl();
    if (_upperBoundIndex == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError('Attempt to get `upperBound` from type '
          'variable mirror without capability.');
    }
    return _data.typeMirrors[_upperBoundIndex];
  }

  @override
  bool isAssignableTo(TypeMirror other) {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `isAssignableTo` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return upperBound.isSubtypeOf(other) || other.isSubtypeOf(this);
  }

  @override
  bool isSubtypeOf(TypeMirror other) {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `isSubtypeOf` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return upperBound.isSubtypeOf(other);
  }

  @override
  TypeMirror get originalDeclaration {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `originalDeclaration` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return this;
  }

  @override
  bool get isOriginalDeclaration => true;

  @override
  List<TypeMirror> get typeArguments {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `typeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return const <TypeMirror>[];
  }

  @override
  List<Type> get reflectedTypeArguments {
    if (!_supportsTypeRelations(_reflector) ||
        !_supportsReflectedType(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `reflectedTypeArguments` for `$qualifiedName` '
          'without `typeRelationsCapability` or `reflectedTypeCapability`');
    }
    return const <Type>[];
  }

  @override
  List<TypeVariableMirror> get typeVariables {
    if (!_supportsTypeRelations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to evaluate `typeVariables` for `$qualifiedName` '
          'without `typeRelationsCapability`');
    }
    return <TypeVariableMirror>[];
  }

  @override
  Type get reflectedType {
    throw UnsupportedError('Attempt to get `reflectedType` from type '
        'variable $simpleName');
  }

  @override
  bool get hasReflectedType => false;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw NoSuchCapabilityError('Attempt to get `metadata` from type '
          'variable $simpleName without capability');
    }
    return <Object>[];
  }

  @override
  SourceLocation get location => throw UnsupportedError('location');

  @override
  bool get isTopLevel => false;

  @override
  bool get isPrivate => false;

  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError(
          'Trying to get owner of type parameter `$qualifiedName` '
          'without capability');
    }
    return _data.typeMirrors[_ownerIndex];
  }
}

class LibraryMirrorImpl extends _DataCaching implements LibraryMirror {
  @override
  final ReflectableImpl _reflector;

  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// declarations of the reflected class. This includes method mirrors for
  /// top level functions of this library and it directly corresponds to
  /// `declarations`. Exception: When the given `_reflector.capabilities` do
  /// not support the operation `declarations`, this will be
  /// `<int>[NO_CAPABILITY_INDEX]`. It is enough to check that the list is
  /// non-empty and first element is NO_CAPABILITY_INDEX to detect this
  /// situation, because NO_CAPABILITY_INDEX` will otherwise never occur.
  final List<int> _declarationIndices;

  @override
  final Uri uri;

  @override
  final String simpleName;

  final Map<String, _StaticGetter> getters;
  final Map<String, _StaticSetter> setters;

  final Map<String, int> _parameterListShapes;

  LibraryMirrorImpl(
      this.simpleName,
      this.uri,
      this._reflector,
      this._declarationIndices,
      this.getters,
      this.setters,
      this._metadata,
      this._parameterListShapes);

  Map<String, DeclarationMirror> _declarations;

  @override
  Map<String, DeclarationMirror> get declarations {
    if (_declarations == null) {
      Map<String, DeclarationMirror> result = <String, DeclarationMirror>{};
      for (int declarationIndex in _declarationIndices) {
        // We encode a missing `declarations` capability as an index with
        // the value NO_CAPABILITY_INDEX. Note that `_declarations` will not be
        // initialized and hence we will come here repeatedly if that is the
        // case; however, performing operations for which there is no capability
        // need not have stellar performance, it is almost always a bug to do
        // that.
        if (declarationIndex == NO_CAPABILITY_INDEX) {
          throw NoSuchCapabilityError(
              'Requesting declarations of `$qualifiedName` without capability');
        }
        DeclarationMirror declarationMirror =
            _data.memberMirrors[declarationIndex];
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _data.typeMirrors.forEach((TypeMirror typeMirror) {
        if (typeMirror is ClassMirror && typeMirror.owner == this) {
          result[typeMirror.simpleName] = typeMirror;
        }
      });
      _declarations = UnmodifiableMapView<String, DeclarationMirror>(result);
    }
    return _declarations;
  }

  bool _checkParameterListShape(String memberName,
      int numberOfPositionalArguments, Iterable<Symbol> namedArgumentNames) {
    bool checkUsingShape(List parameterListShape,
        int numberOfPositionalArguments, Iterable<Symbol> namedArgumentNames) {
      assert(parameterListShape.length == 3);
      int numberOfPositionalParameters = parameterListShape[0];
      int numberOfOptionalPositionalParameters = parameterListShape[1];
      List namesOfNamedParameters = parameterListShape[2];
      if (numberOfPositionalArguments <
              numberOfPositionalParameters -
                  numberOfOptionalPositionalParameters ||
          numberOfPositionalArguments > numberOfPositionalParameters) {
        return false;
      }
      if (namedArgumentNames == null) return true;
      return namedArgumentNames
          .every((Symbol name) => namesOfNamedParameters.contains(name));
    }

    if (_parameterListShapes != null) {
      // We have the ready-to-use parameter list shape information; we check
      // for that first because it is preferred over the slower computation
      // based on declaration mirror traversal. Check whether [methodName]
      // is known.
      int shapeIndex = _parameterListShapes[memberName];
      // If [methodName] is unknown then there exists such a method in the
      // program, but not in the receiver class/instance; hence, the check has
      // failed.
      if (shapeIndex == null) return false;
      // There exists a method of the specified name, now check whether the
      // invocation received an argument list that it supports. It is a bug if
      // `shapeIndex` is out of range for `parameterListShapes`, but if that
      // happens the built-in range check will catch it.
      return checkUsingShape(_data.parameterListShapes[shapeIndex],
          numberOfPositionalArguments, namedArgumentNames);
    } else {
      // Without ready-to-use parameter list shape information we must compute
      // the shape from declaration mirrors.
      DeclarationMirror declarationMirror = declarations[memberName];
      // If [memberName] is unknown then there exists such a member in the
      // program, but it is not in this library; the member may also be a
      // non-method; in these cases the the check has failed.
      if (declarationMirror == null || declarationMirror is! MethodMirror) {
        return false;
      }
      MethodMirror methodMirror = declarationMirror;
      if (methodMirror is ImplicitGetterMirrorImpl) {
        return numberOfPositionalArguments == 0 &&
            (namedArgumentNames == null || namedArgumentNames.isEmpty);
      } else if (methodMirror is ImplicitSetterMirrorImpl) {
        return numberOfPositionalArguments == 1 &&
            (namedArgumentNames == null || namedArgumentNames.isEmpty);
      }
      // We do not expect other kinds of method mirrors than the accessors and
      // `MethodMirrorImpl`
      MethodMirrorImpl methodMirrorImpl = methodMirror;
      // Let the [methodMirrorImpl] check it based on declaration mirrors.
      return methodMirrorImpl._isArgumentListShapeAppropriate(
          numberOfPositionalArguments, namedArgumentNames);
    }
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    void fail() {
      throw reflectableNoSuchMethodError(
          null, memberName, positionalArguments, namedArguments);
    }

    _StaticGetter getter = getters[memberName];
    if (getter == null) fail();
    if (!_checkParameterListShape(
        memberName, positionalArguments.length, namedArguments?.keys)) {
      fail();
    }
    return Function.apply(getter(), positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String getterName) {
    _StaticGetter getter = getters[getterName];
    if (getter == null) {
      throw reflectableNoSuchGetterError(null, getterName, [], {});
    }
    return getter();
  }

  @override
  Object invokeSetter(String name, Object value) {
    String setterName =
        _isSetterName(name) ? name : _getterNameToSetterName(name);
    _StaticSetter setter = setters[setterName];
    if (setter == null) {
      throw reflectableNoSuchSetterError(null, setterName, [value], {});
    }
    return setter(value);
  }

  /// A library cannot be private.
  @override
  bool get isPrivate => false;

  @override
  bool get isTopLevel => false;

  @override
  SourceLocation get location => throw UnsupportedError('location');

  final List<Object> _metadata;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw NoSuchCapabilityError(
          'Requesting metadata of library `$simpleName` without capability');
    }
    return _metadata;
  }

  @override
  DeclarationMirror get owner => null;

  @override
  String get qualifiedName => simpleName;

  @override
  bool operator ==(other) {
    return other is LibraryMirrorImpl &&
        other.uri == uri &&
        other._reflector == _reflector &&
        other._declarationIndices == _declarationIndices;
  }

  @override
  int get hashCode =>
      uri.hashCode ^ _reflector.hashCode ^ _declarationIndices.hashCode;

  // TODO(sigurdm) implement: Need to implement this, with the requirement that
  // a [LibraryCapability] must be available.
  @override
  List<LibraryDependencyMirror> get libraryDependencies =>
      throw unimplementedError('libraryDependencies');
}

class MethodMirrorImpl extends _DataCaching implements MethodMirror {
  /// An encoding of the attributes and kind of this mirror.
  final int _descriptor;

  /// The name of this method. Setter names will end in '='.
  final String _name;

  /// The index of the [ClassMirror] of the owner of this method, respectively
  /// the [LibraryMirror] of the owner of this top-level function,
  final int _ownerIndex;

  /// The index of the mirror for the return type of this method.
  final int _returnTypeIndex;

  /// The return type of this method.
  final int _reflectedReturnTypeIndex;

  /// The return type of this method, erased to have `dynamic` for all
  /// type arguments; a null value indicates that it is identical to
  /// `reflectedReturnType` if that value is available they are equal; if
  /// `reflectedReturnType` is unavailable then so is
  /// `dynamicReflectedReturnType`.
  final int _dynamicReflectedReturnTypeIndex;

  /// The [Type] values of the actual type arguments of the return type of this
  /// method, if supported. If the actual type arguments are not supported,
  /// [_reflectedTypeArgumentsOfReturnType] is null. The actual type arguments
  /// are not supported if they are not compile-time constant, e.g., if such an
  /// actual type argument is a type variable declared by the enclosing class.
  final List<int> _reflectedTypeArgumentsOfReturnType;

  /// The indices of the [ParameterMirror]s describing the formal parameters
  /// of this method.
  final List<int> _parameterIndices;

  /// The [Reflectable] associated with this mirror.
  @override
  final ReflectableImpl _reflector;

  /// The metadata of the mirrored method. The empty list means no metadata,
  /// null means that [_reflector] does not have
  /// [metadataCapability].
  final List<Object> _metadata;

  MethodMirrorImpl(
      this._name,
      this._descriptor,
      this._ownerIndex,
      this._returnTypeIndex,
      this._reflectedReturnTypeIndex,
      this._dynamicReflectedReturnTypeIndex,
      this._reflectedTypeArgumentsOfReturnType,
      this._parameterIndices,
      this._reflector,
      this._metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError(
          'Trying to get owner of method `$qualifiedName` '
          'without `LibraryCapability`');
    }
    return isTopLevel
        ? _data.libraryMirrors[_ownerIndex]
        : _data.typeMirrors[_ownerIndex];
  }

  @override
  String get constructorName => isConstructor ? _name : '';

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
  bool get isOperator =>
      isRegularMethod &&
      ['+', '-', '*', '/', '[', '<', '>', '=', '~', '%'].contains(_name[0]);

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
  bool get isTopLevel => (_descriptor & constants.topLevelAttribute != 0);

  bool get _hasDynamicReturnType =>
      (_descriptor & constants.dynamicReturnTypeAttribute != 0);

  bool get _hasClassReturnType =>
      (_descriptor & constants.classReturnTypeAttribute != 0);

  bool get _hasVoidReturnType =>
      (_descriptor & constants.voidReturnTypeAttribute != 0);

  bool get _hasGenericReturnType =>
      (_descriptor & constants.genericReturnTypeAttribute != 0);

  @override
  SourceLocation get location => throw UnsupportedError('location');

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw NoSuchCapabilityError(
          'Requesting metadata of method `$simpleName` without capability');
    }
    return _metadata;
  }

  @override
  List<ParameterMirror> get parameters {
    if (!_supportsDeclarations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `parameters` without `DeclarationsCapability`');
    }
    return _parameterIndices
        .map((int parameterIndex) => _data.parameterMirrors[parameterIndex])
        .toList();
  }

  @override
  String get qualifiedName => '${owner.qualifiedName}.$_name';

  @override
  TypeMirror get returnType {
    if (_returnTypeIndex == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError(
          'Requesting returnType of method `$simpleName` without capability');
    }
    if (_hasDynamicReturnType) return DynamicMirrorImpl();
    if (_hasVoidReturnType) return VoidMirrorImpl();
    if (_hasClassReturnType) {
      return _hasGenericReturnType
          ? _createInstantiatedGenericClass(_data.typeMirrors[_returnTypeIndex],
              null, _reflectedTypeArgumentsOfReturnType)
          : _data.typeMirrors[_returnTypeIndex];
    }
    throw unreachableError('Unexpected kind of returnType');
  }

  @override
  bool get hasReflectedReturnType =>
      _reflectedReturnTypeIndex != NO_CAPABILITY_INDEX;

  @override
  Type get reflectedReturnType {
    if (_reflectedReturnTypeIndex == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError('Requesting reflectedReturnType of method '
          '`$simpleName` without capability');
    }
    return _data.types[_reflectedReturnTypeIndex];
  }

  @override
  bool get hasDynamicReflectedReturnType =>
      _dynamicReflectedReturnTypeIndex != NO_CAPABILITY_INDEX ||
      hasReflectedReturnType;

  @override
  Type get dynamicReflectedReturnType {
    return _dynamicReflectedReturnTypeIndex != NO_CAPABILITY_INDEX
        ? _data.types[_dynamicReflectedReturnTypeIndex]
        : reflectedReturnType;
  }

  @override
  String get simpleName => isConstructor
      ? (_name == '' ? '${owner.simpleName}' : '${owner.simpleName}.$_name')
      : _name;

  @override
  String get source => null;

  void _setupParameterListInfo() {
    _numberOfPositionalParameters = 0;
    _numberOfOptionalPositionalParameters = 0;
    _namesOfNamedParameters = <Symbol>{};
    for (ParameterMirrorImpl parameterMirror in parameters) {
      if (parameterMirror.isNamed) {
        _namesOfNamedParameters.add(parameterMirror._nameSymbol);
      } else {
        _numberOfPositionalParameters++;
        if (parameterMirror.isOptional) {
          _numberOfOptionalPositionalParameters++;
        }
      }
    }
  }

  /// Returns the number of positional parameters of this method; computed
  /// from the given parameter mirrors, then cached.
  int get numberOfPositionalParameters {
    if (_numberOfPositionalParameters == null) _setupParameterListInfo();
    return _numberOfPositionalParameters;
  }

  /// Cache for the number of positional parameters of this method; `null`
  /// means not yet cached.
  int _numberOfPositionalParameters;

  /// Returns the number of optional positional parameters of this method;
  /// computed from the given parameter mirrors, then cached.
  int get numberOfOptionalPositionalParameters {
    if (_numberOfOptionalPositionalParameters == null) {
      _setupParameterListInfo();
    }
    return _numberOfOptionalPositionalParameters;
  }

  /// Cache for the number of optional positional parameters of this method;
  /// `null` means not yet cached.
  int _numberOfOptionalPositionalParameters;

  /// Returns the [Set] of [Symbol]s used for named parameters of this method;
  /// computed based on the given parameter mirrors, then cached.
  Set<Symbol> get namesOfNamedParameters {
    if (_namesOfNamedParameters == null) _setupParameterListInfo();
    return _namesOfNamedParameters;
  }

  /// Cache for the set of symbols used for named parameters for this method;
  /// `null` means not yet cached.
  Set<Symbol> _namesOfNamedParameters;

  bool _isArgumentListShapeAppropriate(
      int numberOfPositionalArguments, Iterable<Symbol> namedArgumentNames) {
    if (numberOfPositionalArguments <
            numberOfPositionalParameters -
                numberOfOptionalPositionalParameters ||
        numberOfPositionalArguments > numberOfPositionalParameters) {
      return false;
    }
    if (namedArgumentNames == null) return true;
    return namedArgumentNames
        .every((Symbol name) => namesOfNamedParameters.contains(name));
  }

  @override
  String toString() => 'MethodMirrorImpl($qualifiedName)';
}

abstract class ImplicitAccessorMirrorImpl extends _DataCaching
    implements MethodMirror {
  @override
  final ReflectableImpl _reflector;

  final int _variableMirrorIndex;

  /// Index of this [ImplicitAccessorMirrorImpl] in `_data.memberMirrors`.
  final int _selfIndex;

  VariableMirrorImpl get _variableMirror =>
      _data.memberMirrors[_variableMirrorIndex];

  ImplicitAccessorMirrorImpl(
      this._reflector, this._variableMirrorIndex, this._selfIndex);

  int get kind => constants.kindFromEncoding(_variableMirror._descriptor);

  @override
  DeclarationMirror get owner => _variableMirror.owner;

  @override
  String get constructorName => '';

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

  @override
  SourceLocation get location => throw UnsupportedError('location');

  @override
  List<Object> get metadata => <Object>[];

  @override
  TypeMirror get returnType => _variableMirror.type;

  @override
  bool get hasReflectedReturnType => _variableMirror.hasReflectedType;

  @override
  Type get reflectedReturnType => _variableMirror.reflectedType;

  @override
  bool get hasDynamicReflectedReturnType =>
      _variableMirror.hasDynamicReflectedType;

  @override
  Type get dynamicReflectedReturnType => _variableMirror.dynamicReflectedType;

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
  List<ParameterMirror> get parameters {
    if (!_supportsDeclarations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `parameters` without `DeclarationsCapability`');
    }
    return <ParameterMirror>[];
  }

  @override
  String get qualifiedName => _variableMirror.qualifiedName;

  @override
  String get simpleName => _variableMirror.simpleName;

  @override
  String toString() => 'ImplicitGetterMirrorImpl($qualifiedName)';
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
    if (_variableMirror._isClassType) {
      descriptor |= constants.classTypeAttribute;
    }

    return descriptor;
  }

  @override
  List<ParameterMirror> get parameters {
    if (!_supportsDeclarations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `parameters` without `DeclarationsCapability`');
    }
    return <ParameterMirror>[
      ParameterMirrorImpl(
          _variableMirror.simpleName,
          _parameterDescriptor,
          _selfIndex,
          _variableMirror._reflector,
          _variableMirror._classMirrorIndex,
          _variableMirror._reflectedTypeIndex,
          _variableMirror._dynamicReflectedTypeIndex,
          _variableMirror._reflectedTypeArguments,
          const <Object>[],
          null,
          null)
    ];
  }

  @override
  String get qualifiedName => '${_variableMirror.qualifiedName}=';

  @override
  String get simpleName => '${_variableMirror.simpleName}=';

  @override
  String toString() => 'ImplicitSetterMirrorImpl($qualifiedName)';
}

abstract class VariableMirrorBase extends _DataCaching
    implements VariableMirror {
  final String _name;
  final int _descriptor;
  final int _ownerIndex;

  @override
  final ReflectableImpl _reflector;

  final int _classMirrorIndex;
  final int _reflectedTypeIndex;
  final int _dynamicReflectedTypeIndex;
  final List<int> _reflectedTypeArguments;
  final List<Object> _metadata;

  VariableMirrorBase(
      this._name,
      this._descriptor,
      this._ownerIndex,
      this._reflector,
      this._classMirrorIndex,
      this._reflectedTypeIndex,
      this._dynamicReflectedTypeIndex,
      this._reflectedTypeArguments,
      this._metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  @override
  bool get isPrivate => (_descriptor & constants.privateAttribute != 0);

  @override
  bool get isTopLevel => (_descriptor & constants.topLevelAttribute != 0);

  @override
  bool get isFinal => (_descriptor & constants.finalAttribute != 0);

  bool get _isDynamic => (_descriptor & constants.dynamicAttribute != 0);

  bool get _isClassType => (_descriptor & constants.classTypeAttribute != 0);

  bool get _isGenericType =>
      (_descriptor & constants.genericTypeAttribute != 0);

  @override
  SourceLocation get location => throw UnsupportedError('location');

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw NoSuchCapabilityError(
          'Requesting metadata of field `$simpleName` without capability');
    }
    return _metadata;
  }

  @override
  String get simpleName => _name;

  @override
  String get qualifiedName => '${owner.qualifiedName}.$_name';

  @override
  TypeMirror get type {
    if (_classMirrorIndex == NO_CAPABILITY_INDEX) {
      if (!_supportsType(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to get `type` without `TypeCapability`');
      }
      throw NoSuchCapabilityError(
          'Attempt to get class mirror for un-marked class (type of `$_name`)');
    }
    if (_isDynamic) return DynamicMirrorImpl();
    if (_isClassType) {
      return _isGenericType
          ? _createInstantiatedGenericClass(
              _data.typeMirrors[_classMirrorIndex],
              hasReflectedType ? reflectedType : null,
              _reflectedTypeArguments)
          : _data.typeMirrors[_classMirrorIndex];
    }
    throw unreachableError('Unexpected kind of type');
  }

  @override
  bool get hasReflectedType =>
      _isDynamic || _reflectedTypeIndex != NO_CAPABILITY_INDEX;

  @override
  Type get reflectedType {
    if (_reflectedTypeIndex == NO_CAPABILITY_INDEX) {
      if (!_supportsReflectedType(_reflector)) {
        throw NoSuchCapabilityError(
            'Attempt to get `reflectedType` without `reflectedTypeCapability`');
      }
      throw UnsupportedError(
          'Attempt to get reflectedType without capability (of `$_name`)');
    }
    if (_isDynamic) return dynamic;
    return _data.types[_reflectedTypeIndex];
  }

  @override
  bool get hasDynamicReflectedType =>
      _dynamicReflectedTypeIndex != NO_CAPABILITY_INDEX || hasReflectedType;

  @override
  Type get dynamicReflectedType =>
      _dynamicReflectedTypeIndex != NO_CAPABILITY_INDEX
          ? _data.types[_dynamicReflectedTypeIndex]
          : reflectedType;

  /// Override requested by linter.
  @override
  bool operator ==(other);

  // Note that [operator ==] is redefined slightly differently in the two
  // subtypes of this class, but they share this [hashCode] implementation.
  @override
  int get hashCode => simpleName.hashCode ^ owner.hashCode;
}

class VariableMirrorImpl extends VariableMirrorBase {
  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw NoSuchCapabilityError(
          'Trying to get owner of variable `$qualifiedName` '
          'without capability');
    }
    return isTopLevel
        ? _data.libraryMirrors[_ownerIndex]
        : _data.typeMirrors[_ownerIndex];
  }

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isConst => (_descriptor & constants.constAttribute != 0);

  VariableMirrorImpl(
      String name,
      int descriptor,
      int ownerIndex,
      ReflectableImpl reflectable,
      int classMirrorIndex,
      int reflectedTypeIndex,
      int dynamicReflectedTypeIndex,
      List<int> reflectedTypeArguments,
      List<Object> metadata)
      : super(
            name,
            descriptor,
            ownerIndex,
            reflectable,
            classMirrorIndex,
            reflectedTypeIndex,
            dynamicReflectedTypeIndex,
            reflectedTypeArguments,
            metadata);

  // Note that the corresponding implementation of [hashCode] is inherited from
  // [VariableMirrorBase].
  @override
  bool operator ==(other) =>
      other is VariableMirrorImpl &&
      other.simpleName == simpleName &&
      other.owner == owner;

  /// Override requested by linter.
  @override
  int get hashCode;
}

class ParameterMirrorImpl extends VariableMirrorBase
    implements ParameterMirror {
  final Object _defaultValue;

  /// Symbol for the name of this parameter, if named; otherwise null.
  final Symbol _nameSymbol;

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isConst => (_descriptor & constants.constAttribute != 0);

  @override
  bool get hasDefaultValue {
    if (!_supportsDeclarations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `hasDefaultValue` without `DeclarationsCapability`');
    }
    return (_descriptor & constants.hasDefaultValueAttribute != 0);
  }

  @override
  Object get defaultValue {
    if (!_supportsDeclarations(_reflector)) {
      throw NoSuchCapabilityError(
          'Attempt to get `defaultValue` without `DeclarationsCapability`');
    }
    return _defaultValue;
  }

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
      int classMirrorIndex,
      int reflectedTypeIndex,
      int dynamicReflectedTypeIndex,
      List<int> reflectedTypeArguments,
      List<Object> metadata,
      this._defaultValue,
      this._nameSymbol)
      : super(
            name,
            descriptor,
            ownerIndex,
            reflectable,
            classMirrorIndex,
            reflectedTypeIndex,
            dynamicReflectedTypeIndex,
            reflectedTypeArguments,
            metadata);

  // Note that the corresponding implementation of [hashCode] is inherited from
  // [VariableMirrorBase].
  @override
  bool operator ==(other) =>
      other is ParameterMirrorImpl &&
      other.simpleName == simpleName &&
      other.owner == owner;

  /// Override requested by linter.
  @override
  int get hashCode;
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
  String get simpleName => 'dynamic';

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  List<TypeVariableMirror> get typeVariables => const <TypeVariableMirror>[];

  @override
  List<TypeMirror> get typeArguments => const <TypeMirror>[];

  @override
  List<Type> get reflectedTypeArguments => const <Type>[];

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  TypeMirror get originalDeclaration => this;

  @override
  SourceLocation get location => throw UnsupportedError('location');

  // TODO(eernst) implement: We ought to check for the capability, which
  // means that we should have a `_reflector`, and then we should throw a
  // [NoSuchCapabilityError] if there is no `typeRelationsCapability`.
  // However, it seems near-benign to omit the check and give the correct
  // reply in all cases.
  @override
  bool isSubtypeOf(TypeMirror other) => true;

  // TODO(eernst) implement: We ought to check for the capability, which
  // means that we should have a `_reflector`, and then we should throw a
  // [NoSuchCapabilityError] if there is no `typeRelationsCapability`.
  // However, it seems near-benign to omit the check and give the correct
  // reply in all cases.
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
  Type get reflectedType =>
      throw UnsupportedError('Attempt to get the reflected type of `void`');

  @override
  String get simpleName => 'void';

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  List<TypeVariableMirror> get typeVariables => const <TypeVariableMirror>[];

  @override
  List<TypeMirror> get typeArguments => const <TypeMirror>[];

  @override
  List<Type> get reflectedTypeArguments => const <Type>[];

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  TypeMirror get originalDeclaration => this;

  @override
  SourceLocation get location => throw UnsupportedError('location');

  // TODO(eernst) implement: We ought to check for the capability, which
  // means that we should have a `supportsTypeRelations` bool, and then we
  // should throw a [NoSuchCapabilityError] if it is not true.
  // However, it seems near-benign to omit the check and give the correct
  // reply in all cases.
  // TODO(eernst) clarify: check the spec!
  @override
  bool isSubtypeOf(TypeMirror other) => other is DynamicMirrorImpl;

  // TODO(eernst) implement: We ought to check for the capability, which
  // means that we should have a `supportsTypeRelations` bool, and then we
  // should throw a [NoSuchCapabilityError] if it is not true.
  // However, it seems near-benign to omit the check and give the correct
  // reply in all cases.
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
      [ReflectCapability cap0,
      ReflectCapability cap1,
      ReflectCapability cap2,
      ReflectCapability cap3,
      ReflectCapability cap4,
      ReflectCapability cap5,
      ReflectCapability cap6,
      ReflectCapability cap7,
      ReflectCapability cap8,
      ReflectCapability cap9])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const ReflectableImpl.fromList(List<ReflectCapability> capabilities)
      : super.fromList(capabilities);

  @override
  bool canReflect(Object reflectee) {
    return data[this].classMirrorForInstance(reflectee) != null;
  }

  @override
  InstanceMirror reflect(Object reflectee) {
    return _InstanceMirrorImpl(reflectee, this);
  }

  bool get _hasTypeCapability {
    return capabilities
        .any((ReflectCapability capability) => capability is TypeCapability);
  }

  @override
  bool canReflectType(Type type) {
    return _hasTypeCapability && data[this].classMirrorForType(type) != null;
  }

  @override
  TypeMirror reflectType(Type type) {
    ClassMirror result = data[this].classMirrorForType(type);
    if (result == null || !_hasTypeCapability) {
      throw NoSuchCapabilityError(
          'Reflecting on type `$type` without capability');
    }
    return result;
  }

  @override
  LibraryMirror findLibrary(String libraryName) {
    ReflectorData reflectorData = data[this];
    if (reflectorData.libraryMirrors == null) {
      throw NoSuchCapabilityError('Using `findLibrary` without capability. '
          'Try adding `libraryCapability`.');
    }
    // The specification says that an exception shall be thrown if there
    // is anything other than one library with a matching name.
    int matchCount = 0;
    LibraryMirror matchingLibrary;
    for (LibraryMirror libraryMirror in reflectorData.libraryMirrors) {
      if (libraryMirror.qualifiedName == libraryName) {
        matchCount++;
        matchingLibrary = libraryMirror;
      }
    }
    switch (matchCount) {
      case 0:
        throw ArgumentError('No such library: $libraryName');
      case 1:
        return matchingLibrary;
      default:
        throw ArgumentError('Ambiguous library name: $libraryName');
    }
  }

  @override
  Map<Uri, LibraryMirror> get libraries {
    ReflectorData reflectorData = data[this];
    if (reflectorData.libraryMirrors == null) {
      throw NoSuchCapabilityError('Using `libraries` without capability. '
          'Try adding `libraryCapability`.');
    }
    Map<Uri, LibraryMirror> result = <Uri, LibraryMirror>{};
    for (LibraryMirror library in reflectorData.libraryMirrors) {
      result[library.uri] = library;
    }
    return UnmodifiableMapView(result);
  }

  @override
  Iterable<ClassMirror> get annotatedClasses {
    return List<ClassMirror>.unmodifiable(
        data[this].typeMirrors.whereType<ClassMirror>());
  }
}

// For mixin-applications and private classes we need to construct objects
// that represents their type.
class FakeType implements Type {
  const FakeType(this.description);

  final String description;

  @override
  String toString() => 'Type($description)';
}

bool _isSetterName(String name) => name.endsWith('=');

String _getterNameToSetterName(String name) => name + '=';

bool _supportsType(ReflectableImpl reflector) {
  return reflector.capabilities
      .any((ReflectCapability capability) => capability is TypeCapability);
}

bool _supportsTypeRelations(ReflectableImpl reflector) {
  return reflector.capabilities.any(
      (ReflectCapability capability) => capability is TypeRelationsCapability);
}

bool _supportsReflectedType(ReflectableImpl reflector) {
  return reflector.capabilities.any(
      (ReflectCapability capability) => capability == reflectedTypeCapability);
}

bool _supportsDeclarations(ReflectableImpl reflector) {
  return reflector.capabilities.any(
      (ReflectCapability capability) => capability is DeclarationsCapability);
}
