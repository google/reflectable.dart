// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflectable code generation.
// Implements a very simple kind of proxy object.

library test_reflectable.test.proxy_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'proxy_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class ProxyReflectable extends Reflectable {
  const ProxyReflectable()
    : super(instanceInvokeCapability, declarationsCapability);
}

const proxyReflectable = ProxyReflectable();

@proxyReflectable
class A {
  int i = 0;
  String foo() => i == 42 ? 'OK!' : 'Error!';
  void bar(int i) {
    this.i = i;
  }
}

class Proxy implements A {
  final dynamic forwardee;
  final Map<Symbol, Function> methodMap;
  const Proxy(this.forwardee, this.methodMap);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return Function.apply(
      methodMap[invocation.memberName]!(forwardee),
      invocation.positionalArguments,
      invocation.namedArguments,
    );
  }
}

Map<Symbol, Function> createMethodMap(Type T) {
  var methodMapForT = <Symbol, Function>{};
  var classMirror = proxyReflectable.reflectType(T) as ClassMirror;
  Map<String, DeclarationMirror> declarations = classMirror.declarations;

  for (String name in declarations.keys) {
    var declaration = declarations[name];
    if (declaration is MethodMirror) {
      methodMapForT.putIfAbsent(
        Symbol(name),
        () => (forwardee) {
          InstanceMirror instanceMirror = proxyReflectable.reflect(forwardee);
          return instanceMirror.invokeGetter(name);
        },
      );
    }
  }
  return methodMapForT;
}

void main() {
  initializeReflectable();

  // Set up support for proxying A instances.
  Map<Symbol, Function> methodMapForA = createMethodMap(A);

  // Set up a single proxy for a single instance.
  final a = A();
  var proxy = Proxy(a, methodMapForA);

  // Use it.
  test('Using proxy', () {
    proxy.bar(42);
    expect(a.i, 42);
    expect(proxy.foo(), 'OK!');
  });
}
