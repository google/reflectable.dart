// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// NB: This is a manually written file whose purpose is to explore how to 
// generate code for transforming dynamic reflectable usage into static
// reflectable usage:  It is similar to the code that will be generated
// as a static version of the libraries
// package:reflectable/{reflectable,reflectable_impl}.dart,
// based on the use of MyReflectable in common.dart.
//
// The transformer will also edit the "import '.../reflectable.dart'
// directive to include the generated code and to import parts of the
// reflectable package that do not use dart:mirrors.  As a result, 
// the program will not depend on dart:mirrors, neither directly nor
// indirectly.

part of reflectable.test.common;

// Manually created 'staticized' specialization of Reflectable, to be
// used with the following classes:
// A, B, C, D, E, E2, F, F2, Annot, AnnotB, AnnotC, G, H, K.
// Copied here (temporarily) in order to enable static class mirrors.

/// Maps a [Symbol] to a [LibraryMirror] for that library.
final Map<Symbol, LibraryMirror>  _reflectLibraryMap = {
  _reflectable_LibrarySymbol: _reflectable_LibraryMirror,
  _a_LibrarySymbol: _a_LibraryMirror,
  _b_LibrarySymbol: _b_LibraryMirror,
  _c_LibrarySymbol: _c_LibraryMirror,
  _core_LibrarySymbol: _core_LibraryMirror
};

/// Symbols and objects used by _reflectLibraryMap.
const _reflectable_LibrarySymbol = const Symbol('reflectable.reflectable');
const _a_LibrarySymbol = const Symbol('reflectable.test.a');
const _b_LibrarySymbol = const Symbol('reflectable.test.b');
const _c_LibrarySymbol = const Symbol('reflectable.test.c');
const _core_LibrarySymbol = const Symbol('dart.core');
final _reflectable_LibraryMirror = new _reflectable_LibraryMirrorImpl();
final _a_LibraryMirror = new _a_LibraryMirrorImpl();
final _b_LibraryMirror = new _b_LibraryMirrorImpl();
final _c_LibraryMirror = new _c_LibraryMirrorImpl();
final _core_LibraryMirror = new _core_LibraryMirrorImpl();

/// Maps a [Type] which denotes a class to a [ClassMirror] that class.
final Map<Type, dynamic> _reflectClassMap = {
  A: new _A_ClassMirrorImpl(),
  B: new _B_ClassMirrorImpl(),
  C: new _C_ClassMirrorImpl(),
  D: new _D_ClassMirrorImpl(),
  E: new _E_ClassMirrorImpl(),
  E2: new _E2_ClassMirrorImpl(),
  F: new _F_ClassMirrorImpl(),
  F2: new _F2_ClassMirrorImpl(),
  AnnotB: new _AnnotB_ClassMirrorImpl(),
  G: new _G_ClassMirrorImpl(),
  H: new _H_ClassMirrorImpl(),
  int: new _int_ClassMirrorImpl(),
  Object: new _Object_ClassMirrorImpl()
};

/// Maps a Type to a factory for a mirror for an instance of that Type.
final Map<Type, dynamic> _reflectMap = {
  A: (o) => new _A_InstanceMirrorImpl(o)
};

class ReflectableX {
  final List<Capability> capabilities;

  const ReflectableX(this.capabilities);

  InstanceMirror reflect(object) {
    if (object is Type) return new _Type_InstanceMirrorImpl(object);
    return _reflectMap[object.runtimeType](object);
  }

  ClassMirror reflectClass(Type type) {
    return _reflectClassMap[type];
  }

  LibraryMirror findLibrary(Symbol libraryName) {
    return _reflectLibraryMap[libraryName];
  }

  // TODO(eernst): write a static version of these two methods
  //
  // List<LibraryMirror> get libraries {
  //   ...
  // }
  //
  // LibraryMirror get mainLibrary {
  //   ...
  // }
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _LibraryMirror extends LibraryMirror {
  Symbol get qualifiedName => throw "TODO";
  Symbol get simpleName => throw "TODO";
  List<LibraryMirror> get imports => throw "TODO";
  List<LibraryMirror> get exports => throw "TODO";
  Map<Symbol, ClassMirror> get classes => throw "TODO";
  Map<Symbol, DeclarationMirror> get declarations => throw "TODO";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _ClassMirror extends ClassMirror {
  Type get type => throw "TODO";
  dynamic newInstance(Symbol member,
                      List positional,
                      [Map<Symbol, dynamic> named]) => throw "TODO";
  dynamic read(Symbol member) => throw "TODO";
  void write(Symbol member, val) => throw "TODO";
  dynamic invoke(Symbol member,
                 List positional,
                 [Map<Symbol, dynamic> named]) => throw "TODO";
  dynamic invokeAdjust(Symbol member, 
                       List positional,
                       [Map<Symbol, dynamic> named]) => throw "TODO";
  Map<Symbol, DeclarationMirror> get declarations => throw "TODO";
  DeclarationMirror getDeclaration(Symbol member) => throw "TODO";
  bool hasGetter(Symbol member) => throw "TODO";
  bool hasSetter(Symbol member) => throw "TODO";
  bool hasInstanceMethod(Symbol member) => throw "TODO";
  bool hasStaticMethod(Symbol member) => throw "TODO";
  bool isSubclassOf(Type type) => throw "TODO";
  bool hasNoSuchMethod() => throw "TODO";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _DeclarationMirror extends DeclarationMirror {
  bool get isField => throw "TODO";
  bool get isProperty => throw "TODO";
  bool get isInstanceGetter => throw "TODO";
  bool get isInstanceSetter => throw "TODO";
  bool get isInstanceMethod => throw "TODO";
  bool get isStaticGetter => throw "TODO";
  bool get isStaticSetter => throw "TODO";
  bool get isStaticMethod => throw "TODO";
  bool get isFinal => throw "TODO";
  bool get isStatic => throw "TODO";
  List<Object> get metadata => throw "TODO";
  Type get type => throw "TODO";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _InstanceMirror extends InstanceMirror {
  dynamic read(Symbol member) {
    throw "TODO";
  }

  void write(Symbol member, val) {
    throw "TODO";
  }

  dynamic invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    throw "TODO";
  }

  dynamic invokeAdjust(Symbol member,
                       List positional,
                       [Map<Symbol, dynamic> named]) {
    throw "TODO";
  }

  bool hasGetter(Symbol member) {
    throw "TODO";
  }

  bool hasSetter(Symbol member) {
    throw "TODO";
  }

  bool hasMethod(Symbol member) {
    throw "TODO";
  }  
}

class _reflectable_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _reflectable_LibrarySymbol;
}

class _a_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _a_LibrarySymbol;

  List<LibraryMirror> get imports =>
      [_reflectable_LibraryMirror, _b_LibraryMirror, _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {
    #m1: new _a_library_m1_DeclarationMirrorImpl()
  };
}

class _b_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _b_LibrarySymbol;

  List<LibraryMirror> get imports =>
      [_c_LibraryMirror, _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {};
}

class _c_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _c_LibrarySymbol;

  List<LibraryMirror> get imports =>
      [_reflectable_LibraryMirror, _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {
    #m3: new _a_library_m3_DeclarationMirrorImpl()
  };
}

class _core_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _core_LibrarySymbol;
}

final Map<Symbol, dynamic> _A_declaration_map = {
  #inc1: new _A_inc1_DeclarationMirrorImpl()
};

class _A_ClassMirrorImpl extends _ClassMirror {
  Type get type => A;

  dynamic invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    if (member == #staticInc) {
      if (positional.length == 0) {
        return A.staticInc();
      } else {
        throw "invoke failed: wrong number of arguments";
      }
    }
  }

  bool hasGetter(Symbol member) => [#i, #j2, #inc2].contains(member);

  bool hasSetter(Symbol member) => [#i, #j2].contains(member);

  bool hasNoSuchMethod() => false;

  bool hasInstanceMethod(Symbol member) => [#inc0].contains(member);

  bool hasStaticMethod(Symbol member) => false;

  DeclarationMirror getDeclaration(Symbol member) => _A_declaration_map[member];

  bool isSubclassOf(Type type) => [A,Object].contains(type);
}

final Map<Symbol, dynamic> _B_declaration_map = {
  #a: new _B_a_DeclarationMirrorImpl(),
  #w: new _B_w_DeclarationMirrorImpl()
};

class _B_ClassMirrorImpl extends _ClassMirror {
  Type get type => B;

  bool hasGetter(Symbol member) => [#a, #f].contains(member);

  bool hasSetter(Symbol member) => [#a].contains(member);

  DeclarationMirror getDeclaration(Symbol member) => _B_declaration_map[member];

  bool isSubclassOf(Type type) => [B,Object].contains(type);
}

class _C_ClassMirrorImpl extends _ClassMirror {
  Type get type => C;

  bool hasInstanceMethod(Symbol member) => [#inc].contains(member);

  bool hasStaticMethod(Symbol member) => false;
}

class _D_ClassMirrorImpl extends _ClassMirror {
  Type get type => D;

  bool hasGetter(Symbol member) => [#i].contains(member);

  bool hasSetter(Symbol member) => [#i].contains(member);

  bool hasInstanceMethod(Symbol member) => [#inc, #inc0].contains(member);

  bool hasStaticMethod(Symbol member) => false;

  bool isSubclassOf(Type type) => [D,C,Object].contains(type);
}

class _E_ClassMirrorImpl extends _ClassMirror {
  Type get type => E;

  bool hasGetter(Symbol member) => [#y].contains(member);

  bool hasSetter(Symbol member) => [#x].contains(member);

  bool hasNoSuchMethod() => true;
}

class _E2_ClassMirrorImpl extends _ClassMirror {
  Type get type => E2;

  bool hasNoSuchMethod() => true;
}

final Map<Symbol, dynamic> _F_declaration_map = {
  #staticMethod: new _F_staticMethod_DeclarationMirrorImpl()
};

class _F_ClassMirrorImpl extends _ClassMirror {
  Type get type => F;

  bool hasInstanceMethod(Symbol member) => false;

  bool hasStaticMethod(Symbol member) => [#staticMethod].contains(member);

  DeclarationMirror getDeclaration(Symbol member) => _F_declaration_map[member];
}

class _F2_ClassMirrorImpl extends _ClassMirror {
  Type get type => F2;

  bool hasInstanceMethod(Symbol member) => false;

  bool hasStaticMethod(Symbol member) => false;
}

class _AnnotB_ClassMirrorImpl extends _ClassMirror {
  Type get type => AnnotB;

  bool isSubclassOf(Type type) => [AnnotB, Annot, Object].contains(type);
}

final Map<Symbol, dynamic> _G_declaration_map = {
  #b: new _G_b_DeclarationMirrorImpl(),
  #d: new _G_d_DeclarationMirrorImpl()
};

class _G_ClassMirrorImpl extends _ClassMirror {
  Type get type => G;

  DeclarationMirror getDeclaration(Symbol member) => _G_declaration_map[member];
}

class _H_ClassMirrorImpl extends _ClassMirror {
  Type get type => H;

  bool isSubclassOf(Type type) => [H,G,Object].contains(type);
}

class _int_ClassMirrorImpl extends _ClassMirror {
  Type get type => K;

  bool hasNoSuchMethod() => false;
}

class _Object_ClassMirrorImpl extends _ClassMirror {
  Type get type => Object;

  bool isSubclassOf(Type type) => (type == Object);
}

class _A_inc1_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #inc1;
  bool get isField => false;
  bool get isProperty => false;
  bool get isMethod => true;
  bool get isFinal => false;
  bool get isStatic => false;
  List<Object> get metadata => [];
  Type get type => Function;
}

class _B_a_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #a;
  bool get isField => true;
  bool get isProperty => false;
  bool get isInstanceMethod => false;
  bool get isFinal => false;
  bool get isStatic => false;
  List<Object> get metadata => [];
  Type get type => A;
}

class _B_w_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #w;
  bool get isField => false;
  bool get isProperty => true;
  bool get isMethod => false;
  bool get isFinal => false;
  bool get isStatic => false;
  List<Object> get metadata => [];
  Type get type => int;
}

class _F_staticMethod_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #staticMethod;
  bool get isField => false;
  bool get isProperty => false;
  bool get isMethod => true;
  bool get isFinal => false;
  bool get isStatic => true;
  List<Object> get metadata => [];
  Type get type => Function;
}

class _G_b_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #b;
  bool get isField => true;
  bool get isProperty => false;
  bool get isMethod => false;
  bool get isFinal => false;
  bool get isStatic => false;
  List<Object> get metadata => [const Annot()];
  Type get type => int;
}

class _G_d_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #d;
  bool get isField => true;
  bool get isProperty => false;
  bool get isMethod => false;
  bool get isFinal => false;
  bool get isStatic => false;
  List<Object> get metadata => [32];
  Type get type => int;
}

class _a_library_m1_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #m1;
}

class _a_library_m3_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get name => #m3;
}

final Map<Symbol, int> _A_method_min_arity = {
  #inc0: 0,
  #inc1: 1,
  #inc2: 0
};

final Map<Symbol, int> _A_method_max_arity = {
  #inc0: 0,
  #inc1: 1,
  #inc2: 1
};

class _A_InstanceMirrorImpl extends _InstanceMirror {
  A _reflectee;

  _A_InstanceMirrorImpl(this._reflectee);

  A get reflectee => _reflectee;

  dynamic read(Symbol member) {
    if (member == #i) return _reflectee.i;
    if (member == #j) return _reflectee.j;
    if (member == #j2) return _reflectee.j2;
    if (member == #inc1) return _reflectee.inc1;
    throw "read failed: unknown member";
  }

  void write(Symbol member, val) {
    if (member == #i) {
      _reflectee.i = val;
      return;
    }
    if (member == #j2) {
      _reflectee.j2 = val;
      return;
    }
    throw "write failed: unknown member";
  }

  dynamic invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    if (member == #inc0) {
      if (positional.length == 0) {
        return _reflectee.inc0();
      } else {
        throw "invoke failed: wrong number of arguments";
      }
    }
    if (member == #inc1) {
      if (positional.length == 1) {
        return _reflectee.inc1(positional[0]);
      } else {
        throw "invoke failed: wrong number of arguments";
      }
    }
    if (member == #inc2) {
      var positional0;
      if (positional.length == 0) {
        positional0 = null;  // Implicit default.
      } else if (positional.length == 1) {
        positional0 = positional[0];  // Explicitly given argument.
      } else {
        // Not an admissible number of arguments.
        throw "invoke failed: wrong number of arguments";
      }
      return _reflectee.inc2(positional0);
    }
    throw "invoke failed: unknown member";
  }

  List _adjustList(List lst, int min, int max) {
    if (lst.length < min) {
      return new List(min)..setRange(0, lst.length, lst);
    }
    if (lst.length > max) {
      return new List(max)..setRange(0, max, lst);
    }
    return lst;
  }

  dynamic invokeAdjust(Symbol member,
                       List positional,
                       [Map<Symbol, dynamic> named]) {
    return invoke(member,
                  _adjustList(positional,
                              _A_method_min_arity[member],
                              _A_method_max_arity[member]),
                  named);
  }
}

class _Type_InstanceMirrorImpl extends _InstanceMirror {
  Type _reflecteeType;

  _Type_InstanceMirrorImpl(this._reflecteeType);

  Type get reflectee => _reflecteeType;

  dynamic invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    if (member == #toString) {
      if (positional.length == 0) {
        return _reflecteeType.toString();
      } else {
        throw "invoke failed: wrong number of arguments";
      }
    }
  }
}

