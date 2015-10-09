// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File being transformed by the reflectable transformer.
/// Part of the entry point 'reflectors_test.dart'.
///
/// Independence: The `ScopeMetaReflector` and `AllReflectorsMetaReflector`
/// classes are independent of the particular entry point 'reflectors_test.dart'
/// and its transitive closure, it could be in a third-party package only
/// depending on reflectable.
library test_reflectable.test.meta_reflectors_scoping;

@GlobalQuantifyCapability(r"^reflectable.reflectable.Reflectable$",
    const AllReflectorsMetaReflector())
import 'package:reflectable/reflectable.dart';

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
    Set<Reflectable> result = new Set<Reflectable>();
    for (LibraryMirror library in libraries.values) {
      for (DeclarationMirror declaration in library.declarations.values) {
        result.addAll(library.invoke(declaration.simpleName, [scope]));
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
    Set<Reflectable> result = new Set<Reflectable>();
    annotatedClasses.forEach((ClassMirror classMirror) {
      if (classMirror.isAbstract) return;
      Reflectable reflector =
          Reflectable.getInstance(classMirror.reflectedType);
      if (reflector != null) result.add(reflector);
    });
    return result;
  }
}
