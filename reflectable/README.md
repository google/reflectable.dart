# Reflectable

*A listing of known limitations is given at the end of this page.*

## Introduction

This package provides support for reflection which may be tailored to cover
certain reflective features and omit others, thus reducing the resource
requirements at runtime.

The core idea is that the desired level of support for reflection is specified
explicitly and statically, and any usage of reflection at runtime must stay
within the boundaries thus specified; otherwise a `NoSuchCapabilityError` is
thrown. In return for statically confining the required reflection support,
programs can be smaller. Other than that, using this package and using
`dart:mirrors` is very similar.

The core concept in the reflection support specification is that of a
reflectable **capability**. For a more detailed discussion about capabilities,
please consult the [reflectable capability design document][1]. On this page we
just use a couple of simple special cases.

[1]: https://github.com/dart-lang/reflectable/blob/master/reflectable/doc/TheDesignOfReflectableCapabilities.md

The resource benefits obtained by using this package are established by
transformation. That is, this package includes a [`pub` transformer][2]. The
transformer receives a specification of which programs to transform (see the
description of `entry_points:` below), and it uses certain elements in the
program itself to decide how to transform it. As a result, the transformed
program will contain generated code providing the requested level of support for
reflection. If a quick turn-around is more important than space economy, it is
also possible to run the code without transformation. In this case, the behavior
of the program is identical, but it is implemented by delegation to
`dart:mirrors`, which means that the execution may be costly in terms of space.

[2]: https://www.dartlang.org/tools/pub/assets-and-transformers.html

In other words, the package can be used in two modes: **transformed** mode and
**untransformed** mode.

For both modes, your code will not depend directly on `dart:mirrors`. In the
untransformed mode there is an indirect dependency because the support for
reflective features is implemented by delegation to mirror objects from
`dart:mirrors`. In the transformed mode there is no dependency on `dart:mirrors`
at all, because the reflectable transformer generates specialized, static code
that supports the required reflective features.

The use of dynamic reflection is supported if and only if the usage is covered
by the set of *capabilities* specified.

In general, reflection is provided via a subclass of the class
`Reflectable` (we use the term *reflector* to designate an instance of such a
subclass).

```dart
class Reflector extends Reflectable {
  const Reflector() : super(capability1, capability2, ...);
}
```

Reflection is disabled by default, and it is enabled by specifying reflectable
capabilities. With `Reflector` we have specified that `capability1`,
`capability2`, and so on must be supported. The main case for using this is
annotating a given class `A` with a reflector. This implies that the specified
level of reflection support for that reflector should be provided for the class
`A` and its instances.

```dart
@Reflector()
class A {
  ...
}
```

Only classes covered by a reflector `R` and their instances can be accessed
reflectively using `R`, and that access is constrained by the capabilities
passed as the superinitializer in the class of `R`. The basic case is when `R`
is used as an annotation of a given class (as is the case with `A` above), but a
class `C` can also be covered by a reflector `R` because a supertype `A` of
`C` is annotated by a reflector which specifies that subtypes of `A` are
covered. There are several other indirect mechanisms in addition to subtype
based coverage, as described in the [capability design document][1].

As a result, the available universe of reflection related operations is so
well-known at compile time that it is possible to specialize the support for
reflection to a purely static form that satisfies the requirements of the given
annotations and capabilities.

## Usage

Here is a simple usage example. Assume that we have the following code in the
file `web/main.dart`:

```dart
import 'package:reflectable/reflectable.dart';

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

You can directly run this code in untransformed mode, for instance using the
Dart VM. To avoid the dependency on `dart:mirrors` and save space, you can
transform the code using the transformer in this package.

In order to do this, add the following to your 'pubspec.yaml':
```yaml
dependencies:
  reflectable: any

transformers:
- reflectable:
    entry_points:
      - web/main.dart # The path to your main file
    formatted: true # Optional.
```

Now run `pub build --mode=debug web` to perform the transformation. This will
rename the file `web/main.dart` and generate a new file `build/web/main.dart`.
That file contains the data needed for  reflection, and a main function that
will initialize the reflection framework before running the original `main`.
When you run this file, it is important that the package-root is set to
`build/web/packages`, because the reflectable package itself is transformed
to a version that uses the generated data, instead of using `dart:mirrors`.

Some elements in this scenario are optional: In the `pub build..` command, you
could omit the final argument when it is equal to `web`, because that is the
default. You could also omit `--mode=debug` if you do not wish to inspect or
use the generated Dart code (typically, that would be because you only need the
final JavaScript output). In 'pubspec.yaml', the `formatted` option can be
omitted, in which case the output from the transformer will skip the formatting
step (saving time and space, but putting most of the generated code into one
very long line). Finally, in 'pubspec.yaml' you can use one more option:
'suppress_warnings'; e.g., you could specify
'suppress_warnings: missing_entry_point' in order to suppress the warnings
given in the situation where an entry point has been specified in
'pubspec.yaml', but no corresponding library (aka 'asset') has been provided
by `pub` to the transformer.

If you want to use the transformer directly rather than having `pub` invoke it,
you can invoke it as a stand-alone tool. This is particularly relevant if you
have several entry points, but at some point you only want to work with one of
them, e.g., because it is being extended or debugged.

The stand-alone version of the transformer will transform exactly the entry
points you specify on the command line, no matter whether each of them is
declared to be an entry point in 'pubspec.yaml'. It works in a similar way as
`pub serve` because it is able to transform subsets of the entry points, but
it differs in that it allows for inspection of the generated code, and it is
completely under the programmer's control.

The stand-alone version of the reflectable transformer is
`bin/reflectable_transformer.dart`. It can be invoked using
`pub global run` (after activating it with
`pub global activate reflectable`):

```
pub global run reflectable:reflectable_transformer \
  <my_package> <my_entry_point>..
```

In that command, `my_package` stands for the name of the package you are
working in, and `my_entry_point` is the entry point to transform. For instance,
the command could look like this in the testing package `test_reflectable`:

```
pub global run reflectable:reflectable_transformer \
  test_reflectable test/export_test.dart
```

The script [`reflectable_transformer`][3] in the `test_reflectable` package
illustrates how you can call it directly if you wish to run it independently
of `pub`.

It should be noted that the stand-alone transformer only works if `pub build..`
has been executed, because the stand-alone only produces transformed files; the
symptoms that arise if `pub build..` has not been executed successfully first
is that some files are missing, including the `packages` directories inside
`build`. When that is in place, stand-alone transformation can be used any
number of times.

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

### Comparison with `dart:mirrors` with `MirrorsUsed` annotations

A lot of the overhead of `dart:mirrors` can be mitigated by using a
suitable `MirrorsUsed` annotation, which has a similar purpose as the
capabilities of reflectable. So why do we have both?

First, on some Dart platforms there is no support for reflection at all, in
which case it is necessary to use an approach that offers execution without
any built-in reflection mechanism, and the reflectable transformer does just
that.

Even when there is support for reflection, it makes sense to use reflectable.
In particular, the concepts and mechanisms embedded in the reflectable
capabilities represent a significant further development and generalization
of the approach used with `MirrorsUsed`, which means that the level of
reflection support can be tailored more precisely.

Another advantage of the reflectable approach is that the same restrictions are
implemented both for running untransformed code (on top of `dart:mirrors`), and
for running transformed code. The behaviour will thus be the same on Dartium
and with code that is transformed and then compiled with Dart2js.

Another advantage is that whereas the interaction between two different
`MirrorsUsed` annotations often is hard to predict, reflectable allows for
several separate mirror-systems (reflectors) with different capabilities.
This means that for some reflection targets used by one sub-system of the
program (say, a serializer) detailed information can be generated. Another
sub-system with simpler requirements could then be supported by a much
smaller amount of information.

## Known limitations

Several parts of the library have not yet been implemented. In particular, the
following parts are still incomplete:

- It is not supported to use reflectable in untransformed mode (that is the
  mode where reflectable uses 'dart:mirrors' internally) with dart2js.
  The reason for this is that some features in 'dart:mirrors' have not been
  implemented in dart2js.

- Reflection on functions/closures. We do not have the required primitives
  to support this feature, so it is expected to remain unsupported for a while.
  There is support for one case: When a function type is given a name with
  `typedef` it is possible to use that name as a type annotation, say, on a
  method parameter or as a return type, and then `reflectedTypeCapability`
  will make it possible to get a corresponding `reflectedType` and
  `dynamicReflectedType`.

- Private declarations. There is currently almost no support for reflection on
  private declarations, as this would require special support from the runtime
  for accessing private names from other libraries. As an example of a case
  where there is some support, library mirrors can deliver class mirrors for
  private classes, and `instanceMembers` includes public members inherited
  from private superclasses. But in the vast majority of situations, private
  declarations are not supported.

- uri's of libraries. The transformer framework does not give us access to
  good uri's of libraries, so these are currently only partially supported:
  A unique uri containing the name given in the `library` directive (if any)
  is generated for each library; this means that equality tests will work,
  and the `toString()` of a uri will be somewhat human readable. But this kind
  of uri does not give any information about the location of a corresponding
  file on disk.

- Type arguments of generic types are only supported in the simple cases. E.g.,
  when it is known that a given list of actual type arguments is empty then
  the empty list is returned. However, when a parameterized type has a
  non-trivial list of actual type arguments then returning the actual type
  arguments would require runtime support that does not currently exist.

- The mirror method `libraryDependencies` has not yet been implemented with
  transformed code.

## Feature requests and bug reports

Please file feature requests and bugs using the
[github issue tracker for this repository][7].

[7]: https://github.com/dart-lang/reflectable/issues
