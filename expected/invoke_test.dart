// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Uses `invoke`.

library reflectable.test.to_be_transformed.invoke_test;

import 'package:reflectable/static_reflectable.dart';
import 'package:unittest/unittest.dart';
import 'package:reflectable/src/mirrors_unimpl.dart';

class MyReflectable extends Reflectable {
  const MyReflectable():
      super(const <ReflectCapability>[invokeMembersCapability]);

  // Generated: Rest of class
  InstanceMirror reflect(Object reflectee) {
    if (reflectee.runtimeType == A) {
      return new Static_A_InstanceMirror(reflectee);
    }
    throw new UnimplementedError("`reflect` on unexpected object '$reflectee'");
  }
}

const myReflectable = const MyReflectable();

@myReflectable
class A {
  int arg0() => 42;
  int arg1(int x) => x - 42;
  int arg1to3(int x, int y, [int z = 0, w]) => x + y + z * 42;
  int argNamed(int x, int y, {int z: 42}) => x + y - z;
}

main() {
  InstanceMirror instanceMirror = myReflectable.reflect(new A());
  test('invoke with no arguments', () {
    expect(instanceMirror.invoke(#arg0, []), 42);
  });
  test('invoke with simple argument list, one argument', () {
    expect(instanceMirror.invoke(#arg1, [84]), 42);
  });
  test('invoke with mandatory arguments, omitting optional ones', () {
    expect(instanceMirror.invoke(#arg1to3, [40, 2]), 42);
  });
  test('invoke with mandatory arguments, plus some optional ones', () {
    expect(instanceMirror.invoke(#arg1to3, [1, -1, 1]), 42);
  });
  test('invoke with mandatory arguments, plus all optional ones', () {
    expect(instanceMirror.invoke(#arg1to3, [21, 21, 0, "Ignored"]), 42);
  });
  test('invoke with mandatory arguments, omitting named ones', () {
    expect(instanceMirror.invoke(#argNamed, [55, 29]), 42);
  });
  test('invoke with mandatory arguments, plus named ones', () {
    expect(instanceMirror.invoke(#argNamed, [21, 21], {#z: 0}), 42);
  });
}

// Generated: Rest of file

class Static_A_ClassMirror extends ClassMirrorUnimpl {
}

class Static_A_InstanceMirror extends InstanceMirrorUnimpl {
  final A reflectee;
  Static_A_InstanceMirror(this.reflectee);
  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
    if (memberName == #arg0) {
      return Function.apply(
          reflectee.arg0, positionalArguments, namedArguments);
    }
    if (memberName == #arg1) {
      return Function.apply(
          reflectee.arg1, positionalArguments, namedArguments);
    }
    if (memberName == #arg1to3) {
      return Function.apply(
          reflectee.arg1to3, positionalArguments, namedArguments);
    }
    if (memberName == #argNamed) {
      return Function.apply(
          reflectee.argNamed, positionalArguments, namedArguments);
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
