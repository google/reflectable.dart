// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

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

library reflectable.capability;

/// A [ReflectCapability] of a reflectable mirror specifies the kinds of
/// reflective operations that are supported for instances of the
/// associated classes.
///
/// A class `C` is connected to a [ReflectCapability] `K` by giving `K`
/// as a const constructor super invocation argument in a subclass `R`
/// of [Reflectable], and then including an instance of `R` in the
/// metadata associated with `C`.
/// TODO(eernst): This is rather technical, provide an example, and
/// insert a link to it.
abstract class ReflectCapability {
  const ReflectCapability();
}

// TODO(eernst): [ReflectCapability] and its subclasses form a DSL, but
// this DSL has not yet been designed nor implemented, and it is likely
// to be unstable for a while.  The classes below just serve as examples,
// to illustrate some relevant cases that the DSL is intended to cover.

/// Specifies for a class `C` that all members can be invoked: Instance
/// members declared in `C` or a superclass of `C` can be invoked on an
/// InstanceMirror, and static members declared in `C` can be invoked on
/// a ClassMirror.
const invokeMembersCapability = const _InvokeMembersCapability();

/// Specifies that all members whose metadata includes [metadata]
/// can be invoked; for such members it works like InvokeMembers.
class InvokeMembersWithMetadataCapability implements ReflectCapability {
  final Object metadata;
  const InvokeMembersWithMetadataCapability(this.metadata);
}

/// Specifies for a class `C` that all instance members declared in `C`
/// or a superclass of `C` up to [superType] can be invoked.
class InvokeInstanceMembersUpToSuperCapability implements ReflectCapability {
  final Type superType;
  const InvokeInstanceMembersUpToSuperCapability(this.superType);
}

/// Specifies for a class `C` that all instance members declared in `C`
/// or a superclass of `C` can be invoked.
const invokeInstanceMembersCapability =
    const InvokeInstanceMembersUpToSuperCapability(Object);

/// Specifies for a class `C` that all static members
/// declared in `C` can be invoked.
const invokeStaticMembersCapability = const _InvokeStaticMembersCapability();

/// Specifies for a class `C` that the instance member named
/// [name] can be invoked.
class InvokeInstanceMemberCapability implements ReflectCapability {
  final Symbol name;
  const InvokeInstanceMemberCapability(this.name);
}

/// Specifies for a class `C` that the static member named [name]
/// can be invoked.
class InvokeStaticMemberCapability implements ReflectCapability {
  final Symbol name;
  const InvokeStaticMemberCapability(this.name);
}

/// Specifies for a class `C` that the constructor named [name]
/// can be invoked with `newInstance` on the `ClassMirror`.
class InvokeConstructorCapability implements ReflectCapability {
  final Symbol name;
  const InvokeConstructorCapability(this.name);
}

const invokeConstructorsCapability = const _InvokeConstructorsCapability();

/// Specifies for a class `C` that all constructors with the given metadata
///  can be invoked with `newInstance` on the `ClassMirror`.
class InvokeConstructorsWithMetaDataCapability implements ReflectCapability {
  final Object metadata;
  const InvokeConstructorsWithMetaDataCapability(this.metadata);
}

// Private classes

class _InvokeMembersCapability implements ReflectCapability {
  const _InvokeMembersCapability();
}

class _InvokeStaticMembersCapability implements ReflectCapability {
  const _InvokeStaticMembersCapability();
}

/// Specifies for a class `C` that all constructors can be invoked with
/// `newInstance` on the `ClassMirror`.
class _InvokeConstructorsCapability implements ReflectCapability {
  const _InvokeConstructorsCapability();
}

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
  Symbol memberName;
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
