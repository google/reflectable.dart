// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses 'reflect', with a constraint to invocation based on
// 'invokeMembersCapability'.

library reflectable.test.to_be_transformed.members_capability_test;

import 'package:reflectable/static_reflectable.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(const [invokeMembersCapability]);

  // Generated: Rest of class
  InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == Foo) {
      return new Static_Foo_InstanceMirror(reflectee);
    }
    throw new UnimplementedError("`reflect` on unexpected object '$reflectee'");
  }
}
const myReflectable = const MyReflectable();

@myReflectable
class Foo {
  x() => 42;
  y(int n) => "Hello";
}

main() {
  myReflectable.reflect(new Foo()).invoke(new Symbol('x'), []);
}

// Generated: Rest of file

class Static_Foo_ClassMirror extends ClassMirrorUnimpl {
}

class Static_Foo_InstanceMirror extends InstanceMirrorUnimpl {
  final Foo reflectee;
  Static_Foo_InstanceMirror(this.reflectee);
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
    if (memberName == #x) {
      return Function.apply(
          reflectee.x, positionalArguments, namedArguments);
    }
    if (memberName == #y) {
      return Function.apply(
          reflectee.y, positionalArguments, namedArguments);
    }
    if (memberName == #toString) {
      return Function.apply(
          reflectee.toString, positionalArguments, namedArguments);
    }
    if (memberName == #noSuchMethod) {
      return Function.apply(
          reflectee.noSuchMethod, positionalArguments, namedArguments);
    }
    // Want `reflectee.noSuchMethod(invocation);` where `invocation` holds
    // memberName, positionalArguments, and namedArguments.  But we cannot
    // create an instance of [Invocation] in user code.
    throw new UnimplementedError('Cannot call `noSuchMethod`');
  }
}
