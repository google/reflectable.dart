// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.reflectable_implementation;

@dm.MirrorsUsed(targets: '*', override: '*')
import 'dart:mirrors' as dm;

import '../capability.dart';
import '../mirrors.dart';

/// Default behavior for mirror methods.  Used to ensure that all methods
/// are implemented such that compilation succeeds, but any method that
/// a static mirror does not redefine will fail, indicating to users that
/// it is unimplemented.  They should take this as a hint that they are
/// violating the constraints on reflection usage that they have themselves
/// specified using capabilities.
///
/// TODO(eernst): It is probably a good idea to use a subclass of
/// UnimplementedError that gives the above explanation to the user. 
_unsupported() => throw new UnimplementedError();

/// Used to indicate to users that a bug has been encountered, including
/// a recommendation to report it at github.
///
/// TODO(eernst): It would make sense to use `assert` whenever the
/// situation is recognized as being a bug (e.g., when the last test
/// before the `_bug(..)` branch in `wrap..` functions returns false),
/// but this clashes with the desire to inform the user about where to
/// report the bug (assertions do not carry user-defined messages).  So
/// for now we will use `_bug` and [InternalError] rather than `assert`.
_bug(String msg) => throw new InternalError(msg);

/// Used to report bugs to the user in such a way that it is convenient 
/// for the user to report the bug at github.
class InternalError extends Error {
  String msg;
  InternalError(this.msg);
  String toString() =>
      "bug: $msg.\n"
      "Please report it on github.com/dart-lang/reflectable/issues.";
}

abstract class _ObjectMirrorImplMixin implements ObjectMirror {
  dm.ObjectMirror get _objectMirror;

  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol,dynamic> namedArguments]) {
    return _objectMirror
        .invoke(memberName,positionalArguments,namedArguments)
        .reflectee;
  }

  @deprecated
  Object getField(Symbol fieldName) =>
      _objectMirror.getField(fieldName).reflectee;

  Object invokeGetter(Symbol fieldName) =>
      _objectMirror.getField(fieldName).reflectee;

  @deprecated
  Object setField(Symbol fieldName, Object value) =>
      _objectMirror.setField(fieldName, value).reflectee;

  Object invokeSetter(Symbol fieldName, Object value) =>
      _objectMirror.setField(fieldName, value).reflectee;
}

class _InstanceMirrorImpl extends _ObjectMirrorImplMixin
                          implements InstanceMirror {
  final dm.InstanceMirror _instanceMirror;
  dm.ObjectMirror get _objectMirror => _instanceMirror;

  _InstanceMirrorImpl(this._instanceMirror);

  TypeMirror get type => _wrapTypeMirror(_instanceMirror.type);

  bool get hasReflectee => _instanceMirror.hasReflectee;

  get reflectee => _instanceMirror.reflectee;

  bool operator == (other) => 
      other is _InstanceMirrorImpl && _instanceMirror == other._instanceMirror;

  delegate(Invocation invocation) => _instanceMirror.delegate(invocation);

  String toString() => "_InstanceMirrorImpl('$_instanceMirror')";
}

InstanceMirror _wrapInstanceMirror(dm.InstanceMirror m) {
  if (m is dm.ClosureMirror) {
    // TODO(eernst): return new _ClosureMirrorImpl(m);
    _unsupported();
  } else if (m is dm.InstanceMirror) {
    return new _InstanceMirrorImpl(m);
  } else {
    _bug("unexpected subtype of InstanceMirror");
  }
}

TypeMirror _wrapTypeMirror(dm.TypeMirror m) {
  if (m is dm.TypeVariableMirror) {
    // TODO(eernst): return new _TypeVariableMirrorImpl(m);
    _unsupported();
  }
  else if (m is dm.TypedefMirror) {
    // TODO(eernst): return new _TypedefMirrorImpl(m);
    _unsupported();
  }
  else if (m is dm.ClassMirror) {
    return _wrapClassMirror(m);
  }
  else {
    _bug("unexpected subtype of TypeMirror");
  }
}

ClassMirror _wrapClassMirror(dm.ClassMirror m) {
  if (m is dm.FunctionTypeMirror) {
    // TODO(eernst): return new _FunctionTypeMirrorImpl(cm);
    _unsupported();
  }
  else if (m is dm.ClassMirror) {
    // TODO(eernst): return new _ClassMirrorImpl(m);
    _unsupported();
  }
  else {
    _bug("unexpected subtype of ClassMirror");
  }
}

InstanceMirror reflect(o) {
  return _wrapInstanceMirror(dm.reflect(o));
}
