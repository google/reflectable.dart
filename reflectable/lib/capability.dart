// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.capability;

// The class [ReflectCapability] and its subclasses form a domain
// specific language (DSL) in that they can be used to create tree
// structures that correspond to abstract syntax trees for expressions.
// The semantics of those expressions is to enable a certain subset of
// the operations on mirrors that are available according to the APIs in
// mirrors.dart.  The constraints specify both which members of
// instances of a given mirror class are available, and which arguments
// they can receive.  An exception is thrown if a method is invoked
// which is not supported according to the given constraints, and if an
// available method is called with arguments that do not satisfy the
// constraints.  The point is that the constraints define a subset of
// the apparent functionality of mirrors.dart, and the amount of code
// generated for such a subset will be much smaller than the amount of
// code generated for the unconstrained case.
//
// NB! It is crucial that all changes made in this library are
// performed in the corresponding manner in `src/element_capability.dart`,
// and vice versa.

import 'reflectable.dart';

/// A [ReflectCapability] of a reflectable mirror specifies the kinds of
/// reflective operations that are supported for instances of the
/// associated classes.
///
/// A class `C` is connected to a [ReflectCapability] `K` by giving `K`
/// as a const constructor superinitializer in a subclass `R`
/// of [Reflectable], and then including an instance of `R` in the
/// metadata associated with `C`. More details can be found in the
/// design document about this library.
/// TODO(eernst) doc: Insert a link to the design document; if we change the
/// design document to markdown and store it in the reflectable repo it might
/// be possible to use a markdown link here.
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

/// Capability class requesting support for reflective invocation
/// of instance members (methods, getters, and setters). The given
/// [namePattern] is used as a regular expression, and the name of
/// each candidate member is tested: the member receives reflection
/// support iff its name matches [namePattern].
class InstanceInvokeCapability extends NamePatternCapability {
  const InstanceInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `InstanceInvokeCapability("")`, meaning the capability to
/// reflect over all instance members.
const instanceInvokeCapability = const InstanceInvokeCapability("");

/// Capability class requesting support for reflective invocation
/// of instance members (methods, getters, and setters). The given
/// [metadata] instance is searched within the metadata associated with
/// each candidate member declaration, and that member declaration
/// receives reflection support iff the search succeeds.
class InstanceInvokeMetaCapability extends MetadataQuantifiedCapability {
  const InstanceInvokeMetaCapability(Type metadataType) : super(metadataType);
}

/// Capability class requesting support for reflective invocation
/// of static members (static methods, getters, and setters). The given
/// [namePattern] is used as a regular expression, and the name of
/// each candidate member is tested: the member receives reflection
/// support iff its name matches [namePattern].
class StaticInvokeCapability extends NamePatternCapability
    implements TypeCapability {
  const StaticInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `StaticInvokeCapability("")`, meaning the capability to
/// reflect over all static members.
const staticInvokeCapability = const StaticInvokeCapability("");

/// Capability class requesting support for reflective invocation
/// of static members (static methods, getters, and setters).
/// The metadata associated with each candidate member declaration, is searched
/// for objects with the given type (exact match). And that member declaration
/// receives reflection support iff the search succeeds. Note that this
/// capability implies [TypeCapability], because there is no way to
/// perform a `newInstance` operation without class mirrors.
class StaticInvokeMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const StaticInvokeMetaCapability(Type metadata) : super(metadata);
}

/// Capability class requesting support for reflective invocation
/// of top-level members(top-level methods, getters, and setters). The given
/// [namePattern] is used as a regular expression, and the name of
/// each candidate member is tested: the member receives reflection
/// support iff its name matches [namePattern].
class TopLevelInvokeCapability extends NamePatternCapability {
  const TopLevelInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `TopLevelInvokeCapability("")`, meaning the capability to
/// reflect over all top-level members.
const topLevelInvokeCapability = const TopLevelInvokeCapability("");

/// Capability class requesting support for reflective invocation
/// of top-level members (top-level methods, getters, and setters).
/// The metadata associated with each candidate member declaration, is searched
/// for objects with the given type (exact match). And that member declaration
/// receives reflection support iff the search succeeds.
class TopLevelInvokeMetaCapability extends MetadataQuantifiedCapability {
  const TopLevelInvokeMetaCapability(Type metadata) : super(metadata);
}

/// Capability class requesting support for reflective invocation
/// of constructors (of all kinds). The given [namePattern] is used
/// as a regular expression, and the name of each candidate member
/// is tested: the member receives reflection support iff its name
/// matches [namePattern]. In this test, constructors whose name is
/// empty are considered to have the name `new`. Note that this
/// capability implies [TypeCapability], because there is no way to
/// perform a `newInstance` operation without class mirrors.
class NewInstanceCapability extends NamePatternCapability
    implements TypeCapability {
  const NewInstanceCapability(String namePattern) : super(namePattern);
}

/// Short hand for `NewInstanceCapability("")`, meaning the capability to
/// reflect over all constructors.
const newInstanceCapability = const NewInstanceCapability("");

/// Capability class requesting support for reflective invocation
/// of constructors (of all kinds).
/// The metadata associated with each candidate member declaration, is searched
/// for objects with the given type (exact match). And that member declaration
/// receives reflection support iff the search succeeds. Note that this
/// capability implies [TypeCapability], because there is no way to
/// perform a `newInstance` operation without class mirrors.
class NewInstanceMetaCapability extends MetadataQuantifiedCapability
    implements TypeCapability {
  const NewInstanceMetaCapability(Type metadataType) : super(metadataType);
}

/// Capability instance requesting support for retrieving the names of
/// named declarations, corresponding to the methods `simpleName`,
/// `qualifiedName` and `constructorName` on `DeclarationMirror` and
/// `MethodMirror`.
const nameCapability = const _NameCapability();

/// Capability instance requesting support for classification
/// predicates such as `isPrivate`, `isStatic` .., offered by
/// `DeclarationMirror`, `LibraryDependencyMirror`, `CombinatorMirror'
/// `TypeMirror`, `ClassMirror`, `TypeVariableMirror`,
/// `MethodMirror`, `VariableMirror`, and `ParameterMirror`.
/// The corresponding class is private because the set of `const`
/// instances of that class contains at most one instance, which means
/// that the `const` constructor invocations that we could have used
/// would just be a more verbose way to obtain the same instance.
const classifyCapability = const _ClassifyCapability();

/// Capability instance requesting support for reflective access
/// to metadata associated with a declaration reflected by a given
/// declaration mirror. The corresponding class is private for the
/// same reason as mentioned with [classifyCapability].
const metadataCapability = const _MetadataCapability();

/// Supertype of all capabilities requesting support for types. For the
/// detailed semantics, please see the instance `typeCapability`, which is
/// the capability that users of the package reflectable should use in case
/// they wish to request the type capability alone. This class has been
/// defined in order to equip a number of capabilities with a link to the
/// type capability (by being subtypes of this class) such that the inclusion
/// of one of them (e.g., `declarationsCapability`) automatically implies the
/// latter (so a lone `declarationsCapability` will work exactly like the pair
/// `declarationCapability, typeCapability`).
class TypeCapability implements ApiReflectCapability {
  const TypeCapability();
}

/// Capability instance requesting support for invocation of the method
/// `reflectType` on instances of subclasses of `Recflectable` (also
/// known as a reflector) with an argument which is a class supported
/// by that reflector, and for invocation of the method `type` on
/// instances of `InstanceMirror`. Note that without this capability
/// there is no need to support any kind of reflective operations
/// producing mirrors of source code entities (that is, instances of
/// `ClassMirror`, `MethodMirror`, `DeclarationMirror`, `LibraryMirror`,
/// `LibraryDependencyMirror`, `CombinatorMirror`, `TypeMirror`,
/// `FunctionTypeMirror`, `TypeVariableMirror`, `TypedefMirror`,
/// `VariableMirror`, and `ParameterMirror`), which may reduce the space
/// consumption significantly because generation of the associated code
/// can be avoided. Note, however, that this capability will be included
/// implicitly if one of the subtypes of `TypeCapability` is included
/// (for instance, if `declarationsCapability` is included).
const typeCapability = const TypeCapability();

/// Capability instance requesting reflective support for the following
/// mirror methods, coming from several mirror classes: `typeVariables`,
/// `typeArguments`, `originalDeclaration`, `isSubtypeOf`, `isAssignableTo`,
/// `superclass`, `superinterfaces`, `mixin`, `isSubclassOf`, `upperBound`,
/// and `referent`. Note that it is useless to request this capability if
/// no other capabilities have given rise to the generation of source code
/// related mirror classes, because these methods are only defined by those
/// mirror classes. The corresponding class is private for the same reason
/// as mentioned with [classifyCapability].
const typeRelationsCapability = const _TypeRelationsCapability();

/// Capability instance requesting reflective support for library mirrors.
/// This will cause support for reflecting for all libraries containing
/// annotated classes (enabling support for [ClassMirror.owner]), and all
/// annotated libraries.
const libraryCapability = const _LibraryCapability();

/// Capability instance requesting reflective support for the following
/// mirror methods, coming from several mirror classes: `declarations`,
/// `instanceMembers`, `staticMembers`, `callMethod`, `parameters`, and
/// `defaultValue`. Note that it is useless to request this capability if
/// no other capabilities have given rise to the generation of source code
/// related mirror classes, because these methods are only defined by those
/// mirror classes. The corresponding class is private for the same reason
/// as mentioned with [classifyCapability].
const declarationsCapability = const _DeclarationsCapability();

/// Capability instance requesting support for the mirror method `uri`.
/// The corresponding class is private for the same reason as mentioned
/// with [classifyCapability].
const uriCapability = const _UriCapability();

/// Capability instance requesting support for the following mirror
/// methods: `sourceLibrary`, `targetLibrary`, `prefix`, and
/// `combinators`. The corresponding class is private for the same
/// reason as mentioned with [classifyCapability].
const libraryDependenciesCapability = const _LibraryDependenciesCapability();

/// Grouping capability, used to request all the capabilities requested by
/// InstanceInvokeCapability, StaticInvokeCapability, and NewInstanceCapability,
/// all holding the same [namePattern].
class InvokingCapability extends NamePatternCapability
    implements
        InstanceInvokeCapability,
        StaticInvokeCapability,
        NewInstanceCapability {
  const InvokingCapability(String namePattern) : super(namePattern);
}

/// Short hand for `InvokingCapability("")`, meaning the capability to
/// reflect over all top-level and static members.
const invokingCapability = const InvokingCapability("");

/// Grouping capability, used to request all the capabilities requested by
/// InstanceInvokeMetaCapability, StaticInvokeMetaCapability, and
/// NewInstanceMetaCapability, all holding the same [metadata].
class InvokingMetaCapability extends MetadataQuantifiedCapability
    implements
        InstanceInvokeMetaCapability,
        StaticInvokeMetaCapability,
        NewInstanceMetaCapability {
  const InvokingMetaCapability(Type metadataType) : super(metadataType);
}

/// Grouping capability, used to request all the capabilities requested by
/// TypeCapability([UpperBound]), nameCapability, classifyCapability,
/// metadataCapability, typeRelationsCapability, ownerCapability,
/// declarationsCapability, uriCapability, and libraryDependenciesCapability.
class TypingCapability
    implements
        TypeCapability, // Redundant, just included for readability.
        _NameCapability,
        _ClassifyCapability,
        _MetadataCapability,
        _TypeRelationsCapability,
        _DeclarationsCapability,
        _UriCapability,
        _LibraryDependenciesCapability {
  const TypingCapability();
}

// ---------- Reflectee quantification oriented capability classes.

/// Abstract superclass for all capability classes supporting quantification
/// over the set of potential reflectees. The quantifying capability classes
/// are capable of recieving a list of up to ten [ApiReflectCapability]
/// arguments in a varargs style (just a comma separated list of arguments,
/// rather than enclosing them in `<ApiReflectCapability>[]`). When even more
/// than ten arguments are needed, the `fromList` constructor should be used.
abstract class ReflecteeQuantifyCapability implements ReflectCapability {
  const ReflecteeQuantifyCapability();
}

/// Quantifying capability instance specifying that the reflection support
/// requested by the [ApiReflectCapability] instances held by the same
/// [Reflectable] which also holds this capability should be provided
/// for all subtypes of the classes which carry that [Reflectable] as
/// metadata.
const subtypeQuantifyCapability = const _SubtypeQuantifyCapability();

/// Quantifying capability instance specifying that the reflection support
/// requested by the [ApiReflectCapability] instances held by the same
/// [Reflectable] which also holds this capability should be provided for
/// each class which is (1) a superclasses, directly or indirectly, of a
/// class which carries that [Reflectable] as metadata or is matched by
/// a global quantifier for that [Reflectable], and which is also (2) a
/// subclass of the given [upperbound].
class SuperclassQuantifyCapability implements ReflecteeQuantifyCapability {
  final Type upperBound;
  final bool excludeUpperBound;
  const SuperclassQuantifyCapability(this.upperBound,
      {bool excludeUpperBound: false})
      : excludeUpperBound = excludeUpperBound;
}

/// Quantifying capability class specifying that the reflection support
/// requested by the [ApiReflectCapability] instances held by the same
/// [Reflectable] which also holds this capability should be provided
/// for all superclasses of the classes which carry that [Reflectable]
/// as metadata.
const superclassQuantifyCapability = const SuperclassQuantifyCapability(Object);

/// Quantifying capability instance specifying that the reflection support
/// requested by the [ApiReflectCapability] instances held by the same
/// [Reflectable] which also holds this capability should be provided for
/// instances of the target class whose metadata includes this capability,
/// but also that it should be possible to request reflection support for
/// instances of subtypes of the target class as if they had been instances
/// of the target class. In other words, this capability makes it possible
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
const admitSubtypeCapability = const _AdmitSubtypeCapability();

/// Abstract superclass for all capabilities which are used to specify
/// that a given reflector must be considered to be applied as metadata
/// to a set of targets. Note that in order to work correctly, this
/// kind of capability can only be used as metadata on an import of
/// 'package:reflectable/reflectable.dart'.
class ImportAttachedCapability {
  final Reflectable reflector;
  const ImportAttachedCapability(this.reflector);
}

/// Second order capability class specifying that the reflection support
/// requested by the given [reflector] should be provided for every class
/// in the program whose qualified name matches the given [classNamePattern]
/// considered as a regular expression. Note that in order to get this
/// semantics, this kind of capability can only be used as metadata on an
/// import of 'package:reflectable/reflectable.dart'.
class GlobalQuantifyCapability extends ImportAttachedCapability {
  final String classNamePattern;
  const GlobalQuantifyCapability(this.classNamePattern, Reflectable reflector)
      : super(reflector);
}

/// Second order capability class specifying that the reflection support
/// requested by the given [reflector] should be provided for every class
/// in the program whose metadata includes the given [metadata]. Note that
/// in order to get this semantics, this kind of capability can only be used
/// as metadata on an import of 'package:reflectable/reflectable.dart'.
class GlobalQuantifyMetaCapability extends ImportAttachedCapability {
  final Type metadataType;
  const GlobalQuantifyMetaCapability(this.metadataType, Reflectable reflector)
      : super(reflector);
}

// ---------- Private classes used to enable capability instances above.

// TODO(eernst) clarify: This should be enforced or deleted,
// where 'enforced' means that `..name..` related methods must fail with a
// [NoSuchCapabilityError] if this capability is not present. This sounds
// like a really strict approach for a very cheap feature, but there might
// be reasons (maybe related to code obfuscation) for keeping the names out
// of reach.
class _NameCapability implements TypeCapability {
  const _NameCapability();
}

class _ClassifyCapability implements TypeCapability {
  const _ClassifyCapability();
}

class _MetadataCapability implements TypeCapability {
  const _MetadataCapability();
}

class _TypeRelationsCapability implements TypeCapability {
  const _TypeRelationsCapability();
}

// TODO(sigurdm) feature: Split this into EnclosingLibraryCapability(),
// LibraryCapabiliy(String regex) and LibraryMetaCapability(Type type).
class _LibraryCapability implements ApiReflectCapability {
  const _LibraryCapability();
}

class _DeclarationsCapability implements TypeCapability {
  const _DeclarationsCapability();
}

// TODO(eernst) clarify: Should this "imply" LibraryCapability?
class _UriCapability implements ApiReflectCapability {
  const _UriCapability();
}

// TODO(eernst) clarify: Should this "imply" LibraryCapability?
class _LibraryDependenciesCapability implements ApiReflectCapability {
  const _LibraryDependenciesCapability();
}

class _SubtypeQuantifyCapability implements ReflecteeQuantifyCapability {
  const _SubtypeQuantifyCapability();
}

class _AdmitSubtypeCapability implements ReflecteeQuantifyCapability {
  const _AdmitSubtypeCapability();
}

// ---------- Exception handling.

/// Thrown when reflection is invoked outside given capabilities.
abstract class NoSuchCapabilityError extends Error {
  factory NoSuchCapabilityError(message) = _NoSuchCapabilityErrorImpl;
}

class _NoSuchCapabilityErrorImpl extends Error
    implements NoSuchCapabilityError {
  final String _message;

  _NoSuchCapabilityErrorImpl(String message) : _message = message;

  toString() => _message;
}

/// Thrown when a method is invoked via a reflectable, but the reflectable
/// doesn't have the capabilities to invoke it.
class NoSuchInvokeCapabilityError extends Error
    implements NoSuchCapabilityError {
  Object receiver;
  String memberName;
  List positionalArguments;
  Map<Symbol, dynamic> namedArguments;
  List existingArgumentNames;

  NoSuchInvokeCapabilityError(this.receiver, this.memberName,
      this.positionalArguments, this.namedArguments,
      [this.existingArgumentNames = null]);

  toString() {
    String description =
        "NoSuchCapabilityError: no capability to invoke '$memberName'\n"
        "Receiver: $receiver\n"
        "Arguments: $positionalArguments\n";
    if (namedArguments != null) {
      description += "Named arguments: $namedArguments\n";
    }
    if (existingArgumentNames != null) {
      description += "Existing argument names: $existingArgumentNames\n";
    }
    return description;
  }
}
