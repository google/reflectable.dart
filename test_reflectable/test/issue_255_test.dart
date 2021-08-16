// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests a situation where a top level variable needs to have `ownerIndex`
// `NO_CAPABILITY_INDEX` (because there is no support for accessing the
// corresponding library mirror). This used to cause a null error.

import 'package:reflectable/reflectable.dart';
import 'issue_255_test.reflectable.dart';

@c
class C extends Reflectable {
  const C() : super(topLevelInvokeCapability);
}

const c = C();

void main() {
  initializeReflectable();
}
