// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.encoding_constants;

// The first `flagsBit-1` bits are used to enumerate the "kind" of the
// declaration. The more significant bits are flags.
const flagsBit = 4;

// Kinds:
const generativeConstructor = 0;
const factoryConstructor = 1;
const method = 2; // Instance method.
const getter = 3;
const setter = 4;
const field = 5;
const parameter = 6;
const clazz = 7; // Cannot use keyword `class`.
const function = 8; // Top level function.

// Flags:
const staticAttribute = 1 << (flagsBit);
const privateAttribute = 1 << (flagsBit + 1);
const syntheticAttribute = 1 << (flagsBit + 2);
const constAttribute = 1 << (flagsBit + 3);
const redirectingConstructorAttribute = 1 << (flagsBit + 4);
const abstractAttribute = 1 << (flagsBit + 5);
const finalAttribute = 1 << (flagsBit + 6);
const hasDefaultValueAttribute = 1 << (flagsBit + 7);
const optionalAttribute = 1 << (flagsBit + 8);
const namedAttribute = 1 << (flagsBit + 9);
const dynamicAttribute = 1 << (flagsBit + 10);
const classTypeAttribute = 1 << (flagsBit + 11);
const dynamicReturnTypeAttribute = 1 << (flagsBit + 12);
const classReturnTypeAttribute = 1 << (flagsBit + 13);
const voidReturnTypeAttribute = 1 << (flagsBit + 14);
const enumAttribute = 1 << (flagsBit + 15);
const topLevelAttribute = 1 << (flagsBit + 16);
const genericTypeAttribute = 1 << (flagsBit + 17);
const genericReturnTypeAttribute = 1 << (flagsBit + 18);

int kindFromEncoding(int encoding) => encoding & ((1 << flagsBit) - 1);

/// Used in place of an index into a list, where a needed capability to provide
/// the actual value is missing.
const int NO_CAPABILITY_INDEX = -1;
