// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.encoding_constants;

// The first `flagsBit-1` bits are used to enumerate the "kind" of the
// declaration. The more significant bits are flags.
const flagsBit = 4;

// Kinds:
const generativeConstructor = 0;
const factoryConstructor = 1;
const method = 2;
const getter = 3;
const setter = 4;
const field = 5;

// Flags:
const staticAttribute = 1 << (flagsBit);
const privateAttribute = 1 << (flagsBit + 1);
const syntheticAttribute = 1 << (flagsBit + 2);
const constAttribute = 1 << (flagsBit + 3);
const redirectingConstructorAttribute = 1 << (flagsBit + 4);
const abstractAttribute = 1 << (flagsBit + 5);
const finalAttribute = 1 << (flagsBit + 6);

int kindFromEncoding(int encoding) => encoding & ((1 << flagsBit) - 1);
