// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File being transformed by the reflectable transformer.
// Imports the core file of this package and re-exports
// it.  Such an export must be adjusted similarly to the
// adjustment applied to the import.

library reflectable.test.to_be_transformed.bad_export_test;
import 'package:reflectable/reflectable.dart';
export 'package:reflectable/reflectable.dart';

const Reflectable ignored = null;  // To avoid 'unused import'.

main() {}
