// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_errors;

import 'package:analyzer/src/generated/error.dart';

class TransformationErrorCode extends ErrorCode {
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
  /// of Reflectable metadata, no matter whether they were used for a
  /// different purpose or they were the result of a lack of knowledge
  /// that such metadata will not have any effect.
  static const CompileTimeErrorCode REFLECTABLE_METADATA_NOT_DIRECT_SUBCLASS =
      const CompileTimeErrorCode('REFLECTABLE_METADATA_NOT_DIRECT_SUBCLASS',
          "Metadata has type Reflectable, but is not an instance of "
          "a direct subclass of Reflectable");

  /// It is a transformation time error to export the library
  /// `../reflectable.dart`.
  static const CompileTimeErrorCode REFLECTABLE_LIBRARY_EXPORTED =
      const CompileTimeErrorCode('REFLECTABLE_LIBRARY_EXPORTED',
          "The library 'package:reflectable/reflectable.dart' is exported.");

  /// It is a transformation time error to use an enum as a Reflectable
  /// metadata class.
  static const CompileTimeErrorCode REFLECTABLE_IS_ENUM =
      const CompileTimeErrorCode('REFLECTABLE_IS_ENUM',
          "Encountered a Reflectable metadata class which is an enum.");

  /// Initialize a newly created error code to have the given [name], to
  /// be associated with the given [message] template, and to use the
  /// given [correction] template.
  const TransformationErrorCode(String name,
                                String message,
                                [String correction]):
      super(name, message, correction);

  @override
  ErrorSeverity get errorSeverity => ErrorType.COMPILE_TIME_ERROR.severity;

  @override
  ErrorType get type => ErrorType.COMPILE_TIME_ERROR;
}
