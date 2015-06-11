// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.encoding_constants;

// The first bits are used to enumerate the "kind" of the declaration.
// The more significant bits are flags.

// Kinds:
const generativeConstructor = 0;
const factoryConstructor = 1;
const redirectingConstructor = 2;
const method = 3;
const getter = 4;
const setter = 5;

// Flags:
const staticAttribute = 16;
const abstractAttribute = 32;
const constAttribute = 64;
const privateAttribute = 128;
const syntheticAttribute = 256;

int kindFromEncoding(int encoding) => encoding & 15;