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
import 'incompleteness.dart';
import 'reflectable_base.dart';

bool get isTransformed => true;

/// Returns the set of reflectors in the current program.
Set<Reflectable> get reflectors => data.keys.toSet();

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

  /// List of [Type]s used to select class mirrors: If M is a class
  /// mirror in [typeMirrors] at index `i`, the mirrored class (and
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

  ReflectorData(this.typeMirrors, this.memberMirrors, this.parameterMirrors,
      this.types, this.getters, this.setters, this.libraryMirrors);

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
        _typeToClassMirrorCache =
            new Map.fromIterables(types, typeMirrors.sublist(0, types.length));
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
              classMirror, instance.runtimeType);
        }
      }
    }
    // Inform the caller that this object has no coverage.
    return null;
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
    _type = _data.classMirrorForInstance(reflectee);
    if (_type == null) {
      // We may not have a `TypeCapability`, in which case we need to check
      // whether there is support based on the stored types.
      if (!_data.types.contains(reflectee.runtimeType)) {
        // No chance: this is an instance of an unsupported type.
        throw new NoSuchCapabilityError(
            "Reflecting on un-marked type '${reflectee.runtimeType}'");
      }
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

  int get hashCode => _reflector.hashCode ^ reflectee.hashCode;

  delegate(Invocation invocation) => unimplementedError("delegate");

  @override
  Object invokeGetter(String getterName) {
    Function getter = _data.getters[getterName];
    if (getter != null) {
      return getter(reflectee);
    }
    throw new NoSuchInvokeCapabilityError(reflectee, getterName, [], {});
  }

  @override
  Object invokeSetter(String name, Object value) {
    String setterName =
        _isSetterName(name) ? name : _getterNameToSetterName(name);
    Function setter = _data.setters[setterName];
    if (setter != null) {
      return setter(reflectee, value);
    }
    throw new NoSuchInvokeCapabilityError(reflectee, setterName, [value], {});
  }
}

abstract class ClassMirrorImpl extends _DataCaching implements ClassMirror {
  /// The reflector which represents the mirror system that this
  /// mirror belongs to.
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

  List<ClassMirror> get superinterfaces {
    return _superinterfaceIndices.map((int i) => _data.typeMirrors[i]).toList();
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

  final String simpleName;
  final String qualifiedName;
  final List<Object> _metadata;
  final Map<String, _StaticGetter> _getters;
  final Map<String, _StaticSetter> _setters;
  final Map<String, Function> _constructors;

  ClassMirrorImpl(
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
      this._metadata);

  bool get isAbstract => (_descriptor & constants.abstractAttribute != 0);

  Map<String, DeclarationMirror> _declarations;

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
      Map<String, MethodMirror> result = <String, MethodMirror>{};
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
      Map<String, MethodMirror> result = <String, MethodMirror>{};
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
    return _data.typeMirrors[_mixinIndex];
  }

  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    Function constructor = _constructors["$constructorName"];
    if (constructor == null) {
      throw new NoSuchCapabilityError(
          "Attempt to invoke constructor $constructorName without capability.");
    }
    return Function.apply(constructor, positionalArguments, namedArguments);
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
  Object invokeSetter(String name, Object value) {
    String setterName =
        _isSetterName(name) ? name : _getterNameToSetterName(name);
    _StaticSetter setter = _setters[setterName];
    if (setter == null) {
      throw new NoSuchInvokeCapabilityError(
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

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      String description =
          hasReflectedType ? reflectedType.toString() : qualifiedName;
      throw new NoSuchCapabilityError(
          "Requesting metadata of '$description' without capability");
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

  // TODO(eernst) feature: Implement `isAssignableTo`.
  @override
  bool isAssignableTo(TypeMirror other) =>
      throw unimplementedError("isAssignableTo");

  // TODO(eernst) feature: Implement `isSubTypeOf`.
  @override
  bool isSubtypeOf(TypeMirror other) => throw unimplementedError("isSubtypeOf");

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
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Trying to get owner of class '$qualifiedName' "
          "without 'LibraryCapability'");
    }
    return _data.libraryMirrors[_ownerIndex];
  }

  ClassMirror get superclass {
    if (_superclassIndex == null) return null; // Superclass of [Object].
    if (_superclassIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Requesting mirror on un-marked class, superclass of '$simpleName'");
    }
    return _data.typeMirrors[_superclassIndex];
  }

  // Because we take care to only ever create one instance for each
  // type/reflector-combination we can rely on the default `hashCode` and `==`
  // operations.
}

class NonGenericClassMirrorImpl extends ClassMirrorImpl {
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
      List<Object> metadata)
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
            metadata);

  @override
  List<TypeMirror> get typeArguments => <TypeMirror>[];

  @override
  List<TypeVariableMirror> get typeVariables => <TypeVariableMirror>[];

  @override
  bool get isOriginalDeclaration => true;

  @override
  TypeMirror get originalDeclaration => this;

  @override
  bool get hasReflectedType => true;

  @override
  Type get reflectedType => _data.types[_classIndex];

  @override
  bool get hasDynamicReflectedType => true;

  @override
  Type get dynamicReflectedType => reflectedType;

  String toString() => "NonGenericClassMirrorImpl($qualifiedName)";
}

typedef bool InstanceChecker(Object instance);

class GenericClassMirrorImpl extends ClassMirrorImpl {
  /// Used to enable instance checks. Let O be an instance and let C denote the
  /// generic class modeled by this mirror. The check is then such that the
  /// result is true iff there exists a list of type arguments X1..Xk such that
  /// O is an instance of C<X1..Xk>. We can perform this check by checking that
  /// O is an instance of C<dynamic .. dynamic>, and O is not an instance
  /// of any of Dj<dynamic .. dynamic> for j in {1..n}, where D1..Dn is the
  /// complete set of classes in the current program which are direct
  /// subinterfaces of C (i.e., classes which directly `extends` or `implements`
  /// C). The check is implemented by this function.
  final InstanceChecker _isGenericRuntimeTypeOf;

  final List<int> _typeVariableIndices;

  final Type _dynamicReflectedType;

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
      this._isGenericRuntimeTypeOf,
      this._typeVariableIndices,
      this._dynamicReflectedType)
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
            metadata);

  @override
  List<TypeMirror> get typeArguments => <TypeMirror>[];

  // The type variables declared by this generic class, in declaration order.
  // The value `null` means no capability. The empty list would mean no type
  // parameters, but the empty list does not occur: [this] mirror would then
  // model a non-generic class.
  @override
  List<TypeVariableMirror> get typeVariables {
    if (_typeVariableIndices == null) {
      throw new NoSuchCapabilityError(
          "Requesting type variables of '$simpleName' without capability");
    }
    List<TypeVariableMirror> result = <TypeVariableMirror>[];
    for (int typeVariableIndex in _typeVariableIndices) {
      TypeVariableMirror typeVariableMirror =
          _data.typeMirrors[typeVariableIndex];
      assert(typeVariableMirror is TypeVariableMirror);
      result.add(typeVariableMirror);
    }
    return new List<TypeVariableMirror>.unmodifiable(result);
  }

  @override
  bool get isOriginalDeclaration => true;

  @override
  TypeMirror get originalDeclaration => this;

  @override
  bool get hasReflectedType => false;

  @override
  Type get reflectedType {
    throw new UnsupportedError("Attempt to obtain `reflectedType` "
        "from generic class '$qualifiedName'.");
  }

  @override
  bool get hasDynamicReflectedType => true;

  @override
  Type get dynamicReflectedType => _dynamicReflectedType;

  String toString() => "GenericClassMirrorImpl($qualifiedName)";
}

class InstantiatedGenericClassMirrorImpl extends ClassMirrorImpl {
  final GenericClassMirrorImpl _originalDeclaration;
  final Type _reflectedType;

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
      this._originalDeclaration,
      this._reflectedType)
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
            metadata);

  // TODO(sigurdm) implement: Implement typeArguments.
  @override
  List<TypeMirror> get typeArguments =>
      throw unimplementedError("typeArguments");

  @override
  List<TypeVariableMirror> get typeVariables =>
      originalDeclaration.typeVariables;

  @override
  bool get isOriginalDeclaration => false;

  @override
  TypeMirror get originalDeclaration => _originalDeclaration;

  @override
  bool get hasReflectedType => _reflectedType != null;

  @override
  Type get reflectedType {
    if (_reflectedType != null) return _reflectedType;
    throw new UnsupportedError("Cannot provide `reflectedType` of "
        "instance of generic type '$simpleName'.");
  }

  @override
  bool get hasDynamicReflectedType =>
      _originalDeclaration.hasDynamicReflectedType;

  @override
  Type get dynamicReflectedType => _originalDeclaration.dynamicReflectedType;

  String toString() => "InstantiatedGenericClassMirrorImpl($qualifiedName)";
}

InstantiatedGenericClassMirrorImpl _createInstantiatedGenericClass(
    GenericClassMirrorImpl genericClassMirror, Type reflectedType) {
  // TODO(eernst) implement: Pass a representation of type arguments to this
  // method, and create an instantiated generic class which includes that
  // information.
  return new InstantiatedGenericClassMirrorImpl(
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
      genericClassMirror,
      reflectedType);
}

class TypeVariableMirrorImpl extends _DataCaching
    implements TypeVariableMirror {
  /// The simple name of this type variable.
  final String simpleName;

  /// The qualified name of this type variable, i.e., the qualified name of
  /// the declaring class followed by its simple name.
  final String qualifiedName;

  /// The reflector which represents the mirror system that this
  /// mirror belongs to.
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
    if (_upperBoundIndex == null) return new DynamicMirrorImpl();
    if (_upperBoundIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError("Attempt to get `upperBound` from type "
          "variable mirror without capability.");
    }
    return _data.typeMirrors[_upperBoundIndex];
  }

  @override
  bool isAssignableTo(TypeMirror other) =>
      throw unimplementedError("isAssignableTo");

  @override
  bool isSubtypeOf(TypeMirror other) => throw unimplementedError("isSubtypeOf");

  @override
  TypeMirror get originalDeclaration => this;

  @override
  bool get isOriginalDeclaration => true;

  @override
  List<TypeMirror> get typeArguments => <TypeMirror>[];

  @override
  List<TypeVariableMirror> get typeVariables => <TypeVariableMirror>[];

  @override
  Type get reflectedType {
    throw new UnsupportedError("Attempt to get `reflectedType` from type "
        "variable $simpleName");
  }

  @override
  bool get hasReflectedType => false;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError("Attempt to get `metadata` from type "
          "variable $simpleName without capability");
    }
    return <Object>[];
  }

  /// It is allowed to return null;
  @override
  SourceLocation get location => null;

  @override
  bool get isTopLevel => false;

  @override
  bool get isPrivate => false;

  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Trying to get owner of type parameter '$qualifiedName' "
          "without capability");
    }
    return _data.typeMirrors[_ownerIndex];
  }
}

class LibraryMirrorImpl extends _DataCaching implements LibraryMirror {
  LibraryMirrorImpl(this.simpleName, this.uri, this._reflector,
      this._declarationIndices, this.getters, this.setters, this._metadata);

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
          throw new NoSuchCapabilityError(
              "Requesting declarations of '$qualifiedName' without capability");
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
      _declarations =
          new UnmodifiableMapView<String, DeclarationMirror>(result);
    }
    return _declarations;
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    _StaticGetter getter = getters[memberName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(
          null, memberName, positionalArguments, namedArguments);
    }
    return Function.apply(getter(), positionalArguments, namedArguments);
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
  Object invokeSetter(String name, Object value) {
    String setterName =
        _isSetterName(name) ? name : _getterNameToSetterName(name);
    _StaticSetter setter = setters[setterName];
    if (setter == null) {
      throw new NoSuchInvokeCapabilityError(null, setterName, [value], {});
    }
    return setter(value);
  }

  /// A library cannot be private.
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

  bool operator ==(other) {
    return other is LibraryMirrorImpl &&
        other.uri == uri &&
        other._reflector == _reflector &&
        other._declarationIndices == _declarationIndices;
  }

  int get hashCode =>
      uri.hashCode ^ _reflector.hashCode ^ _declarationIndices.hashCode;

  // TODO(sigurdm) implement: Need to implement this. Probably only when a given
  // capability is enabled.
  List<LibraryDependencyMirror> get libraryDependencies =>
      throw unimplementedError("libraryDependencies");
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
  final Type _reflectedReturnType;

  /// The return type of this method, erased to have `dynamic` for all
  /// type arguments; a null value indicates that it is identical to
  /// `reflectedReturnType` if that value is available they are equal; if
  /// `reflectedReturnType` is unavailable then so is
  /// `dynamicReflectedReturnType`.
  final Type _dynamicReflectedReturnType;

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
      this._reflectedReturnType,
      this._dynamicReflectedReturnType,
      this._parameterIndices,
      this._reflector,
      this._metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Trying to get owner of method '$qualifiedName' "
          "without 'LibraryCapability'");
    }
    return isTopLevel
        ? _data.libraryMirrors[_ownerIndex]
        : _data.typeMirrors[_ownerIndex];
  }

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
  bool get isTopLevel => (_descriptor & constants.topLevelAttribute != 0);

  bool get _hasDynamicReturnType =>
      (_descriptor & constants.dynamicReturnTypeAttribute != 0);

  bool get _hasClassReturnType =>
      (_descriptor & constants.classReturnTypeAttribute != 0);

  bool get _hasVoidReturnType =>
      (_descriptor & constants.voidReturnTypeAttribute != 0);

  bool get _hasGenericReturnType =>
      (_descriptor & constants.genericReturnTypeAttribute != 0);

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
    if (_hasClassReturnType) {
      return _hasGenericReturnType
          ? _createInstantiatedGenericClass(
              _data.typeMirrors[_returnTypeIndex], null)
          : _data.typeMirrors[_returnTypeIndex];
    }
    throw unreachableError("Unexpected kind of returnType");
  }

  @override
  bool get hasReflectedReturnType => _reflectedReturnType != null;

  @override
  Type get reflectedReturnType {
    if (_reflectedReturnType == null) {
      throw new NoSuchCapabilityError(
          "Requesting reflectedReturnType of method "
          "'$simpleName' without capability");
    }
    return _reflectedReturnType;
  }

  @override
  bool get hasDynamicReflectedReturnType =>
      _dynamicReflectedReturnType != null || hasReflectedReturnType;

  @override
  Type get dynamicReflectedReturnType {
    return _dynamicReflectedReturnType != null
        ? _dynamicReflectedReturnType
        : reflectedReturnType;
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
  final Type _reflectedType;
  final Type _dynamicReflectedType;

  /// Index of this [ImplicitAccessorMirrorImpl] in `_data.memberMirrors`.
  final int _selfIndex;

  VariableMirrorImpl get _variableMirror =>
      _data.memberMirrors[_variableMirrorIndex];

  ImplicitAccessorMirrorImpl(this._reflector, this._variableMirrorIndex,
      this._reflectedType, this._dynamicReflectedType, this._selfIndex);

  int get kind => constants.kindFromEncoding(_variableMirror._descriptor);

  DeclarationMirror get owner => _variableMirror.owner;

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
  ImplicitGetterMirrorImpl(ReflectableImpl reflector, int variableMirrorIndex,
      Type reflectedType, Type dynamicReflectedType, int selfIndex)
      : super(reflector, variableMirrorIndex, reflectedType,
            dynamicReflectedType, selfIndex);

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
  ImplicitSetterMirrorImpl(ReflectableImpl reflector, int variableMirrorIndex,
      Type reflectedType, Type dynamicReflectedType, int selfIndex)
      : super(reflector, variableMirrorIndex, reflectedType,
            dynamicReflectedType, selfIndex);

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
          _variableMirror._reflectedType,
          _variableMirror._dynamicReflectedType,
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
  final int _classMirrorIndex;
  final Type _reflectedType;
  final Type _dynamicReflectedType;
  final List<Object> _metadata;

  VariableMirrorBase(
      this._name,
      this._descriptor,
      this._ownerIndex,
      this._reflector,
      this._classMirrorIndex,
      this._reflectedType,
      this._dynamicReflectedType,
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
      return _isGenericType
          ? _createInstantiatedGenericClass(
              _data.typeMirrors[_classMirrorIndex], null)
          : _data.typeMirrors[_classMirrorIndex];
    }
    throw unreachableError("Unexpected kind of type");
  }

  @override
  bool get hasReflectedType => _reflectedType != null;

  @override
  Type get reflectedType {
    if (_reflectedType == null) {
      throw new NoSuchCapabilityError(
          "Attempt to get reflectedType without capability (of '$_name')");
    }
    return _reflectedType;
  }

  @override
  bool get hasDynamicReflectedType =>
      _dynamicReflectedType != null || hasReflectedType;

  @override
  Type get dynamicReflectedType =>
      _dynamicReflectedType != null ? _dynamicReflectedType : reflectedType;

  // Note that [operator ==] is redefined slightly differently in the two
  // subtypes of this class, but they share this [hashCode] implementation.
  @override
  int get hashCode => simpleName.hashCode ^ owner.hashCode;
}

class VariableMirrorImpl extends VariableMirrorBase {
  @override
  DeclarationMirror get owner {
    if (_ownerIndex == NO_CAPABILITY_INDEX) {
      throw new NoSuchCapabilityError(
          "Trying to get owner of variable '$qualifiedName' "
          "without capability");
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
      Type reflectedType,
      Type dynamicReflectedType,
      List<Object> metadata)
      : super(name, descriptor, ownerIndex, reflectable, classMirrorIndex,
            reflectedType, dynamicReflectedType, metadata);

  // Note that the corresponding implementation of [hashCode] is inherited from
  // [VariableMirrorBase].
  @override
  bool operator ==(other) => other is VariableMirrorImpl &&
      other.simpleName == simpleName &&
      other.owner == owner;
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
      int classMirrorIndex,
      Type reflectedType,
      Type dynamicReflectedType,
      List<Object> metadata,
      this.defaultValue)
      : super(name, descriptor, ownerIndex, reflectable, classMirrorIndex,
            reflectedType, dynamicReflectedType, metadata);

  // Note that the corresponding implementation of [hashCode] is inherited from
  // [VariableMirrorBase].
  @override
  bool operator ==(other) => other is ParameterMirrorImpl &&
      other.simpleName == simpleName &&
      other.owner == owner;
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
  Type get reflectedType =>
      throw new UnsupportedError("Attempt to get the reflected type of `void`");

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
  bool canReflect(Object reflectee) {
    return data[this].classMirrorForInstance(reflectee) != null;
  }

  @override
  InstanceMirror reflect(Object reflectee) {
    return new _InstanceMirrorImpl(reflectee, this);
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
      throw new NoSuchCapabilityError(
          "Reflecting on type '$type' without capability");
    }
    return result;
  }

  @override
  LibraryMirror findLibrary(String libraryName) {
    if (data[this].libraryMirrors == null) {
      throw new NoSuchCapabilityError("Using 'findLibrary' without capability. "
          "Try adding `libraryCapability`.");
    }
    return data[this].libraryMirrors.singleWhere(
        (LibraryMirror mirror) => mirror.qualifiedName == libraryName);
  }

  @override
  Map<Uri, LibraryMirror> get libraries {
    if (data[this].libraryMirrors == null) {
      throw new NoSuchCapabilityError("Using 'libraries' without capability. "
          "Try adding `libraryCapability`.");
    }
    Map<Uri, LibraryMirror> result = <Uri, LibraryMirror>{};
    for (LibraryMirror library in data[this].libraryMirrors) {
      result[library.uri] = library;
    }
    return new UnmodifiableMapView(result);
  }

  @override
  Iterable<ClassMirror> get annotatedClasses {
    return new List<ClassMirror>.unmodifiable(data[this]
        .typeMirrors
        .where((TypeMirror typeMirror) => typeMirror is ClassMirror));
  }
}

// For mixin-applications and private classes we need to construct objects
// that represents their type.
class FakeType implements Type {
  const FakeType(this.description);

  final String description;

  String toString() => "Type($description)";
}

bool _isSetterName(String name) => name.endsWith("=");

String _getterNameToSetterName(String name) => name + "=";
