// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of reflectable.reflectable;

// ----------------------------------------------------------------------
// Auxiliary functions and values.

/// Used by _safeSuperclass.
final _objectType = dm.reflectClass(Object);

/// Returns a mirror of the immediate superclass of [type], defaulting to
/// Object if no other supertype can be found; never returns null.
/// This method was copied from smoke/lib/mirrors.dart and adjusted.
dm.ClassMirror _safeSuperclass(dm.ClassMirror type) {
  try {
    var t = type.superclass;
    if (t != null && t.owner != null && t.owner.isPrivate) t = _objectType;
    return t;
  } on UnsupportedError catch (e) {
    return _objectType;
  }
}

/// Returns a Symbol representing the name of the setter corresponding
/// to the name [getter], which is assumed to be the name of a getter.
/// TODO(eernst): this seems to be needed in a more general setting:
/// Not private, and generated as a static feature for each "mirror
/// system" rather than fixed and global.  Should maybe be an instance
/// method on the Reflectable subclass?
Symbol setterName(Symbol getter) =>
    new Symbol('${dm.MirrorSystem.getName(getter)}=');

/// Returns a list of positional arguments adjusted to omit the
/// extraneous arguments when too many are given and to include
/// extra [null] values when too few are given; uses [parMirrors]
/// (mirroring the declared parameters of the method which is being
/// called) to detect the number of positional arguments and the
/// number of those which are optional.
List _adjustArgumentList(List arguments, List<dm.ParameterMirror> parMirrors) {
  int min = -1;
  int max = 0;
  // Compute [min]/[max](imal number of positional parameters).
  for (dm.ParameterMirror pm in parMirrors) {
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

// ----------------------------------------------------------------------
// Auxiliary Private Classes.

class _SuperTypeIterator extends Iterator <dm.ClassMirror> {
  bool firstInvocation = true;  // At first [moveNext] starts; at end: noop.
  dm.ClassMirror _initialClassMirror;
  dm.ClassMirror _currentClassMirror = null;  // [null] initially and at end.

  _SuperTypeIterator(this._initialClassMirror);

  bool moveNext() {
    if (firstInvocation) {
      // Start iterating.
      firstInvocation = false;
      _currentClassMirror = _initialClassMirror;
      return true;
    }
    if (_currentClassMirror == _objectType) {
      // Cannot go further.
      _currentClassMirror = null;
      return false;
    } else {
      // Find the next super class and make that [current].
      _currentClassMirror = _safeSuperclass(_currentClassMirror);
      return true;
    }
  }

  dm.ClassMirror get current => _currentClassMirror;
}

class _SuperTypeIterable extends IterableMixin<dm.ClassMirror> {
  dm.ClassMirror _initialClassMirror;

  _SuperTypeIterable(this._initialClassMirror);

  Iterator<dm.ClassMirror> get iterator {
    return new _SuperTypeIterator(_initialClassMirror);
  }
}

// ----------------------------------------------------------------------
// Mirror Implementation Classes.

class _LibraryMirrorImpl extends LibraryMirror {
  final dm.LibraryMirror _libraryMirror;

  _LibraryMirrorImpl(this._libraryMirror);

  Symbol get qualifiedName => _libraryMirror.qualifiedName;

  Symbol get simpleName => _libraryMirror.simpleName;

  List<LibraryMirror> _filterDeps(List<dm.LibraryDependencyMirror> deps,
                                  bool filter(LibraryDependency)) {
    return deps
        .where(filter)
        .map((dep) => dep.targetLibrary)
        .map((lib) => new _LibraryMirrorImpl(lib))
        .toList();
  }

  List<LibraryMirror> get imports {
    return _filterDeps(_libraryMirror.libraryDependencies,
                       (dep) => dep.isImport);
  }

  List<LibraryMirror> get exports {
    return _filterDeps(_libraryMirror.libraryDependencies,
                       (dep) => dep.isExport);
  }

  Map<Symbol, ClassMirror> get classes {
    Map<Symbol, dm.DeclarationMirror> decls = _libraryMirror.declarations;
    Iterable<Symbol> relevantKeys =
        decls.keys
        .where((k) => decls[k] is dm.ClassMirror)
        .where((k) {
          List<dm.InstanceMirror> metadata = decls[k].metadata;
          for (var item in metadata) {
            if (item.hasReflectee && item.reflectee is ReflectableX) return true;
          }
          return false;
        });
    return new Map<Symbol, ClassMirror>.fromIterable(
        relevantKeys,
        key: (k) => k,
        value: (v) => new _ClassMirrorImpl(decls[v]));
  }

  Map<Symbol, DeclarationMirror> get declarations {
    Map<Symbol, dm.DeclarationMirror> decls = _libraryMirror.declarations;
    Iterable<Symbol> nonClassKeys = decls.keys
        .where((k) => decls[k] is! dm.ClassMirror)
        .where((k) {
          List<dm.InstanceMirror> metadata = decls[k].metadata;
          for (var item in metadata) {
            if (item.hasReflectee && item.reflectee is ReflectableX) return true;
          }
          return false;
        });
    return new Map<Symbol, DeclarationMirror>.fromIterable(
        nonClassKeys,
        key: (k) => k,
        value: (v) => new _DeclarationMirrorImpl(decls[v]));
  }

  String toString() => "LibraryMirror('${_libraryMirror.simpleName}')";
}

class _InstanceMirrorImpl extends InstanceMirror {
  final dm.InstanceMirror _instanceMirror;

  _InstanceMirrorImpl(this._instanceMirror);

  dynamic get reflectee => _instanceMirror.reflectee;

  dynamic read(Symbol member) {
    return _instanceMirror.getField(member).reflectee;
  }

  void write(Symbol member, val) {
    _instanceMirror.setField(member,val);
  }

  dynamic invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    return _instanceMirror.invoke(member, positional, named).reflectee;
  }

  /// Returns a mirror of the declaration of [member], if the mirrored
  /// entity is an instance of a class and such a declaration exists;
  /// otherwise returns null.
  dm.DeclarationMirror _getDeclaration(Symbol member) {
    var typeMirror = _instanceMirror.type;
    if (typeMirror is! dm.ClassMirror) return null;
    // Search up through all superclasses for the requested declaration.
    for (dm.ClassMirror cm in new _SuperTypeIterable(typeMirror)) {
      dm.DeclarationMirror decl = cm.declarations[member];
      if (decl != null) return decl;
    }
    // No such declaration in any superclass.
    return null;
  }

  dynamic invokeAdjust(Symbol member,
                       List positional,
                       [Map<Symbol, dynamic> named]) {
    var declMirror = _getDeclaration(member);
    if (declMirror is dm.MethodMirror && declMirror.isRegularMethod) {
      List<dm.ParameterMirror> parMirrors = declMirror.parameters;
      List adjusted_positional = _adjustArgumentList(positional,parMirrors);
      return _instanceMirror
          .invoke(member, adjusted_positional, named)
          .reflectee;
    }
    // [invokeAdjust] will not invoke a non-method.
    throw "TODO(eernst): select the right thing to throw here";
  }

  bool hasGetter(Symbol member) {
    dm.DeclarationMirror decl = _getDeclaration(member);
    // TODO(eernst): may need to adjust semantecs and/or rename ('canGet'?)
    // Semantics following pkg/smoke/lib/mirrors.dart, hasGetter;
    // apparently 'hasGetter' means that there is a declaration at
    // all, instance or static, variable or method; also note that the
    // semantics here _does_ include getters in Object (which makes a
    // difference for hashCode and runtimeType).
    return decl != null;
  }

  bool hasSetter(Symbol member) {
    // TODO(eernst): may need to adjust semantecs and/or rename ('canSet'?)
    // Semantics following pkg/smoke/lib/mirrors.dart, hasSetter; note that the
    // semantics here includes setters in Object in the search (but this
    // currently makes no difference because Object does not have any setters).
    dm.DeclarationMirror decl = _getDeclaration(member);
    if (decl is dm.VariableMirror && !decl.isFinal) return true;
    return _getDeclaration(setterName(member)) != null;
  }

  bool hasMethod(Symbol member) {
    // Semantics inspired by pkg/smoke/lib/mirrors.dart, which however does not
    // declare hasMethod; note that it includes methods in Object in the search
    // (so we include noSuchMethod and toString).
    dm.DeclarationMirror decl = _getDeclaration(member);
    return decl is dm.MethodMirror && decl.isRegularMethod;
  }
}

class _ClassMirrorImpl extends ClassMirror {
  final dm.ClassMirror _classMirror;

  _ClassMirrorImpl(this._classMirror);

  Type get type => _classMirror.reflectedType;

  dynamic newInstance(Symbol member,
                      List positional,
                      [Map<Symbol, dynamic> named]) {
    return _classMirror.newInstance(member, positional, named).reflectee;
  }

  dynamic read(Symbol member) {
    return _classMirror.getField(member).reflectee;
  }

  void write(Symbol member, val) {
    _classMirror.setField(member,val);
  }

  dynamic invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    return _classMirror.invoke(member, positional, named).reflectee;
  }

  dynamic invokeAdjust(Symbol member,
                       List positional,
                       [Map<Symbol, dynamic> named]) {
    var declMirror = _getLocalDeclaration(member);
    if (declMirror is dm.MethodMirror && declMirror.isRegularMethod) {
      List<dm.ParameterMirror> parMirrors = declMirror.parameters;
      List adjusted_positional = _adjustArgumentList(positional, parMirrors);
      return _classMirror.invoke(member, adjusted_positional, named).reflectee;
    }
    // invokeAdjust will not invoke a non-method.
    throw "TODO(eernst): select the right thing to throw here";
  }

  Map<Symbol, DeclarationMirror> get declarations {
    Map<Symbol, dm.DeclarationMirror> decls = _classMirror.declarations;
    return new Map<Symbol, DeclarationMirror>.fromIterable(
        decls.keys,
        key: (k) => k,
        value: (v) => new _DeclarationMirrorImpl(decls[v]));
  }

  /// Returns a mirror of the declaration of [member], if the mirrored
  /// entity is a class and such a declaration exists in that class
  /// (superclasses are not considered); otherwise returns null.
  dm.DeclarationMirror _getLocalDeclaration(Symbol member) {
    return _classMirror.declarations[member];
  }

  /// Returns a mirror of the declaration of [member], if the mirrored
  /// entity is an instance of a class and such a declaration exists in that
  /// class or one of its superclasses except Object; otherwise returns null.
  dm.DeclarationMirror _getDeclarationExceptObject(Symbol member) {
    // Search up through all superclasses for the requested declaration.
    for (dm.ClassMirror cm in new _SuperTypeIterable(_classMirror)) {
      if (cm == _objectType) return null;
      dm.DeclarationMirror decl = cm.declarations[member];
      if (decl != null) return decl;
    }
    // No such declaration in any superclass.
    return null;
  }

  /// Returns a mirror of the declaration of [member], if the mirrored
  /// entity is an instance of a class and such a declaration exists in
  /// that class or one of its superclasses; otherwise returns null.
  dm.DeclarationMirror _getDeclaration(Symbol member) {
    // Search up through all superclasses for the requested declaration.
    for (dm.ClassMirror cm in new _SuperTypeIterable(_classMirror)) {
      dm.DeclarationMirror decl = cm.declarations[member];
      if (decl != null) return decl;
    }
    // No such declaration in any superclass.
    return null;
  }

  DeclarationMirror getDeclaration(Symbol member) {
    dm.DeclarationMirror decl = _getLocalDeclaration(member);
    if (decl == null) return null;
    return new _DeclarationMirrorImpl(decl);
  }

  bool hasGetter(Symbol member) {
    dm.DeclarationMirror decl = _getDeclaration(member);
    // TODO(eernst): may need to adjust semantecs and/or rename ('canGet'?).
    // Semantics following pkg/smoke/lib/mirrors.dart, hasGetter;
    // apparently 'hasGetter' means that there is a declaration at
    // all, instance or static, variable or method.
    return decl != null;
  }

  bool hasSetter(Symbol member) {
    // TODO(eernst): may need to adjust semantecs and/or rename ('canSet'?).
    // Semantics following pkg/smoke/lib/mirrors.dart, hasSetter, except
    // that we _do_ include declarations in Object (this makes a difference
    // for hashCode and runtimeType).
    dm.DeclarationMirror decl = _getDeclaration(member);
    if (decl is dm.VariableMirror && !decl.isFinal) return true;
    return _getDeclaration(setterName(member)) != null;
  }

  bool hasInstanceMethod(Symbol member) {
    // Semantics following pkg/smoke/lib/mirrors.dart, except that we _do_
    // include declarations in Object (which makes a difference for noSuchMethod
    // and toString).
    dm.DeclarationMirror decl = _getDeclaration(member);
    return decl is dm.MethodMirror && decl.isRegularMethod && !decl.isStatic;
  }

  bool hasStaticMethod(Symbol member) {
    // Semantics following pkg/smoke/lib/mirrors.dart.
    dm.DeclarationMirror decl = _getLocalDeclaration(member);
    return decl is dm.MethodMirror && decl.isRegularMethod && decl.isStatic;
  }

  bool isSubclassOf(Type type) {
    for (dm.ClassMirror cm in new _SuperTypeIterable(_classMirror)) {
      if (cm.reflectedType == type) return true;
    }
    // No such superclass.
    return false;
  }

  bool hasNoSuchMethod() {
    dm.DeclarationMirror decl = _getDeclarationExceptObject(#noSuchMethod);
    return decl is dm.MethodMirror && decl.isRegularMethod;
  }
}

class _DeclarationMirrorImpl extends DeclarationMirror {
  final dm.DeclarationMirror _declarationMirror;

  _DeclarationMirrorImpl(this._declarationMirror);

  Symbol get name => _declarationMirror.simpleName;

  bool get isField => _declarationMirror is dm.VariableMirror;

  bool get isInstanceGetter {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isGetter && !isStatic;
    } else {
      return false;
    }
  }

  bool get isInstanceSetter {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isSetter && !isStatic;
    } else {
      return false;
    }
  }

  bool get isInstanceMethod {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return !decl.isGetter && !decl.isSetter && !isStatic;
    } else {
      return false;
    }
  }

  bool get isStaticGetter {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isGetter && isStatic;
    } else {
      return false;
    }
  }

  bool get isStaticSetter {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isSetter && isStatic;
    } else {
      return false;
    }
  }

  bool get isStaticMethod {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return !decl.isGetter && !decl.isSetter && isStatic;
    } else {
      return false;
    }
  }

  bool get isConstructor {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isConstructor;
    } else {
      return false;
    }
  }

  bool get isProperty {
    // Not entirely clear what it should do. But we have this in smoke:
    //   bool get isProperty =>
    //     _original is MethodMirror && !_original.isRegularMethod;
    // where dart2js_member_mirrors.dart has this:
    //   bool get isRegularMethod => !(isGetter || isSetter || isConstructor);
    // so we must return the following (no matter what it means. ;-)
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isGetter || decl.isSetter || decl.isConstructor;
    } else {
      return false;
    }
  }

  bool get isFinal {
    var decl = _declarationMirror;
    if (decl is dm.VariableMirror) {
      return decl.isFinal;
    } else {
      return false;
    }
  }

  bool get isStatic {
    var decl = _declarationMirror;
    if (decl is dm.MethodMirror) {
      return decl.isStatic;
    } else if (decl is dm.VariableMirror) {
      return decl.isStatic;
    } else if (decl is dm.TypeMirror) {
      return false;
    } else if (decl is dm.LibraryMirror) {
      return false;
    }
    // This point is only reached if some case above has been forgotten.
    throw "Bug, please report to @eernst";
  }

  bool get isPrivate => _declarationMirror.isPrivate;

  List<Object> get metadata {
    return _declarationMirror.metadata.map((item) => item.reflectee);
  }

  /// Copied from pkg/smoke/lib/mirror.dart, then updated cf. fixed issue 16962.
  Type _toType(dm.TypeMirror t) {
    if (t is dm.ClassMirror) return t.reflectedType;
    if (t == null || t.qualifiedName != #dynamic) {
      _logger.warning('unknown type ($t).');
    }
    return dynamic;
  }

  Type get type {
    var decl = _declarationMirror;  // For conciseness.
    if (decl is dm.MethodMirror && decl.isRegularMethod) {
      // TODO(eernst):  This currently follows the semantics of the
      // same getter in pkg/smoke/lib/mirrors.dart, _MirrorDeclaration,
      // but should surely be extended to deliver the function type.
      return Function;
    }
    var typeMirror = decl is dm.VariableMirror ? decl.type : decl.returnType;
    return _toType(typeMirror);
  }
}
