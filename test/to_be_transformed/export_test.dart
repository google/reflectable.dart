// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and re-exports
// it.  This is not supported, and it must cause an error
// during transformation.

// TODO(eernst): It may be useful to add some code that uses the export (which
// would require an additional file such that one does the export and another
// one uses it), but we currently don't plan to do this because there's nothing
// new in using an export, it just boils down to checking that class Reflectable
// in reflectable.dart and static_reflectable.dart are equivalent.

library reflectable.test.to_be_transformed.bad_export_test;
import 'package:reflectable/reflectable.dart';
export 'package:reflectable/reflectable.dart';

main() {}
