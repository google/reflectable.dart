// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and declares that
// it is `deferred`.  The use of a `deferred` modifier on
// this import is not supported, and it must give rise to
// an error during transformation.

library reflectable.test.to_be_transformed.bad_import_3_test;
import 'package:reflectable/reflectable.dart' deferred as r;
