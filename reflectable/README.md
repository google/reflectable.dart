# Reflectable

*Please note that parts of this package are still unimplemented.*

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

[1]: https://github.com/dart-lang/reflectable/blob/master/reflectable/doc/TheDesignofReflectableCapabilities.pdf

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
at all, because the transformer `reflectable` generates specialized, static code
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
class `C` can also be covered by a reflector `R` if a supertype `A` of `C` is
annotated by a reflector which specifies that subtypes of `A` are covered as
well.

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

In order to do this, add the following to your `pubspec.yaml`:
```yaml
dependencies:
  reflectable: any

transformers:
- reflectable:
    entry_points:
      - web/main.dart # The path to your main file
```

And then run `pub build --mode=debug web` (you can omit `web` because that
is the default). This will create a new file
`build/web/main_reflection_data.dart` containing the static data needed for
reflection, and a modified `build/web/main.dart` that will initialize the
reflection framework before running `main`. When you run this file, it is
important that the package-root is set to `build/web/packages` for everything to
work.

For a more advanced example implementing the base of a serialization framework,
please look into [serialize_test.dart][3] test and its [library][4].

[3]: https://github.com/dart-lang/reflectable/test_reflectable/test/serialize_test.dart
[4]: https://github.com/dart-lang/reflectable/test_reflectable/lib/serialize.dart


### Comparison with `dart:mirrors` with `MirrorsUsed` annotations

A lot of the overhead of `dart:mirrors` can be mitigated by using a
`MirrorsUsed` annotation, just as specifying capabilities of reflectable.

One advantage of the reflectable approach is that the same restrictions are
implemented both for running untransformed (on top of `dart:mirrors` in the VM)
and transformed. So the behaviour will be the same on Dartium and the
transformed code compiled with Dart2js.

Another advantage is that, where the interaction between two different
`MirrorsUsed` annotations often is hard to predict, `Reflectable` allows for
several separate mirror-systems (reflectors) with different capabilities. It
means that for some reflection-targets used by one sub-system of the program
(say, a serializer) detailed information can be generated, and only little
information about those used by another.


## Known limitations

Several parts of the library have not yet been implemented. In particular, the
following parts are still missing:

- Side-tagging, i.e., the ability to annotate a class in another file.
- Library-mirrors (hence top-level functions).
- Generic types.
- Reflection on closures.
- Private members. There is currently no support for reflection on private
members, as this would require special support from the runtime for accessing
private names from other libraries.

## Feature requests and bug reports

Please file feature requests and bugs using the
[github issue tracker for this repository][5].

[5]: https://github.com/dart-lang/reflectable/issues
