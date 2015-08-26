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
class StaticInvokeCapability extends NamePatternCapability {
  const StaticInvokeCapability(String namePattern) : super(namePattern);
}

/// Short hand for `StaticInvokeCapability("")`, meaning the capability to
/// reflect over all static members.
const staticInvokeCapability = const StaticInvokeCapability("");

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
/// of static members (static methods, getters, and setters).
/// The metadata associated with each candidate member declaration, is searched
/// for objects with the given type (exact match). And that member declaration
/// receives reflection support iff the search succeeds.
class StaticInvokeMetaCapability extends MetadataQuantifiedCapability {
  const StaticInvokeMetaCapability(Type metadata) : super(metadata);
}

/// Capability class requesting support for reflective invocation
/// of constructors (of all kinds). The given [namePattern] is used
/// as a regular expression, and the name of each candidate member
/// is tested: the member receives reflection support iff its name
/// matches [namePattern]. In this test, constructors whose name is
/// empty are considered to have the name `new`.
class NewInstanceCapability extends NamePatternCapability {
  const NewInstanceCapability(String namePattern) : super(namePattern);
}

/// Short hand for `NewInstanceCapability("")`, meaning the capability to
/// reflect over all constructors.
const newInstanceCapability = const NewInstanceCapability("");

/// Capability class requesting support for reflective invocation
/// of constructors (of all kinds).
/// The metadata associated with each candidate member declaration, is searched
/// for objects with the given type (exact match). And that member declaration
/// receives reflection support iff the search succeeds.
class NewInstanceMetaCapability extends MetadataQuantifiedCapability {
  const NewInstanceMetaCapability(Type metadataType) : super(metadataType);
}

// TODO(eernst) doc: Document this.
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

/// Capability class requesting support for invocation of the
/// method `reflectType` on instances of subclasses of `Recflectable`,
/// and for invocation of the method `type` on instances of
/// `InstanceMirror`. Note that without this, there is no need to support
/// any kind of reflective operations producing mirrors of source code
/// entities (that is, instances of `ClassMirror`, `MethodMirror`,
/// `DeclarationMirror`, `LibraryMirror`, `LibraryDependencyMirror`,
/// `CombinatorMirror`, `TypeMirror`, `FunctionTypeMirror`,
/// `TypeVariableMirror`, `TypedefMirror`, `VariableMirror`, and
/// `ParameterMirror`), which may reduce the space consumption
/// significantly because the generation of those classes can be
/// avoided entirely. The given [upperBound] is used to specify that
/// the abovementioned mirror classes need only be generated for
/// the classes which are subtypes of [upperBound], along with
/// method mirrors for their methods and so on. The value [null] given
/// as an [upperBound] is taken to mean the target class itself, i.e.,
/// source code related mirrors are generated for a class that has a
/// reflector (or which is included in a quantification with such a
/// reflector), and not for any of its supertypes, unless they are
/// themselves targets for a reflector which requests their type.
class TypeCapability implements ApiReflectCapability {
  final Type upperBound;
  const TypeCapability(this.upperBound);
}

/// Short hand using [Object] as the upper bound for the type
/// capability, such that all mirror classes of all supertypes
/// and their methods etc. are generated.
const typeCapability = const TypeCapability(Object);

/// Short hand using [null] as the upper bound for the type capability,
/// such that only the mirror classes concerned with the source code of
/// the target class itself are generated, but not any of the ones
/// concerned with its supertypes.
const localTypeCapability = const TypeCapability(null);

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

/// Capability instance requesting reflective support for library-mirrors.
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
class TypingCapability extends TypeCapability
    implements
        _NameCapability,
        _ClassifyCapability,
        _MetadataCapability,
        _TypeRelationsCapability,
        _DeclarationsCapability,
        _UriCapability,
        _LibraryDependenciesCapability {
  const TypingCapability(Type upperBound) : super(upperBound);
}

// ---------- Reflectee quantification oriented capability classes.

/// Abstract superclass for all capability classes supporting quantification
/// over the set of potential reflectees. The quantifying capability classes
/// are capable of recieving a list of up to ten [ApiReflectCapability]
/// arguments in a varargs style (just a comma separated list of arguments,
/// rather than enclosing them in `<ApiReflectCapability>[]`). When even more
/// than ten arguments are needed, the `fromList` constructor should be used.
abstract class ReflecteeQuantifyCapability implements ReflectCapability {
  // Fields holding capabilities; we use discrete fields rather than a list
  // of fields because this allows us to use a syntax similar to a varargs
  // invocation as the superinitializer (omitting `<ReflectCapability>[]` and
  // directly giving the elements of that list as constructor arguments).
  // This will only work up to a fixed number of arguments (we have chosen
  // to support at most 10 arguments), and with a larger number of arguments
  // the fromList constructor must be used.

  final bool _capabilitiesGivenAsList;

  final ApiReflectCapability _cap0, _cap1, _cap2, _cap3, _cap4;
  final ApiReflectCapability _cap5, _cap6, _cap7, _cap8, _cap9;

  final List<ApiReflectCapability> _capabilities;

  List<ApiReflectCapability> get capabilities {
    if (_capabilitiesGivenAsList) return _capabilities;
    List<ApiReflectCapability> result = <ApiReflectCapability>[];

    void add(ApiReflectCapability cap) {
      if (cap != null) result.add(cap);
    }

    add(_cap0);
    add(_cap1);
    add(_cap2);
    add(_cap3);
    add(_cap4);
    add(_cap5);
    add(_cap6);
    add(_cap7);
    add(_cap8);
    add(_cap9);
    return result;
  }

  /// Const constructor, allowing for varargs style invocation with up
  /// to ten arguments.
  const ReflecteeQuantifyCapability(
      [this._cap0 = null,
      this._cap1 = null,
      this._cap2 = null,
      this._cap3 = null,
      this._cap4 = null,
      this._cap5 = null,
      this._cap6 = null,
      this._cap7 = null,
      this._cap8 = null,
      this._cap9 = null])
      : _capabilitiesGivenAsList = false,
        _capabilities = null;

  /// Const constructor, allowing for arbitrary length list.
  const ReflecteeQuantifyCapability.fromList(this._capabilities)
      : _capabilitiesGivenAsList = true,
        _cap0 = null,
        _cap1 = null,
        _cap2 = null,
        _cap3 = null,
        _cap4 = null,
        _cap5 = null,
        _cap6 = null,
        _cap7 = null,
        _cap8 = null,
        _cap9 = null;
}

/// Second order capability class specifying that the reflection support
/// requested by the given list of [ApiReflectCapability] instances should
/// be provided not just for the target class whose metadata includes this
/// capability, but also all classes which are subtypes of the target
/// class.
class SubtypeQuantifyCapability extends ReflecteeQuantifyCapability {
  const SubtypeQuantifyCapability(
      [ApiReflectCapability cap0,
      ApiReflectCapability cap1,
      ApiReflectCapability cap2,
      ApiReflectCapability cap3,
      ApiReflectCapability cap4,
      ApiReflectCapability cap5,
      ApiReflectCapability cap6,
      ApiReflectCapability cap7,
      ApiReflectCapability cap8,
      ApiReflectCapability cap9])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const SubtypeQuantifyCapability.fromList(
      List<ApiReflectCapability> capabilities)
      : super.fromList(capabilities);
}

/// Second order capability class specifying that the reflection support
/// requested by the given list of [ApiReflectCapability] instances should
/// be provided for instances of the target class whose metadata includes
/// this capability, but also that it should be possible to request
/// reflection support for instances of subtypes of the target class
/// as if they had been instances of the target class. In other words,
/// this capability makes it possible to obtain a mirror which is
/// intended to mirror an instance of a target class `C`, but it is actually
/// mirroring a reflectee of a proper subtype `D` of `C`.
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
class AdmitSubtypeCapability extends ReflecteeQuantifyCapability {
  const AdmitSubtypeCapability(
      [ApiReflectCapability cap0,
      ApiReflectCapability cap1,
      ApiReflectCapability cap2,
      ApiReflectCapability cap3,
      ApiReflectCapability cap4,
      ApiReflectCapability cap5,
      ApiReflectCapability cap6,
      ApiReflectCapability cap7,
      ApiReflectCapability cap8,
      ApiReflectCapability cap9])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const AdmitSubtypeCapability.fromList(List<ApiReflectCapability> capabilities)
      : super.fromList(capabilities);
}

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

class _NameCapability implements ApiReflectCapability {
  const _NameCapability();
}

class _ClassifyCapability implements ApiReflectCapability {
  const _ClassifyCapability();
}

class _MetadataCapability implements ApiReflectCapability {
  const _MetadataCapability();
}

class _TypeRelationsCapability implements ApiReflectCapability {
  const _TypeRelationsCapability();
}

// TODO(sigurdm) feature: Split this into EnclosingLibraryCapability(),
// LibraryCapabiliy(String regex) and LibraryMetaCapability(Type type).
class _LibraryCapability implements ApiReflectCapability {
  const _LibraryCapability();
}

class _DeclarationsCapability implements ApiReflectCapability {
  const _DeclarationsCapability();
}

class _UriCapability implements ApiReflectCapability {
  const _UriCapability();
}

class _LibraryDependenciesCapability implements ApiReflectCapability {
  const _LibraryDependenciesCapability();
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
