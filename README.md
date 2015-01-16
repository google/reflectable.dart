# reflectable

Reflectable is a library that allows programmers to eliminate certain
usages of dynamic reflection by specialization of reflective code to
an equivalent implementation using only static techniques.  The use of
dynamic reflection is constrained in order to ensure that the
specialized code can be generated and will have a reasonable size.

In general, reflection is disabled unless it is explicitly enabled, and
it is enabled by adding specific kinds of metadata, namely instances
of subclasses of the class Reflectable.  As a starting point, only
instances of classes with that kind of metadata can be accessed
reflectively, and that access can be further constrained by giving
constructor arguments to Reflectable in a super constructor invocation
in said subclasses of Reflectable.  As a result, the available universe
of reflection related operations is so well-known at compile time that
it is possible to specialize the generic support for reflection (based
on dart:mirrors) to a purely static form that satisfies the requirement
of the given body of user code.  The transformation is performed by the
pub transformer reflectable_transformer, available in this package.

## Usage

A simple usage example:

    import 'package:reflectable/reflectable.dart';

    class MyReflectable extends Reflectable {
      const MyReflectable():
          super(/* ..constrain, but do not prevent invoke on #foo.. */);
    }

    const myReflectable = const MyReflectable;

    @myReflectable
    class MyClass { ... bool foo(int x) {..} ... }

    main() {
      var x = new MyClass();
      // Normal invocation.
      x.foo(3);
      // Reflectable invocation.
      var xr = myReflectable.reflect(x);
      xr.invoke(#foo, [3]);
    }

## Features and bugs

Please file feature requests and bugs at dartbug.com, area=Dart2JS.

