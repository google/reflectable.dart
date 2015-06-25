// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.mirrors_unimpl;

import '../capability.dart';
import '../mirrors.dart';
import '../reflectable.dart';
import 'encoding_constants.dart' as constants;
import 'reflectable_base.dart';

import 'dart:collection' show UnmodifiableMapView, UnmodifiableListView;

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

abstract class DeclarationMirrorUnimpl implements DeclarationMirror {
  String get simpleName => _unsupported();
  String get qualifiedName => _unsupported();
  DeclarationMirror get owner => _unsupported();
  bool get isPrivate => _unsupported();
  bool get isTopLevel => _unsupported();
  SourceLocation get location => _unsupported();
  List<Object> get metadata => _unsupported();
}

abstract class ObjectMirrorUnimpl implements ObjectMirror {
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) => _unsupported();
  Object invokeGetter(String getterName) => _unsupported();
  Object invokeSetter(String setterName, Object value) => _unsupported();

  Object getField(String name) {
    throw new UnsupportedError("Use invokeGetter instead of getField");
  }

  void setField(String name, Object value) {
    throw new UnsupportedError("Use invokeSetter instead of setField");
  }
}

abstract class InstanceMirrorUnimpl extends ObjectMirrorUnimpl
    implements InstanceMirror {
  ClassMirror get type => _unsupported();
  bool get hasReflectee => _unsupported();
  get reflectee => _unsupported();
  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();
  delegate(Invocation invocation) => _unsupported();
}

/// Invokes a getter on an object.
typedef Object InvokerOfGetter(Object instance);

/// Invokes a setter on an object.
typedef Object InvokerOfSetter(Object instance, Object value);

/// The data backing a reflector.
class ReflectorData {
  final List<ClassMirror> classMirrors;
  final List<MethodMirror> memberMirrors;
  final Map<String, Function> staticMethods;
  final List<Type> types;
  final Map<String, Function> constructors;
  final Map<String, InvokerOfGetter> getters;
  final Map<String, InvokerOfSetter> setters;

  Map<Type, ClassMirror> _typeToClassMirrorCache;

  ReflectorData(this.classMirrors, this.memberMirrors, this.staticMethods,
      this.types, this.constructors, this.getters, this.setters);

  ClassMirror classMirrorForType(Type type) {
    if (_typeToClassMirrorCache == null) {
      _typeToClassMirrorCache = new Map.fromIterables(types, classMirrors);
    }
    ClassMirror result = _typeToClassMirrorCache[type];
    if (result == null) {
      throw new NoSuchCapabilityError(
          "Reflecting on type $type that is not reflector-marked.");
    }
    return result;
  }
}

/// This mapping contains the mirror-data for each reflector.
/// It will be initialized in the generated code.
Map<Reflectable, ReflectorData> data;

class InstanceMirrorImpl implements InstanceMirror {
  ReflectorData _dataCache;
  ReflectorData get _data {
    if (_dataCache == null) {
      _dataCache = data[reflectable];
    }
    return _dataCache;
  }

  final Reflectable reflectable;

  final Object reflectee;

  InstanceMirrorImpl(this.reflectee, this.reflectable);

  ClassMirror get type => _data.classMirrorForType(reflectee.runtimeType);

  Object invoke(String methodName, List<Object> positionalArguments,
      [Map<Symbol, Object> namedArguments]) {
    Function methodTearer = _data.getters[methodName];
    if (methodTearer != null) {
      return Function.apply(
          methodTearer(reflectee), positionalArguments, namedArguments);
    }
    throw new NoSuchInvokeCapabilityError(
        reflectee, methodName, positionalArguments, namedArguments);
  }
  bool get hasReflectee => true;
  bool operator ==(other) {
    return other is InstanceMirrorImpl &&
        other._data == _data &&
        other.reflectee == reflectee;
  }

  int get hashCode => reflectee.hashCode;

  delegate(Invocation invocation) => _unsupported();

  @override
  Object invokeGetter(String getterName) {
    return _data.getters[getterName](reflectee);
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (setterName.substring(setterName.length - 1) != "=") {
      setterName += "=";
    }
    return _data.setters[setterName](reflectee, value);
  }
}

abstract class ClosureMirrorUnimpl extends InstanceMirrorUnimpl
    implements ClosureMirror {
  MethodMirror get function => _unsupported();
  InstanceMirror apply(List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) => _unsupported();
}

abstract class LibraryMirrorUnimpl extends DeclarationMirrorUnimpl
    with ObjectMirrorUnimpl implements LibraryMirror {
  Uri get uri => _unsupported();
  Map<String, DeclarationMirror> get declarations => _unsupported();
  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();
  List<LibraryDependencyMirror> get libraryDependencies => _unsupported();
}

class LibraryDependencyMirrorUnimpl implements LibraryDependencyMirror {
  bool get isImport => _unsupported();
  bool get isExport => _unsupported();
  bool get isDeferred => _unsupported();
  LibraryMirror get sourceLibrary => _unsupported();
  LibraryMirror get targetLibrary => _unsupported();
  String get prefix => _unsupported();
  List<CombinatorMirror> get combinators => _unsupported();
  SourceLocation get location => _unsupported();
  List<Object> get metadata => _unsupported();
}

abstract class CombinatorMirrorUnimpl implements CombinatorMirror {
  List<String> get identifiers => _unsupported();
  bool get isShow => _unsupported();
  bool get isHide => _unsupported();
}

abstract class TypeMirrorUnimpl extends DeclarationMirrorUnimpl
    implements TypeMirror {
  bool get hasReflectedType => _unsupported();
  Type get reflectedType => _unsupported();
  List<TypeVariableMirror> get typeVariables => _unsupported();
  List<TypeMirror> get typeArguments => _unsupported();
  bool get isOriginalDeclaration => _unsupported();
  TypeMirror get originalDeclaration => _unsupported();
  bool isSubtypeOf(TypeMirror other) => _unsupported();
  bool isAssignableTo(TypeMirror other) => _unsupported();
}

class ClassMirrorImpl implements ClassMirror {
  ReflectorData _dataCache;
  ReflectorData get _data {
    if (_dataCache == null) {
      _dataCache = data[_reflectable];
    }
    return _dataCache;
  }
  final Reflectable _reflectable;
  /// The index of this mirror in the [ReflectorData.classMirrors] table.
  /// Also this is the index of the Type of the reflected class in
  /// [ReflectorData.types].
  final int _classIndex;
  /// A list of the indices in [ReflectorData.memberMirrors] of the declarations
  /// of the reflected class.
  final List<int> _declarationIndices;
  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// instanceMembers of the reflected class.
  final List<int> _instanceMemberIndices;
  /// The index of the mirror of the superclass in the
  /// [ReflectorData.classMirrors] table.
  final int _superclassIndex;
  final String simpleName;
  final String qualifiedName;
  final List<Object> _metadata;

  ClassMirrorImpl(this.simpleName, this.qualifiedName, this._classIndex,
      this._reflectable, this._declarationIndices, this._instanceMemberIndices,
      this._superclassIndex, metadata)
      : _metadata = metadata == null
          ? null
          : new UnmodifiableListView(metadata);

  ClassMirror get superclass {
    return _data.classMirrors[_superclassIndex];
  }

  List<ClassMirror> get superinterfaces => _unsupported();

  bool get isAbstract => _unsupported();

  Map<String, DeclarationMirror> _declarations;

  Map<String, DeclarationMirror> get declarations {
    if (_declarations == null) {
      Map<String, MethodMirror> result = new Map<String, MethodMirror>();
      for (int methodIndex in _declarationIndices) {
        MethodMirror methodMirror = _data.memberMirrors[methodIndex];
        result[methodMirror.simpleName] = methodMirror;
      }
      _declarations = new Map.unmodifiable(result);
    }
    return _declarations;
  }

  Map<String, DeclarationMirror> _instanceMembers;

  Map<String, MethodMirror> get instanceMembers {
    if (_instanceMembers == null) {
      Map<String, MethodMirror> result = new Map<String, MethodMirror>();
      for (int methodIndex in _instanceMemberIndices) {
        MethodMirror methodMirror = _data.memberMirrors[methodIndex];
        result[methodMirror.simpleName] = methodMirror;
      }
      _instanceMembers = new Map.unmodifiable(result);
    }
    return _instanceMembers;
  }

  Map<String, MethodMirror> get staticMembers => _unsupported();

  ClassMirror get mixin => _unsupported();

  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    // TODO(sigurdm): Move the constructors-data to the ClassMirrors.
    return Function.apply(_data.constructors["$qualifiedName.$constructorName"],
        positionalArguments, namedArguments);
  }

  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();

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
  bool get hasReflectedType => _unsupported();

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    // TODO(sigurdm): Implement static methods.
    return _unsupported();
  }

  // TODO(eernst, sigurdm): Implement.
  @override
  Object invokeGetter(String getterName) => _unsupported();

  // TODO(eernst, sigurdm): Implement.
  @override
  Object invokeSetter(String setterName, Object value) => _unsupported();

  // TODO(eernst, sigurdm): Implement.
  @override
  bool isAssignableTo(TypeMirror other) => _unsupported();

  // TODO(eernst, sigurdm): Implement if we choose to handle generics.
  @override
  bool get isOriginalDeclaration => _unsupported();

  // For now we only support reflection on public classes.
  @override
  bool get isPrivate => false;

  // TODO(eernst, sigurdm): Implement isSubTypeOf.
  @override
  bool isSubtypeOf(TypeMirror other) => _unsupported();

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
          "Requesting metadata of $reflectedType without capability");
    }
    return _metadata;
  }

  @override
  TypeMirror get originalDeclaration => _unsupported();

  @override
  DeclarationMirror get owner => _unsupported();

  @override
  Type get reflectedType => _data.types[_classIndex];

  @override
  List<TypeMirror> get typeArguments => _unsupported();

  @override
  List<TypeVariableMirror> get typeVariables => _unsupported();
}

abstract class TypeVariableMirrorUnimpl extends TypeMirrorUnimpl
    implements TypeVariableMirror {
  TypeMirror get upperBound => _unsupported();
  bool get isStatic => _unsupported();
  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();
}

abstract class TypedefMirrorUnimpl extends TypeMirrorUnimpl
    implements TypedefMirror {
  FunctionTypeMirror get referent => _unsupported();
}

abstract class MethodMirrorUnimpl extends DeclarationMirrorUnimpl
    implements MethodMirror {
  TypeMirror get returnType => _unsupported();
  String get source => _unsupported();
  List<ParameterMirror> get parameters => _unsupported();
  bool get isStatic => _unsupported();
  bool get isAbstract => _unsupported();
  bool get isSynthetic => _unsupported();
  bool get isRegularMethod => _unsupported();
  bool get isOperator => _unsupported();
  bool get isGetter => _unsupported();
  bool get isSetter => _unsupported();
  bool get isConstructor => _unsupported();
  String get constructorName => _unsupported();
  bool get isConstConstructor => _unsupported();
  bool get isGenerativeConstructor => _unsupported();
  bool get isRedirectingConstructor => _unsupported();
  bool get isFactoryConstructor => _unsupported();
  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();
}

class MethodMirrorImpl implements MethodMirror {
  final int descriptor;
  final String name;
  final int ownerIndex;
  final Reflectable reflectable;

  const MethodMirrorImpl(
      this.name, this.descriptor, this.ownerIndex, this.reflectable);

  int get kind => constants.kindFromEncoding(descriptor);

  ClassMirror get owner => data[reflectable].classMirrors[ownerIndex];

  @override
  String get constructorName => name;

  @override
  bool get isAbstract => 0 != descriptor & constants.abstractAttribute;

  @override
  bool get isConstConstructor => 0 != descriptor & constants.constAttribute;

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
      ["+", "-", "*", "/", "[", "<", ">", "=", "~", "%"].contains(name[0]);

  @override
  bool get isPrivate => 0 != descriptor & constants.privateAttribute;

  @override
  bool get isRedirectingConstructor =>
      0 != descriptor & constants.redirectingConstructor;

  @override
  bool get isRegularMethod => kind == constants.method;

  @override
  bool get isSetter => kind == constants.setter;

  @override
  bool get isStatic => 0 != descriptor & constants.staticAttribute;

  @override
  bool get isSynthetic => 0 != descriptor & constants.syntheticAttribute;

  @override
  bool get isTopLevel => owner is LibraryMirror;

  @override
  SourceLocation get location =>
      throw new UnsupportedError("Location not supported");

  // TODO(sigurdm, eernst): implement metadata
  @override
  List<Object> get metadata => throw new UnimplementedError();

  // TODO(sigurdm, eernst): implement parameters
  @override
  List<ParameterMirror> get parameters => throw new UnimplementedError();

  @override
  String get qualifiedName => "${owner.qualifiedName}.$name";

  // TODO(sigurdm, eernst): implement returnType
  @override
  TypeMirror get returnType => throw new UnimplementedError();

  @override
  String get simpleName => isConstructor
      ? (name == '' ? "${owner.simpleName}" : "${owner.simpleName}.$name")
      : name;

  @override
  String get source => null;

  @override
  String toString() => "MethodMirror($name)";
}

abstract class VariableMirrorUnimpl extends DeclarationMirrorUnimpl
    implements VariableMirror {
  TypeMirror get type => _unsupported();
  bool get isStatic => _unsupported();
  bool get isFinal => _unsupported();
  bool get isConst => _unsupported();
  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();
}

abstract class ParameterMirrorUnimpl extends VariableMirrorUnimpl
    implements ParameterMirror {
  TypeMirror get type => _unsupported();
  bool get isOptional => _unsupported();
  bool get isNamed => _unsupported();
  bool get hasDefaultValue => _unsupported();
  Object get defaultValue => _unsupported();
}

abstract class SourceLocationUnimpl {
  int get line => _unsupported();
  int get column => _unsupported();
  Uri get sourceUri => _unsupported();
}

abstract class Reflectable extends ReflectableBase
    implements ReflectableInterface {

  /// Const constructor, to enable usage as metadata, allowing for varargs
  /// style invocation with up to ten arguments.
  const Reflectable([ReflectCapability cap0 = null,
      ReflectCapability cap1 = null, ReflectCapability cap2 = null,
      ReflectCapability cap3 = null, ReflectCapability cap4 = null,
      ReflectCapability cap5 = null, ReflectCapability cap6 = null,
      ReflectCapability cap7 = null, ReflectCapability cap8 = null,
      ReflectCapability cap9 = null])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const Reflectable.fromList(List<ReflectCapability> capabilities)
      : super.fromList(capabilities);

  @override
  InstanceMirror reflect(Object reflectee) {
    return new InstanceMirrorImpl(reflectee, this);
  }

  @override
  ClassMirror reflectType(Type type) {
    return data[this].classMirrorForType(type);
  }

  @override
  LibraryMirror findLibrary(String library) => _unsupported();

  @override
  Map<Uri, LibraryMirror> get libraries => _unsupported();

  @override
  Iterable<ClassMirror> get annotatedClasses {
    return new List<ClassMirror>.unmodifiable(data[this].classMirrors);
  }
}
