## 5.0.0

- **Breaking change**: Split the code generator off of the package
  `reflectable`. This code generator must henceforth be obtained from
  the package `reflectable_builder`.  The point is that this can be a
  `dev_dependency`. This also implies that `build.yaml` must specify
  the reflectable code generator as `reflectable_builder:`
  rather than just `reflectable:`.

## 4.0.15

- Use language version 3.9. In particular, use the 3.9 style of
  formatting.

## 4.0.14

- Use language version 3.7.
- Migrate reflectable to use analyzer version ^7.0.0 (which removes
  the dependency on `_macros`, which doesn't exist any more).
- This includes a small part of the migration work needed in order
  to use the new element model in the analyzer (`Element2`, for now).
- Lots of reformatting (creates a big diff).

## 4.0.13

- Use language version 3.6.
- Use newer versions of `build_runner_core` (^8.0.0) and `dart_style`
  (^3.0.0), to enable the new formatting style.
- Ignore deprecated member use because `build_runner` is not yet
  ready for the new `Element` model.
- Add support for suppression of warnings via environment variables.
  The environment variable has prefix `REFLECTABLE_SUPPRESS_...` and
  then `UPPER_CASE` of the `WarningKind`. For example,
  `export REFLECTABLE_SUPPRESS_BAD_METADATA=yes` will suppress
  the `badMetadata` warning.
- Reformat the implementation to use the new style.
- Introduce support for specifying the language version used by the
  formatter by setting `REFLECTABLE_FORMATTER_LANGUAGE_VERSION` to
  a value of the form `[0-9]+\\.[0-9]+`.
- Added information to the design document in `doc` about the supported
  environment variables.

## 4.0.12

* Revert analyzer dependency to 6.8.0 and lints to 5.0.0 due to macro
  related version resolution conflict. Undo some changes that are
  required for analyzer 6.11.0, but which are errors with 6.8.0.

## 4.0.11

* Fix bug 291 (such that metadata on enum values can be obtained).
* Update dependencies to use analyzer 6.11.0 and lints 5.1.0.
* Change the implementation to use `..._obvious_local_variable_types`
  lints.
* Update the [capability design document][1] slightly.

## 4.0.10

* Reintroduce support for newer versions of the analyzer (6.7.0 and up).

## 4.0.9

* Lower the upper bound for the analyzer to avoid a complaint that we
  should import a library that doesn't exist with the analyzer when using
  the lower bound. Import the older library that does exist.

## 4.0.8

* Downgrade analyzer to 6.5.0, to avoid version conflict involving
  `macros` and `_macros` (that we can't do anything about from here).

## 4.0.7

* Update dependencies to use sdk 3.4.0 and analyzer 6.7.0.

## 4.0.6

* Update dependencies to use analyzer 6.4.0.

## 4.0.5

* Remove legacy tests (they cannot be executed when using a version of Dart
  which will be released soon).
* Use an upper bound of 4.0.0 for the SDK constraint, preparing for said
  release.
* Change the computation of the Uri of a library mirror such that it is taken
  from the `AssetId` of the library, when possible. This should be helpful in
  situations where the Uri is used to find the actual file. This is technically
  a breaking change, but we do not consider it to be a breaking change in
  practice, because the Uri's provided in previous versions were essentially
  meaningless strings. They were just known to be distinct for distinct
  libraries, and that property also holds with this change.

  For documentation about how these URIs are generated, please see
  https://pub.dev/documentation/build/latest/build/AssetId/uri.html and
  https://pub.dev/documentation/build/latest/build/AssetId-class.html .

  For documentation about package URIs, please see
  `https://api.dart.dev/stable/2.19.2/dart-isolate/Isolate/packageConfig.html`
  and, for example, `https://pub.dev/packages/package_config`.

## 4.0.4

* Resolve bug #300. Expressions of the form `f<T>` denoting a generic
  instantiation of a function (that is: the result of passing the type
  argument `T` to the generic function `f`, yielding a non-generic
  function) was not supported; this version supports it.

## 4.0.3

* Change code generation such that null safe programs do not give rise
  to a language version comment in the generated code. Previously, such
  programs would have `// @dart = 2.12` in the generated library, but
  this causes newer features to be unavailable in the generated code.
  As before, programs which are not fully null safe will have a
  generated library that contains `// @dart = 2.9`.

## 4.0.2

* Change handling of 'dart:...' libraries, to handle new behavior by
  `build_resolvers` 2.1.0: 'dart:html' wasn't reported before by
  `resolver.libraries`, but is now included. To preserve existing
  behavior (and avoid generating code that imports 'dart:html'), this
  update removes 'dart:html' from the set of libraries that are
  considered "importable" by generated code.

## 4.0.1

* Update reflectable to use (and require) analyzer 5.2.0. This is a
  substantial update, because several analyzer members in the analyzer
  have been deprecated.

## 4.0.0

* Update reflectable to use (and require) analyzer 5.0.0. This is a
  substantial update, because several analyzer members in the analyzer
  have been deprecated, and some replacements have different return
  types.
* **Breaking change**: The analyzer now reports that the 'mixin' of a
  'mixin application class' (e.g., `class B = A with M1, M2;`) is the class
  itself (i.e., `B`), and the last mixin (`M2`) is obtained as
  `mirror.superclass.mixin`. Previously the same mixin would be obtained with
  `mirror.mixin`. This is actually a more faithful model than the one used
  previously, so the new behavior is also used by reflectable. (In particular,
  if we have `class B2 = A with M1, M2;` then `B == B2` is _not_ true, which
  implies that the mixin application class works like a regular class
  declaration with an empty body, e.g., `class B = A with M1, M2;` works like
  `class B extends A with M1, M2 {}`, where `mirror.superclass.mixin` is
  the natural way to obtain a mirror of `M2`). This is a breaking change,
  but it only affects usages where there is a dependency on the exact
  superclass structure, and it seems likely that this only happens rarely:
  we may well traverse all supertypes or all superclasses, but we are not
  likely to do things like "go to the 5th superclass, find the mixin, and
  check that it has a `foo` method".

## 3.0.10

* Perform a minimal migration to use analyzer 4.6.0.

## 3.0.9

* Add support for checking whether a `TypeMirror` is reflecting on a
  nullable or non-nullable type.
* Update dependencies to use analyzer ^4.2.0, lints ^2.0.0.

## 3.0.8

* Correct bug reported as #267 (`null` was generated in a case where the
  expression had to have type `int`).
* Change code generation such that no invocations of generative constructors
  of enums are generated (such that it works with 'enhanced-enums').

## 3.0.7

* Change `analysis_options.yaml` such that we get the same linting locally
  and on pub.dev. Update many libraries and tests to conform to the currently
  recommended lints.

## 3.0.6

* Update reflectable to require analyzer ^3.2.0; adjust several locations
  in the code where null is handled, but analyzer methods will now return
  a non-null value. Optimize several capability related getters by caching
  the result.

## 3.0.5

* Update reflectable to require analyzer ^3.0.0 (currently using 3.1.0),
  and to replace the package `pedantic` by the package `lints`.

## 3.0.4

* Fix the bug reported as #255.

## 3.0.3

* Update dependencies: analyzer: ^2.0.0
* Fix issue #253.

## 3.0.2

* Migrate the code generator. The reflectable package is hereby fully migrated
  to null safety.
* Update the following dependencies: `build_config` ^1.0.0,
  `build_runner`: ^2.0.1, `build_runner_core`: ^7.0.0.

## 3.0.1

* Use `dart_style` ^2.0.0.

## 3.0.0

* Support null safety in a stable version of reflectable.
* Change minimum SDK constraint to 2.12.0.
* Use `analyzer` ^1.1.0; `build` ^2.0.0; `build_resolvers` ^2.0.0; `glob` ^2.0.0;
  `logging` ^1.0.0; `package_config` ^2.0.0.
* Bug fix: Handle types of the form `T*` in some extra cases.

## 3.0.0-nullsafety.1

* Enable analyzer version 0.41.2.
* Change code generation to use new `Resolver.astNodeFor` method, eliminating
  the `InconsistentAnalysisException` workaround in most cases.
* Prevent unnecessary code generation for inputs named `*.vm_test.*`,
  `*.node_test.*`, or `*.browser_test.*`, to reduce code generation time.

## 3.0.0-nullsafety.0

* Migrate the generated code and its dependencies to null safety.
* Remove `bestEffortReflectedType`, `hasBestEffortReflectedType`,
  deprecated since version 0.5.0.
* Change the return type of `ObjectMirror.delegate` from `dynamic` to
  `Object?`, for consistency with several methods named `invoke...`.

## 2.2.9

* Change `build.yaml` to ensure that 'lib/main.dart' will again be considered
  an entry point for code generation.
* Update dependencies to include analyzer 0.40.5, 0.40.6, 0.41.0, 0.41.1.
* Re-fixing issue #198, cf. `google/built_value.dart` issue #941.

## 2.2.8

* Update dependencies to include analyzer 0.40.4, with 0.40.3 as lower bound
  because of a breaking change.

## 2.2.7

* Update dependencies to support analyzers up to version 0.40.3.

## 2.2.6

* Resolve #198 (InconsistentAnalysisException), based on workaround from
  dart-lang/build#2634. Also widen the analyzer version constraint to
  include all 0.39 versions published at this point.

## 2.2.5

* Update dependencies. In particular, analyzer can now be 0.39.10.
  Handle issue with `sync*` functions, cf. issue #210.

## 2.2.4

* Eliminate dependency on package `package_resolver` (which is deprecated).

## 2.2.3

* Introduce support for the type `void` as a reified type.

## 2.2.2

* Generate code which will not cause `implementation_imports` diagnostics.

## 2.2.1+2

* Update reflectable to work with analyzer 0.39.4.

## 2.2.1+1

* Restricting analyzer version to <= 0.39.3, because 0.39.3 contains a
  breaking change in the parameter list of a constructor.

## 2.2.1

* Fix a bug concerned with the ordering of named parameters in a constructor
  declaration.
* Update reflectable to use package analyzer version `<0.40.0`.
* Ensure that generated code is lint free with package pedantic 1.9.0.
* Make reflectable itself lint free with package pedantic 1.9.0.

## 2.2.0

* Adjust implementation to satisfy 'pedantic' lints. The generated code
  does this as well, except that some `const` modifiers are generated even
  though they could be omitted (an `// ignore_for_file` comment is generated
  such that the linter does not complain about this). Upgrade dependencies
  to allow using analyzer 0.38.5, and current versions of many other packages.

## 2.1.0

* Code generator rewritten in order to work with changes in the analyzer
  APIs, enabling the use of analyzer version 0.37.0 (and newer versions of
  many other packages), which addresses issue #173. See issue #180 about
  missing support for two features: This affects code in platform libraries
  (that is, libraries imported with 'dart:...' except 'dart:ui'). If a
  declaration in a platform library has metadata, a query for this metadata
  using `DeclarationMirror.metadata` will return null. Also, if a constructor
  in a platform library has a parameter with a default value, and that
  parameter is omitted in a reflective invocation, the value passed will be
  `null` rather than the declared value. This is a bug, but it is blocked on
  getting access to AST nodes in platform libraries from the resolver provided
  by build.

## 2.0.12

* Follow-up bug fix related to #170: Corrected `ParameterMirror.defaultValue`
  for initializing formals.

## 2.0.11

* Bug fix #170: Default values for initializing formals are now included
  when generating function literals for `newInstance`.

## 2.0.10+1

* Lint fixes (e.g., `T x;` rather than `T x = null;`).

## 2.0.10

* Updated dependency to allow using source_span 1.5.3.

## 2.0.9

* Updated dependency to allow using analyzer 0.34.

## 2.0.8+1

* Corrected the email address listed in `pubspec.yaml` for Dart Team.

## 2.0.8

* Fix version conflict #153: Updated version constraints on analyzer, build,
  build_runner, and test. Ported reflectable_builder.dart to work with new
  build API.

## 2.0.7

* Bug fix #132: We used to generate terms like `prefix2.di.inject` in order
  to denote a top level declaration named `inject`, but that's an error
  because `di` is an import prefix from client code. We now strip off such
  prefixes (yielding `prefix2.inject`) in the cases reported in issue #132.

## 2.0.6

* Adjusts an implementation class (`MixinApplication`) such that a
  compile-time error occurring with analyzer 0.32.5 is avoided.

## 2.0.5

* Enhancement of the support for reflection on type arguments, covering
  cases where a type annotation is a parameterized type where all type
  arguments are resolved statically (e.g., `List<int> f();`). We (still) do
  not support cases where one or more type arguments are or contain
  type variables from an enclosing function or class (like the type of
  the formal parameter to `List.addAll`: `List<E>`), and with such type
  arguments a dynamic error is raised if an attempt is made to access it.
  Similarly, we (still) do not support extracting the value of the actual
  type arguments for an instance of a generic class (e.g., for a given
  list, we cannot obtain the precise value of the actual type argument;
  we can test things like `myList is List<num>` and `myList is List<String>`
  without reflection at all, but that only reveals an upper bound, not
  the precise value of the type argument, and we cannot get that precise
  value without support for some additional primitives).

* The `build.yaml` file in reflectable was adjusted such that a much larger
  set of files are included for code generation. This means that we will
  err on the side of generating code for too many files rather than too few,
  but this choice seems to be more user-friendly. Developers who get
  irritated about seeing warnings like "This reflector does not match
  anything" (which is a likely outcome for code generation applied to some
  arbitrary library which is not an entry point) can then add a
  `build.yaml` file specifying more precisely which libraries to generate
  code for.

## 2.0.4

* Null error bug fix.

## 2.0.3

A stable version of Dart 2 has been released at this point. This version
of reflectable contains a rather substantial number of changes needed in
order to make it possible to use this package with the current Dart 2
tools, and under the associated version constraints.

* Eliminates the use of package barback (which is now deprecated). This
  change requires many changes in the implementation, but it should not
  give rise to incompatibilities for clients of reflectable.

* Updates many version dependencies: analyzer, build_resolvers, build_config,
  build_runner, and test, in order to enable the use of Dart 2 tools.

* Changes a handful of implementation details such that every downcast is
  concretely justified. Removed `new` from the implementation (but not from
  generated code), because code generation must anyway use Dart 2, but
  generated code may still need to run as Dart 1.

* Improves code generation ERROR, WARNING, and INFO messages such that it
  includes a precise source code location.

* Now includes `lib/main.dart` among possible build targets, because Flutter
  uses that as the standard entry point.

## 2.0.2

* Update the SDK version constraint to 3.0.0 to satisfy Dart 2 requirements.

## 2.0.1

* This version is a tiny update: It solves a version problem by changing some
  package dependencies.

## 2.0.0

This version is updated for Dart 2, to the extent that this is possible
at this point (a stable version of Dart 2 has not yet been released).
Minor updates will be used to track the language updates as needed,
so a dependency on reflectable version `^2.0.0` should work for Dart 2.

* Update version number, prepare package for being published.

## 2.0.0-dev.3.0

* Now supports client packages using commands like
  `pub run build_runner test` to generate code and run tests.
* Added support for generating code to obtain the `Type` value
  of function types (including the new inline function types like
  `String Function(int)`).
* Fixed bugs associated with error handling: In several situations
  where the build process would get stuck indefinitely, it will
  now terminate with the intended error message.
* Added note to README.md that generated code should not be published
  (it should be regenerated, such that it matches the current version of
  all dependencies).
* Added 'dart:ui' to the set of platform libraries that reflectable will
  recognize (and potentially import). This will only work on Flutter,
  but there would not be any references to 'dart:ui' for any non-Flutter
  program, unless it is already broken in other ways.

## 2.0.0-dev.2.0

* Removed bin/reflectable_transformer.dart, which is obsolete.
* Changed `TestTransform` to require its 3rd constructor argument,
  because there is no default way to obtain the path to '.packages'.
* Generated files are now placed in 'test' rather than 'build/test';
  adjusted 'test_transform.dart' to work with that setup, and enable
  `pub run test`.

## 2.0.0-dev.1.0

This version is a pre-release of the version 2.0.0 which makes all the
changes described below. Henceforth, reflectable will be based on code
generation using `build` rather than a pub transformer, because
transformers will not be supported in the future.

* Switched to a new technology stack: Reflectable no longer provides a pub
  transformer, it uses package `build` to generate code as a separate
  step. This is a **breaking change** for *every* program using reflectable
  because it requires a different workflow, it requires the generated code to
  be imported explicitly by the root library (the one that contains the `main`
  function), and it requires invocation of `initializeReflectable()` at the
  beginning of `main`. To see the commands in this new workflow, please
  consult [README.md][readme_md].

[readme_md]: https://github.com/dart-lang/reflectable/blob/master/reflectable/README.md

## 1.0.4

* Updated version constraint on `analyzer` to include versions `^0.30.0`. Note
  that this forces a lower bound of `0.30.0` because of a breaking change in the
  analyzer.

## 1.0.3

* Updated version constraint on `dart_style`.

## 1.0.2

* Bug fix, handling the case where `prefix` is null on a library mirror,
  and the case where `targetLibrary` is null on a library dependency mirror.

## 1.0.1

* Updates `analyzer` and `code_transformers` dependencies.
* As a consequence of these version updates, changes a method signature and
  deletes a method (overriding a previously deprecated, now deleted method).
  These changes should not affect clients of this package.

## 1.0.0

* Updates documentation about capabilities required for each method.
* **Potentially breaking bug fix**: Several mirror methods perform more strict
  checks on capabilities, to make them match the documented requirements. In
  particular, `LibraryMirror.libraryDependencies` requires a
  `libraryCapability`; `ClosureMirror.apply` requires an
  `InstanceInvokeCapability`; `ParameterMirror.hasDefaultValue`,
  `ParameterMirror.defaultValue`, `MethodMirror.parameters`,
  `GetterMirror.parameters`, and `SetterMirror.parameters` require a
  `DeclarationsCapability`; `TypeMirror.isOriginalDeclaration`,
  `TypeMirror.typeArguments`, `ClassMirror.isAssignableTo`,
  `TypeVariableMirror.isAssignableTo` and `TypeVariableMirror.isSubtypeOf`
  require a `TypeRelationsCapability`; and `ClassMirror.dynamicReflectedType`
  and `VariableMirror.reflectedType` require a `ReflectedTypeCapability`.
* Updates tests to work with `--no-packages-dir`.
* Deprecates `NameCapability`, `nameCapability`, `ClassifyCapability`, and
  `classifyCapability`; these capabilities are now always enabled.
* Uses more strict typing in generated code: `List` and `Map` literals will now
  consistently include type arguments. This is rarely detectable in client code,
  but could for instance be detected in some situations with complex metadata.
* Uses more strict typing in the implementation, in order to pass strong mode
  checks.

## 0.5.4

* **Potentially breaking bug fix**: Several additional mirror methods
  documented to require a `typeRelationsCapability` will now actually require
  it. Concretely, this affects the methods `typeVariables`, `typeArguments`,
  `superclass`, `superinterfaces`, `mixin`, `isSubclassOf`, `isAssignableTo`,
  `isSubtypeOf`, `originalDeclaration`. Programs relying on the previous
  (incorrect) behavior may need to have the relevant reflectors extended with
  a `typeRelationsCapability`. This change also enables throwing an error
  which blames the missing capability rather than incorrectly blaming lack of
  coverage for a specific class. This fixes issue 77.
* Adds constant resolution requests for metadata such that some spurious 'This
  reflector does not match anything' events are avoided; fixes issue 82.
* Corrects treatment of metadata with enum values, fixing issue 80.
* Adds two missing package dependencies, fixing issue 81.

## 0.5.3

* Eliminates the binding to `analyzer` 0.27.1, using ^0.27.2 instead; also uses
  `code_transformers` ^0.4.1.
* Introduces support for entry point globbing; for more information please
  consult commit
  [8936f98](https://github.com/dart-lang/reflectable/commit/8936f98be71cd4325928b8b249b906f83aa54034).

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
  consult the main comment on commit
  [8f90cb9](https://github.com/dart-lang/reflectable/commit/8f90cb92341431097ad97b0d7aa442362e90e5b3).
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
