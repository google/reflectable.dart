// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// NB: This is a manually written file whose purpose is to explore how to 
// generate code for transforming dynamic reflectable usage into static
// reflectable usage:  It is similar to the code that will be generated
// as a static version of the libraries
// package:reflectable/old/{reflectable,reflectable_impl}.dart,
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
const _common_LibrarySymbol = const Symbol('reflectable.test.common');
const _a_LibrarySymbol = const Symbol('reflectable.test.a');
const _b_LibrarySymbol = const Symbol('reflectable.test.b');
const _c_LibrarySymbol = const Symbol('reflectable.test.c');
const _core_LibrarySymbol = const Symbol('dart.core');
final _reflectable_LibraryMirror = new _reflectable_LibraryMirrorImpl();
final _common_LibraryMirror = new _common_LibraryMirrorImpl();
final _a_LibraryMirror = new _a_LibraryMirrorImpl();
final _b_LibraryMirror = new _b_LibraryMirrorImpl();
final _c_LibraryMirror = new _c_LibraryMirrorImpl();
final _core_LibraryMirror = new _core_LibraryMirrorImpl();

/// Maps a [Type] which denotes a class to a [ClassMirror] of that class.
final Map<Type, ClassMirror> _reflectClassMap = {
  A: new _A_ClassMirrorImpl(),
  B: new _B_ClassMirrorImpl(),
  C: new _C_ClassMirrorImpl(),
  D: new _D_ClassMirrorImpl(),
  E: new _E_ClassMirrorImpl(),
  E2: new _E2_ClassMirrorImpl(),
  F: new _F_ClassMirrorImpl(),
  F2: new _F2_ClassMirrorImpl(),
  Annot: new _Annot_ClassMirrorImpl(),
  AnnotB: new _AnnotB_ClassMirrorImpl(),
  G: new _G_ClassMirrorImpl(),
  H: new _H_ClassMirrorImpl(),
  int: new _int_ClassMirrorImpl(),
  Object: new _Object_ClassMirrorImpl()
};

typedef InstanceMirror InstanceMirrorProducer(Object);

/// Maps a Type to a factory for a mirror for an instance of that Type.
final Map<Type, InstanceMirrorProducer> _reflectMap = {
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
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _ObjectMirror implements ObjectMirror {
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol,dynamic> namedArguments]) =>
      throw "Not implemented: $this";
  Object getField(Symbol fieldName) =>
      throw "Not implemented: $this";
  Object setField(Symbol fieldName, Object value) =>
      throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _LibraryMirror extends _ObjectMirror implements LibraryMirror {
  Symbol get simpleName => throw "Not implemented: $this";
  Symbol get qualifiedName => throw "Not implemented: $this";
  DeclarationMirror get owner => throw "Not implemented: $this";
  bool get isPrivate => throw "Not implemented: $this";
  bool get isTopLevel => throw "Not implemented: $this";
  List<Object> get metadata => throw "Not implemented: $this";
  Uri get uri => throw "Not implemented: $this";
  Map<Symbol, DeclarationMirror> get declarations =>
      throw "Not implemented: $this";
  bool operator == (other) => throw "Not implemented: $this";
  List<LibraryDependencyMirror> get libraryDependencies =>
      throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _ClassMirror extends _TypeMirror with _ObjectMirror 
                            implements ClassMirror {
  Symbol get simpleName => throw "Not implemented: $this";
  Symbol get qualifiedName => throw "Not implemented: $this";
  DeclarationMirror get owner => throw "Not implemented: $this";
  bool get isPrivate => throw "Not implemented: $this";
  bool get isTopLevel => throw "Not implemented: $this";
  List<Object> get metadata => throw "Not implemented: $this";
  ClassMirror get superclass => throw "Not implemented: $this";
  bool get isAbstract => throw "Not implemented: $this";
  Map<Symbol, DeclarationMirror> get declarations =>
      throw "Not implemented: $this";
  Map<Symbol, MethodMirror> get instanceMembers =>
      throw "Not implemented: $this";
  Map<Symbol, MethodMirror> get staticMembers => throw "Not implemented: $this";
  ClassMirror get mixin => throw "Not implemented: $this";
  Object newInstance(Symbol constructorName,
                     List positionalArguments,
                     [Map<Symbol,dynamic> namedArguments]) =>
      throw "Not implemented: $this";
  bool operator == (other) => throw "Not implemented: $this";
  bool isSubclassOf(ClassMirror other) => throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _DeclarationMirror implements DeclarationMirror {
  Symbol get simpleName => throw "Not implemented: $this";
  Symbol get qualifiedName => throw "Not implemented: $this";
  DeclarationMirror get owner => throw "Not implemented: $this";
  bool get isPrivate => throw "Not implemented: $this";
  bool get isTopLevel => throw "Not implemented: $this";
  List<Object> get metadata => throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _MethodMirror extends _DeclarationMirror 
                             implements MethodMirror {
  TypeMirror get returnType => throw "Not implemented: $this";
  String get source => throw "Not implemented: $this";
  List<ParameterMirror> get parameters => throw "Not implemented: $this";
  bool get isStatic => throw "Not implemented: $this";
  bool get isAbstract => throw "Not implemented: $this";
  bool get isSynthetic => throw "Not implemented: $this";
  bool get isRegularMethod => throw "Not implemented: $this";
  bool get isOperator => throw "Not implemented: $this";
  bool get isGetter => throw "Not implemented: $this";
  bool get isSetter => throw "Not implemented: $this";
  bool get isConstructor => throw "Not implemented: $this";
  Symbol get constructorName => throw "Not implemented: $this";
  bool get isConstConstructor => throw "Not implemented: $this";
  bool get isGenerativeConstructor => throw "Not implemented: $this";
  bool get isRedirectingConstructor => throw "Not implemented: $this";
  bool get isFactoryConstructor => throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _VariableMirror extends _DeclarationMirror
                               implements VariableMirror {
  TypeMirror get type => throw "Not implemented: $this";
  bool get isStatic => throw "Not implemented: $this";
  bool get isFinal => throw "Not implemented: $this";
  bool get isConst => throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _ParameterMirror extends _VariableMirror
                                implements ParameterMirror {
  bool get isOptional => throw "Not implemented: $this";
  bool get isNamed => throw "Not implemented: $this";
  bool get hasDefaultValue => throw "Not implemented: $this";
  Object get defaultValue => throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _TypeMirror extends _DeclarationMirror implements TypeMirror {
  bool get hasReflectedType => throw "Not implemented: $this";
  Type get reflectedType => throw "Not implemented: $this";
  List<TypeVariableMirror> get typeVariables => throw "Not implemented: $this";
  List<TypeMirror> get typeArguments => throw "Not implemented: $this";
  bool get isOriginalDeclaration => throw "Not implemented: $this";
  TypeMirror get originalDeclaration => throw "Not implemented: $this";
  bool isSubtypeOf(TypeMirror other) => throw "Not implemented: $this";
  bool isAssignableTo(TypeMirror other) => throw "Not implemented: $this";
}

/// Used to provide default implementations of otherwise missing elements.
abstract class _InstanceMirror extends _ObjectMirror implements InstanceMirror {
  TypeMirror get type => throw "Not implemented: $this";
  bool get hasReflectee => throw "Not implemented: $this";
  get reflectee => throw "Not implemented: $this";
  bool operator == (other) => throw "Not implemented: $this";
  delegate(Invocation invocation) => throw "Not implemented: $this";
}

class _LibraryDependencyMirror implements LibraryDependencyMirror {
  bool get isImport => throw "Not implemented: $this";
  bool get isExport => throw "Not implemented: $this";
  LibraryMirror get sourceLibrary => throw "Not implemented: $this";
  LibraryMirror get targetLibrary => throw "Not implemented: $this";
  Symbol get prefix => throw "Not implemented: $this";
  List<Object> get metadata => throw "Not implemented: $this";
}

class _reflectable_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _reflectable_LibrarySymbol;

  bool get isPrivate => false;
}

class _common_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _common_LibrarySymbol;

  bool get isPrivate => false;

  List<LibraryMirror> get imports =>
      [ _reflectable_LibraryMirror,
        _a_LibraryMirror, _b_LibraryMirror, _c_LibraryMirror,
        _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {
    // #foo: new _common_library_foo_DeclarationMirrorImpl()
  };
}

class _a_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _a_LibrarySymbol;

  bool get isPrivate => false;

  List<LibraryMirror> get imports =>
      [_reflectable_LibraryMirror, _b_LibraryMirror, _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {
    #m1: new _a_library_m1_DeclarationMirrorImpl()
  };

  List<LibraryDependencyMirror> get libraryDependencies =>
      <LibraryDependencyMirror>[
        new _a_0_LibraryDependencyMirrorImpl(),
        new _a_1_LibraryDependencyMirrorImpl(),
        new _a_2_LibraryDependencyMirrorImpl()
      ];
}

class _a_0_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _core_LibraryMirrorImpl();
}

class _a_1_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _reflectable_LibraryMirrorImpl();
}

class _a_2_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _b_LibraryMirrorImpl();
}

class _b_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _b_LibrarySymbol;

  bool get isPrivate => false;

  List<LibraryMirror> get imports =>
      [_c_LibraryMirror, _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {};

  List<LibraryDependencyMirror> get libraryDependencies =>
      <LibraryDependencyMirror>[
        new _b_0_LibraryDependencyMirrorImpl(),
        new _b_1_LibraryDependencyMirrorImpl(),
      ];
}

class _b_0_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _core_LibraryMirrorImpl();
}

class _b_1_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _c_LibraryMirrorImpl();
}

class _c_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _c_LibrarySymbol;

  bool get isPrivate => false;

  List<LibraryMirror> get imports =>
      [_reflectable_LibraryMirror, _core_LibraryMirror];

  Map<Symbol, DeclarationMirror> get declarations => {
    #m3: new _a_library_m3_DeclarationMirrorImpl()
  };

  List<LibraryDependencyMirror> get libraryDependencies =>
      <LibraryDependencyMirror>[
        new _c_0_LibraryDependencyMirrorImpl(),
        new _c_1_LibraryDependencyMirrorImpl(),
      ];
}

class _c_0_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _core_LibraryMirrorImpl();
}

class _c_1_LibraryDependencyMirrorImpl extends _LibraryDependencyMirror {
  bool get isImport => true;
  LibraryMirror get targetLibrary => new _reflectable_LibraryMirrorImpl();
}

class _core_LibraryMirrorImpl extends _LibraryMirror {
  Symbol get simpleName => _core_LibrarySymbol;

  bool get isPrivate => false;
}

final Map<Symbol, DeclarationMirror> _A_declaration_map = {
  #i: new _A_i_DeclarationMirrorImpl(),
  #j2: new _A_j2_DeclarationMirrorImpl(),
  const Symbol("j2="): new _A_j2equals_DeclarationMirrorImpl(),
  #inc0: new _A_inc0_DeclarationMirrorImpl(),
  #inc1: new _A_inc1_DeclarationMirrorImpl(),
  #inc2: new _A_inc2_DeclarationMirrorImpl()
};

class _A_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _Object_ClassMirrorImpl();

  Type get reflectedType => A;

  DeclarationMirror get owner => _common_LibraryMirror;

  invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    if (member == #staticInc) {
      if (positional.length == 0) {
        return A.staticInc();
      } else {
        throw "invoke failed: wrong number of arguments";
      }
    }
  }

  Map<Symbol, DeclarationMirror> get declarations => _A_declaration_map;

  bool isSubclassOf(ClassMirror cm) => [A,Object].contains(cm.reflectedType);
}

class _AmixC_ClassMirrorImpl extends _A_ClassMirrorImpl {
  ClassMirror get superclass => new _C_ClassMirrorImpl();
}

final Map<Symbol, DeclarationMirror> _B_declaration_map = {
  #a: new _B_a_DeclarationMirrorImpl(),
  #w: new _B_w_DeclarationMirrorImpl(),
  #f: new _B_f_DeclarationMirrorImpl()
};

class _B_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _Object_ClassMirrorImpl();

  Type get reflectedType => B;

  Map<Symbol, DeclarationMirror> get declarations => _B_declaration_map;

  bool isSubclassOf(ClassMirror cm) => [B,Object].contains(cm.reflectedType);
}

final Map<Symbol, DeclarationMirror> _C_declaration_map = {
  #inc: new _C_inc_DeclarationMirrorImpl()
};

class _C_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _Object_ClassMirrorImpl();

  Map<Symbol, DeclarationMirror> get declarations => _C_declaration_map;

  Type get reflectedType => C;

  DeclarationMirror get owner => _common_LibraryMirror;
}

final Map<Symbol, DeclarationMirror> _D_declaration_map = {
};

class _D_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _AmixC_ClassMirrorImpl();

  Map<Symbol, DeclarationMirror> get declarations => _D_declaration_map;

  Type get reflectedType => D;

  bool isSubclassOf(ClassMirror cm) => [D,C,Object].contains(cm.reflectedType);
}

final Map<Symbol, DeclarationMirror> _E_declaration_map = {
  const Symbol("x="): new _E_x_DeclarationMirrorImpl(),
  #y: new _E_y_DeclarationMirrorImpl(),
  #noSuchMethod: new _E_noSuchMethod_DeclarationMirrorImpl()
};

class _E_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _Object_ClassMirrorImpl();

  Map<Symbol, DeclarationMirror> get declarations => _E_declaration_map;

  Type get reflectedType => E;
}

final Map<Symbol, DeclarationMirror> _E2_declaration_map = {
  #noSuchMethod: new _E2_noSuchMethod_DeclarationMirrorImpl(),
};

class _E2_ClassMirrorImpl extends _ClassMirror {
  Type get reflectedType => E2;
  Map<Symbol, DeclarationMirror> get declarations => _E2_declaration_map;
}

final Map<Symbol, DeclarationMirror> _F_declaration_map = {
  #staticMethod: new _F_staticMethod_DeclarationMirrorImpl()
};

class _F_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _F_ClassMirrorImpl();
  Map<Symbol, DeclarationMirror> get declarations => _F_declaration_map;
  Type get reflectedType => F;
  DeclarationMirror get owner => _common_LibraryMirror;
}

final Map<Symbol, DeclarationMirror> _F2_declaration_map = {
};

class _F2_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => new _F_ClassMirrorImpl();
  Type get reflectedType => F2;
  Map<Symbol, DeclarationMirror> get declarations => _F2_declaration_map;
}

class _Annot_ClassMirrorImpl extends _ClassMirror {
  Type get reflectedType => Annot;
  bool isSubclassOf(ClassMirror cm) =>
      [Annot, Object].contains(cm.reflectedType);
}

class _AnnotB_ClassMirrorImpl extends _ClassMirror {
  Type get reflectedType => AnnotB;
  bool isSubclassOf(ClassMirror cm) => 
      [AnnotB, Annot, Object].contains(cm.reflectedType);
}

final Map<Symbol, DeclarationMirror> _G_declaration_map = {
  #b: new _G_b_DeclarationMirrorImpl(),
  #d: new _G_d_DeclarationMirrorImpl()
};

class _G_ClassMirrorImpl extends _ClassMirror {
  Map<Symbol, DeclarationMirror> get declarations => _G_declaration_map;
  Type get reflectedType => G;
}

class _H_ClassMirrorImpl extends _ClassMirror {
  Type get reflectedType => H;
  bool isSubclassOf(ClassMirror cm) => [H,G,Object].contains(cm.reflectedType);
}

final Map<Symbol, DeclarationMirror> _int_declaration_map = {
};

class _int_ClassMirrorImpl extends _ClassMirror {
  Type get reflectedType => int;
  ClassMirror get superclass => new _Object_ClassMirrorImpl();
  Map<Symbol, DeclarationMirror> get declarations => _int_declaration_map;
}

final Map<Symbol, DeclarationMirror> _Object_declaration_map = {
  #Object: new _Object_Object_DeclarationMirrorImpl(),
  #noSuchMethod: new _Object_noSuchMethod_DeclarationMirrorImpl(),
  #toString: new _Object_toString_DeclarationMirrorImpl(),
  #==: new _Object_equals_DeclarationMirrorImpl(),
  #hashCode: new _Object_hashCode_DeclarationMirrorImpl(),
  #runtimeType: new _Object_runtimeType_DeclarationMirrorImpl(),
};

class _Object_ClassMirrorImpl extends _ClassMirror {
  ClassMirror get superclass => null;
  Map<Symbol, DeclarationMirror> get declarations => _Object_declaration_map;
  Type get reflectedType => Object;
  DeclarationMirror get owner => _core_LibraryMirror;
  bool isSubclassOf(ClassMirror cm) => (cm.reflectedType == Object);
}

class _A_i_DeclarationMirrorImpl extends _VariableMirror {
  Symbol get simpleName => #i;
  Symbol get qualifiedName => #reflectable.test.common.A.i;
  bool get isPrivate => false;
  TypeMirror get type => new _int_ClassMirrorImpl();
  bool get isFinal => false;
}

class _A_j2_DeclarationMirrorImpl extends _MethodMirror {
  Symbol get simpleName => #j2;
  Symbol get qualifiedName => #reflectable.test.common.A.j2;
  bool get isPrivate => false;
  bool get isRegularMethod => false;
  bool get isGetter => true;
}

class _A_j2equals_DeclarationMirrorImpl extends _MethodMirror {
  Symbol get simpleName => const Symbol("j2=");
  Symbol get qualifiedName => const Symbol("reflectable.test.common.A.j2=");
  bool get isPrivate => false;
  bool get isRegularMethod => false;
  bool get isGetter => false;
  bool get isSetter => true;
}

class _A_inc0_DeclarationMirrorImpl extends _MethodMirror {
  bool get isRegularMethod => true;
  bool get isStatic => false;
  List<ParameterMirror> get parameters => <ParameterMirror>[];
}

class _A_inc1_DeclarationMirrorImpl extends _MethodMirror {
  Symbol get simpleName => #inc1;
  Symbol get qualifiedName => #reflectable.test.common.A.inc1;
  bool get isPrivate => false;
  bool get isRegularMethod => true;
  bool get isStatic => false;
  List<Object> get metadata => [];
  List<ParameterMirror> get parameters => <ParameterMirror>[
    new _A_inc1_v_DeclarationMirrorImpl()
  ];
}

class _A_inc1_v_DeclarationMirrorImpl extends _ParameterMirror {
  bool get isOptional => false;
  bool get isNamed => false;
}

class _A_inc2_DeclarationMirrorImpl extends _MethodMirror {
  Symbol get simpleName => #inc2;
  Symbol get qualifiedName => #reflectable.test.common.A.inc2;
  bool get isPrivate => false;
  bool get isRegularMethod => true;
  List<ParameterMirror> get parameters => <ParameterMirror>[
    new _A_inc2_v_DeclarationMirrorImpl()
  ];
}

class _A_inc2_v_DeclarationMirrorImpl extends _ParameterMirror {
  bool get isOptional => true;
  bool get isNamed => false;
}

class _B_a_DeclarationMirrorImpl extends _VariableMirror {
  Symbol get simpleName => #a;
  Symbol get qualifiedName => #reflectable.test.common.B.a;
  bool get isPrivate => false;
  bool get isFinal => false;
  bool get isStatic => false;
  List<Object> get metadata => [];
  TypeMirror get type => new _A_ClassMirrorImpl();
}

class _B_w_DeclarationMirrorImpl extends _MethodMirror {
  Symbol get simpleName => #w;
  Symbol get qualifiedName => #reflectable.test.common.B.w;
  bool get isPrivate => false;
  bool get isRegularMethod => false;
  bool get isStatic => false;
  List<Object> get metadata => [];
  TypeMirror get returnType => new _int_ClassMirrorImpl();
}

class _B_f_DeclarationMirrorImpl extends _VariableMirror {
  Symbol get simpleName => #f;
  Symbol get qualifiedName => #reflectable.test.common.B.f;
  bool get isPrivate => false;
  bool get isFinal => true;
}

class _C_inc_DeclarationMirrorImpl extends _MethodMirror {
  bool get isRegularMethod => true;
  bool get isStatic => false;
}

class _E_x_DeclarationMirrorImpl extends _MethodMirror {
  bool get isRegularMethod => false;
  bool get isGetter => false;
  bool get isStatic => false;
  bool get isSetter => true;
}

class _E_y_DeclarationMirrorImpl extends _MethodMirror {
  bool get isRegularMethod => false;
  bool get isGetter => true;  
}

class _E_noSuchMethod_DeclarationMirrorImpl extends _MethodMirror {
  bool get isRegularMethod => true;
}

class _E2_noSuchMethod_DeclarationMirrorImpl extends _MethodMirror {
  bool get isRegularMethod => true;
}

class _F_staticMethod_DeclarationMirrorImpl extends _MethodMirror {
  Symbol get simpleName => #staticMethod;
  Symbol get qualifiedName => #reflectable.test.common.F.staticMethod;
  bool get isPrivate => false;
  bool get isRegularMethod => true;
  bool get isStatic => true;
  List<Object> get metadata => [];
}

class _G_b_DeclarationMirrorImpl extends _VariableMirror {
  Symbol get simpleName => #b;
  Symbol get qualifiedName => #reflectable.test.common.G.b;
  bool get isPrivate => false;
  List<Object> get metadata => [const Annot()];
  bool get isFinal => false;
  bool get isStatic => false;
  TypeMirror get type => new _int_ClassMirrorImpl();
}

class _G_d_DeclarationMirrorImpl extends _VariableMirror {
  Symbol get simpleName => #d;
  Symbol get qualifiedName => #reflectable.test.common.G.d;
  bool get isPrivate => false;
  List<Object> get metadata => [32];
  bool get isFinal => false;
  bool get isStatic => false;
  TypeMirror get type => new _int_ClassMirrorImpl();
}

class _Object_Object_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #Object;
  Symbol get qualifiedName => #reflectable.test.common.Object.Object;
  bool get isPrivate => false;
  List<Object> get metadata => [];
}

class _Object_noSuchMethod_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #noSuchMethod;
  Symbol get qualifiedName => #reflectable.test.common.Object.noSuchMethod;
  bool get isPrivate => false;
  List<Object> get metadata => [];
}

class _Object_toString_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #toString;
  Symbol get qualifiedName => #reflectable.test.common.Object.toString;
  bool get isPrivate => false;
  List<Object> get metadata => [];
}

class _Object_equals_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => const Symbol("==");
  Symbol get qualifiedName => const Symbol("reflectable.test.common.Object.==");
  bool get isPrivate => false;
  List<Object> get metadata => [];
}

class _Object_hashCode_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #hashCode;
  Symbol get qualifiedName => #reflectable.test.common.Object.hashCode;
  bool get isPrivate => false;
  List<Object> get metadata => [];
}

class _Object_runtimeType_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #runtimeType;
  Symbol get qualifiedName => #reflectable.test.common.Object.runtimeType;
  bool get isPrivate => false;
  List<Object> get metadata => [];
}

class _a_library_m1_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #m1;
}

class _a_library_m3_DeclarationMirrorImpl extends _DeclarationMirror {
  Symbol get simpleName => #m3;
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

  TypeMirror get type => new _A_ClassMirrorImpl();

  Object getField(Symbol member) {
    if (member == #i) return _reflectee.i;
    if (member == #j) return _reflectee.j;
    if (member == #j2) return _reflectee.j2;
    if (member == #inc1) return _reflectee.inc1;
    throw "getField failed: unknown member";
  }

  Object setField(Symbol member, Object value) {
    if (member == #i) {
      _reflectee.i = value;
      return value;
    }
    if (member == #j2) {
      _reflectee.j2 = value;
      return value;
    }
    throw "setField failed: unknown member";
  }

  invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
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

  invokeAdjust(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
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

  invoke(Symbol member, List positional, [Map<Symbol, dynamic> named]) {
    if (member == #toString) {
      if (positional.length == 0) {
        return _reflecteeType.toString();
      } else {
        throw "invoke failed: wrong number of arguments";
      }
    }
  }
}

final Map<Symbol, String> _symbolToNameTable = {
  #i: "i"
};

String symbolToName(Symbol symbol) => _symbolToNameTable[symbol];

Symbol nameToSymbol(String name) => new Symbol(name);
