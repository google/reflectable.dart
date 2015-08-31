// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Implements a very simple kind of proxy object.

library test_reflectable.test.proxy_test;

import 'package:reflectable/reflectable.dart';
import 'package:unittest/unittest.dart';

class ProxyReflectable extends Reflectable {
  const ProxyReflectable()
      : super(instanceInvokeCapability, declarationsCapability);
}
const proxyReflectable = const ProxyReflectable();

@proxyReflectable
class A {
  int i = 0;
  String foo() => i == 42 ? "OK!" : "Error!";
  void bar(int i) {
    this.i = i;
  }
}

@proxy
class Proxy {
  final forwardee;
  final Map<Symbol, Function> methodMap;
  const Proxy(this.forwardee, this.methodMap);
  noSuchMethod(Invocation invocation) {
    return Function.apply(methodMap[invocation.memberName](this.forwardee),
        invocation.positionalArguments, invocation.namedArguments);
  }
}

Map<Symbol, Function> createMethodMap(Type T) {
  Map<Symbol, Function> methodMapForT = <Symbol, Function>{};
  ClassMirror classMirror = proxyReflectable.reflectType(T);
  Map<String, DeclarationMirror> declarations = classMirror.declarations;

  for (String name in declarations.keys) {
    DeclarationMirror declaration = declarations[name];
    if (declaration is MethodMirror) {
      methodMapForT.putIfAbsent(new Symbol(name), () => (forwardee) {
        InstanceMirror instanceMirror = proxyReflectable.reflect(forwardee);
        return instanceMirror.invokeGetter(name);
      });
    }
  }
  return methodMapForT;
}

main() {
  // Set up support for proxying A instances.
  Map<Symbol, Function> methodMapForA = createMethodMap(A);

  // Set up a single proxy for a single instance.
  final A a = new A();
  Proxy proxy = new Proxy(a, methodMapForA);

  // Use it.
  test("Using proxy", () {
    proxy.bar(42);
    expect(a.i, 42);
    expect(proxy.foo(), "OK!");
  });
}
