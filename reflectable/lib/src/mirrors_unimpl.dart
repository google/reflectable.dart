// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import '../mirrors.dart';
import 'encoding_constants.dart' as constants;
export 'dart:collection' show UnmodifiableMapView;
export '../capability.dart';
export '../static_reflectable.dart';

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

abstract class ClassMirrorUnimpl extends TypeMirrorUnimpl
    with ObjectMirrorUnimpl implements ClassMirror {
  ClassMirror get superclass => _unsupported();
  List<ClassMirror> get superinterfaces => _unsupported();
  bool get isAbstract => _unsupported();
  Map<String, DeclarationMirror> get declarations => _unsupported();
  Map<String, MethodMirror> get instanceMembers => _unsupported();
  Map<String, MethodMirror> get staticMembers => _unsupported();
  ClassMirror get mixin => _unsupported();
  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) => _unsupported();
  bool operator ==(other) => _unsupported();
  int get hashCode => _unsupported();
  bool isSubclassOf(ClassMirror other) => _unsupported();
}

abstract class FunctionTypeMirrorUnimpl extends ClassMirrorUnimpl
    implements FunctionTypeMirror {
  TypeMirror get returnType => _unsupported();
  List<ParameterMirror> get parameters => _unsupported();
  MethodMirror get callMethod => _unsupported();
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
  @override
  final DeclarationMirror owner;

  const MethodMirrorImpl(this.name, this.descriptor, this.owner);

  int get kind => constants.kindFromEncoding(descriptor);

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
