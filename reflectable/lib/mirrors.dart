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
// These selected cases are [invoke], [getField], and
// [setField] in [ObjectMirror], [newInstance] in
// [ClassMirror], and [defaultValue] in [ParameterMirror], where the
// return type has been changed from InstanceMirror to Object.
// Similarly, the return type for [metadata] in [DeclarationMirror] and
// in [LibraryDependencyMirror] was changed from List<InstanceMirror> to
// List<Object>.  The relevant locations in the code below have been
// marked with comments on the form '// RET: <old-return-type>'
// resp. '// TYARG: <old-type-argument>' and the discrepancies are
// mentioned in the relevant class dartdoc.
//
// TODO(eernst) doc: The information given in the previous paragraph
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

// TODO(eernst) doc: The preceeding comment blocks should be made a dartdoc
// on the library when/if such dartdoc comments are supported.
// TODO(eernst) doc: Change the preceeding comment to use a more
// user-centric style.

// TODO(eernst) doc: This is a Meta-TODO, adding detail to several TODOs below
// saying 'make this .. more user friendly' as well as the comment above
// saying 'more user-centric'. All those "not-so-friendly" comments originate
// in the `mirrors.dart` file that implements the `dart:mirrors` library, so
// missing dartdoc comments in this file would typically be taken from
// there and then adjusted to match the preferred style in this library.
// The following points should be kept in mind in this adjustment process:
//   1. The documentation from `dart:mirrors` is too abstract for typical
// programmers (it is in a near-spec style), so maybe that kind of
// documentation should be provided in a separate location, and the
// documentation that programmers get to see first will be example based
// and less abstract.
//   2. Formatting: *name* is used to indicate pseudo-semantic entities
// such as objects (that may or may not be the value of a known expression)
// and meta-variables for identifiers, etc. This is explained in the
// documentation for `dart:mirrors` (search 'Dart pseudo-code' on
// https://api.dartlang.org/apidocs/channels/stable/dartdoc-viewer/dart:mirrors)
//   3. Semantic precision may be pointless in cases where the underlying
// concepts are obvious; having an example based frontmost layer and a more
// spec-styled layer behind it would be helpful with this as well, because
// the example layer could be quite simple.
//   4. Considering `invokeGetter`, the example based approach could be
// similar to the following:
//
//   Invokes a getter and returns the result. Conceptually, this function is
//   equivalent to `this.reflectee.name` where the `name` identifier is the
//   value of the given [getterName].
//
//   Example:
//     var m = reflectable.reflect(o);
//     m.invokeGetter("foo");  // Equivalent to o.foo.
//
//   (then give more detail if the simple explanation above needs it).

library reflectable.mirrors;

// Currently skip 'abstract class MirrorSystem': represented by reflectors.

// Currently skip 'external MirrorSystem currentMirrorSystem': represented by
// reflectors.

// Omit 'external InstanceMirror reflect': method on reflectors.

// Currently skip 'external ClassMirror reflectClass'.

// Omit 'external TypeMirror reflectType': method on reflectors.

abstract class Mirror {}

// Currently skip 'abstract class IsolateMirror implements Mirror'.

abstract class DeclarationMirror implements Mirror {
  String get simpleName;
  String get qualifiedName;
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
   * TODO(eernst) doc: Make this comment more user friendly.
   * TODO(eernst) implement: Include comments as `metadata`, remember to
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
   * Invokes the function or method [memberName], and returns the result.
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
   * the result *r*.
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   *
   * TODO(eernst) doc: make this comment more user friendly.
   * TODO(eernst) doc: revise language on private members when semantics known.
   */
  Object invoke(String memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]); // RET: InstanceMirror

  /**
   * Invokes a getter and returns the result. The getter can be the
   * implicit getter for a field, or a user-defined getter method.
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
   * method on its reflectee, the result of the invocation is a closure
   * corresponding to that method.
   *
   * If this mirror is a [LibraryMirror], and [fieldName] denotes a top-level
   * method in the corresponding library, the result of the invocation is a
   * closure corresponding to that method.
   *
   * If this mirror is a [ClassMirror], and [fieldName] denotes a static method
   * in the corresponding class, the result of the invocation is a closure
   * corresponding to that method.
   *
   * If the invocation returns a result *r*, this method returns
   * the result *r*.
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   *
   * TODO(eernst) doc: make this comment more user friendly.
   * TODO(eernst) doc: revise language on private members when semantics known.
   */
  Object invokeGetter(String getterName);

  /**
   * Invokes a setter and returns the result. The setter may be either
   * the implicit setter for a non-final field, or a user-defined setter
   * method. The name of the setter can include the final `=`; if it is
   * not present, it will be added.
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
   * the result *r*.
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * Note that the return type of the corresponding method in
   * dart:mirrors is InstanceMirror.
   *
   * TODO(eernst) doc: make this comment more user friendly.
   * TODO(eernst) doc: revise language on private members when semantics known.
   */
  Object invokeSetter(String setterName, Object value);
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
  Map<String, DeclarationMirror> get declarations;
  bool operator ==(other);
  List<LibraryDependencyMirror> get libraryDependencies;
}

abstract class LibraryDependencyMirror implements Mirror {
  bool get isImport;
  bool get isExport;
  bool get isDeferred;
  LibraryMirror get sourceLibrary;
  LibraryMirror get targetLibrary;
  String get prefix;
  List<CombinatorMirror> get combinators;
  SourceLocation get location;

  /// Note that the return type of the corresponding method in
  /// dart:mirrors is List<InstanceMirror>.
  List<Object> get metadata; // TYARG: InstanceMirror
}

abstract class CombinatorMirror implements Mirror {
  List<String> get identifiers;
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
  // The non-abstract members declared in this class.
  Map<String, DeclarationMirror> get declarations;
  Map<String, MethodMirror> get instanceMembers;
  Map<String, MethodMirror> get staticMembers;

  ClassMirror get mixin;

  /**
   * Invokes the named constructor and returns the result.
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
   * the result *r*.
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
   * TODO(eernst) doc: make this comment more user friendly.
   * TODO(eernst) doc: revise language on private members when semantics known.
   */
  Object newInstance(String constructorName,
                     List positionalArguments,
                     [Map<Symbol, dynamic> namedArguments]);
                     // RET: InstanceMirror

  bool operator ==(other);

  // Possible ARG: Type.
  // Input from Gilad on [TypeMirror#isSubtypeOf] is also relevant for this
  // case.
  bool isSubclassOf(ClassMirror other);

  /**
   * Returns an invoker builder for the given [memberName]. An invoker builder
   * is a closure that takes an object and returns an invoker for that object.
   * The returned invoker is a closure that invokes the [memberName] on the
   * object it is specialized for. In other words, the invoker-builder returns
   * a tear-off of [memberName] for any given object that implements the
   * class this [ClassMirror] reflects on.
   *
   * Example:
   *   var invokerBuilder = classMirror.invoker("foo");
   *   var invoker = invokerBuilder(o);
   *   invoker(42);  // Equivalent to o.foo(42).
   *
   * More precisely, let *c* be the returned closure, let *f* be the simple
   * name of the member denoted by [memberName], and let *o* be an instance
   * of the class reflected by this mirror. Consider the following invocation:
   *  *c(o)(a1, ..., an, k1: v1, ..., km: vm)*
   * This invocation corresponds to the following non-reflective invocation:
   *  *o.f(a1, ..., an, k1: v1, ..., km: vm)*
   * in a scope that has access to the private members
   * of the class of *o*.
   * If the invocation returns a result *r*, this method returns
   * the result *r*.
   * If the invocation causes a compilation error
   * the effect is the same as if a non-reflective compilation error
   * had been encountered.
   * If the invocation throws an exception *e* (that it does not catch)
   * this method throws *e*.
   *
   * Note that this method is not available in the corresponding dart:mirrors
   * interface. It was added here because it enables many invocations
   * of a reflectively chosen method on different receivers using just
   * one reflective operation, whereas the dart:mirrors interface requires
   * a reflective operation for each new receiver (which is in practice
   * likely to mean a reflective operation for each invocation).
   *
   * TODO(eernst) doc: revise language on private members when semantics known.
   */
  Function invoker(String memberName);
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
  String get constructorName;
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
