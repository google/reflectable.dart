@c
library test_reflectable.test.generic_metadata_test;

import 'package:reflectable/reflectable.dart';
import 'package:test/test.dart';
import 'generic_metadata_test.reflectable.dart';

class MyReflectable extends Reflectable {
  const MyReflectable()
      : super(metadataCapability, instanceInvokeCapability,
            staticInvokeCapability, declarationsCapability, libraryCapability);
}

const myReflectable = MyReflectable();

const b = 0;

const c = [
  Bar<num>({'a': 14})
];

const d = true;

class K {
  static const p = 2;
}

@myReflectable
@Bar<Object?>({
  b: deprecated,
  c: Deprecated('tomorrow'),
  1 + 2: (d ? 3 : 4),
  identical(1, 2): 's',
  K.p: 6
})
@Bar<Never>({})
@Bar<void>.namedConstructor({})
@c
class Foo {
  @Bar<bool>({})
  @Bar<Bar<Bar>>({})
  @Bar<MyReflectable>.namedConstructor({})
  @Bar<void Function()>.namedConstructor({})
  @c
  void foo() {}
  var x = 10;
}

class Bar<X> {
  final Map<Object, X> m;
  const Bar(this.m);
  const Bar.namedConstructor(this.m);

  @override
  String toString() => 'Bar<$X>($m)';
}

void main() {
  initializeReflectable();

  test('metadata on class', () {
    expect(myReflectable.reflectType(Foo).metadata, const [
      MyReflectable(),
      Bar<Object?>({
        b: deprecated,
        c: Deprecated('tomorrow'),
        3: 3,
        false: 's',
        2: 6,
      }),
      [
        Bar<num>({'a': 14})
      ],
    ]);

    var fooMirror = myReflectable.reflectType(Foo) as ClassMirror;
    expect(fooMirror.declarations['foo']!.metadata, const [
      Bar<bool>({}),
      Bar<Bar<Bar<dynamic>>>({}),
      Bar<MyReflectable>({}),
      Bar<void Function()>({}),
      [
        Bar<num>({'a': 14})
      ],
    ]);

    // The synthetic accessors do not have metadata.
    expect(fooMirror.instanceMembers['x']!.metadata, []);
    expect(fooMirror.instanceMembers['x=']!.metadata, []);

    // Test metadata on libraries
    expect(myReflectable.reflectType(Foo).owner!.metadata, [c]);
  });
}