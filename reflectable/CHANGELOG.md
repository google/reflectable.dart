# Changelog

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
