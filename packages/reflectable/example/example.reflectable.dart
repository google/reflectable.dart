// Copyright (c) 2025, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// ILLUSTRATION OF GENERATED CODE.
//
// This file has been written manually in order to show the small amount
// of code which is the core of the output of the code generator
// `reflectable_builder`. Any real usage of this package would rely on
// the code generator `reflectable_builder` to generate a file named
// `<name_of_main>.reflectable.dart` (in this example `<name_of_main>` is
// `example`), and it would contain generated code that includes the core
// parts shown below.

import 'package:reflectable/src/reflectable_builder_based.dart' as r;
import 'package:reflectable/reflectable.dart' as r show Reflectable;

final _data = <r.Reflectable, r.ReflectorData>{};
final _memberSymbolMap = null;

void initializeReflectable() {
  r.data = _data;
  r.memberSymbolMap = _memberSymbolMap;
}
