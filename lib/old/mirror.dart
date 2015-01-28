// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.mirror;

// This file defines the same types as sdk/lib/mirrors/mirrors.dart, in
// order to enable code using dart:mirrors to switch to using Reflectable
// based mirrors with the smallest possible change.

// One kind of difference exists:  We took the opportunity to change the
// returned values from reflective operations from mirrors to base values.
// The point is that returning base values may be cheaper in typical
// scenarios (no mirror objects created, and they were never used anyway)
// and there is no loss of information (we can just ask for a mirror on
// the returned value).  So we replace the "pure" design where the
// reflective level is preserved to a "practical" model where we return
// to the base level anywhere possible.  These changes have been marked
// below by comments formatted as follows: '// RET: <old-return-type>'.
// Similarly, modified type arguments have '// TYARG: <old-tyarg>'.
// We can do this for reflective execution of "normal behavior", e.g.,
// looking up the value of a field, or calling a method; but we cannot
// do it for introspective operations (get the class of this object,
// get the fields of this class), i.e., when the returned mirror
// is used to inspect a source code entity (like a class or method).
// In other words, we can change InstanceMirror to Object, but we
// do not change LibraryMirror.

abstract class Mirror {}

// Currently skip 'abstract class IsolateMirror implements Mirror'.

abstract class DeclarationMirror implements Mirror {
  Symbol get simpleName;
  Symbol get qualifiedName;
  DeclarationMirror get owner;
  bool get isPrivate;
  bool get isTopLevel;
  // Currently skip 'SourceLocation get location;'.
  List<Object> get metadata; // TYARG: InstanceMirror
}

abstract class ObjectMirror implements Mirror {
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol,dynamic> namedArguments]); // RET: InstanceMirror
  Object getField(Symbol fieldName); // RET: InstanceMirror
  Object setField(Symbol fieldName, Object value); // RET: InstanceMirror
}

abstract class InstanceMirror implements ObjectMirror {
  TypeMirror get type; // Possible RET: Type
  bool get hasReflectee;
  get reflectee;
  bool operator == (other);
  delegate(Invocation invocation);
}

// Currently skip 'abstract class ClosureMirror implements InstanceMirror'.

abstract class LibraryMirror implements DeclarationMirror, ObjectMirror {
  Uri get uri;
  Map<Symbol, DeclarationMirror> get declarations;
  bool operator == (other);
  List<LibraryDependencyMirror> get libraryDependencies;
}

abstract class LibraryDependencyMirror implements Mirror {
  bool get isImport;
  bool get isExport;
  LibraryMirror get sourceLibrary;
  LibraryMirror get targetLibrary;
  Symbol get prefix;
  // Currently skip 'List<CombinatorMirror> get combinators;'.
  // Currently skip 'SourceLocation get location;'.
  List<Object> get metadata; // TYARG: InstanceMirror
}

// Currently skip 'abstract class CombinatorMirror implements Mirror'.

abstract class TypeMirror implements DeclarationMirror {
  bool get hasReflectedType;
  Type get reflectedType;
  List<TypeVariableMirror> get typeVariables;
  List<TypeMirror> get typeArguments; // Possible TYARG: Type
  bool get isOriginalDeclaration;
  TypeMirror get originalDeclaration; // Possible RET: Type
  bool isSubtypeOf(TypeMirror other); // Possible ARG: Type
  bool isAssignableTo(TypeMirror other); // Possible ARG: Type
}

abstract class ClassMirror implements TypeMirror, ObjectMirror {
  ClassMirror get superclass;
  // Currently skip 'List<ClassMirror> get superinterfaces;'
  bool get isAbstract;
  Map<Symbol, DeclarationMirror> get declarations;
  Map<Symbol, MethodMirror> get instanceMembers;
  Map<Symbol, MethodMirror> get staticMembers;
  ClassMirror get mixin; // Possible RET: Type
  Object newInstance(Symbol constructorName,
                     List positionalArguments,
                     [Map<Symbol,dynamic> namedArguments]);
                     // RET: InstanceMirror
  bool operator == (other);
  bool isSubclassOf(ClassMirror other); // Possible ARG: Type
}

// Currently skip 'abstract class FunctionTypeMirror implements ClassMirror'.

abstract class TypeVariableMirror extends TypeMirror {
  TypeMirror get upperBound; // Possible RET: Type
  bool get isStatic;
  bool operator == (other);
}

// Currently skip 'abstract class TypedefMirror implements TypeMirror'.

abstract class MethodMirror implements DeclarationMirror {
  TypeMirror get returnType; // Possible RET: Type
  String get source;
  List<ParameterMirror> get parameters;
  bool get isStatic;
  bool get isAbstract;
  bool get isSynthetic;
  bool get isRegularMethod;
  bool get isOperator;
  bool get isGetter;
  bool get isSetter;
  bool get isConstructor;
  Symbol get constructorName;
  bool get isConstConstructor;
  bool get isGenerativeConstructor;
  bool get isRedirectingConstructor;
  bool get isFactoryConstructor;
  bool operator == (other);
}

abstract class VariableMirror implements DeclarationMirror {
  TypeMirror get type; // Possible RET: Type
  bool get isStatic;
  bool get isFinal;
  bool get isConst;
  bool operator == (other);
}

abstract class ParameterMirror implements VariableMirror {
  TypeMirror get type; // Possible RET: Type
  bool get isOptional;
  bool get isNamed;
  bool get hasDefaultValue;
  Object get defaultValue; // RET: InstanceMirror
}
