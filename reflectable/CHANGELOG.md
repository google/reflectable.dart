# Changelog

## 0.5.2

* **Potentially breaking bug fix**: In transformed code, `superinterfaces`
  used to be callable even without a `typeRelationsCapability`. That
  capability is now required (as it should be according to the documentation)
  and this will break programs that rely on the old, incorrect behavior.
* Adds support for recognizing a `const` field as a reflector (e.g., class `C`
  can be covered by having `@SomeClass.aConstField` as metadata on `C`).
* Fixes bug: misleading error messages from `isSubtypeOf` and `isAssignableTo`
  corrected.
* Fixes bug: now named constructors can be used in metadata (e.g.,
  `@F.foo(42) var x;` can be used to get reflective support for `x`). 
* Fixes bug: certain external function type mirrors seem to be unequal to
  themselves, which caused an infinite loop; now that case is handled.
* Adds a stand-alone version of the transformer; for more information please
  consult the main comment on commit 8f90cb92341431097ad97b0d7aa442362e90e5b3.
* Fixes bug: some private names could occur in generated code; this situation
  is now detected more consistently and transformation fails.
* The documentation now clearly states that it is not supported to use
  reflectable in untransformed mode with `dart2js` generated code.
* Adds a small corner of support for function types: A `typedef` can be used
  to give a function type a name, and such a type can be used as a type
  annotation (say, for a method parameter) for which it is possible to obtain
  a mirror, and that type `hasReflectedType`.
* Fixes bug: in the case where a reflector does not match anything at all there
  used to be a null error; now that is handled, and a warning is emitted.
* Switches from using an `AggregateTransform` to using a plain `Transform` for
  all transformations; this reduces the number of redundant transformations
  performed in the context of `pub serve`.
* Adds extra tests such that line coverage in the transformer is again complete.
* Fixes bug: `hasReflectedType` used to incorrectly return `true` in some cases
  where a type variable was used in a nested generic type instantiation.
* Fixes bugs associated with anonymous mixin applications involving type
  arguments.
* Fixes bug: several error messages claimed 'no such method' where they should
  claim 'no such constructor' etc.
* Fixes bug: it is now possible to invoke a constructor in an abstract class
  reflectively, as long as it is a `factory`.
* `List` receives some constructor arguments with default values which are
  different on different platforms, and the analyzer reports that there are
  no default values; this release introduces a special case for that.
* Fixes bug: some constructors of native classes were omitted, are now
  available like other members.

## 0.5.1

* Changes the version constraint on analyzer to 0.27.1, to avoid an issue with
  version 0.27.1+1 which breaks all reflectable transformations. Note that this
  is a tight constraint (just one version allowed), but currently all other
  versions above 0.27.0 will fail so there is no point in trying them.
* Bug fix: The transformer now treats the entry points as a set such that
  duplicates are eliminated; duplicates of entry points are not useful, and
  they can trigger an infinite loop if present.

## 0.5.0

* **Breaking:** The methods `hasBestEffortReflectedType` and
  `bestEffortReflectedType` are now deprecated. They will be removed in the
  next published version.
* **Breaking:** Implements a new semantics for no-such-method situations: When
  a reflectable invocation (`invoke`, `invokeGetter`, `invokeSetter`,
  `newInstance`, `delegate`) fails due to an unknown selector or an argument
  list with the wrong shape, a `ReflectableNoSuchMethodError` is thrown. (In
  particular, `noSuchMethod` is *not* invoked, and no `NoSuchMethodError` is
  thrown). For more details, please consult the [capability design document][1]
  near occurrences of 'no-such-method'.
* Fixes issue 51, which is concerned with coverage of getters/setters for
  variables inherited from non-covered classes.
* **Breaking:** Changes coverage such that it requires a
  `SuperclassQuantifyCapability` in order to include support for an 
  anonymous mixin application (like `A with M` in `class B extends A with M..`).
  Such mixin applications used to be included even without the
  `SuperclassQuantifyCapability`, but that was an anomaly.
* **Breaking:** Changes the semantics of `superclass` to strictly follow the
  documentation: It is now required to have a `TypeRelationsCapability` in 
  order to perform `superclass`, even in the cases where this yields a mixin
  application.
* **Breaking:** Changes the semantics of `instanceMembers` and `staticMembers`
  to strictly follow the documentation: It is now required to have a
  `DeclarationsCapability` in order to perform these methods.
* **Breaking**: Eliminates the non-trivial upper bound on the version of the
  `analyzer` package (because the constant evaluation issue has been resolved).
  The analyzer dependency is now '^0.27.0'. Switches to `code_transformers`
  version '^0.3.0'.
* Updates the [capability design document][1] to document the new treatment of
  no-such-method situations.
* Implements `isSubtypeOf` and `isAssignableTo` for type mirrors.
* Fixes issue 48, which is about wrong code generation involving mixin 
  applications.
* Implements `delegate` on instance mirrors, and adds a `delegateCapability`
  to enable it. The reason why this requires a separate capability is that
  the cost of storing maps between strings and symbols needed by `delegate`
  is non-trivial.
* Changes code generation to avoid generating code for some unused mirrors.
* Fixes bug which prevented recognition of some forms of metadata during
  metadata based capability checking.

[1]: https://github.com/dart-lang/reflectable/blob/master/reflectable/doc/TheDesignOfReflectableCapabilities.md

## 0.4.0

* Changes the representation of reflected types such that duplication of
  `Type` expressions is avoided (by using indices into a shared list).
* Adds methods `dynamicReflectedType` and `hasDynamicReflectedType` to several
  mirror classes, yielding the erased version of the reflected type (for
  `List<int>` it would return `List<dynamic>`, i.e., `List`). This method is
  capable of returning a result in some cases where `reflectedType` fails.
* Corrects the behavior of methods `reflectedType` and `hasReflectedType`, such
  that `reflectedType` returns an instantiated generic class when that is
  appropriate, and `hasReflectedType` returns false in some cases where it
  used to return true, because the correct instantiated generic class cannot
  be obtained.
* Adds method `bestEffortReflectedType` which will use `reflectedType` and
  `dynamicReflectedType` to obtain a reflected type if at all possible (though
  with a less precise specification, because it may be one or the other). Adds
  method `hasBestEffortReflectedType` to go with it. This pair of methods
  resembles the 0.3.3 and earlier semantics of `reflectedType`.

The version number is stepped up to 0.4.0 because `reflectedType` behaves
differently now than it did in 0.3.3 and earlier, which turned out to break
some programs. In some cases the best reaction may be to replace invocations
of `reflectedType` and `hasReflectedType` by the corresponding "best effort"
methods, but it may also be better to use both the `reflectedType` and the
`dynamicReflectedType` method pairs, taking the precise semantics into
account when using the returned result.

Note that version 0.3.4 also deals with `reflectedType` in a stricter way
than 0.3.3 and earlier versions, but at that point the changes were
considered to be bug fixes or implementations of missing features.

## 0.3.4

* **NB** Adds a non-trivial upper version constraint on analyzer in order to
  require version 0.26.1+14 or older. This is necessary because newer versions
  of analyzer have changed in ways that are incompatible with reflectable in
  several ways. We expect to be able to allow using the newest version of
  analyzer again soon.
* Implements support for moving additional kinds of expressions (for
  argument default values and metadata), esp. when they use a library
  prefix (such as `@myLib.myMetadata`).
* Adds test cases for previously untested capabilities
  (`NewInstanceMetaCapability` and `TypingCapability`).
* Fixes bug where pre-transform check would attempt to use `null` but should
  instead throw `NoSuchCapabilityError`.
* Adds missing checks in pre-transform code (e.g., checking that a
  `LibraryCapability` is available when performing a top-level invocation).
* Corrects inconsistency among the type hierarchies for pre/post-transform
  capabilities (which caused the post-transform code to act incorrectly).
* Corrects treatment of `TypingCapability`, adjusted it to include
  `LibraryCapability`.
* Introduces `UnreachableError` and adjusted error handling to throw this in
  all cases where a location should never be reached.
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

* **Breaking**: Add support for type annotation quantification. This is a 
  breaking change: we used to do that implicitly, but that is expensive, and
  now it is only available on request.
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

* **Breaking:** Enforces the use of a `TypeCapability` as specified in the
  design document, and makes it a supertype of several other capabilities such
  that it is automatically included with, e.g., `declarationsCapability`.
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
