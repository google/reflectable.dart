// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.test.reflectee;

import 'my_reflectable_s.dart';  // Provides declarations for metadata.

@myReflectable
class A {
  int i = 42;
  int j = 44;
  int get j2 => j;
  void set j2(int v) { j = v; }
  void inc0() { i++; }
  void inc1(int v) { i = i + (v == null ? -10 : v); }
  void inc2([int v]) { i = i + (v == null ? -10 : v); }

  static int staticValue = 42;
  static void staticInc() { staticValue++; }
}

@myReflectable
class B {
  final int f = 3;
  int _w;
  int get w => _w;
  set w(int v) { _w = v; }

  String z;
  A a;

  B(this._w, this.z, this.a);
}

@myReflectable
class C {
  int x;
  String y;
  B b;

  inc(int n) {
    x = x + n;
  }
  dec(int n) {
    x = x - n;
  }

  C(this.x, this.y, this.b);
}

@myReflectable
class D extends C with A {
  int get x2 => x;
  int get i2 => i;

  D(x, y, b) : super(x, y, b);
}

