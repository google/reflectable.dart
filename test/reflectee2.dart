// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.reflectee2;

import 'reflectee1.dart';  // Provides method argument type.
import 'my_reflectable.dart';  // Provides declarations for metadata.

@myReflectable
class E {
  set x(int v) { }
  int get y => 1;

  noSuchMethod(i) => y;
}

@myReflectable
class E2 extends E {}

@myReflectable
class F {
  static int staticMethod(A a) => a.i;
}

@myReflectable
class F2 extends F {}

@myReflectable
class Annot { const Annot(); }

@myReflectable
class AnnotB extends Annot { const AnnotB(); }

@myReflectable
class AnnotC { const AnnotC({bool named: false}); }

const a1 = const Annot();
const a2 = 32;
const a3 = const AnnotB();

@myReflectable
class G {
  int a;
  @a1 int b;
  int c;
  @a2 int d;
}

@myReflectable
class H extends G {
  int e;
  @a1 int f;
  @a1 int g;
  @a2 int h;
  @a3 int i;
}

@myReflectable
class K {
  @AnnotC(named: true) int k;
  @AnnotC() int k2;
}

