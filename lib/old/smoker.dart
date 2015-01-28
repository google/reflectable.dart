// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
//
// Convenience methods, making smoke code more portable.

import 'reflectable.dart';
import 'src/smoker_implementation.dart' as implementation;

/// TODO(eernst): describe
bool canGet(ClassMirror cm, Symbol name) => implementation.canGet(cm, name);

/// TODO(eernst): describe
bool canSet(ClassMirror cm, Symbol name) => implementation.canSet(cm, name);

/// TODO(eernst): describe
bool hasNoSuchMethod(ClassMirror cm) => implementation.hasNoSuchMethod(cm);

/// TODO(eernst): describe
bool hasInstanceMethod(ClassMirror cm, Symbol member) =>
    implementation.hasInstanceMethod(cm, member);

/// TODO(eernst): describe
bool hasStaticMethod(ClassMirror cm, Symbol member) =>
    implementation.hasStaticMethod(cm, member);

/// TODO(eernst): describe
DeclarationMirror getDeclaration(ClassMirror cm, Symbol name) =>
    implementation.getDeclaration(cm, name);

/// TODO(eernst): describe
bool isField(DeclarationMirror m) => implementation.isField(m);

/// TODO(eernst): describe
bool isFinal(DeclarationMirror m) => implementation.isFinal(m);

/// TODO(eernst): describe
bool isMethod(DeclarationMirror m) => implementation.isMethod(m);

/// TODO(eernst): describe
List<LibraryMirror> imports(LibraryMirror lm) => implementation.imports(lm);

/// TODO(eernst): describe
List<LibraryMirror> exports(LibraryMirror lm) => implementation.exports(lm);

/// TODO(eernst): describe
bool isProperty(DeclarationMirror m) => implementation.isProperty(m);

/// TODO(eernst): describe
Object instanceInvokeAdjust(InstanceMirror m,
                            Symbol memberName,
                            List positionalArguments,
                            [Map<Symbol,dynamic> namedArguments]) =>
    implementation
    .instanceInvokeAdjust(m, memberName, positionalArguments, namedArguments);

/// TODO(eernst): describe
Object classInvokeAdjust(ClassMirror m,
                         Symbol memberName,
                         List positionalArguments,
                         [Map<Symbol,dynamic> namedArguments]) =>
    implementation
    .classInvokeAdjust(m, memberName, positionalArguments, namedArguments);
