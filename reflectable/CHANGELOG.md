# Changelog

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
