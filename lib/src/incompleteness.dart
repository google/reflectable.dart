// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library provides shared features dealing with incompleteness in
/// the package, e.g., exceptions intended to be thrown when an unimplemented
/// method is called.
library reflectable.src.incompleteness;

/// Throwing an instance of this class indicates that a location in code
/// has been reached which should never be reached, typically because the code
/// should maintain certain invariants under which that location can never
/// be reached.
class UnreachableError extends Error {
  final String message;
  UnreachableError(this.message);

  @override
  String toString() => message;
}

/// Used to throw an [UnreachableError]. Can be invoked with
/// `throw unreachableError(..)`, which will indicate to the compiler that this
/// expression throws (even though it actually happens here). This way we avoid
/// warnings about a missing return problem, and the code may be more readable.
Null unreachableError(String message) {
  var extendedMessage =
      '*** Unexpected situation encountered!\nPlease report a bug on '
      'github.com/dart-lang/reflectable: $message.';
  throw UnreachableError(extendedMessage);
}

/// Used to throw an [UnimplementedError]. Can be invoked with
/// `throw unimplementedError(..)`, which will indicate to the compiler that
/// this expression throws (even though it actually happens here). This way we
/// avoid warnings about a missing return problem, and the code may be more
/// readable.
Null unimplementedError(String message) {
  var extendedMessage = '*** Unfortunately, this feature has not yet been '
      'implemented: $message.\n'
      'If you wish to ensure that it is prioritized, please report it '
      'on github.com/dart-lang/reflectable.';
  throw UnimplementedError(extendedMessage);
}
