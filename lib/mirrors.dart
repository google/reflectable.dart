// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// This file defines the same types as sdk/lib/mirrors/mirrors.dart, in
// order to enable code using [dart:mirrors] to switch to using
// [Reflectable] based mirrors with the smallest possible change.
// The changes are discussed below, under headings on the form
// 'API Change: ..'.

// API Change: Incompleteness.
//
// Compared to the corresponding classes in [dart:mirrors], a number of
// classes have been omitted and some methods have been omitted from some
// classes, based on the needs arising in concrete examples.  Additional
// methods may be added later if the need arises and if they can be
// implemented.  These missing elements are indicated by comments on the
// form '// Currently skip ..' in the code below.

// API Change: Returning non-mirrors.
//
// One kind of difference exists:  We took the opportunity to change the
// returned values of reflective operations from mirrors to base values.
// E.g., [invoke] in [ObjectMirror] has return type [Object] rather than
// [InstanceMirror].  If myObjectMirror is [ObjectMirror] then evaluation
// of, e.g., myObjectMirror.invoke(..) yields the same result as that of
// myObjectMirror.invoke(..).reflectee in [dart:mirrors].  The point is
// that returning base values may be cheaper in typical scenarios (no
// mirror objects created, and they were never used anyway) and there is
// no loss of information (we can get a mirror on the returned value).
// So we move from the "pure" design where the reflective level is
// always preserved to a "practical" model where we return to the base
// level in selected cases.
//
// These selected cases are [invoke], [@deprecated getField], and
// [@deprecated setField] in [ObjectMirror], [newInstance] in
// [ClassMirror], and [defaultValue] in [ParameterMirror], where the
// return type has been changed from InstanceMirror to Object.
// Similarly, the return type for [metadata] in [DeclarationMirror] and
// in [LibraryDependencyMirror] was changed from List<InstanceMirror> to
// List<Object>.  The relevant locations in the code below have been
// marked with comments on the form '// RET: <old-return-type>'
// resp. '// TYARG: <old-type-argument>' and the discrepancies are
// mentioned in the relevant class dartdoc.
//
// TODO(eernst): The information given in the previous paragraph
// should be made part of the dartdoc comments on each of the relevant
// methods; since those comments will now differ from the ones in
// dart:mirrors, we should copy them all and add the discrepancies.
//
// A similar change could have been applied to many other methods, but
// in those cases it seems more likely that the mirror will be used
// in its own right rather than just to get 'theMirror.reflectee'.
// Some of these locations are marked with '// Possible'.  They are in
// general concerned with types in a broad sense: [ClassMirror],
// [TypeMirror], and [LibraryMirror].

// TODO(eernst): The preceeding comment blocks should be made a dartdoc
// on the library when/if such dartdoc comments are supported.
// TODO(eernst): Change the preceeding comment to use a more
// user-centric style.

library reflectable.mirrors;

// Currently skip 'abstract class MirrorSystem'

// Currently skip 'external MirrorSystem currentMirrorSystem'

// Currently skip 'external InstanceMirror reflect'

// Currently skip 'external ClassMirror reflectClass'

// Currently skip 'external TypeMirror reflectType'

abstract class Mirror {}

// Currently skip 'abstract class IsolateMirror implements Mirror'.

abstract class DeclarationMirror implements Mirror {
  Symbol get simpleName;
  Symbol get qualifiedName;
  DeclarationMirror get owner;
  bool get isPrivate;
  bool get isTopLevel;
  SourceLocation get location;

  /**
   * A list of the metadata associated with this declaration.
   *
   * Let *D* be the declaration this mirror reflects.
   * If *D* is decorated with annotations *A1, ..., An*
   * where *n > 0*, then for each annotation *Ai* associated
   * with *D, 1 <= i <= n*, let *ci* be the constant object
   * specified by *Ai*. Then this method returns a list whose
   * members are instance mirrors on *c1, ..., cn*.
   * If no annotations are associated with *D*, then
   * an empty list is returned.
   *
   * If evaluating any of *c1, ..., cn* would cause a
   * compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is List<InstanceMirror>.
   *
   * TODO(eernst): Make this comment more user friendly.
   * TODO(eernst): Include comments as `metadata`, remember to
   * indicate which ones are doc comments (`isDocComment`),
   * cf. https://github.com/dart-lang/reflectable/issues/3.
   * Note that we may wish to represent a comment as an
   * instance of [Comment] from reflectable/mirrors.dart,
   * which is required in order to indicate explicitly that it is
   * a doc comment; or we may decide that this violation of the
   * "return a base object, not a mirror" rule is unacceptable, and
   * return a [String], thus requiring the receiver to determine
   * whether or not it is a doc comment, based on the contents
   * of the [String].  
   * Remark from sigurdm@ on this topic, 2015/03/19 09:50:06: We
   * could also consider extending the interface with a
   * `docComments` or similar.  To me it is highly confusing that
   * metadata returns comments.  But if dart:mirrors does this we
   * might just want to follow along.
   */
  List<Object> get metadata; // TYARG: InstanceMirror
}

abstract class ObjectMirror implements Mirror {

  /**
   * Invokes the named function and returns a mirror on the result.
   *
   * Let *o* be the object reflected by this mirror, let
   * *f* be the simple name of the member denoted by [memberName],
   * let *a1, ..., an* be the elements of [positionalArguments]
   * let *k1, ..., km* be the identifiers denoted by the elements of
   * [namedArguments.keys]
   * and let *v1, ..., vm* be the elements of [namedArguments.values].
   * Then this method will perform the method invocation
   *  *o.f(a1, ..., an, k1: v1, ..., km: vm)*
   * in a scope that has access to the private members
   * of *o* (if *o* is a class or library) or the private members of the
   * class of *o* (otherwise).
   * If the invocation returns a result *r*, this method returns
   * the result of calling [reflect](*r*).
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   *
   * TODO(eernst): make this comment more user friendly.
   */
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]); // RET: InstanceMirror

  /**
   * Deprecated method which has the same semantics as [invokeGetter].
   *
   * Ahead, [invokeGetter] is expected to be the only name for this operation,
   * and the name [@deprecated getField] is expected to be reused for a
   * different semantics that reads the value of a field, bypassing any getters.
   * Since this is a breaking change it is not likely to happen before a major
   * step in the version number, but users of mirrors can already now start
   * using the future-safe name [invokeGetter].
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   */
  @deprecated
  Object getField(Symbol fieldName); // RET: InstanceMirror

  /**
   * Invokes a getter and returns a mirror on the result. The getter
   * can be the implicit getter for a field or a user-defined getter
   * method.
   *
   * Let *o* be the object reflected by this mirror, let
   * *f* be the simple name of the getter denoted by [fieldName],
   * Then this method will perform the getter invocation
   *  *o.f*
   * in a scope that has access to the private members
   * of *o* (if *o* is a class or library) or the private members of the
   * class of *o* (otherwise).
   *
   * If this mirror is an [InstanceMirror], and [fieldName] denotes an instance
   * method on its reflectee, the result of the invocation is an instance
   * mirror on a closure corresponding to that method.
   *
   * If this mirror is a [LibraryMirror], and [fieldName] denotes a top-level
   * method in the corresponding library, the result of the invocation is an
   * instance mirror on a closure corresponding to that method.
   *
   * If this mirror is a [ClassMirror], and [fieldName] denotes a static method
   * in the corresponding class, the result of the invocation is an instance
   * mirror on a closure corresponding to that method.
   *
   * If the invocation returns a result *r*, this method returns
   * the result of calling [reflect](*r*).
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * TODO(eernst): make this comment more user friendly.
   */
  Object invokeGetter(Symbol fieldName) => getField(fieldName);

  /**
   * Deprecated method which has the same semantics as [invokeSetter].
   *
   * Ahead, [invokeSetter] is expected to be the only name for this
   * operation, and the name [@deprecated setField] is expected to be
   * reused for a different semantics that writes the value of a field,
   * bypassing any setters.  Since this is a breaking change it is not
   * likely to happen before a major step in the version number, but
   * users of mirrors can already now start using the future-safe name
   * [invokeSetter].
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   */
  @deprecated
  Object setField(Symbol fieldName, Object value); // RET: InstanceMirror

  /**
   * Invokes a setter and returns a mirror on the result. The setter
   * may be either the implicit setter for a non-final field or a
   * user-defined setter method.
   *
   * Let *o* be the object reflected by this mirror, let
   * *f* be the simple name of the getter denoted by [fieldName],
   * and let *a* be the object bound to [value].
   * Then this method will perform the setter invocation
   * *o.f = a*
   * in a scope that has access to the private members
   * of *o* (if *o* is a class or library) or the private members of the
   * class of *o* (otherwise).
   * If the invocation returns a result *r*, this method returns
   * the result of calling [reflect]([value]).
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   *
   * TODO(eernst): make this comment more user friendly.
   */
  Object invokeSetter(Symbol fieldName, Object value) =>
      setField(fieldName, value);
}

abstract class InstanceMirror implements ObjectMirror {
  ClassMirror get type;
  bool get hasReflectee;
  get reflectee;
  bool operator ==(other);
  delegate(Invocation invocation);
}

abstract class ClosureMirror implements InstanceMirror {
  MethodMirror get function;
  Object apply(List positionalArguments,
               [Map<Symbol, dynamic> namedArguments]); // RET: InstanceMirror
}

abstract class LibraryMirror implements DeclarationMirror, ObjectMirror {
  Uri get uri;
  Map<Symbol, DeclarationMirror> get declarations;
  bool operator ==(other);
  List<LibraryDependencyMirror> get libraryDependencies;
}

abstract class LibraryDependencyMirror implements Mirror {
  bool get isImport;
  bool get isExport;
  bool get isDeferred;
  LibraryMirror get sourceLibrary;
  LibraryMirror get targetLibrary;
  Symbol get prefix;
  List<CombinatorMirror> get combinators;
  SourceLocation get location;

  /// Note that the return type of the corresponding method in
  /// dart:mirrors is List<InstanceMirror>.
  List<Object> get metadata; // TYARG: InstanceMirror
}

abstract class CombinatorMirror implements Mirror {
  List<Symbol> get identifiers;
  bool get isShow;
  bool get isHide;
}

abstract class TypeMirror implements DeclarationMirror {
  bool get hasReflectedType;
  Type get reflectedType;
  List<TypeVariableMirror> get typeVariables;
  List<TypeMirror> get typeArguments;
  bool get isOriginalDeclaration;
  TypeMirror get originalDeclaration;

  // Possible ARG: Type.
  // Input from Gilad on this issue:
  // I think we could consider using Type objects as arguments, because that is
  // actually more uniform; in general, the mirror API takes in base level
  // objects and produces meta-level objects. As a practical matter, I'd say we
  // take both.  Union types make that more natural, though there will be some
  // slight cost in checking what kind of argument we get.
  bool isSubtypeOf(TypeMirror other);

  // Possible ARG: Type.
  // Input from Gilad on isSubtypeOf is also relevant for this case.
  bool isAssignableTo(TypeMirror other);
}

abstract class ClassMirror implements TypeMirror, ObjectMirror {
  ClassMirror get superclass;
  List<ClassMirror> get superinterfaces;
  bool get isAbstract;
  Map<Symbol, DeclarationMirror> get declarations;
  Map<Symbol, MethodMirror> get instanceMembers;
  Map<Symbol, MethodMirror> get staticMembers;
  ClassMirror get mixin;

   /**
   * Invokes the named constructor and returns a mirror on the result.
   *
   * Let *c* be the class reflected by this mirror
   * let *a1, ..., an* be the elements of [positionalArguments]
   * let *k1, ..., km* be the identifiers denoted by the elements of
   * [namedArguments.keys]
   * and let *v1, ..., vm* be the elements of [namedArguments.values].
   * If [constructorName] was created from the empty string
   * Then this method will execute the instance creation expression
   * *new c(a1, ..., an, k1: v1, ..., km: vm)*
   * in a scope that has access to the private members
   * of *c*. Otherwise, let
   * *f* be the simple name of the constructor denoted by [constructorName]
   * Then this method will execute the instance creation expression
   *  *new c.f(a1, ..., an, k1: v1, ..., km: vm)*
   * in a scope that has access to the private members
   * of *c*.
   * In either case:
   * If the expression evaluates to a result *r*, this method returns
   * the result of calling [reflect](*r*).
   * If evaluating the expression causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If evaluating the expression throws an exception *e*
   * (that it does not catch)
   * this method throws *e*.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   *
   * TODO(eernst): make this comment more user friendly.
   */
  Object newInstance(Symbol constructorName,
                     List positionalArguments,
                     [Map<Symbol,dynamic> namedArguments]);
                     // RET: InstanceMirror

  bool operator ==(other);

  // Possible ARG: Type.
  // Input from Gilad on [TypeMirror#isSubtypeOf] is also relevant for this
  // case.
  bool isSubclassOf(ClassMirror other);
}

abstract class FunctionTypeMirror implements ClassMirror {
  TypeMirror get returnType;
  List<ParameterMirror> get parameters;
  MethodMirror get callMethod;
}

abstract class TypeVariableMirror extends TypeMirror {
  TypeMirror get upperBound; // Possible RET: Type
  bool get isStatic;
  bool operator ==(other);
}

abstract class TypedefMirror implements TypeMirror {
  FunctionTypeMirror get referent;
}

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
  bool operator ==(other);
}

abstract class VariableMirror implements DeclarationMirror {
  TypeMirror get type; // Possible RET: Type
  bool get isStatic;
  bool get isFinal;
  bool get isConst;
  bool operator ==(other);
}

abstract class ParameterMirror implements VariableMirror {
  TypeMirror get type; // Possible RET: Type
  bool get isOptional;
  bool get isNamed;
  bool get hasDefaultValue;
  Object get defaultValue; // RET: InstanceMirror
}

abstract class SourceLocation {
  int get line;
  int get column;
  Uri get sourceUri;
}

class Comment {
  final String text;
  final String trimmedText;
  final bool isDocComment;
  const Comment(this.text, this.trimmedText, this.isDocComment);
}
