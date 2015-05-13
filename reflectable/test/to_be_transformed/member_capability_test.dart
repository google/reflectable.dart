// Use reflectable.

import 'package:reflectable/reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable() : super(const <ReflectCapability>[
      const InvokeInstanceMemberCapability(#x)
  ]);
}
const myReflectable = const MyReflectable();

@myReflectable
class Foo {
  x() => 42;
  y(int n) => "Hello";
}

main() {
  myReflectable.reflect(new Foo()).invoke(#x, []);
}
