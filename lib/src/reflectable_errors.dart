// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_errors;

/// It is a transformation time error to use an instance of a
/// class that is not a direct subclass of [Reflectable] as
/// metadata.
///
/// Rationale: A client may actually use instances of [Reflectable]
/// itself, or of subsubclasses etc. of [Reflectable] as metadata, for
/// entirely different purposes than using this transformer.  But we
/// consider these cases to be without merit: It would be very
/// error-prone if we were to silently ignore such "alien" usages of
/// metadata conforming to the type [Reflectable], and it is so easy
/// to create a new class which is unrelated to [Reflectable] but
/// structurally identical that they could just stop using
/// [Reflectable] and use that.  So we simply outlaw all these usages
/// of reflectors, no matter whether they were used for a different
/// purpose or they were the result of a lack of knowledge that
/// such metadata will not have any effect.
const String METADATA_NOT_DIRECT_SUBCLASS =
    'Metadata has type Reflectable, but is not an instance of '
    'a direct subclass of Reflectable';

/// It is a transformation time error to give an argument to the super
/// constructor invocation in a subclass of Reflectable that is of
/// a non-class type.
const String SUPER_ARGUMENT_NON_CLASS =
    'The super constructor invocation receives an argument whose'
    ' type `{type}` is not a class.';

/// It is a transformation time error to give an argument to the super
/// constructor invocation in a subclass of Reflectable that is defined
/// outside the library 'package:reflectable/capability.dart'.
const String SUPER_ARGUMENT_WRONG_LIBRARY =
    'The super constructor invocation receives an argument whose'
    ' type `{element}` is defined outside the library `{library}`.';

/// It is a transformation time error to give an argument to the super
/// constructor invocation in a subclass of Reflectable that is non-const.
const String SUPER_ARGUMENT_NON_CONST =
    'The super constructor invocation receives an argument'
    ' which is not a constant.';

/// It is a transformation time error to use an enum as a reflector class.
const String IS_ENUM = 'Encountered a reflector class which is an enum.';

/// Finds any template holes of the form {name} in [template] and replaces them
/// with the corresponding value in [replacements].
String applyTemplate(String template, Map<String, String> replacements) {
  return template.replaceAllMapped(RegExp(r'{(.*?)}'), (Match match) {
    var index = match.group(1);
    var replacement = replacements[index];
    if (replacement == null) {
      throw ArgumentError('Missing template replacement for $index');
    }
    return replacements[index];
  });
}
