// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// NB! It is crucial that all changes made in this library are
// performed in the corresponding manner in `src/element_capability.dart`,
// and vice versa.

/// Provides the classes and constants used for configuring the capabilities of
/// a reflector (an instance of a subclass of `Reflectable`).
///
/// The subclasses of [ReflectCapability] can be used to describe the classes
/// and methods that are covered by a reflector, and what queries are allowed.
///
/// The goal is to be able to describe as precisely as possible what the
/// reflector needs to "know", so only the minimal amount of support code has to
/// be generated.
///
/// In general the semantics are additive --- meaning that adding a capability
/// will only allow more reflection --- and commutative, so the order of the
/// capabilities does not matter.
///
/// Most of the member-specifying capabilities exist in a version using a String
/// denoting a RegExp to match member names, and in a version taking a `Type`,
/// and matching all members with a metadata annotation of that type or a
/// subtype thereof.
///
/// For example `InstanceInvokeCapability(r'^foo')` will cover all instance
/// members of annotated classes that start with
/// 'foo'. `InstanceInvokeMetaCapability(Deprecated)` would cover all instance
/// members that are marked as `Deprecated`.
///
/// Hint: It is important to realize that the amount of generated code might not
/// be what will have the biggest impact on the amount of code generated by the
/// compilation to JavaScript, because it is dominated by code that it prevents
/// from being tree-shaken away. And especially the set of instance-methods
/// will generate closures that invoke that method on any target, thus
/// preventing dart2js from removing any method with that name of any
/// instantiated class.
///
/// More details can be found in the [design
/// document](https://github.com/dart-lang/reflectable/blob/master/reflectable/doc/TheDesignOfReflectableCapabilities.md)
/// about this library.
library reflectable.capability;

import 'reflectable.dart';

/// A [ReflectCapability] of a reflectable mirror specifies the kinds of
/// reflective operations that are supported for instances of the
/// associated classes.
///
/// A class `C` is connected to a [ReflectCapability] `K` by giving `K` as a
/// const constructor superinitializer in a subclass `R` of [Reflectable], and
/// then including an instance of `R` in the metadata associated with `C`.
abstract class ReflectCapability {
  const ReflectCapability();
}

// ---------- API oriented capability classes and instances.

/// Abstract superclass of all capabilities concerned with the request for
/// reflective support for a certain part of the mirror class APIs, as
/// opposed to the second order capabilities which are used to associate
/// these API based capabilities with a certain set of potential
/// reflectees.
abstract class ApiReflectCapability implements ReflectCapability {
  const ApiReflectCapability();
}

/// Abstract superclass of all capability classes using a regular
/// expression to match names of behaviors (such as methods and
/// constructors).
abstract class NamePatternCapability implements ApiReflectCapability {
  final String namePattern;
  const NamePatternCapability(this.namePattern);
}

/// Abstract superclass of all capability classes recognizing a particular
/// instance used as metadata as a criterion for providing the annotated
/// declaration with reflection support. Note that there are no constraints
/// on the type of metadata, i.e., it could be metadata which is already
/// used for other purposes related to other packages, but which happens
/// to occur in just the right locations.
abstract class MetadataQuantifiedCapability implements ApiReflectCapability {
  final Type metadataType;
  const MetadataQuantifiedCapability(this.metadataType);
}

/// Gives support for reflective invocation of instance members (methods,
/// getters, and setters) matching [namePattern] interpreted as a regular
/// expression.
class InstanceInvokeCapability extends NamePatternCapability {
  const InstanceInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `InstanceInvokeCapability('')`, meaning the capability to
/// reflect over all instance members.
const instanceInvokeCapability = InstanceInvokeCapability('');

/// Gives support for reflective invocation of instance members (methods,
/// getters, and setters) annotated with instances of [metadataType] or a
/// subtype thereof.
class InstanceInvokeMetaCapability extends MetadataQuantifiedCapability {
  const InstanceInvokeMetaCapability(Type metadataType) : super(metadataType);
}

/// Gives support for reflective invocation of static members (static methods,
/// getters, and setters) matching [namePattern] interpreted as a regular
/// expression.
class StaticInvokeCapability extends NamePatternCapability
    implements TypeCapability {
  const StaticInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `StaticInvokeCapability('')`, meaning the capability to
/// reflect over all static members.
const staticInvokeCapability = StaticInvokeCapability('');

/// Gives support for reflective invocation of static members (static methods,
/// getters, and setters) that are annotated with instances of [metadataType]
/// or a subtype thereof.
class StaticInvokeMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const StaticInvokeMetaCapability(Type metadata) : super(metadata);
}

/// Gives support for reflective invocation of top-level members (top-level
/// methods, getters, and setters) matching [namePattern] interpreted as a
/// regular expression.
class TopLevelInvokeCapability extends NamePatternCapability {
  const TopLevelInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `TopLevelInvokeCapability('')`, meaning the capability to
/// reflect over all top-level members.
const topLevelInvokeCapability = TopLevelInvokeCapability('');

/// Gives support for reflective invocation of top-level members (top-level
/// methods, getters, and setters) that are annotated with instances of
/// [metadataType].
class TopLevelInvokeMetaCapability extends MetadataQuantifiedCapability {
  const TopLevelInvokeMetaCapability(Type metadataType) : super(metadataType);
}

/// Gives support for reflective invocation of constructors (of all kinds)
///  matching [namePattern] interpreted as a regular expression.
///
/// Constructors with the empty name are considered to have the name 'new'.
///
/// Note that this capability implies [TypeCapability], because there is no way
/// to perform a `newInstance` operation without class mirrors.
class NewInstanceCapability extends NamePatternCapability
    implements TypeCapability {
  const NewInstanceCapability(String namePattern) : super(namePattern);
}

/// Short hand for `const NewInstanceCapability('')`, meaning the capability to
/// reflect over all constructors.
const newInstanceCapability = NewInstanceCapability('');

/// Gives support for reflective invocation
/// of constructors (of all kinds) annotated by instances of [metadataType]
/// or a subtype thereof.
class NewInstanceMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const NewInstanceMetaCapability(Type metadataType) : super(metadataType);
}

/// Gives support for reflective access to metadata associated with a
/// declaration reflected by a given declaration mirror.
class MetadataCapability implements TypeCapability {
  const MetadataCapability();
}

/// Shorthand for `const MetadataCapability()`.
const metadataCapability = MetadataCapability();

/// Gives support for invocation of the method `reflectType` on reflectors, and
/// for invocation of the method `type` on instances of `InstanceMirror` and
/// `ParameterMirror` as well as the method `returnType` on instances of
/// `MethodMirror`.
///
/// Note that without this, there is no need to support any kind of reflective
/// operations producing mirrors of source code entities (that is, instances of
/// `ClassMirror`, `MethodMirror`, `DeclarationMirror`, `LibraryMirror`,
/// `LibraryDependencyMirror`, `CombinatorMirror`, `TypeMirror`,
/// `FunctionTypeMirror`, `TypeVariableMirror`, `TypedefMirror`,
/// `VariableMirror`, and `ParameterMirror`), which may reduce the space
/// consumption significantly because the generation of those classes can be
/// avoided entirely.
class TypeCapability implements ApiReflectCapability {
  const TypeCapability();
}

/// Shorthand for `const TypeCapability()`.
const typeCapability = TypeCapability();

/// Gives support for: `typeVariables`, `typeArguments`,
/// `originalDeclaration`, `isSubtypeOf`, `isAssignableTo`, `superclass`,
/// `superinterfaces`, `mixin`, `isSubclassOf`, `upperBound`, and `referent`.
class TypeRelationsCapability implements TypeCapability {
  const TypeRelationsCapability();
}

/// Shorthand for `const TypeRelationsCapability()`.
const typeRelationsCapability = TypeRelationsCapability();

/// Gives support for the method `reflectedType` on `VariableMirror` and
/// `ParameterMirror`, and for the method `reflectedReturnType` on
/// `MethodMirror`.
const reflectedTypeCapability = _ReflectedTypeCapability();

/// Gives support for library-mirrors.
///
/// This will cause support for reflecting for all libraries containing
/// annotated classes (enabling support for [ClassMirror.owner]), and all
/// annotated libraries.
///
/// TODO(sigurdm) feature: Split this into EnclosingLibraryCapability(),
/// LibraryCapabiliy(String regex) and LibraryMetaCapability(Type type).
class LibraryCapability implements ApiReflectCapability {
  const LibraryCapability();
}

/// Shorthand for `const LibraryCapability()`.
const libraryCapability = LibraryCapability();

/// Gives support for: `declarations`, `instanceMembers`, `staticMembers`,
/// `callMethod`, `parameters`, and `defaultValue`.
///
/// Note that it is useless to
/// request this capability if no other capabilities have given rise to the
/// generation of source code related mirror classes, because these methods are
/// only defined by those mirror classes.
class DeclarationsCapability implements TypeCapability {
  const DeclarationsCapability();
}

/// Shorthand for `const DeclarationsCapability()`.
const declarationsCapability = DeclarationsCapability();

/// Gives support for the mirror method `uri` on LibraryMirrors.
class UriCapability implements LibraryCapability {
  const UriCapability();
}

/// Shorthand for `const UriCapability()`.
const uriCapability = UriCapability();

/// Gives support for: `sourceLibrary`, `targetLibrary`, `prefix`, and
/// `combinators`.
class LibraryDependenciesCapability implements LibraryCapability {
  const LibraryDependenciesCapability();
}

/// Shorthand for `const LibraryDependenciesCapability()`.
const libraryDependenciesCapability = LibraryDependenciesCapability();

/// Gives all the capabilities of [InstanceInvokeCapability]([namePattern]),
/// [StaticInvokeCapability]([namePattern]), and
/// [NewInstanceCapability]([namePattern]).
class InvokingCapability extends NamePatternCapability
    implements
        InstanceInvokeCapability,
        StaticInvokeCapability,
        NewInstanceCapability {
  const InvokingCapability(String namePattern) : super(namePattern);
}

/// Short hand for `InvokingCapability('')`, meaning the capability to
/// reflect over all top-level and static members.
const invokingCapability = InvokingCapability('');

/// Gives the capabilities of all the capabilities requested by
/// [InstanceInvokeMetaCapability]([metadata]),
/// [StaticInvokeMetaCapability]([metadata]), and
/// [NewInstanceMetaCapability]([metadata]).
class InvokingMetaCapability extends MetadataQuantifiedCapability
    implements
        InstanceInvokeMetaCapability,
        StaticInvokeMetaCapability,
        NewInstanceMetaCapability {
  const InvokingMetaCapability(Type metadataType) : super(metadataType);
}

/// Gives the capabilities of [TypeCapability], [metadataCapability],
/// [typeRelationsCapability], [declarationsCapability], [uriCapability], and
/// [libraryDependenciesCapability].
class TypingCapability
    implements
        TypeCapability, // Redundant, just included for readability.
        MetadataCapability,
        TypeRelationsCapability,
        DeclarationsCapability,
        UriCapability,
        LibraryDependenciesCapability {
  const TypingCapability();
}

/// Shorthand for `const TypingCapability()`.
const typingCapability = TypingCapability();

/// Capability instance giving support for the `delegate` method on instance
/// mirrors when it leads to invocation of a method where instance invocation
/// is supported. Also implies support for translation of [Symbol]s of covered
/// members to their corresponding [String]s.
const delegateCapability = _DelegateCapability();

// ---------- Reflectee quantification oriented capability classes.

/// Abstract superclass for all capability classes supporting quantification
/// over the set of potential reflectees.
///
/// The quantifying capability classes
/// are capable of recieving a list of up to ten [ApiReflectCapability]
/// arguments in a varargs style (just a comma separated list of arguments,
/// rather than enclosing them in `<ApiReflectCapability>[]`). When even more
/// than ten arguments are needed, the `fromList` constructor should be used.
abstract class ReflecteeQuantifyCapability implements ReflectCapability {
  const ReflecteeQuantifyCapability();
}

/// Quantifying capability instance specifying that the reflection support
/// covers all subclasses of annotated classes and classes matching global
/// quantifiers.
///
/// Note that this is applied before `superclassQuantifyCapability` and before
/// any `TypeAnnotationQuantifyCapability`.
const subtypeQuantifyCapability = _SubtypeQuantifyCapability();

/// Gives support for reflection on all superclasses of covered classes up to
/// [upperBound]
///
/// The class [upperBound] itself is not included if [excludeUpperBound] is
/// `true`.
class SuperclassQuantifyCapability implements ReflecteeQuantifyCapability {
  final Type upperBound;
  final bool excludeUpperBound;
  const SuperclassQuantifyCapability(this.upperBound,
      {bool excludeUpperBound = false})
      : excludeUpperBound = excludeUpperBound;
}

/// Gives support for reflection on all superclasses of covered classes.
///
/// Short for: `const SuperclassQuantifyCapability(Object)`.
const superclassQuantifyCapability = SuperclassQuantifyCapability(Object);

/// Gives support for reflecting on the classes used as type annotations
/// of covered methods, parameters and fields. If [transitive] is true the
/// support also extends to annotations of their methods, parameters and fields
/// etc.
class TypeAnnotationQuantifyCapability implements ReflecteeQuantifyCapability {
  final bool transitive;
  const TypeAnnotationQuantifyCapability({bool transitive = false})
      : transitive = transitive;
}

/// Gives support for reflecting on the classes used as type annotations
/// of covered methods, parameters and fields.
///
/// Short for `const TypeAnnotationQuantifyCapability()`.
const typeAnnotationQuantifyCapability = TypeAnnotationQuantifyCapability();

/// Gives support for reflecting on the full closure of type annotations
/// of covered methods/parameters.
///
/// Short for `const TypeAnnotationQuantifyCapability(transitive: true)`.
///
/// Gives the same reflection capabilities for all classes used as type
/// annotations in variables and parameters or as return types of methods in
/// the vocered classes, as well as the transitive closure thereof (that is,
/// including classes used as type annotations in classes used as type
/// annotations, etc.).
const typeAnnotationDeepQuantifyCapability =
    TypeAnnotationQuantifyCapability(transitive: true);

/// Quantifying capability instance specifying that the reflection support
/// for any given explicitly declared getter must also be given to its
/// corresponding explicitly declared setter, if any.
const correspondingSetterQuantifyCapability =
    _CorrespondingSetterQuantifyCapability();

/// Gives support for calling `.reflect` on subtypes of covered instances.
///
/// In other words, this capability makes it possible
/// to obtain a mirror which is intended to mirror an instance of a target
/// class `C`, but it is actually mirroring a reflectee of a proper subtype
/// `D` of `C`.
///
/// Please note that this is a subtle situation that may easily cause
/// confusing and unintended results. It is only intended for usage in
/// cases where the associated size reductions are highly appreciated,
/// and the subtle semantics clearly understood!
///
/// In particular, note that declarations of members in subtypes are ignored
/// unless they implement or override a declaration in the target class
/// or a supertype thereof. Also note that the method `type` on an
/// `InstanceMirror` will throw an exception, because it will otherwise
/// have to return a `ClassMirror` for the target class, and that would
/// yield results which are plain wrong.
///
/// For more information about this potentially dangerous device, please
/// refer to the design document.
/// TODO(eernst) doc: Insert a link to the design document.
const admitSubtypeCapability = _AdmitSubtypeCapability();

/// Abstract superclass for all capabilities which are used to specify
/// that a given reflector must be considered to be applied as metadata
/// to a set of targets. Note that in order to work correctly, this
/// kind of capability can only be used as metadata on an import of
/// 'package:reflectable/reflectable.dart'.
class ImportAttachedCapability {
  final Reflectable reflector;
  const ImportAttachedCapability(this.reflector);
}

/// Gives reflection support in [reflector] for every class in the program whose
/// qualified name matches the given [classNamePattern] considered as a regular
/// expression.
///
/// The semantics are as if the matching classes had been annotated with the
/// [reflector].
///
/// Note: It is used by attaching an instance of a subtype of
/// [GlobalQuantifyCapability] as metadata on an import of
/// 'package:reflectable/reflectable.dart'.
class GlobalQuantifyCapability extends ImportAttachedCapability {
  final String classNamePattern;
  const GlobalQuantifyCapability(this.classNamePattern, Reflectable reflector)
      : super(reflector);
}

/// Gives reflection support in [reflector] for every class
/// in the program whose metadata includes instances of [metadataType] or
/// a subtype thereof.
///
/// The semantics are as if the matching classes had been annotated with the
/// [reflector].
///
/// Note: It is used by attaching an instance of a subtype of
/// [GlobalQuantifyCapability] as metadata on an import of
/// 'package:reflectable/reflectable.dart'.
class GlobalQuantifyMetaCapability extends ImportAttachedCapability {
  final Type metadataType;
  const GlobalQuantifyMetaCapability(this.metadataType, Reflectable reflector)
      : super(reflector);
}

// ---------- Private classes used to enable capability instances above.

class _ReflectedTypeCapability implements DeclarationsCapability {
  const _ReflectedTypeCapability();
}

class _DelegateCapability extends ApiReflectCapability {
  const _DelegateCapability();
}

class _SubtypeQuantifyCapability implements ReflecteeQuantifyCapability {
  const _SubtypeQuantifyCapability();
}

class _CorrespondingSetterQuantifyCapability
    implements ReflecteeQuantifyCapability {
  const _CorrespondingSetterQuantifyCapability();
}

class _AdmitSubtypeCapability implements ReflecteeQuantifyCapability {
  const _AdmitSubtypeCapability();
}

// ---------- Exception handling.

/// Thrown when reflection is invoked without sufficient capabilities.
abstract class NoSuchCapabilityError extends Error {
  factory NoSuchCapabilityError(String message) = _NoSuchCapabilityErrorImpl;
}

class _NoSuchCapabilityErrorImpl extends Error
    implements NoSuchCapabilityError {
  final String _message;

  _NoSuchCapabilityErrorImpl(String message) : _message = message;

  @override
  String toString() => _message;
}

enum StringInvocationKind { method, getter, setter, constructor }

class _StringInvocation extends StringInvocation {
  final StringInvocationKind kind;

  @override
  final String memberName;

  @override
  final List positionalArguments;

  @override
  final Map<Symbol, dynamic> namedArguments;

  @override
  bool get isMethod => kind == StringInvocationKind.method;

  @override
  bool get isGetter => kind == StringInvocationKind.getter;

  @override
  bool get isSetter => kind == StringInvocationKind.setter;

  _StringInvocation(this.memberName, this.positionalArguments,
      this.namedArguments, this.kind);
}

/// Thrown when a method is invoked via a reflectable, but the reflectable
/// doesn't have the capabilities to invoke it.
class ReflectableNoSuchMethodError extends Error
    implements NoSuchCapabilityError {
  /// [receiver] is nullable because (1) we can reflect on the null object and
  /// hence it can be the receiver, (2) a static method invocation uses the
  /// reflected type as the receiver, but null is used when no capability
  /// was requested for the reflected type, and (3) a top-level function uses
  /// null as the receiver.
  final Object? receiver;
  final String memberName;
  final List positionalArguments;

  /// [namedArguments] is nullable because `invoke` and similar methods on
  /// mirrors allow their `namedArguments` parameter to be null. It specifies
  /// that there are no named arguments.
  final Map<Symbol, dynamic>? namedArguments;

  final StringInvocationKind kind;

  ReflectableNoSuchMethodError(
      this.receiver,
      this.memberName,
      this.positionalArguments,
      this.namedArguments,
      this.kind);

  StringInvocation get invocation => _StringInvocation(
      memberName, positionalArguments, namedArguments ?? const {}, kind);

  @override
  String toString() {
    String kindName;
    switch (kind) {
      case StringInvocationKind.getter:
        kindName = 'getter';
        break;
      case StringInvocationKind.setter:
        kindName = 'setter';
        break;
      case StringInvocationKind.method:
        kindName = 'method';
        break;
      case StringInvocationKind.constructor:
        kindName = 'constructor';
        break;
      default:
        // Reaching this point is a bug, so we ought to do this:
        // `throw unreachableError('Unexpected StringInvocationKind value');`
        // but it is a bit harsh to raise an exception because of a slightly
        // imprecise diagnostic message, so we use a default instead.
        kindName = '';
    }
    var description = 'NoSuchCapabilityError: no capability to invoke the '
        '$kindName "$memberName"\n'
        'Receiver: $receiver\n'
        'Arguments: $positionalArguments\n';
    if (namedArguments != null) {
      description += 'Named arguments: $namedArguments\n';
    }
    return description;
  }
}

dynamic reflectableNoSuchInvokableError(
    Object? receiver,
    String memberName,
    List positionalArguments,
    Map<Symbol, dynamic>? namedArguments,
    StringInvocationKind kind) {
  throw ReflectableNoSuchMethodError(receiver, memberName, positionalArguments,
      namedArguments, kind);
}

dynamic reflectableNoSuchMethodError(Object? receiver, String memberName,
    List positionalArguments, Map<Symbol, dynamic>? namedArguments) {
  throw ReflectableNoSuchMethodError(receiver, memberName, positionalArguments,
      namedArguments, StringInvocationKind.method);
}

dynamic reflectableNoSuchGetterError(Object? receiver, String memberName,
    List positionalArguments, Map<Symbol, dynamic>? namedArguments) {
  throw ReflectableNoSuchMethodError(receiver, memberName, positionalArguments,
      namedArguments, StringInvocationKind.getter);
}

dynamic reflectableNoSuchSetterError(Object? receiver, String memberName,
    List positionalArguments, Map<Symbol, dynamic>? namedArguments) {
  throw ReflectableNoSuchMethodError(receiver, memberName, positionalArguments,
      namedArguments, StringInvocationKind.setter);
}

dynamic reflectableNoSuchConstructorError(
    Object? receiver,
    String constructorName,
    List positionalArguments,
    Map<Symbol, dynamic>? namedArguments) {
  throw ReflectableNoSuchMethodError(
      receiver,
      constructorName,
      positionalArguments,
      namedArguments,
      StringInvocationKind.constructor);
}
