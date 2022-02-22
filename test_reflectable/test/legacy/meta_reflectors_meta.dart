// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.
// @dart = 2.9

/// File used to test reflectable code generation.
/// Part of the entry point 'meta_reflectors_test.dart'.
///
/// Independence: The `ScopeMetaReflector` and `AllReflectorsMetaReflector`
/// classes are independent of the particular entry point 'reflectors_test.dart'
/// and its transitive closure, it could be in a third-party package only
/// depending on reflectable.
library test_reflectable.test.meta_reflectors_meta;

@GlobalQuantifyCapability(
    r'^reflectable.reflectable.Reflectable$', AllReflectorsMetaReflector())
import 'package:reflectable/reflectable.dart';

// ignore_for_file: omit_local_variable_types

/// Used to provide access to reflectors associated with a given scope,
/// which is a [String]. The connection is created by top level functions
/// in the program with the annotation `@MetaReflector()`. Such a function
/// must have type `F` where `typedef Iterable<Reflectable> F(String _)`,
/// and it is assumed to return the set of reflectors which belong to the
/// scope specified by the argument.
class ScopeMetaReflector extends Reflectable {
  const ScopeMetaReflector()
      : super(const TopLevelInvokeMetaCapability(ScopeMetaReflector),
            declarationsCapability, libraryCapability);
  Set<Reflectable> reflectablesOfScope(String scope) {
    var result = <Reflectable>{};
    for (LibraryMirror library in libraries.values) {
      for (DeclarationMirror declaration in library.declarations.values) {
        if (declaration is MethodMirror) {
          result.addAll(library.invoke(declaration.simpleName, [scope]));
        }
      }
    }
    return result;
  }
}

/// Used to get access to all reflectors.
class AllReflectorsMetaReflector extends Reflectable {
  const AllReflectorsMetaReflector()
      : super(subtypeQuantifyCapability, newInstanceCapability);

  Set<Reflectable> get reflectors {
    var result = <Reflectable>{};
    for (var classMirror in annotatedClasses) {
      if (classMirror.isAbstract) continue;
      Reflectable reflector =
          Reflectable.getInstance(classMirror.reflectedType);
      if (reflector != null) result.add(reflector);
    }
    return result;
  }
}
