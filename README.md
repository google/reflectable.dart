# Reflectable

*A listing of known limitations is given at the end of this page.*


## Introduction

This package provides support for reflection which may be tailored to cover
certain reflective features and omit others, thus reducing the resource
requirements at run time.

The core idea is that the desired level of support for reflection is
specified explicitly and statically, and any usage of reflection at run
time must stay within the boundaries thus specified; otherwise a
`NoSuchCapabilityError` is thrown. In return for statically confining the
required reflection support, programs can be smaller. Other than that,
using this package and using `dart:mirrors` is very similar.

The core concept in the reflection support specification is that of a
reflectable **capability**. For a more detailed discussion about
capabilities, please consult the [reflectable capability design
document][1]. On this page we just use a couple of simple special cases.

[1]: https://github.com/dart-lang/reflectable/blob/master/doc/TheDesignOfReflectableCapabilities.md

This package uses code generation to provide support for reflection at the
level which is specified using capabilities. The [`build` package][2] is
used to manage the code generation, and a major part of this package is
concerned with generating that code. It is specified which programs to
transform, and certain elements in the program itself are used to decide
how to transform it. As a result, the transformed program will contain
generated code providing the requested level of support for reflection.

[2]: https://pub.dartlang.org/packages/build

The use of dynamic reflection is supported if and only if the usage is
covered by the set of *capabilities* specified.

In general, reflection is provided via a subclass of the class
`Reflectable` (we use the term *reflector* to designate an instance of such
a subclass).

```dart
class Reflector extends Reflectable {
  const Reflector() : super(capability1, capability2, ...);
}
```

Reflection is disabled by default, and it is enabled by specifying
reflectable capabilities. With `Reflector` we have specified that
`capability1`, `capability2`, and so on must be supported. The main case
for using this is annotating a given class `A` with a reflector. This
implies that the specified level of reflection support for that reflector
should be provided for the class `A` and its instances.

```dart
@Reflector()
class A {
  ...
}
```

Only classes covered by a reflector `R` and their instances can be accessed
reflectively using `R`, and that access is constrained by the capabilities
passed as the superinitializer in the class of `R`. The basic case is when
`R` is used as an annotation of a given class (as is the case with `A`
above), but a class `C` can also be covered by a reflector `R` because a
supertype `A` of `C` is annotated by a reflector which specifies that
subtypes of `A` are covered. There are several other indirect mechanisms in
addition to subtype based coverage, as described in the [capability design
document][1].

As a result, the available universe of reflection related operations is so
well-known at compile time that it is possible to specialize the support
for reflection to a purely static form that satisfies the requirements of
the given annotations and capabilities.


## Usage

Here is a simple usage example. Assume that we have the following code in
the file `web/main.dart`:

```dart
import 'package:reflectable/reflectable.dart';
import 'main.reflectable.dart'; // Import generated code.

// Annotate with this class to enable reflection.
class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability); // Request the capability to invoke methods.
}

const reflector = const Reflector();

@reflector // This annotation enables reflection on A.
class A {
  final int a;
  A(this.a);
  greater(int x) => x > a;
  lessEqual(int x) => x <= a;
}

main() {
  initializeReflectable(); // Set up reflection support.
  A x = new A(10);
  // Reflect upon [x] using the const instance of the reflector:
  InstanceMirror instanceMirror = reflector.reflect(x);
  int weekday = new DateTime.now().weekday;
  // On Fridays we test if 3 is greater than 10, on other days if it is less
  // than or equal.
  String methodName = weekday == DateTime.FRIDAY ? "greater" : "lessEqual";
  // Reflectable invocation:
  print(instanceMirror.invoke(methodName, [3]));
}
```

It is necessary to **import the generated code**, which is stored in a
library whose file name is obtained by taking the file name of the main
library of the program and adding `.reflectable`. In the example, this
amounts to `import 'main.reflectable.dart'`.

Note that it is **not recommended to publish generated code**, i.e.,
published packages on `pub.dartlang.org` should not include files whose
name is of the form `*.reflectable.dart`. The reason for this is that the
generated code may change because some direct or indirect dependency
changes (say, your package indirectly imports package `path` and then
`path` changes), and this could make some generated code invalid.

It is also necessary to **initialize the reflection support** by calling
`initializeReflectable()`, as shown at the beginning of `main` in the
example.

You also need to add the following dependency to your 'pubspec.yaml':
```yaml
dependencies:
  reflectable: any
```

You may also wish to specify constraints on the version, depending on the
approach to version management that your software otherwise employs.

The root of your library may need to contain a file `build.yaml` which
will specify how to run the code generation step. For an example of
how to write this file, please consult [test_reflectable/build.yaml][8]
and the general documentation about [package build][9].

[8]: https://github.com/dart-lang/test_reflectable/blob/master/build.yaml
[9]: https://github.com/dart-lang/build/tree/master/docs

In order to generate code you will need to run the following command from the
root directory of your package:

```console
> pub run build_runner build DIR
```

where `DIR` should be replaced by a relative path that specifies the directory
where the entry point(s) are located, that is, the main file(s) for the
program(s) that you wish to generate code for. In the example where we have an
entry point at `web/myProgram.dart` the command would be as follows:

```console
> pub run build_runner build web
```

You may appreciate the following shortcut command which will work when you wish
to generate code for entry points in the `test` subdirectory and also run the
tests (given that the tests are written using package test):

```console
> pub run build_runner test
```

This approach (using `pub run build_runner ...`) includes support for
incremental code generation, that is, it offers shorter execution times for the
code generation step because strives to only generate code that relies on
something that changed. This is the recommended approach.

However, if you have a complex setup then you may wish to study the packages
`build`, `build_runner`, etc. in order to learn more about how to control
the build process in more detail.

To give a hint about a more low-level approach, you may choose to write a tiny
Dart program which imports the actual builder, and run the build process from
there, rather than using `pub run build_runner ...`. This will give you more
control, but also more ways to shoot yourself in the foot.

Here's an example which shows how to get started. The code of such a
builder program can be as concise as the following:

```dart
import 'package:reflectable/reflectable_builder.dart' as builder;

main(List<String> arguments) async {
  await builder.reflectableBuild(arguments);
}
```

You may now run the code generation step with the root of your package as
the current directory:

```console
> dart tool/builder.dart web/myProgram.dart
```

where `web/myProgram.dart` should be replaced by a path that specifies the
entry point(s) for which you wish to generate code. For a set of test files
in `test`, this would typically be `tool/builder.dart test/*_test.dart`.

It should be noted that you need to generate code for the _same_ set of
entry points every time you run `builder.dart`. This is because the build
framework stores data about the code generation in a single database in the
directory `.dart_tool`, so you will get complaints about inconsistencies if
you switch from generating code for `web/myProgram.dart` to generating code
for `web/myOtherProgram.dart`. If and when you need to generate code for
another set of programs, delete all files named `*.reflectable.dart`, and
delete the whole directory `.dart_tool`.

Again, the approach where you are using your own `builder.dart` to generate
the code is more flexible, but the recommended standard approach is to use
`pub run build_runner ...`.

Note that it is necessary to perform the code generation step if you
use reflectable directly *or indirectly* by depending on a package that
uses reflectable. Even in the indirect case there may (typically will!) be
a need to generate code based on files in your package.

Conversely, if you are writing a package which uses reflectable and is
expected to be used by clients, please make it explicit that such clients
must run this step in order to obtain the generated code for each root
library.

The generated file contains the data needed for reflection, and a
declaration of the top-level function `initializeReflectable`,
which will initialize the reflection framework and which must be called
before any reflective features are used.

For a more advanced example, you could look at [serialize_test.dart][4] and
its [library][5], where the base of a serialization framework is
implemented; or you could look at [meta_reflectors_test.dart][6] and the
libraries it imports, which illustrates how reflectable can be used to
dynamically make a choice among several kinds of reflection, and how to
eliminate several kinds of static dependencies among libraries.

[4]: https://github.com/dart-lang/test_reflectable/tree/master/test/serialize_test.dart
[5]: https://github.com/dart-lang/test_reflectable/tree/master/lib/serialize.dart
[6]: https://github.com/dart-lang/test_reflectable/tree/master/test/meta_reflectors_test.dart


## Known limitations

Several parts of the library have not yet been implemented. In particular,
the following parts are still incomplete:

- Reflection on functions/closures. We do not have the required primitives
  to support this feature, so it is expected to remain unsupported for a while.
  There is support for one case: When a function type is given a name with
  `typedef` it is possible to use that name as a type annotation, say, on a
  method parameter or as a return type, and then `reflectedTypeCapability`
  will make it possible to get a corresponding `reflectedType` and
  `dynamicReflectedType`. For non-generic function types this will also
  work with anonymous (inline) function types like `void Function(int)`.

- Private declarations. There is currently almost no support for reflection
  on private declarations, as this would require special support from the
  runtime for accessing private names from other libraries. As an example
  of a case where there is some support, library mirrors can deliver class
  mirrors for private classes, and `instanceMembers` includes public
  members inherited from private superclasses. But in the vast majority of
  situations, private declarations are not supported.

- uri's of libraries. The transformer framework does not give us access to
  good uri's of libraries, so these are currently only partially supported:
  A unique uri containing the name given in the `library` directive (if
  any) is generated for each library; this means that equality tests will
  work, and the `toString()` of a uri will be somewhat human readable. But
  this kind of uri does not give any information about the location of a
  corresponding file on disk.

- Type arguments of generic types are only supported in some statically
  resolved cases, because we do not have the primitives required for a
  general implementation. E.g., when it is known statically that a given
  list of actual type arguments is empty then the empty list is
  returned. Moreover, if a type annotation contains only types which are
  fully resolved statically, it is possible to get these type arguments, as
  mirrors or as instances of `Type` using various reflected type
  features. An example is shown below.

- The mirror method `libraryDependencies` has not yet been implemented.

Here is an example illustrating the partial support for type arguments:

```dart
class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability, typingCapability, reflectedTypeCapability);
}

const reflector = Reflector();

@reflector
class A<X> {
  A<B> ab;
  A<X> ax;
}

@reflector
class B {}

main() {
  initializeReflectable();
  ClassMirror aMirror = reflector.reflectType(A);
  final declarations = aMirror.declarations;
  VariableMirror abMirror = declarations['ab'];
  VariableMirror axMirror = declarations['ax'];
  print(abMirror.type.typeArguments[0].reflectedType); // Prints 'B'.
  print(abMirror.type.reflectedTypeArguments[0] == B); // Prints 'true'.
  try {
    print(axMirror.type.typeArguments[0]); // Throws 'UnimplementedError'.
    print("Not reached");
  } on UnimplementedError catch (_) {
    print("As expected: Could not get type mirror for type argument.");
  }
  try {
    axMirror.type.reflectedTypeArguments[0]; // Throws 'UnimplementedError'.
    print("Not reached");
  } on UnimplementedError catch (_) {
    print("As expected: Could not get reflected type argument.");
  }
}

// Output:
//   B
//   true
//   As expected: Could not get type mirror for type argument.
//   As expected: Could not get reflected type argument.
```

As the example above illustrates, we can invoke `reflectedTypeArguments` on
the mirror of the type annotation of `ai` and get `<Type>[int]`, because
that type argument list is statically resolved, but we cannot do it with
`ax` because `X` will have different values at different occasions at run
time (that is, it is not fully resolved statically).

Similarly, it is not supported to obtain the actual type arguments for an
existing instance; e.g., if we have an expression of type `Iterable` then
we may evaluate it and get an instance `x` of `List<int>`. We can test
`x is List<num>` and get true, and we can get false for `x is
List<double>`, but we cannot directly extract the type argument (`int`)
using reflection. That is because it can only be done with support for
some primitives (that is, built-in operations with special powers) that
do not exist today.


## Feature requests and bug reports

Please file feature requests and bugs using the
[github issue tracker for this repository][7].

[7]: https://github.com/dart-lang/reflectable/issues
