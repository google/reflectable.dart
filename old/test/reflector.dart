// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of reflectable.test.reflector;

main() {
  test('read value', () {
    var a = new A();
    var m = myReflectable.reflect(a);
    expect(m.getField(#i), 42);
    expect(m.getField(#j), 44);
    expect(m.getField(#j2), 44);
  });

  test('write value', () {
    var a = new A();
    var m = myReflectable.reflect(a);
    m.setField(#i, 43);
    expect(a.i, 43);
    m.setField(#j2, 46);
    expect(a.j, 46);
    expect(a.j2, 46);
    expect(m.getField(#j), 46);
    expect(m.getField(#j2), 46);
  });

  test('invoke', () {
    var a = new A();
    var m = myReflectable.reflect(a);

    m.invoke(#inc0, []);
    expect(a.i, 43);
    expect(m.getField(#i), 43);
    expect(() => m.invoke(#inc0, [2]), throws);
    expect(a.i, 43);
    expect(() => m.invoke(#inc0, [1, 2, 3]), throws);
    expect(a.i, 43);

    expect(() => m.invoke(#inc1, []), throws);
    expect(a.i, 43);
    m.invoke(#inc1, [4]);
    expect(a.i, 47);

    m.invoke(#inc2, []);
    expect(a.i, 37);
    m.invoke(#inc2, [4]);
    expect(a.i, 41);

    expect(() => m.invoke(#inc1, [4, 5]), throws);
    expect(a.i, 41);
  });

  test('static invoke', () {
    A.staticValue = 42;
    var m = myReflectable.reflectClass(A);
    m.invoke(#staticInc, []);
    expect(A.staticValue, 43);
  });

  test('read and invoke function', () {
    var a = new A();
    var m = myReflectable.reflect(a);
    expect(a.i, 42);
    var f = m.getField(#inc1);
    f(4);
    expect(a.i, 46);
    Function.apply(f, [4]);
    expect(a.i, 50);
  });

  test('invoke with adjust', () {
    var a = new A();
    var m = myReflectable.reflect(a);
    instanceInvokeAdjust(m, #inc0, []);
    expect(a.i, 43);
    instanceInvokeAdjust(m, #inc0, [2]);
    expect(a.i, 44);
    instanceInvokeAdjust(m, #inc0, [1, 2, 3]);
    expect(a.i, 45);

    instanceInvokeAdjust(m, #inc1, []);  // treat as null (-10).
    expect(a.i, 35);
    instanceInvokeAdjust(m, #inc1, [4]);
    expect(a.i, 39);

    instanceInvokeAdjust(m, #inc2, []);  // default is null (-10).
    expect(a.i, 29);
    instanceInvokeAdjust(m, #inc2, [4, 5]);
    expect(a.i, 33);
  });

  test('has getter', () {
    var mA = myReflectable.reflectClass(A);
    var mB = myReflectable.reflectClass(B);
    var mD = myReflectable.reflectClass(D);
    var mE = myReflectable.reflectClass(E);

    expect(canGet(mA, #i), isTrue);
    expect(canGet(mA, #j2), isTrue);
    expect(canGet(mA, #inc2), isTrue);
    expect(canGet(mB, #a), isTrue);
    expect(canGet(mB, #i), isFalse);
    expect(canGet(mB, #f), isTrue);
    expect(canGet(mD, #i), isTrue);

    expect(canGet(mE, #x), isFalse);
    expect(canGet(mE, #y), isTrue);
    expect(canGet(mE, #z), isFalse);  // don't consider noSuchMethod.
  });

  test('has setter', () {
    var mA = myReflectable.reflectClass(A);
    var mB = myReflectable.reflectClass(B);
    var mD = myReflectable.reflectClass(D);
    var mE = myReflectable.reflectClass(E);

    expect(canSet(mA, #i), isTrue);
    expect(canSet(mA, #j2), isTrue);
    expect(canSet(mA, #inc2), isFalse);
    expect(canSet(mB, #a), isTrue);
    expect(canSet(mB, #i), isFalse);
    expect(canSet(mB, #f), isFalse);
    expect(canSet(mD, #i), isTrue);

    expect(canSet(mE, #x), isTrue);
    expect(canSet(mE, #y), isFalse);
    expect(canSet(mE, #z), isFalse);  // don't consider noSuchMethod.
  });

  test('no such method', () {
    expect(hasNoSuchMethod(myReflectable.reflectClass(A)), isFalse);
    expect(hasNoSuchMethod(myReflectable.reflectClass(E)), isTrue);
    expect(hasNoSuchMethod(myReflectable.reflectClass(E2)), isTrue);
    expect(hasNoSuchMethod(myReflectable.reflectClass(int)), isFalse);
  });

  test('has instance method', () {
    var mA = myReflectable.reflectClass(A);
    var mC = myReflectable.reflectClass(C);
    var mD = myReflectable.reflectClass(D);
    var mF = myReflectable.reflectClass(F);
    var mF2 = myReflectable.reflectClass(F2);

    expect(hasInstanceMethod(mA, #inc0), isTrue);
    expect(hasInstanceMethod(mA, #inc3), isFalse);
    expect(hasInstanceMethod(mC, #inc), isTrue);
    expect(hasInstanceMethod(mD, #inc), isTrue);  // Do include superclasses.
    expect(hasInstanceMethod(mD, #inc0), isTrue);  // .. including mixins.
    expect(hasInstanceMethod(mF, #staticMethod), isFalse);
    expect(hasInstanceMethod(mF2, #staticMethod), isFalse);
  });

  test('has static method', () {
    var mA = myReflectable.reflectClass(A);
    var mC = myReflectable.reflectClass(C);
    var mD = myReflectable.reflectClass(D);
    var mF = myReflectable.reflectClass(F);
    var mF2 = myReflectable.reflectClass(F2);

    expect(hasStaticMethod(mA, #inc0), isFalse);
    expect(hasStaticMethod(mC, #inc), isFalse);
    expect(hasStaticMethod(mD, #inc), isFalse);
    expect(hasStaticMethod(mD, #inc0), isFalse);
    expect(hasStaticMethod(mF, #staticMethod), isTrue);
    expect(hasStaticMethod(mF2, #staticMethod), isFalse);
  });

  test('get declaration', () {
    var mB = myReflectable.reflectClass(B);

    var d = getDeclaration(mB, #a);
    expect(d.simpleName, #a);
    expect(isField(d), isTrue);
    expect(isProperty(d), isFalse);
    expect(isMethod(d), isFalse);
    expect(isFinal(d), isFalse);
    expect(d.isStatic, isFalse);
    expect(d.metadata, []);
    expect(d.type.reflectedType, A);

    d = getDeclaration(mB, #w);
    expect(d.simpleName, #w);
    expect(isField(d), isFalse);
    expect(isProperty(d), isTrue);
    expect(isMethod(d), isFalse);
    expect(isFinal(d), isFalse);
    expect(d.isStatic, isFalse);
    expect(d.metadata, []);
    expect(d.returnType.reflectedType, int);

    var mA = myReflectable.reflectClass(A);
    d = getDeclaration(mA, #inc1);
    expect(d.simpleName, #inc1);
    expect(isField(d), isFalse);
    expect(isProperty(d), isFalse);
    expect(isMethod(d), isTrue);
    expect(isFinal(d), isFalse);
    expect(d.isStatic, isFalse);
    expect(d.metadata, []);
    // NB: Used to have 'expect(d.type.reflectedType, Function);' but a method
    // does not just have type Function; to get the same effect we test for
    // having gotten a MethodMirror, still ignoring the actual signature
    expect(d is MethodMirror, isTrue);

    var mF = myReflectable.reflectClass(F);
    d = getDeclaration(mF, #staticMethod);
    expect(d.simpleName, #staticMethod);
    expect(isField(d), isFalse);
    expect(isProperty(d), isFalse);
    expect(isMethod(d), isTrue);
    expect(isFinal(d), isFalse);
    expect(d.isStatic, isTrue);
    expect(d.metadata, []);
    // NB: Used to have 'expect(d.type.reflectedType, Function);'.
    // See first 'd is MethodMirror' for more info.
    expect(d is MethodMirror, isTrue);

    var mG = myReflectable.reflectClass(G);
    d = getDeclaration(mG, #b);
    expect(d.simpleName, #b);
    expect(isField(d), isTrue);
    expect(isProperty(d), isFalse);
    expect(isMethod(d), isFalse);
    expect(isFinal(d), isFalse);
    expect(d.isStatic, isFalse);
    expect(d.metadata, [const Annot()]);
    expect(d.type.reflectedType, int);

    d = getDeclaration(mG, #d);
    expect(d.simpleName, #d);
    expect(isField(d), isTrue);
    expect(isProperty(d), isFalse);
    expect(isMethod(d), isFalse);
    expect(isFinal(d), isFalse);
    expect(d.isStatic, isFalse);
    expect(d.metadata, [32]);
    expect(d.type.reflectedType, int);
  });

  test('isSuperclass', () {
    var mObject = myReflectable.reflectClass(Object);
    var mA = myReflectable.reflectClass(A);
    var mB = myReflectable.reflectClass(B);
    var mC = myReflectable.reflectClass(C);
    var mD = myReflectable.reflectClass(D);
    var mG = myReflectable.reflectClass(G);
    var mH = myReflectable.reflectClass(H);
    var mAnnot = myReflectable.reflectClass(Annot);
    var mAnnotB = myReflectable.reflectClass(AnnotB);

    expect(mD.isSubclassOf(mC), isTrue);
    expect(mH.isSubclassOf(mG), isTrue);
    expect(mH.isSubclassOf(mH), isTrue);
    expect(mH.isSubclassOf(mObject), isTrue);
    expect(mB.isSubclassOf(mObject), isTrue);
    expect(mA.isSubclassOf(mObject), isTrue);
    expect(mAnnotB.isSubclassOf(mAnnot), isTrue);

    expect(mD.isSubclassOf(mA), isFalse);
    expect(mH.isSubclassOf(mB), isFalse);
    expect(mB.isSubclassOf(mA), isFalse);
    expect(mObject.isSubclassOf(mA), isFalse);
  });

  group('query', () {
    _checkQuery(result, names) {
      expect(result.map((e) => e.name), unorderedEquals(names));
    }

  //   test('default', () {
  //     var options = new QueryOptions();
  //     var res = query(A, options);
  //     _checkQuery(res, [#i, #j, #j2]);
  //   });

  //   test('only fields', () {
  //     var options = new QueryOptions(includeProperties: false);
  //     var res = query(A, options);
  //     _checkQuery(res, [#i, #j]);
  //   });

  //   test('only properties', () {
  //     var options = new QueryOptions(includeFields: false);
  //     var res = query(A, options);
  //     _checkQuery(res, [#j2]);
  //   });

  //   test('properties and methods', () {
  //     var options = new QueryOptions(includeMethods: true);
  //     var res = query(A, options);
  //     _checkQuery(res, [#i, #j, #j2, #inc0, #inc1, #inc2]);
  //   });

  //   test('inherited properties and fields', () {
  //     var options = new QueryOptions(includeInherited: true);
  //     var res = query(D, options);
  //     _checkQuery(res, [#x, #y, #b, #i, #j, #j2, #x2, #i2]);
  //   });

  //   test('inherited fields only', () {
  //     var options = new QueryOptions(includeInherited: true,
  //         includeProperties: false);
  //     var res = query(D, options);
  //     _checkQuery(res, [#x, #y, #b, #i, #j]);
  //   });

  //   test('exact annotation', () {
  //     var options = new QueryOptions(includeInherited: true,
  //         withAnnotations: const [a1]);
  //     var res = query(H, options);
  //     _checkQuery(res, [#b, #f, #g]);

  //     options = new QueryOptions(includeInherited: true,
  //         withAnnotations: const [a2]);
  //     res = query(H, options);
  //     _checkQuery(res, [#d, #h]);

  //     options = new QueryOptions(includeInherited: true,
  //         withAnnotations: const [a1, a2]);
  //     res = query(H, options);
  //     _checkQuery(res, [#b, #d, #f, #g, #h]);
  //   });

  //   test('type annotation', () {
  //     var options = new QueryOptions(includeInherited: true,
  //         withAnnotations: const [Annot]);
  //     var res = query(H, options);
  //     _checkQuery(res, [#b, #f, #g, #i]);
  //   });

  //   test('mixed annotations (type and exact)', () {
  //     var options = new QueryOptions(includeInherited: true,
  //         withAnnotations: const [a2, Annot]);
  //     var res = query(H, options);
  //     _checkQuery(res, [#b, #d, #f, #g, #h, #i]);
  //   });

    test('symbol to name', () {
      expect(symbolToName(#i), 'i');
    });

    test('name to symbol', () {
      expect(nameToSymbol('i'), #i);
    });
  });

  test('invoke Type instance methods', () {
    var a = new A();
    var m = myReflectable.reflect(a.runtimeType);
    expect(m.invoke(#toString, []), a.runtimeType.toString());
  });

  test('libraries', () {
    var aLib = myReflectable.findLibrary(const Symbol('reflectable.test.a'));
    var bLib = myReflectable.findLibrary(const Symbol('reflectable.test.b'));
    var cLib = myReflectable.findLibrary(const Symbol('reflectable.test.c'));

    final reflectableSym = const Symbol('reflectable.reflectable');
    final bSym = const Symbol('reflectable.test.b');
    final cSym = const Symbol('reflectable.test.c');
    final coreSym = const Symbol('dart.core');

    var aLibImportSyms = new Set<Symbol>.from([reflectableSym, bSym, coreSym]);
    var bLibImportSyms = new Set<Symbol>.from([cSym, coreSym]);
    var cLibImportSyms = new Set<Symbol>.from([reflectableSym, coreSym]);

    chkImportSyms(syms, imports) {
      expect(imports.length, syms.length);
      for (var imp in imports) {
        expect(syms.contains(imp.simpleName), isTrue);
      }
    }
    chkImportSyms(aLibImportSyms, imports(aLib));
    chkImportSyms(bLibImportSyms, imports(bLib));
    chkImportSyms(cLibImportSyms, imports(cLib));

    var aLibDeclSyms = new Set<Symbol>.from([#m1]);
    var bLibDeclSyms = new Set<Symbol>.from([]);
    var cLibDeclSyms = new Set<Symbol>.from([#m3]);

    void chkDecls(syms, decls) {
      expect(decls.length, syms.length);
      for (var key in decls.keys) {
        expect(syms.contains(decls[key].simpleName), isTrue);
      }
    }
    chkDecls(aLibDeclSyms, aLib.declarations);
    chkDecls(bLibDeclSyms, bLib.declarations);
    chkDecls(cLibDeclSyms, cLib.declarations);
  });
}
