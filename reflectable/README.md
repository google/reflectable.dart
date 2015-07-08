# Reflectable

*Please note that parts of this package are still unimplemented.*

## Introduction

This library provides an alternative to certain usages of `dart:mirrors`,
allowing one to declare restricted mirror-systems tailored to the intended
 usage. 

It can be used in two modes: **untransformed** or **transformed**.

For both modes, your code will not depend directly on `dart:mirrors`. In the
untransformed mode there is an indirect dependency because the support for
reflective features is implemented by delegation to mirror objects from
`dart:mirrors`. In the transformed mode there is no dependency on `dart:mirrors`
at all, because the transformer `reflectable` generates specialized, static code
that supports the reflective features.

The use of dynamic reflection is constrained to only be within a declared set of
*capabilities* in order to ensure that the specialized code can be generated and
will have a reasonable size.

In general, reflection is done via a subclass of the class
`Reflectable` (a *reflector*).

```dart
class Reflector extends Reflectable {
  const Reflector() : super(capability1, capability2, ...);
}
```

Reflection is disabled by default, and is enabled by annotating classes with the
reflector.

```dart
@Reflector()
class A {
  ...
}
```

Only instances of classes annotated with a reflector `R` can be accessed
reflectively using `R`, and that access is constrained by the capabilities
passed as argument to the super constructor. (There are ways a class can be
annotated indirectly, such as using a capability that includes all subclasses of
 the annotated classes).

As a result, the available universe of reflection related operations is 
so well-known at compile time that it is possible to specialize the generic
support for reflection (based on dart:mirrors) to a purely static form that
satisfies the requirements of the given annotations and capabilities.

## Usage

A simple usage example. This is the file `web/main.dart`:

```dart
import 'package:reflectable/reflectable.dart';

// Annotate with this class to enable reflection.
class Reflector extends Reflectable {
  const Reflector()
  : super(invokingCapability); // Generate code for invoking methods.
}

const reflector = const Reflector();

@reflector // This annotation enables reflection on A.
class A {
  final int a;
  A(this.a);
  greater(int x) => x > a;
  lessThanEqual(int x) => x <= a;
}

main() {
  A x = new A(10);
  // Reflect using the const instance of the reflector:
  InstanceMirror instanceMirror = reflector.reflect(x);
  int weekday = new DateTime.now().weekday;
  // On Fridays we test if 3 is greater than 10, on other days if it is less
  // than or equal.
  String methodName = weekday == DateTime.FRIDAY ? "greater" : "lessThanEqual";
  // Reflectable invocation:
  print(instanceMirror.invoke(methodName, [3]));
}
```

Running in untransformed mode, this will work but it will rely on
`dart:mirrors`. For instance, you can directly run it on the VM to get that
effect. If you wish to avoid the dependency on `dart:mirrors` you can transform
the code using the transformer in this package.

In order to do this, add the following to your `pubspec.yaml`:
```yaml
dependencies:
  reflectable: any

transformers:
- reflectable:
    entry_points:
      - web/main.dart # The path to your main file 
```

And then run `pub build --mode=debug web` (and you can omit `web` because that
is the default). This will create a new file
`build/web/main_reflection_data.dart` containing the static data needed for
reflection, and a modified `build/web/main.dart` that will initialize the
reflection framework before running `main`. When you run this file, it is
important that the package-root is set to `build/web/packages` for everything to
work.

For a more advanced example implementing the base of a serialization framework
 look into 
  [serialize_test.dart](../test_reflectable/test/serialize_test.dart) test
and its [library](../test_reflectable/lib/serialize.dart).

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

- There is still no support for 'side-tagging', meaning the ability to annotate
a class in another file.
- Still there are no library-mirrors, and thus also no support for top-level
functions.
- There is no support for generic types - it is still not clear how this
will/can be implemented.
- There is still no support for reflecting on closures - it is however
not clear how useful this is.
- There is currently no planned support for reflection on private members. This
would require special support from the runtime for accessing private names from
other libraries.

## Feature requests and bug reports

Please file feature requests and bugs using the github issue tracker
for this repository.
