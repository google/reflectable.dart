// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File being transformed by the reflectable transformer.
/// Uses public features of an instance of a private class in a different
/// library. This illustrates that there is (very limited) support for access
/// to private features.
library test_reflectable.test.private_class_test;

@GlobalQuantifyCapability("PublicClass", privacyReflectable)
import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';
import 'private_class_library.dart';
import 'private_class_test.reflectable.dart';

class PrivacyReflectable extends Reflectable {
  const PrivacyReflectable()
      : super(
            subtypeQuantifyCapability,
            reflectedTypeCapability,
            instanceInvokeCapability,
            declarationsCapability,
            libraryCapability);
}

const privacyReflectable = const PrivacyReflectable();

final Set<String> libraryClassNames = <String>[
  "PublicClass",
  "_PrivateClass1",
  "_PrivateClass2",
  "PublicSubclass1",
  "PublicSubclass2"
].toSet();

void testPrivacyViolation(PublicClass object, String description,
    {bool doReflect: true}) {
  test("Privacy, $description", () {
    bool canReflect = privacyReflectable.canReflect(object);
    expect(canReflect, doReflect);
    if (canReflect) {
      // Check that we can reflect upon [object], and that its class
      // is among the expected ones.
      InstanceMirror instanceMirror = privacyReflectable.reflect(object);
      ClassMirror classMirror = instanceMirror.type;
      expect(libraryClassNames.contains(classMirror.simpleName), true);

      // Browse [object] and call a method declared in a private class.
      classMirror.declarations.values.forEach((DeclarationMirror declaration) {
        expect(declaration is MethodMirror, true);
        MethodMirror method =
            declaration; // Declaration needed, no type propagation.
        expect(method.reflectedReturnType, int);
        expect(method.parameters.length, 0);
        expect(
            <String>[
              "publicMethod",
              "supposedlyPrivate",
              "supposedlyPrivateToo"
            ].contains(method.simpleName),
            true);
        if (method.simpleName != "publicMethod") {
          expect(instanceMirror.invoke(declaration.simpleName, []),
              -object.publicMethod());
        }
      });
    }
  });
}

main() {
  initializeReflectable();

  test("Privacy, libraries", () {
    // Check that we can browse libraries.
    Map<Uri, LibraryMirror> libraries = privacyReflectable.libraries;
    Uri libraryUri = libraries.keys.firstWhere(
        (Uri uri) => uri.toString().contains("private_class_library"));
    LibraryMirror library = libraries[libraryUri];
    expect(library.declarations.keys, libraryClassNames);
  });

  testPrivacyViolation(func1(), "private subclass", doReflect: false);
  testPrivacyViolation(func2(), "private subtype", doReflect: false);
  testPrivacyViolation(func3(), "public subclass of private subclass");
  testPrivacyViolation(func4(), "public subclass of private subtype");
}
