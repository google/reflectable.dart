# Changelog

## 0.3.4

* Several 'README.md' files updated to match the current status.
* A couple of smaller unimplemented methods implemented.
* Eliminates many of the 'Missing entry point' messages: If it is specified
  that an entry point 'web/foo.dart' must be transformed, but no such asset
  is provided to the transformer, then the warning is only emitted if the
  file does not exist (with `pub build test`, 'web/foo.dart' is not provided
  to the transformer, but that is not a problem).
* Corrects the bug that `typeRelationsCapability` was sometimes not required
  with certain operations (including `superclass`), even though the
  documentation states that it is required. Similarly, a `TypeCapability` is
  now required in a few extra cases where it should be required.
* Correct the cyclic-dependency bug which previously made
  'expanding_generics_test.dart' fail.
* Adds support for enum classes.
* Implement support for all the trivial parts of genericity: empty lists of
  type arguments are now delivered rather than throwing `UnimplementedError`,
  and static information like type variables (that is, formals) is supported.
* Implement several missing class members, including `isEnum`, `isPrivate`,
  `isOriginalDeclaration`, `originalDeclaration`.
* Correct several bugs in the implementation of `LibraryMirror`.
* Correct several bugs with `owner`.
* Implement several features for top-level entities, especially variables.
* Correct several incorrect type annotations (e.g., `List` required, but
  only `Iterable` justified).
* Implement simple code coverage support.

## 0.3.3

* Update many DartDoc comments in 'capability.dart'.
* Update the document _The Design of Reflectable Capabilities_ to match the
  current selection of quantifiers and their semantics.
* Add very limited support for private classes: They are preserved such that
  iteration over all superclasses will work even if some of them are private,
  and private class mirrors are included in `declarations` of library mirrors.
  However, it is not possible to `reflect` on an instance of a private class,
  to create new instances with `newInstance`, nor to call its static methods.
* Fix bug where some private names were used in generated code (which makes
  subsequent compilation fail).
* Add option to format the generated code (off by default).
* Add `correspondingSetterQuantifyCapability`, which will add the corresponding
  setter for each already included explicitly declared getter.
* Change generated code: Eliminate many invocations of
  `new UnmodifiableListView..`, replace many plain list literals by `const`
  list literals, for better startup time and more redundancy elimination.
* Fix bug where an `InvokingMetaCapability` was treated as a
  `NewInstanceMetaCapability`.
* Fix bugs in the publication support script.

## 0.3.2

* Introduce `reflectedTypeCapability` which enables methods `reflectedType` on
  variable and parameter mirrors, and `reflectedReturnType` on method mirrors.
  This enables limited access to type annotations while avoiding the generation
  of many class mirrors.
* Introduce `Reflectable.getInstance` which delivers the canonical instance of
  any given reflector class which is being used in the current program. An
  example shows how this enables "meta-reflection".
* Fixed bugs in methods `isAbstract`, `isSynthetic`; fixed bug in selection of
  supported members of library mirrors; and implemented methods `libraries`
  and `declarations` for library mirrors; and fixed several other library
  related bugs.

## 0.3.1

* Fix bug where metadata was searched the same way for invocation and for
  declarations with `InstanceInvokeMetaCapability` (invocation must traverse
  superclasses).
* Fix bug where some libraries were imported into generated code, even though
  they cannot be imported (private to core).
* Fix bugs in publication support script.

## 0.3.0

* Add support for type annotation quantification (this is a breaking change: we
  used to do that implicitly, but that is expensive and now it is only available
  on request).
* Change the way the set of supported classes are computed.
* Fix crash when transforming certain dart:html classes.
* Fix memory leak from the transformer.

## 0.2.1

* Recognize private identifier constants as metadata in certain cases.
* Bump required SDK version in `pubspec.yaml`.
* Correct generation of imports of the original entry point.
* Fix issues with the computation of static members.
* Allows the metadata capabilities to recognize any subtype of the given type.

## 0.2.0

* Enforces the use of a `TypeCapability` as specified in the design document,
  and makes it a supertype of several other capabilities such that it is
  automatically included with, e.g., `declarationsCapability`.
* Fixed homepage link in pubspec
* Fix several bug with mixins in the transformer.
* Add `excludeUpperBound` flag to `SuperClassQuantifyCapability`.
* Use a static initializer in the generated code which helps avoiding a stack
  overflow.

## 0.1.5

* Support for return types of getters and setters.
* Support for superTypeQuantifyCapability.
* Fix bug in the mirror-based implementation's collection of classes that could
  lead to infinite loops.
* Fix bug related to generating code for `operator~` in the transformer.
* Avoid crashing the transformer when an entry-point has no member named `main`

## 0.1.4

* Support for subtype quantification in transformed code.
* Code generation bugs fixed; metadata/library related bugs fixed.
* Faster version of test procedure.

## 0.1.3

* Non-transformed code supports `subTypeQuantifyCapability`
* Transformer implements `.superinterfaces`
* Transformer implements `.mixin`
* Transformer implements reflection on libraries.
* Better support for default values in transformed code.

## 0.1.2

* Our tests started failing because of a version conflict introduced by an
  update to `code_transformers`. Changed `pubspec.yaml` to avoid the conflict.
* Made changes to avoid deprecated features in the new version of `analyzer`.
* Implemented support for implicit accessors (setters, getters).
* Implemented support for `staticMembers` on `ClassMirror`.

## 0.1.1

* Transformer implements `.type` of fields and parameters.
* Transformer has support for `main` function that is not in the entry-point
  file.
* Transformer supports async `main` returning a `Future`.
* Other bug fixes...

## 0.1.0

* First published release.

## 0.0.1

* Initial project creation
