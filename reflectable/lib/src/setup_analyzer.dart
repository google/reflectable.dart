// Copyright (c) 2015, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library reflectable.src.analyzer_setup;

import 'dart:io';
import 'package:analyzer/file_system/file_system.dart' show Folder;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/package_map_provider.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/source/pub_package_map_provider.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source_io.dart';

class AnalyzerSetup {
  final AnalysisContext context;
  final Set<Source> sources;
  AnalyzerSetup(this.context, this.sources);
}

/// Converts [sourcePath] into an absolute path.
String _normalizeSourcePath(String sourcePath) {
  if (sourcePath == null) throw new ArgumentError("sourcePath cannot be null");
  return new File(sourcePath).absolute.path;
}

/// Returns the [Uri] for the given input file.
/// Usually it is a `file:` [Uri], but if [file] is located in the `lib`
/// directory of the [sdk], then returns a `dart:` [Uri].
Uri _getUri(DirectoryBasedDartSdk sdk, JavaFile file) {
  Source source = sdk.fromFileUri(file.toURI());
  if (source != null) return source.uri;
  return file.toURI();
}

/// Returns the list of uri resolvers whose analysis context is
/// the given [sdk] and the given [packageRootPath].
List<UriResolver> _computeUriResolvers(DirectoryBasedDartSdk sdk,
                                       String packageRootPath) {
  List<UriResolver> resolvers =
      [new DartUriResolver(sdk), new FileUriResolver()];
  if (packageRootPath != null) {
    resolvers.add(new PackageUriResolver([new JavaFile(packageRootPath)]));
  } else {
    PubPackageMapProvider pubPackageMapProvider =
        new PubPackageMapProvider(PhysicalResourceProvider.INSTANCE, sdk);
    PackageMapInfo packageMapInfo = pubPackageMapProvider.computePackageMap(
        PhysicalResourceProvider.INSTANCE.getResource('.'));
    Map<String, List<Folder>> packageMap = packageMapInfo.packageMap;
    if (packageMap != null) {
      resolvers.add(
          new PackageMapUriResolver(PhysicalResourceProvider.INSTANCE,
                                    packageMap));
    }
  }
  return resolvers;
}

const int _maxCacheSize = 512;

AnalyzerSetup setupAnalyzer(String sourcePath,
                            DirectoryBasedDartSdk sdk,
                            String packageRootPath,
                            Map<String, String> definedVariables,
                            {bool disableHints: false,
                             bool includePackages: true,
                             bool includeSdk: true}) {
  JavaFile sourceFile = new JavaFile(_normalizeSourcePath(sourcePath));
  Uri libraryUri = _getUri(sdk, sourceFile);
  Source librarySource = new FileBasedSource(sourceFile, libraryUri);
  List<UriResolver> resolvers = _computeUriResolvers(sdk, packageRootPath);
  SourceFactory sourceFactory = new SourceFactory(resolvers);
  AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
  context.sourceFactory = sourceFactory;

  // Install all defined variables into the [context].
  if (!definedVariables.isEmpty) {
    DeclaredVariables declaredVariables = context.declaredVariables;
    definedVariables.forEach((String variableName, String value) {
      declaredVariables.define(variableName, value);
    });
  }

  // Set the analysis options for the [context].
  AnalysisOptionsImpl contextOptions = new AnalysisOptionsImpl();
  contextOptions.cacheSize = _maxCacheSize;
  contextOptions.hint = !disableHints;
  context.analysisOptions = contextOptions;

  // Create and add a [ChangeSet].
  ChangeSet changeSet = new ChangeSet();
  changeSet.addedSource(librarySource);
  context.applyChanges(changeSet);

  // Avoid using a part as an entry point.
  if (context.computeKindOf(librarySource) == SourceKind.PART) {
    print("Only libraries can be analyzed.");
    print("$sourcePath is a part and can not be analyzed.");
    throw new ArgumentError("Analyzing a part");
  }

  /// Gathers libraries for analysis.
  Set<Source> gatherLibrarySources(LibraryElement library) {
    Set<Source> sources = new Set<Source>();
    Set<CompilationUnitElement> units = new Set<CompilationUnitElement>();
    Set<LibraryElement> libraries = new Set<LibraryElement>();

    void addCompilationUnitSource(CompilationUnitElement unit) {
      if (unit == null || units.contains(unit)) return;
      units.add(unit);
      sources.add(unit.source);
    }

    void addLibrarySources(LibraryElement library) {
      if (library == null || !libraries.add(library)) return;
      UriKind uriKind = library.source.uriKind;
      if (!includePackages && uriKind == UriKind.PACKAGE_URI) return;
      if (!includeSdk && uriKind == UriKind.DART_URI) return;
      addCompilationUnitSource(library.definingCompilationUnit);
      library.parts.forEach(addCompilationUnitSource);
      library.importedLibraries.forEach(addLibrarySources);
      library.exportedLibraries.forEach(addLibrarySources);
    }

    addLibrarySources(library);
    return sources;
  }

  return new AnalyzerSetup(
      context,
      gatherLibrarySources(context.computeLibraryElement(librarySource)));
}
