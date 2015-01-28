// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.capability;

// Siggi says this is needed:
//   capability InvokeMembersUpToSuperWithReflectable
//   detecting mixins in the superclass chain, selecting based on them
//   ...

/// Capabilities of a reflectable mirror: Specifies the kinds of reflective
/// operations that are supported for instances of associated classes.  A
/// class C is connected to a capability K by giving K as a const constructor
/// super invocation argument in a subclass R of Reflectable, and then
/// including an instance of R in the metadata associated with C.
class Capability { 
  const Capability();
}

/// Specifies for a class C that all members can be invoked: Instance members
/// declared in C or a subclass of C can be invoked on an InstanceMirror, and
/// static members declared in C can be invoked on a ClassMirror.
class InvokeMembers extends Capability {
  const InvokeMembers();
}

/// Specifies that all members whose metadata includes [_metadata]
/// can be invoked; for such members it works like InvokeMembers.
class InvokeMembersWithMetadata extends Capability {
  final Object _metadata;
  const InvokeMembersWithMetadata(this._metadata);
}

/// Specifies for a class C that all instance members declared in
/// C or a superclass of C up to [_superType] can be invoked.
class InvokeInstanceMembersUpToSuper extends Capability {
  final Type _superType;
  const InvokeInstanceMembersUpToSuper(this._superType);
}

/// Specifies for a class C that all instance members declared
/// in C or a superclass of C can be invoked.
class InvokeInstanceMembers extends Capability {
  const InvokeInstanceMembers();
}

/// Specifies for a class C that all static members
/// declared in C can be invoked.
class InvokeStaticMembers extends Capability {
  const InvokeStaticMembers();
}

/// Specifies for a class C that the instance member named
/// [name] can be invoked; [name] must be declared in C or
/// in a superclass of C.
class InvokeInstanceMember extends Capability {
  final Symbol name;
  const InvokeInstanceMember(this.name);
}

/// Specifies for a class C that the static member named [name]
/// can be invoked; [name] must be declared in C.
class InvokeStaticMember extends Capability {
  final Symbol name;
  const InvokeStaticMember(this.name);
}

