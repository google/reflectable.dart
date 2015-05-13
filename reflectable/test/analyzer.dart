// Copyright (c) 2015, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable.test.analyzer;

import 'dart:io';
import 'package:analyzer/options.dart';
import 'package:analyzer/src/error_formatter.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/interner.dart';
import 'package:analyzer/src/generated/java_engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:reflectable/src/setup_analyzer.dart';

void main(List<String> args) {
  StringUtilities.INTERNER = new MappedInterner();
  List<AnalysisErrorInfo> errorInfos = new List<AnalysisErrorInfo>();
  CommandLineOptions options = CommandLineOptions.parse(args);

  ErrorSeverity computeSeverity(AnalysisError error) {
    if (!options.enableTypeChecks &&
        error.errorCode.type == ErrorType.CHECKED_MODE_COMPILE_TIME_ERROR) {
      return ErrorSeverity.INFO;
    }
    return error.errorCode.errorSeverity;
  }

  bool isDesiredError(AnalysisError error) {
    if (error.errorCode.type == ErrorType.TODO) return false;
    return computeSeverity(error) != ErrorSeverity.INFO ||
        !options.disableHints;
  }

  ErrorFormatter formatter =
      new ErrorFormatter(stdout, options, isDesiredError);
  DirectoryBasedDartSdk sdk =
      new DirectoryBasedDartSdk(new JavaFile(options.dartSdkPath));

  ErrorSeverity maxErrorSeverity(List<AnalysisErrorInfo> errorInfos) {
    var status = ErrorSeverity.NONE;
    for (AnalysisErrorInfo errorInfo in errorInfos) {
      for (AnalysisError error in errorInfo.errors) {
        if (!isDesiredError(error)) continue;
        var severity = computeSeverity(error);
        status = status.max(severity);
      }
    }
    return status;
  }

  for (String sourcePath in options.sourceFiles) {
    ErrorSeverity severity = ErrorSeverity.NONE;

    try {
      AnalyzerSetup setup = setupAnalyzer(
          sourcePath,
          sdk,
          options.packageRootPath,
          options.definedVariables,
          disableHints: options.disableHints,
          includePackages: options.showPackageWarnings,
          includeSdk: options.showSdkWarnings);

      // Perform the analysis and emit diagnostic messages.
      for (Source source in setup.sources) {
        setup.context.computeErrors(source);
        errorInfos.add(setup.context.getErrors(source));
      }
      formatter.formatErrors(errorInfos);

      // Report back to caller how severe problems we have seen.
      severity = maxErrorSeverity(errorInfos);
      if (severity == ErrorSeverity.WARNING && options.warningsAreFatal) {
        severity = ErrorSeverity.ERROR;
      }
    } on ArgumentError catch (error) {
      // [setupAnalyzer] bailed out because [sourcePath] denotes a part.
      severity = ErrorSeverity.ERROR;
    }

    // Set the [exitCode] if we have seen sufficiently severe errors.
    if (severity == ErrorSeverity.ERROR ||
        (options.warningsAreFatal && severity == ErrorSeverity.WARNING)) {
      exitCode = severity.ordinal;
    }
  }
}
