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

[1]: https://github.com/dart-lang/reflectable/blob/master/reflectable/doc/TheDesignOfReflectableCapabilities.md

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

In order to generate code, you will need to run
`dart $REFLECTABLE_PATH/bin/reflectable_builder.dart <targets>`
where `$REFLECTABLE_PATH` is the path to the root of the package
reflectable, and `<targets>` specifies the root libraries for which you
wish to generate code. You should be able to find a line on the form
`reflectable:$REFLECTABLE_PATH/lib`
in the file `.packages` in the root directory of your package, after
running `pub get`.

Now run the code generation step:
```shell
> cd ... # go to the root directory of your package
> dart $REFLECTABLE_PATH/bin/reflectable_builder.dart web/myProgram.dart
```
where `web/myProgram.dart` should be replaced by the root library of the
program for which you wish to generate code. You can generate code for
several programs in one step; for instance, to generate code for a set of
test files in `test`, this would typically be
`pub run reflectable:reflectable_builder test/*_test.dart`.

Note that you should generate code for the _same_ set of root libraries
every time you run `reflectable_builder`. This is because the build
framework stores data about the code generation in a single database in the
directory `.dart_tool`, so you will get complaints about inconsistencies if
you switch from generating code for `web/myProgram.dart` to generating code
for `web/myOtherProgram.dart`.

If and when you need to generate code for another set of programs, delete
all files named `*.reflectable.dart`, and the directory `.dart_tool`.

Also note that it is necessary to perform this code generation step if you
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

[3]: https://github.com/dart-lang/reflectable/blob/master/test_reflectable/tool/reflectable_transformer
[4]: https://github.com/dart-lang/reflectable/blob/master/test_reflectable/test/serialize_test.dart
[5]: https://github.com/dart-lang/reflectable/blob/master/test_reflectable/lib/serialize.dart
[6]: https://github.com/dart-lang/reflectable/blob/master/test_reflectable/test/meta_reflectors_test.dart


## Known limitations

Several parts of the library have not yet been implemented. In particular, the
following parts are still incomplete:

- Reflection on functions/closures. We do not have the required primitives
  to support this feature, so it is expected to remain unsupported for a while.
  There is support for one case: When a function type is given a name with
  `typedef` it is possible to use that name as a type annotation, say, on a
  method parameter or as a return type, and then `reflectedTypeCapability`
  will make it possible to get a corresponding `reflectedType` and
  `dynamicReflectedType`.

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

- Type arguments of generic types are only supported in some simple cases,
  because we do not have the primitives required for a general
  implementation. E.g., when it is known that a given list of actual type
  arguments is empty then the empty list is returned. However, when a
  parameterized type has a non-trivial list of actual type arguments then
  returning the actual type arguments would require runtime support that does
  not currently exist.

- The mirror method `libraryDependencies` has not yet been implemented.


## Feature requests and bug reports

Please file feature requests and bugs using the
[github issue tracker for this repository][7].

[7]: https://github.com/dart-lang/reflectable/issues
