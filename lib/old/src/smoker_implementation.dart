// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
//
// Implementation of convenience methods making smoke code more portable.

import 'dart:collection';
import '../reflectable.dart';

/// Returns a mirror of the immediate superclass of [type], defaulting to
/// Object if no other supertype can be found; never returns null.
/// This method was copied from smoke/lib/mirrors.dart and adjusted.
ClassMirror _safeSuperclass(ClassMirror type) {
  try {
    var t = type.superclass;
    if (t != null && t.owner != null && t.owner.isPrivate) {
      t = typeMirrorForObject;
    } else {
      return t;
    }
  } on UnsupportedError catch (e) {
    return typeMirrorForObject;
  }
}

class _SuperTypeIterator extends Iterator <ClassMirror> {
  bool firstInvocation = true;  // At first [moveNext] starts; at end: noop.
  ClassMirror _initialClassMirror;
  ClassMirror _currentClassMirror = null;  // [null] initially and at end.

  _SuperTypeIterator(this._initialClassMirror);

  bool moveNext() {
    if (firstInvocation) {
      // Start iterating.
      firstInvocation = false;
      _currentClassMirror = _initialClassMirror;
      return true;
    }
    if (_currentClassMirror.reflectedType == Object) {
      // Cannot go further.
      _currentClassMirror = null;
      return false;
    } else {
      // Find the next super class and make that [current].
      _currentClassMirror = _safeSuperclass(_currentClassMirror);
      return true;
    }
  }

  ClassMirror get current => _currentClassMirror;
}

class _SuperTypeIterable extends IterableMixin<ClassMirror> {
  ClassMirror _initialClassMirror;

  _SuperTypeIterable(this._initialClassMirror);

  Iterator<ClassMirror> get iterator {
    return new _SuperTypeIterator(_initialClassMirror);
  }
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is an instance of a class and such a declaration exists in
/// that class or one of its superclasses; otherwise returns null.
DeclarationMirror _getDeclaration(ClassMirror m, Symbol member) {
  // Search up through all superclasses for the requested declaration.
  for (ClassMirror cm in new _SuperTypeIterable(m)) {
    DeclarationMirror decl = cm.declarations[member];
    if (decl != null) return decl;
  }
  // No such declaration in any superclass.
  return null;
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is an instance of a class and such a declaration exists;
/// otherwise returns null.
DeclarationMirror _getInstanceDeclaration(InstanceMirror m, Symbol member) {
  TypeMirror typeMirror = m.type;
  if (typeMirror is! ClassMirror) return null;
  // Search up through all superclasses for the requested declaration.
  for (ClassMirror cm in new _SuperTypeIterable(typeMirror)) {
    DeclarationMirror decl = cm.declarations[member];
    if (decl != null) return decl;
  }
  // No such declaration in any superclass.
  return null;
}

bool canGet(ClassMirror cm, Symbol name) {
  Map<Symbol, DeclarationMirror> decls = cm.declarations;
  DeclarationMirror m = decls[name];
  if (m != null) {
    if (m is VariableMirror
        || (m is MethodMirror && m.isRegularMethod)
        || (m is MethodMirror && m.isGetter)
        || (m is MethodMirror && m.isStatic)) {
      return true;
    }
  }
  if (cm.superclass == null) {
    return false;
  } else {
    return canGet(cm.superclass, name);
  }
}

bool _canSetUsingVariable(ClassMirror cm, Symbol name) {
  Map<Symbol, DeclarationMirror> decls = cm.declarations;
  DeclarationMirror m = decls[name];
  if (m != null) {
    if (m is VariableMirror && !m.isFinal) return true;
  }
  if (cm.superclass == null) {
    return false;
  } else {
    return _canSetUsingVariable(cm.superclass, name);
  }
}

bool _canSetUsingSetter(ClassMirror cm, Symbol name) {
  DeclarationMirror dm = _getDeclaration(cm, setterName(name));
  return dm != null;
}

bool canSet(ClassMirror cm, Symbol name) {
  if (_canSetUsingVariable(cm, name)) return true;
  return _canSetUsingSetter(cm, name);
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is an instance of a class and such a declaration exists in that
/// class or one of its superclasses except Object; otherwise returns null.
DeclarationMirror _getDeclarationExceptObject(ClassMirror initial_cm,
                                              Symbol member) {
  // Search up through all superclasses for the requested declaration.
  for (ClassMirror cm in new _SuperTypeIterable(initial_cm)) {
    if (cm.reflectedType == Object) return null;
    DeclarationMirror decl = cm.declarations[member];
    if (decl != null) return decl;
  }
  // No such declaration in any superclass.
  return null;
}

bool hasNoSuchMethod(ClassMirror cm) {
  DeclarationMirror decl = _getDeclarationExceptObject(cm, #noSuchMethod);
  return decl is MethodMirror && decl.isRegularMethod;
}

bool hasInstanceMethod(ClassMirror cm, Symbol member) {
  // Semantics following pkg/smoke/lib/mirrors.dart, except that we _do_
  // include declarations in Object (which makes a difference for noSuchMethod
  // and toString).
  DeclarationMirror decl = _getDeclaration(cm, member);
  return decl is MethodMirror && decl.isRegularMethod && !decl.isStatic;
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is a class and such a declaration exists in that class
/// (superclasses are not considered); otherwise returns null.
DeclarationMirror _getLocalDeclaration(ClassMirror cm, Symbol member) {
  return cm.declarations[member];
}

bool hasStaticMethod(ClassMirror cm, Symbol member) {
  // Semantics following pkg/smoke/lib/mirrors.dart.
  DeclarationMirror decl = _getLocalDeclaration(cm, member);
  return decl is MethodMirror && decl.isRegularMethod && decl.isStatic;
}

DeclarationMirror getDeclaration(ClassMirror cm, Symbol name) {
  DeclarationMirror decl = _getLocalDeclaration(cm, name);
  return decl;
}

bool isField(DeclarationMirror m) {
  return m is VariableMirror;
}

bool isFinal(DeclarationMirror m) {
  return m is VariableMirror && m.isFinal;
}

bool isMethod(DeclarationMirror m) {
  // Might need to follow the semantics of smoke/lib/smoke.dart
  // Declaration.isMethod, which is just a test for [kind == METHOD]
  // where [kind] is selected when the Declaration is created.
  // TODO(eernst): find the precise semantics of this method,
  // and implement it.  The current implementation does pass the
  // tests in common.dart.
  return m is MethodMirror && m.isRegularMethod;
}

List<LibraryMirror> _filterDeps(LibraryMirror lm,
                                bool filter(LibraryDependency)) {
  return lm.libraryDependencies
      .where(filter)
      .map((dep) => dep.targetLibrary)
      .toList();
}

List<LibraryMirror> imports(LibraryMirror lm) =>
    _filterDeps(lm, (dep) => dep.isImport);

List<LibraryMirror> exports(LibraryMirror lm) =>
    _filterDeps(lm, (dep) => dep.isExport);

bool isProperty(DeclarationMirror m) =>
    m is MethodMirror && !m.isRegularMethod;

/// Returns a list of positional arguments adjusted to omit the
/// extraneous arguments when too many are given and to include
/// extra [null] values when too few are given; uses [parMirrors]
/// (mirroring the declared parameters of the method which is being
/// called) to detect the number of positional arguments and the
/// number of those which are optional.
List _adjustArgumentList(List arguments, List<ParameterMirror> parMirrors) {
  int min = -1;
  int max = 0;
  // Compute [min]/[max](imal number of positional parameters).
  for (ParameterMirror pm in parMirrors) {
    // Setting of min/max stops if named parameters start.
    if (pm.isNamed) break;
    // Register number of mandatory arguments if ending here.
    if (pm.isOptional) min = max;
    // Looking at a positional parameter, so the count goes up.
    max++;
  }
  // If [min] == -1 it was never set, i.e., no optional positional
  // parameters were encountered; if no mandatory positional parameters
  // exist either we have [max] == 0, and [min] should be changed to 0;
  // if some mandatory pos. parameters exist we have [max] > 0, and
  // [min] should be change to [max].  In both cases this will work:
  if (min == -1) min = max;
  if (arguments.length > max) {
    // Too many arguments given, create truncated copy.
    return new List(max)..setRange(0, max, arguments);
  } else if (arguments.length < min) {
    // Too few arguments given, create null-padded copy.
    return new List(min)..setRange(0, arguments.length, arguments);
  } else {
    return arguments;
  }
}

Object instanceInvokeAdjust(InstanceMirror m,
                            Symbol memberName,
                            List positionalArguments,
                            [Map<Symbol,dynamic> namedArguments]) {
  var cm = m.type;
  var declMirror = _getDeclaration(cm, memberName);
  if (declMirror is MethodMirror && declMirror.isRegularMethod) {
    List<ParameterMirror> parMirrors = declMirror.parameters;
    List adjusted_positional = _adjustArgumentList(positionalArguments,
                                                   parMirrors);
    return m.invoke(memberName, adjusted_positional, namedArguments);
  }
  // [invokeAdjust] will not invoke a non-method.
  throw "TODO(eernst): select the right thing to throw here";
}

Object classInvokeAdjust(ClassMirror m,
                         Symbol memberName,
                         List positionalArguments,
                         [Map<Symbol,dynamic> namedArguments]) {
  var declMirror = _getLocalDeclaration(m, memberName);
  if (declMirror is MethodMirror && declMirror.isRegularMethod) {
    List<ParameterMirror> parMirrors = declMirror.parameters;
    List adjusted_positional = _adjustArgumentList(positionalArguments,
                                                   parMirrors);
    return m.invoke(member, adjusted_positional, namedArguments);
  }
  // invokeAdjust will not invoke a non-method.
  throw "TODO(eernst): select the right thing to throw here";
}

