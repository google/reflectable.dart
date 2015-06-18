// (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_implementation;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'encoding_constants.dart' as constants;
import "reflectable_class_constants.dart" as reflectable_class_constants;
import 'source_manager.dart';
import 'transformer_errors.dart' as errors;
import '../capability.dart';

class ReflectionWorld {
  final List<ReflectorDomain> reflectors = new List<ReflectorDomain>();
  final LibraryElement reflectableLibrary;

  ReflectionWorld(this.reflectableLibrary);

  Iterable<ReflectorDomain> reflectorsOfLibrary(LibraryElement library) {
    return reflectors.where((ReflectorDomain domain) {
      return domain.reflector.library == library;
    });
  }

  Iterable<ClassDomain> annotatedClassesOfLibrary(LibraryElement library) {
    return reflectors
        .expand((ReflectorDomain domain) => domain.annotatedClasses)
        .where((ClassDomain classDomain) {
      return classDomain.classElement.library == library;
    });
  }

  void computeNames(Namer namer) {
    reflectors
        .forEach((ReflectorDomain reflector) => reflector.computeNames(namer));
  }
}

/// Information about the program parts that can be reflected by a given
/// Reflector.
class ReflectorDomain {
  final ClassElement reflector;
  final List<ClassDomain> annotatedClasses;
  final Capabilities capabilities;

  /// Libraries that must be imported to `reflector.library`.
  final Set<LibraryElement> missingImports = new Set<LibraryElement>();

  ReflectorDomain(this.reflector, this.annotatedClasses, this.capabilities);

  void computeNames(Namer namer) {
    annotatedClasses
        .forEach((ClassDomain classDomain) => classDomain.computeNames(namer));
  }
}

/// Information about reflectability for a given class.
class ClassDomain {
  final ClassElement classElement;
  final Iterable<MethodElement> invokableMethods;
  final Iterable<MethodElement> declaredMethods;

  ReflectorDomain reflectorDomain;
  String staticClassMirrorName;
  String staticInstanceMirrorName;
  String get baseName => classElement.name;

  ClassDomain(this.classElement, this.invokableMethods, this.declaredMethods,
      this.reflectorDomain);

  Iterable<ExecutableElement> get declarations {
    // TODO(sigurdm): Include constructors.
    // TODO(sigurdm): Include fields.
    // TODO(sigurdm): Include getters and setters.
    // TODO(sigurdm): Include type variables (if we decide to keep them).
    return [declaredMethods].expand((x) => x);
  }

  /// Returns an integer encoding the kind and attributes of the given
  /// method/constructor/getter/setter.
  int _declarationDescriptor(ExecutableElement element) {
    int result;
    if (element is PropertyAccessorElement) {
      result = element.isGetter ? constants.getter : constants.setter;
    } else if (element is ConstructorElement) {
      if (element.isFactory) {
        result = constants.factoryConstructor;
      } else if (element.redirectedConstructor != null) {
        result = constants.redirectingConstructor;
      } else {
        result = constants.generativeConstructor;
      }
      if (element.isConst) {
        result += constants.constAttribute;
      }
    } else {
      result = constants.method;
    }
    if (element.isPrivate) {
      result += constants.privateAttribute;
    }
    if (element.isAbstract) {
      result += constants.abstractAttribute;
    }
    if (element.isStatic) {
      result += constants.staticAttribute;
    }
    return result;
  }

  /// Returns a String with the textual representation of the declarations-map.
  String get declarationsString {
    Iterable<String> declarationParts = declarations.map(
        (ExecutableElement instanceMember) {
      return '"${instanceMember.name}": '
          'new MethodMirrorImpl("${instanceMember.name}", '
          '${_declarationDescriptor(instanceMember)}, this)';
    });
    return "{${declarationParts.join(", ")}}";
  }

  void computeNames(Namer namer) {
    staticClassMirrorName = namer.freshName("Static_${baseName}_ClassMirror");
    staticInstanceMirrorName =
        namer.freshName("Static_${baseName}_InstanceMirror");
  }
}

/// A wrapper around a list of Capabilities.
/// Supports queries about the methods supported by the set of capabilities.
class Capabilities {
  List<ReflectCapability> capabilities;
  Capabilities(this.capabilities);

  instanceMethodsFilterRegexpString() {
    if (capabilities.contains(instanceInvokeCapability)) return ".*";
    if (capabilities.contains(invokingCapability)) return ".*";
    return capabilities.where((ReflectCapability capability) {
      return capability is InstanceInvokeCapability;
    }).map((InstanceInvokeCapability capability) {
      return "(${capability.namePattern})";
    }).join('|');
  }

  bool supportsInstanceInvoke(String methodName) {
    if (capabilities.contains(invokingCapability)) return true;
    if (capabilities.contains(instanceInvokeCapability)) return true;

    bool handleMetadataCapability(ReflectCapability capability) {
      if (capability is! MetadataQuantifiedCapability &&
          capability is! GlobalQuantifyMetaCapability) {
        return false;
      }
      // TODO(eernst): Handle MetadataQuantifiedCapability and
      // GlobalQuantifyMetaCapability.
      throw new UnimplementedError();
    }
    if (capabilities.any(handleMetadataCapability)) return true;

    bool handleInstanceInvokeCapability(ReflectCapability capability) {
      if (capability is InstanceInvokeCapability) {
        return new RegExp(capability.namePattern).firstMatch(methodName) !=
            null;
      } else {
        return false;
      }
    }
    return capabilities.any(handleInstanceInvokeCapability);
  }
}

/// Provides support for generating fresh names.
class Namer {
  // Maps a name without final digits to the highest number it has been seen
  // followed by (0 if it was only seen without following digits.
  final Map<String, int> nameCounts = new Map<String, int>();

  final RegExp splitFinalDigits = new RegExp(r'(.*?)(\d*)$');

  /// Registers [name] such that any results from [freshName] will not collide
  /// with it.
  void registerName(String name) {
    Match match = splitFinalDigits.matchAsPrefix(name);
    String base = match.group(1);
    // Prefixing with '0' makes the empty string yield 0 instead of throwing.
    int numberSuffix = int.parse("0${match.group(2)}");
    int baseCount = nameCounts[base];
    nameCounts[base] = max(baseCount == null ? 0 : baseCount, numberSuffix);
  }

  String freshName(String proposedName) {
    Match match = splitFinalDigits.matchAsPrefix(proposedName);
    String base = match.group(1);
    // Prefixing with '0' makes the empty string yield 0 instead of throwing.
    int numberSuffix = int.parse("0${match.group(2)}");
    if (nameCounts[base] == null) {
      nameCounts[base] = numberSuffix;
      return proposedName;
    }
    nameCounts[base]++;
    return "$base${nameCounts[base]}";
  }
}

// TODO(eernst): Keep in mind, with reference to
// http://dartbug.com/21654 comment #5, that it would be very valuable
// if this transformation can interact smoothly with incremental
// compilation.  By nature, that is hard to achieve for a
// source-to-source translation scheme, but a long source-to-source
// translation step which is invoked frequently will certainly destroy
// the immediate feedback otherwise offered by incremental compilation.
// WORKAROUND: A work-around for this issue which is worth considering
// is to drop the translation entirely during most of development,
// because we will then simply work on a normal Dart program that uses
// dart:mirrors, which should have the same behavior as the translated
// program, and this could work quite well in practice, except for
// debugging which is concerned with the generated code (but that would
// ideally be an infrequent occurrence).

class TransformerImplementation {
  TransformLogger logger;
  Resolver resolver;

  Namer namer = new Namer();

  /// Checks whether the given [type] from the target program is "our"
  /// class [Reflectable] by looking up the static field
  /// [Reflectable.thisClassId] and checking its value (which is a 40
  /// character string computed by sha1sum on an old version of
  /// reflectable.dart).
  ///
  /// Discussion of approach: Checking that we have found the correct
  /// [Reflectable] class is crucial for correctness, and the "obvious"
  /// approach of just looking up the library and then the class with the
  /// right names using [resolver] is unsafe.  The problems are as
  /// follows: (1) Library names are not guaranteed to be unique in a
  /// given program, so we might look up a different library named
  /// reflectable.reflectable, and a class named Reflectable in there.  (2)
  /// Library URIs (which must be unique in a given program) are not known
  /// across all usage locations for reflectable.dart, so we cannot easily
  /// predict all the possible URIs that could be used to import
  /// reflectable.dart; and it would be awkward to require that all user
  /// programs must use exactly one specific URI to import
  /// reflectable.dart.  So we use [Reflectable.thisClassId] which is very
  /// unlikely to occur with the same value elsewhere by accident.
  bool _equalsClassReflectable(ClassElement type) {
    FieldElement idField = type.getField("thisClassId");
    if (idField == null || !idField.isStatic) return false;
    if (idField is ConstFieldElementImpl) {
      EvaluationResultImpl idResult = idField.evaluationResult;
      if (idResult != null) {
        return idResult.value.stringValue == reflectable_class_constants.id;
      }
      // idResult == null: analyzer/.../element.dart does not specify
      // whether this could happen, but it is surely not the right
      // class, so we fall through.
    }
    // Not a const field, cannot be the right class.
    return false;
  }

  /// Returns the ClassElement in the target program which corresponds to class
  /// [Reflectable].
  ClassElement _findReflectableClassElement(LibraryElement reflectableLibrary) {
    for (CompilationUnitElement unit in reflectableLibrary.units) {
      for (ClassElement type in unit.types) {
        if (type.name == reflectable_class_constants.name &&
            _equalsClassReflectable(type)) {
          return type;
        }
      }
    }
    // Class [Reflectable] was not found in the target program.
    return null;
  }

  /// Returns true iff [possibleSubtype] is a direct subclass of [type].
  bool _isDirectSubclassOf(InterfaceType possibleSubtype, InterfaceType type) {
    InterfaceType superclass = possibleSubtype.superclass;
    // Even if `superclass == null` (superclass of Object), the equality
    // test will produce the correct result.
    return type == superclass;
  }

  /// Returns true iff [possibleSubtype] is a subclass of [type], including the
  /// reflexive and transitive cases.
  bool _isSubclassOf(InterfaceType possibleSubtype, InterfaceType type) {
    if (possibleSubtype == type) return true;
    InterfaceType superclass = possibleSubtype.superclass;
    if (superclass == null) return false;
    return _isSubclassOf(superclass, type);
  }

  /// Returns the metadata class in [elementAnnotation] if it is an
  /// instance of a direct subclass of [focusClass], otherwise returns
  /// `null`.  Uses [errorReporter] to report an error if it is a subclass
  /// of [focusClass] which is not a direct subclass of [focusClass],
  /// because such a class is not supported as a Reflector.
  ClassElement _getReflectableAnnotation(
      ElementAnnotation elementAnnotation, ClassElement focusClass) {
    if (elementAnnotation.element == null) {
      // TODO(eernst): The documentation in
      // analyzer/lib/src/generated/element.dart does not reveal whether
      // elementAnnotation.element can ever be null. The following action
      // is based on the assumption that it means "there is no annotation
      // here anyway".
      return null;
    }

    /// Checks that the inheritance hierarchy placement of [type]
    /// conforms to the constraints relative to [classReflectable],
    /// which is intended to refer to the class Reflectable defined
    /// in package:reflectable/reflectable.dart. In case of violations,
    /// reports an error on [logger].
    bool checkInheritance(InterfaceType type, InterfaceType classReflectable) {
      if (!_isSubclassOf(type, classReflectable)) {
        // Not a subclass of [classReflectable] at all.
        return false;
      }
      if (!_isDirectSubclassOf(type, classReflectable)) {
        // Instance of [classReflectable], or of indirect subclass
        // of [classReflectable]: Not supported, report an error.
        logger.error(errors.METADATA_NOT_DIRECT_SUBCLASS,
            span: resolver.getSourceSpan(elementAnnotation.element));
        return false;
      }
      // A direct subclass of [classReflectable], all OK.
      return true;
    }

    Element element = elementAnnotation.element;
    // TODO(eernst): Currently we only handle constructor expressions
    // and simple identifiers.  May be generalized later.
    if (element is ConstructorElement) {
      bool isOk =
          checkInheritance(element.enclosingElement.type, focusClass.type);
      return isOk ? element.enclosingElement.type.element : null;
    } else if (element is PropertyAccessorElement) {
      PropertyInducingElement variable = element.variable;
      // Surprisingly, we have to use [ConstTopLevelVariableElementImpl]
      // here (or a similar type).  This is because none of the "public name"
      // types (types whose name does not end in `..Impl`) declare the getter
      // `evaluationResult`.  Another possible choice of type would be
      // [VariableElementImpl], but with that one we would have to test
      // `isConst` as well.
      if (variable is ConstTopLevelVariableElementImpl) {
        EvaluationResultImpl result = variable.evaluationResult;
        bool isOk = checkInheritance(result.value.type, focusClass.type);
        return isOk ? result.value.type.element : null;
      } else {
        // Not a const top level variable, not relevant.
        return null;
      }
    }
    // Otherwise [element] is some other construct which is not supported.
    //
    // TODO(eernst): We need to consider whether there could be some other
    // syntactic constructs that are incorrectly assumed by programmers to
    // be usable with Reflectable.  Currently, such constructs will silently
    // have no effect; it might be better to emit a diagnostic message (a
    // hint?) in order to notify the programmer that "it does not work".
    // The trade-off is that such constructs may have been written by
    // programmers who are doing something else, intentionally.  To emit a
    // diagnostic message, we must check whether there is a Reflectable
    // somewhere inside this syntactic construct, and then emit the message
    // in cases that we "consider likely to be misunderstood".
    return null;
  }

  /// Finds all the methods in the class and all super-classes.
  Iterable<MethodElement> allMethods(ClassElement classElement) {
    List<MethodElement> result = new List<MethodElement>();
    result.addAll(classElement.methods);
    classElement.allSupertypes.forEach((InterfaceType superType) {
      result.addAll(superType.methods);
    });
    return result;
  }

  Iterable<MethodElement> declaredMethods(
      ClassElement classElement, Capabilities capabilities) {
    return classElement.methods.where((MethodElement method) {
      if (method.isStatic) {
        // TODO(sigurdm): Ask capability about support.
        return true;
      } else {
        return capabilities.supportsInstanceInvoke(method.name);
      }
    });
  }

  Iterable<MethodElement> invocableInstanceMethods(
      ClassElement classElement, Capabilities capabilities) {
    return allMethods(classElement).where((MethodElement method) {
      MethodDeclaration methodDeclaration = method.node;
      // TODO(eernst): We currently ignore method declarations when
      // they are operators. One issue is generation of code (which
      // does not work if we go ahead naively).
      if (methodDeclaration.isOperator) return false;
      String methodName = methodDeclaration.name.name;
      return capabilities.supportsInstanceInvoke(methodName);
    });
  }

  /// Returns a [ReflectionWorld] instantiated with all the reflectors seen by
  /// [resolver] and all classes annotated by them.
  ///
  /// TODO(eernst): Make sure it works also when other packages are being
  /// used by the target program which have already been transformed by
  /// this transformer (e.g., there would be a clash on the use of
  /// reflectableClassId with values near 1000 for more than one class).
  ReflectionWorld _computeWorld(LibraryElement reflectableLibrary) {
    ReflectionWorld world = new ReflectionWorld(reflectableLibrary);
    Map<ClassElement, ReflectorDomain> domains =
        new Map<ClassElement, ReflectorDomain>();
    ClassElement focusClass = _findReflectableClassElement(reflectableLibrary);
    if (focusClass == null) {
      return null;
    }
    LibraryElement capabilityLibrary =
        resolver.getLibraryByName("reflectable.capability");
    for (LibraryElement library in resolver.libraries) {
      for (CompilationUnitElement unit in library.units) {
        for (FunctionElement function in unit.functions) {
          namer.registerName(function.name);
        }
        for (PropertyAccessorElement accessor in unit.accessors) {
          namer.registerName(accessor.name);
        }
        for (TopLevelVariableElement variable in unit.topLevelVariables) {
          namer.registerName(variable.name);
        }
        for (TopLevelVariableElement variable in unit.topLevelVariables) {
          namer.registerName(variable.name);
        }
        for (ClassElement enumClass in unit.enums) {
          namer.registerName(enumClass.name);
        }
        for (ClassElement enumClass in unit.enums) {
          namer.registerName(enumClass.name);
        }
        for (ClassElement type in unit.types) {
          namer.registerName(type.name);
          for (ElementAnnotation metadatum in type.metadata) {
            ClassElement reflector =
                _getReflectableAnnotation(metadatum, focusClass);
            if (reflector == null) continue;
            ReflectorDomain domain = domains.putIfAbsent(reflector, () {
              Capabilities capabilities =
                  _capabilitiesOf(capabilityLibrary, reflector);
              return new ReflectorDomain(
                  reflector, new List<ClassDomain>(), capabilities);
            });
            List<MethodElement> instanceMethods =
                invocableInstanceMethods(type, domain.capabilities).toList();
            List<MethodElement> declaredMethodsOfClass =
                declaredMethods(type, domain.capabilities).toList();
            domain.annotatedClasses.add(new ClassDomain(
                type, instanceMethods, declaredMethodsOfClass, domain));
          }
        }
      }
    }
    domains.values.forEach(_collectMissingImports);

    world.reflectors.addAll(domains.values.toList());
    world.computeNames(namer);
    return world;
  }

  /// Finds all the libraries of classes annotated by the `domain.reflector`,
  /// thus specifying which `import` directives we
  /// need to add during code transformation.
  /// These are added to `domain.missingImports`.
  void _collectMissingImports(ReflectorDomain domain) {
    LibraryElement metadataLibrary = domain.reflector.library;
    for (ClassDomain classData in domain.annotatedClasses) {
      LibraryElement annotatedLibrary = classData.classElement.library;
      if (metadataLibrary != annotatedLibrary) {
        domain.missingImports.add(annotatedLibrary);
      }
    }
  }

  /// Perform `replace` on the given [sourceManager] such that the
  /// URI of the import/export of `reflectableLibrary` specified by
  /// [uriReferencedElement] is replaced by the given [newUri]; it is
  /// required that `uriReferencedElement is` either an `ImportElement`
  /// or an `ExportElement`.
  void _replaceUriReferencedElement(SourceManager sourceManager,
      UriReferencedElement uriReferencedElement, String newUri) {
    // This is intended to work for imports and exports only, i.e., not
    // for compilation units. When this constraint is satisfied, `.node`
    // will return a `NamespaceDirective`.
    assert(uriReferencedElement is ImportElement ||
        uriReferencedElement is ExportElement);
    int uriStart = uriReferencedElement.uriOffset;
    if (uriStart == -1) {
      // Encountered a synthetic element.  We do not expect imports or
      // exports of reflectable to be synthetic, so we make it an error.
      throw new UnimplementedError(
          "Encountered synthetic import of reflectable");
    }
    int uriEnd = uriReferencedElement.uriEnd;
    // If we have `uriStart != -1 && uriEnd == -1` then there is a bug
    // in the implementation of [uriReferencedElement].
    assert(uriEnd != -1);

    int elementOffset = uriReferencedElement.node.offset;
    String elementType;
    if (uriReferencedElement is ExportElement) {
      elementType = "Export";
    } else if (uriReferencedElement is ImportElement) {
      elementType = "Import";
    } else {
      // Yes, we used `assert`, but that's ignored in production mode. So we
      // must still do something if we have neither an export nor an import.
      elementType = "UriReferencedElement";
    }
    sourceManager.replace(elementOffset, elementOffset,
        "// $elementType modified by the reflectable transformer:\n");
    sourceManager.replace(uriStart, uriEnd, "'$newUri'");
  }

  /// Returns the name of the given [classElement].  Note that we may have
  /// multiple classes in a program with the same name in this sense,
  /// because they can be in different libraries, and clashes may have
  /// been avoided because the classes are private, because no single
  /// library imports both, or because all importers of both use prefixes
  /// on one or both of them to resolve the name clash.  Hence, name
  /// clashes must be taken into account when using the return value.
  String _classElementName(ClassDomain classDomain) =>
      classDomain.classElement.node.name.name.toString();

  static const String generatedComment = "// Generated";

  ImportElement _findLastImport(LibraryElement library) {
    if (library.imports.isNotEmpty) {
      ImportElement importElement = library.imports.lastWhere(
          (importElement) => importElement.node != null, orElse: () => null);
      if (importElement != null) {
        // Found an import element with a node (i.e., a non-synthetic one).
        return importElement;
      } else {
        // No non-synthetic imports.
        return null;
      }
    }
    // library.imports.isEmpty
    return null;
  }

  ExportElement _findFirstExport(LibraryElement library) {
    if (library.exports.isNotEmpty) {
      ExportElement exportElement = library.exports.firstWhere(
          (exportElement) => exportElement.node != null, orElse: () => null);
      if (exportElement != null) {
        // Found an export element with a node (i.e., a non-synthetic one)
        return exportElement;
      } else {
        // No non-synthetic exports.
        return null;
      }
    }
    // library.exports.isEmpty
    return null;
  }

  /// Find a suitable index for insertion of additional import directives
  /// into [targetLibrary].
  int _newImportIndex(LibraryElement targetLibrary) {
    // Index in [source] where the new import directive is inserted, we
    // use 0 as the default placement (at the front of the file), but
    // make a heroic attempt to find a better placement first.
    int index = 0;
    ImportElement importElement = _findLastImport(targetLibrary);
    if (importElement != null) {
      index = importElement.node.end;
    } else {
      // No non-synthetic import directives present.
      ExportElement exportElement = _findFirstExport(targetLibrary);
      if (exportElement != null) {
        // Put the new import before the exports
        index = exportElement.node.offset;
      } else {
        // No non-synthetic import nor export directives present.
        LibraryDirective libraryDirective =
            targetLibrary.definingCompilationUnit.node.directives.firstWhere(
                (directive) => directive is LibraryDirective,
                orElse: () => null);
        if (libraryDirective != null) {
          // Put the new import after the library name directive.
          index = libraryDirective.end;
        } else {
          // No library directive either, keep index == 0.
        }
      }
    }
    return index;
  }

  /// Transform all imports of [reflectableLibrary] to import the thin
  /// outline version (`static_reflectable.dart`), such that we do not
  /// indirectly import `dart:mirrors`.  Remove all exports of
  /// [reflectableLibrary] and emit a diagnostic message about the fact
  /// that such an import was encountered (and it violates the constraints
  /// of this package, and hence we must remove it).  All the operations
  /// are using [targetLibrary] to find the source code offsets, and using
  /// [sourceManager] to actually modify the source code.  We require that
  /// there is an import which has no `show` and no `hide` clause (this is
  /// a potentially temporary restriction, we may implement support for
  /// more cases later on, but for now we just prohibit `show` and `hide`).
  /// The returned value is the [PrefixElement] that is used to give
  /// [reflectableLibrary] a prefix; `null` is returned if there is
  /// no such prefix.
  PrefixElement _transformSourceDirectives(LibraryElement reflectableLibrary,
      LibraryElement targetLibrary, SourceManager sourceManager) {
    List<ImportElement> editedImports = <ImportElement>[];

    void replaceUriOfReflectable(UriReferencedElement element) {
      _replaceUriReferencedElement(sourceManager, element,
          "package:reflectable/static_reflectable.dart");
      if (element is ImportElement) editedImports.add(element);
    }

    // Exemption: We do not transform 'reflectable_implementation.dart'.
    if ("$targetLibrary" == "reflectable.src.reflectable_implementation") {
      return null;
    }

    // Transform all imports and exports of reflectable.
    targetLibrary.imports
        .where((element) => element.importedLibrary == reflectableLibrary)
        .forEach(replaceUriOfReflectable);
    targetLibrary.exports
        .where((element) => element.exportedLibrary == reflectableLibrary)
        .forEach(replaceUriOfReflectable);

    // If [reflectableLibrary] is never imported then it has no prefix.
    if (editedImports.isEmpty) return null;

    bool isOK(ImportElement importElement) {
      // We do not support a deferred load of Reflectable.
      if (importElement.isDeferred) {
        logger.error(errors.LIBRARY_UNSUPPORTED_DEFERRED,
            span: resolver.getSourceSpan(editedImports[0]));
        return false;
      }
      // We do not currently support `show` nor `hide` clauses,
      // otherwise this one is OK.
      if (importElement.combinators.isEmpty) return true;
      for (NamespaceCombinator combinator in importElement.combinators) {
        if (combinator is HideElementCombinator) {
          logger.error(errors.LIBRARY_UNSUPPORTED_HIDE,
              span: resolver.getSourceSpan(editedImports[0]));
        }
        assert(combinator is ShowElementCombinator);
        logger.error(errors.LIBRARY_UNSUPPORTED_SHOW,
            span: resolver.getSourceSpan(editedImports[0]));
      }
      return false;
    }

    // Check the imports, report problems with them if any, and try
    // to select the prefix of a good import to return.  If no good
    // imports are found we return `null`.
    PrefixElement goodPrefix = null;
    for (ImportElement importElement in editedImports) {
      if (isOK(importElement)) goodPrefix = importElement.prefix;
    }
    return goodPrefix;
  }

  /// Transform the given [reflector] by adding features needed to
  /// implement the abstract methods in Reflectable from the library
  /// `static_reflectable.dart`.  Use [sourceManager] to perform the
  /// actual source code modification.  The [annotatedClasses] is the
  /// set of reflector-annotated class whose metadata includes an
  /// instance of the reflector, i.e., the set of classes whose
  /// instances [reflector] must provide reflection for.
  void _transformReflectorClass(ReflectorDomain reflector,
      SourceManager sourceManager, PrefixElement prefixElement) {
    // A ClassElement can be associated with an [EnumDeclaration], but
    // this is not supported for a Reflector.
    if (reflector.reflector.node is EnumDeclaration) {
      logger.error(errors.IS_ENUM,
          span: resolver.getSourceSpan(reflector.reflector));
    }
    // Otherwise it is a ClassDeclaration.
    ClassDeclaration classDeclaration = reflector.reflector.node;
    int insertionIndex = classDeclaration.rightBracket.offset;

    // Now insert generated material at insertionIndex.

    void insert(String code) {
      sourceManager.insert(insertionIndex, "$code\n");
    }

    String reflectCaseOfClass(ClassDomain classDomain) => """
    if (reflectee.runtimeType == ${_classElementName(classDomain)}) {
      return new ${classDomain.staticInstanceMirrorName}(reflectee);
    }
""";

    String reflectCases = ""; // Accumulates the body of the `reflect` method.

    // In front of all the generated material, indicate that it is generated.
    insert("  $generatedComment: Rest of class");

    // Add each supported case to [reflectCases].
    reflector.annotatedClasses.forEach((ClassDomain annotatedClass) {
      reflectCases += reflectCaseOfClass(annotatedClass);
    });
    reflectCases += "    throw new "
        "UnimplementedError"
        "(\"`reflect` on unexpected object '\$reflectee'\");\n";

    String prefix = prefixElement == null ? "" : "${prefixElement.name}.";
    insert("  ${prefix}InstanceMirror "
        "reflect(Object reflectee) {\n$reflectCases  }");
    // Add failure case to [reflectCases]: No matching classes, so the
    // user is asking for a kind of reflection that was not requested,
    // which is a runtime error.
    // TODO(eernst, sigurdm): throw NoSuchCapability if no match was found.
    List<String> annotatedClassesStrings = reflector.annotatedClasses
        .map((ClassDomain x) => "new ${x.staticClassMirrorName}()")
        .toList();

    List<String> reflectTypeCases = [];
    // TODO(eernst, sigurdm): This is a linear search. Might want to make
    // smarter lookup if benchmarks require it.
    for (ClassDomain classDomain in reflector.annotatedClasses) {
      reflectTypeCases.add("if (type == ${classDomain.classElement.name}) "
          "return new ${classDomain.staticClassMirrorName}();");
    }
    reflectTypeCases.add("throw new ${prefix}NoSuchCapabilityError("
        "'No capability to reflect on type \$type.');");

    insert("""
  ${prefix}ClassMirror reflectType(Type type) {
    ${reflectTypeCases.join("\n    else ")}
  }""");
    // TODO(sigurdm, eernst): Model type arguments. Here we could just use the
    // trivial arguments, because the type-literal is implicitly instantiated
    // with all `dynamic`.

    insert("""
  Iterable<${prefix}ClassMirror> get annotatedClasses {
    return [${annotatedClassesStrings.join(", ")}];
  }""");
  }

  /// Returns the source code for the reflection free subclass of
  /// [ClassMirror] which is specialized for a `reflectedType` which
  /// is the class modeled by [classElement].
  String _staticClassMirrorCode(ClassDomain classDomain) {
    String declarationsString = classDomain.declarationsString;
    String simpleName = classDomain.classElement.name;
    // When/if we have library-mirrors there could be a generic implementation:
    // String get qualifiedName => "${owner.qualifiedName}.${simpleName}";
    String qualifiedName =
        "${classDomain.classElement.library.name}.$simpleName";
    return """
class ${classDomain.staticClassMirrorName} extends ClassMirrorUnimpl {
  final String simpleName = "$simpleName";
  final String qualifiedName = "$qualifiedName";

  Map<String, MethodMirror> _declarationsCache;

  Map<String, MethodMirror> get declarations {
    if (_declarationsCache == null) {
      _declarationsCache = new UnmodifiableMapView($declarationsString);
    }
    return _declarationsCache;
  }
}
""";
  }

  /// Perform some very simple steps that are consistent with Dart
  /// semantics for the evaluation of constant expressions, such that
  /// information about the value of a given `const` variable can be
  /// obtained.  It is intended to help recognizing values of type
  /// [ReflectCapability], so we only cover cases needed for that.
  /// In particular, we cover lookup (e.g., with `const x = e` we can
  /// see that the value of `x` is `e`, and that step may be repeated
  /// if `e` is an [Identifier], or in general if it has a shape that
  /// is covered); similarly, `C.y` is evaluated to `42` if `C` is a
  /// class containing a declaration like `static const y = 42`. We do
  /// not perform any kind of arithmetic simplification.
  ///
  /// [context] is for error-reporting
  Expression _constEvaluate(Expression expression) {
    // [Identifier] can be [PrefixedIdentifier] and [SimpleIdentifier]
    // (and [LibraryIdentifier], but that is only used in [PartOfDirective],
    // so even when we use a library prefix like in `myLibrary.MyClass` it
    // will be a [PrefixedIdentifier] containing two [SimpleIdentifier]s).
    if (expression is SimpleIdentifier) {
      if (expression.staticElement is PropertyAccessorElement) {
        PropertyAccessorElement propertyAccessor = expression.staticElement;
        PropertyInducingElement variable = propertyAccessor.variable;
        // We expect to be called only on `const` expressions.
        if (!variable.isConst) {
          logger.error(errors.SUPER_ARGUMENT_NON_CONST,
              span: resolver.getSourceSpan(expression.staticElement));
        }
        VariableDeclaration variableDeclaration = variable.node;
        return _constEvaluate(variableDeclaration.initializer);
      }
    }
    if (expression is PrefixedIdentifier) {
      SimpleIdentifier simpleIdentifier = expression.identifier;
      if (simpleIdentifier.staticElement is PropertyAccessorElement) {
        PropertyAccessorElement propertyAccessor =
            simpleIdentifier.staticElement;
        PropertyInducingElement variable = propertyAccessor.variable;
        // We expect to be called only on `const` expressions.
        if (!variable.isConst) {
          logger.error(errors.SUPER_ARGUMENT_NON_CONST,
              span: resolver.getSourceSpan(expression.staticElement));
        }
        VariableDeclaration variableDeclaration = variable.node;
        return _constEvaluate(variableDeclaration.initializer);
      }
    }
    // No evaluation steps succeeded, return [expression] unchanged.
    return expression;
  }

  /// Returns the [ReflectCapability] denoted by the given [initializer].
  ReflectCapability _capabilityOfExpression(
      LibraryElement capabilityLibrary, Expression expression) {
    Expression evaluatedExpression = _constEvaluate(expression);

    DartType dartType = evaluatedExpression.bestType;
    // The AST must have been resolved at this point.
    assert(dartType != null);

    // We insist that the type must be a class, and we insist that it must
    // be in the given `capabilityLibrary` (because we could never know
    // how to interpret the meaning of a user-written capability class, so
    // users cannot write their own capability classes).
    if (dartType.element is! ClassElement) {
      if (dartType.element.source != null) {
        logger.error(errors.applyTemplate(errors.SUPER_ARGUMENT_NON_CLASS, {
          "type": dartType.displayName
        }), span: resolver.getSourceSpan(dartType.element));
      } else {
        logger.error(errors.applyTemplate(
            errors.SUPER_ARGUMENT_NON_CLASS, {"type": dartType.displayName}));
      }
    }
    ClassElement classElement = dartType.element;
    if (classElement.library != capabilityLibrary) {
      logger.error(errors.applyTemplate(errors.SUPER_ARGUMENT_WRONG_LIBRARY, {
        "library": capabilityLibrary,
        "element": classElement
      }), span: resolver.getSourceSpan(classElement));
    }

    ReflectCapability processInstanceCreationExpression(
        InstanceCreationExpression expression, String expectedConstructorName,
        ReflectCapability defaultCapability,
        ReflectCapability factory(String arg)) {
      // The [expression] came from a static evaluation of a const,
      // could never be a non-const.
      assert(expression.isConst);
      // We do not invoke some other constructor (in that case
      // [expression] would have had a different type).
      assert(expression.constructorName == expectedConstructorName);
      // There is only one constructor in that class, with one argument.
      assert(expression.argumentList.length == 1);
      Expression argument = expression.argumentList.arguments[0];
      if (argument is SimpleStringLiteral) {
        if (argument.value == "") return defaultCapability;
        return factory(argument.value);
      }
      // TODO(eernst): Deny support for all other kinds of arguments, or
      // implement some more cases.
      throw new UnimplementedError("$expression not yet supported!");
    }

    switch (classElement.name) {
      case "_NameCapability":
        return nameCapability;
      case "_ClassifyCapability":
        return classifyCapability;
      case "_MetadataCapability":
        return metadataCapability;
      case "_TypeRelationsCapability":
        return typeRelationsCapability;
      case "_OwnerCapability":
        return ownerCapability;
      case "_DeclarationsCapability":
        return declarationsCapability;
      case "_UriCapability":
        return uriCapability;
      case "_LibraryDependenciesCapability":
        return libraryDependenciesCapability;

      case "InstanceInvokeCapability":
        if (evaluatedExpression is SimpleIdentifier &&
            evaluatedExpression.name == "instanceInvokeCapability") {
          return instanceInvokeCapability;
        }
        // In simple cases, the [evaluatedExpression] is directly an
        // invocation of the constructor in this class.
        if (evaluatedExpression is InstanceCreationExpression) {
          return processInstanceCreationExpression(evaluatedExpression,
              "InstanceInvokeCapability", instanceInvokeCapability,
              (String arg) => new InstanceInvokeCapability(arg));
        }
        // TODO(eernst): other cases
        throw new UnimplementedError("$expression not yet supported!");
      case "InstanceInvokeMetaCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "StaticInvokeCapability":
        if (evaluatedExpression is SimpleIdentifier &&
            evaluatedExpression.name == "staticInvokeCapability") {
          return staticInvokeCapability;
        }
        // In simple cases, the [evaluatedExpression] is directly an
        // invocation of the constructor in this class.
        if (evaluatedExpression is InstanceCreationExpression) {
          return processInstanceCreationExpression(evaluatedExpression,
              "StaticInvokeCapability", staticInvokeCapability,
              (String arg) => new StaticInvokeCapability(arg));
        }
        // TODO(eernst): other cases
        throw new UnimplementedError("$expression not yet supported!");
      case "StaticInvokeMetaCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "NewInstanceCapability":
        if (evaluatedExpression is SimpleIdentifier &&
            evaluatedExpression.name == "newInstanceCapability") {
          return newInstanceCapability;
        }
        // In simple cases, the [evaluatedExpression] is directly an
        // invocation of the constructor in this class.
        if (evaluatedExpression is InstanceCreationExpression) {
          return processInstanceCreationExpression(evaluatedExpression,
              "NewInstanceCapability", newInstanceCapability,
              (String arg) => newInstanceCapability(arg));
        }
        // TODO(eernst): other cases
        throw new UnimplementedError("$expression not yet supported!");
      case "NewInstanceMetaCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "TypeCapability":
        if (evaluatedExpression is SimpleIdentifier &&
            evaluatedExpression.name == "typeCapability") {
          return typeCapability;
        }
        if (evaluatedExpression is SimpleIdentifier &&
            evaluatedExpression.name == "localTypeCapability") {
          return localTypeCapability;
        }
        // TODO(eernst): problem, how can we create a Type object
        // corresponding to the one denoted by part of the given
        // evaluatedExpression?
        throw new UnimplementedError(
            "$classElement with an argument not yet supported!");
      case "InvokingCapability":
        if (evaluatedExpression is SimpleIdentifier &&
            evaluatedExpression.name == "invokingCapability") {
          return invokingCapability;
        }
        // In simple cases, the [evaluatedExpression] is directly an
        // invocation of the constructor in this class.
        if (evaluatedExpression is InstanceCreationExpression) {
          return processInstanceCreationExpression(evaluatedExpression,
              "InvokingCapability", invokingCapability,
              (String arg) => new InvokingCapability(arg));
        }
        // TODO(eernst): other cases.
        throw new UnimplementedError("$classElement not yet supported!");
      case "InvokingMetaCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "TypingCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "SubtypeQuantifyCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "AdmitSubtypeCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "GlobalQuantifyCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      case "GlobalQuantifyMetaCapability":
        // TODO(eernst)
        throw new UnimplementedError("$classElement not yet supported!");
      default:
        throw new UnimplementedError("Unexpected capability $classElement");
    }
  }

  /// Returns the list of Capabilities given given as a superinitializer by the
  /// reflector.
  Capabilities _capabilitiesOf(
      LibraryElement capabilityLibrary, ClassElement reflector) {
    List<ConstructorElement> constructors = reflector.constructors;
    // The superinitializer must be unique, so there must be 1 constructor.
    assert(constructors.length == 1);
    ConstructorElement constructorElement = constructors[0];
    // It can only be a const constructor, because this class has been
    // used for metadata; it is a bug in the transformer if not.
    // It must also be a default constructor.
    assert(constructorElement.isConst);
    // TODO(eernst): Ensure that some other location in this transformer
    // checks that the reflector class constructor is indeed a default
    // constructor, such that this can be a mere assertion rather than
    // a user-oriented error report.
    assert(constructorElement.isDefaultConstructor);
    NodeList<ConstructorInitializer> initializers =
        constructorElement.node.initializers;

    if (initializers.length == 0) {
      // Degenerate case: Without initializers, we will obtain a reflector
      // without any capabilities, which is not useful in practice. We do
      // have this degenerate case in tests "just because we can", and
      // there is no technical reason to prohibit it, so we will handle
      // it here.
      return new Capabilities(<ReflectCapability>[]);
    }
    // TODO(eernst): Ensure again that this can be a mere assertion.
    assert(initializers.length == 1);

    // Main case: the initializer is exactly one element. We must
    // handle two cases: `super(..)` and `super.fromList(<_>[..])`.
    SuperConstructorInvocation superInvocation = initializers[0];

    ReflectCapability capabilityOfExpression(Expression expression) {
      return _capabilityOfExpression(capabilityLibrary, expression);
    }

    if (superInvocation.constructorName == null) {
      // Subcase: `super(..)` where 0..k arguments are accepted for some
      // k that we need not worry about here.
      NodeList<Expression> arguments = superInvocation.argumentList.arguments;
      return new Capabilities(arguments.map(capabilityOfExpression).toList());
    }
    assert(superInvocation.constructorName == "fromList");

    // Subcase: `super.fromList(const <..>[..])`.
    NodeList<Expression> arguments = superInvocation.argumentList.arguments;
    assert(arguments.length == 1);
    ListLiteral listLiteral = arguments[0];
    NodeList<Expression> expressions = listLiteral.elements;
    return new Capabilities(expressions.map(capabilityOfExpression).toList());
  }

  /// Returns a [String] containing generated code for the `invoke`
  /// method of the static `InstanceMirror` class corresponding to
  /// the given [classElement], bounded by the permissions given
  /// in [capabilities].
  String _staticInstanceMirrorInvokeCode(ClassDomain classDomain) {
    List<String> methodCases = new List<String>();
    for (MethodElement methodElement in classDomain.invokableMethods) {
      String methodName = methodElement.name;
      methodCases.add("if (memberName == '$methodName') {"
          "method = reflectee.$methodName; }");
    }
    // TODO(eernst, sigurdm): Create an instance of [Invocation] in user code.
    methodCases.add("if (instanceMethodFilter.hasMatch(memberName)) {"
        "throw new UnimplementedError('Should call noSuchMethod'); }");
    methodCases.add("{ throw new NoSuchInvokeCapabilityError("
        "reflectee, memberName, positionalArguments, namedArguments); }");
    // Handle the cases where permission is given even though there is
    // no corresponding method. One case is where _all_ methods can be
    // invoked. Another case is when the user has specified a name
    // `"foo"` and a reflector `@reflector` allowing for invocation
    // of `foo`, and then attached `@reflector` to a class that does
    // not define nor inherit any method `foo`.  In these cases we
    // invoke `noSuchMethod`.
    // We have the capability to invoke _all_ methods, and since the
    // requested one does not fit, it should give rise to an invocation
    // of `noSuchMethod`.
    // TODO(eernst): Cf. the problem mentioned below in relation to the
    // invocation of `noSuchMethod`: It might be a good intermediate
    // solution to create our own implementation of Invocation holding
    // the information mentioned below; it would not be able to support
    // `delegate`, but for a broad range of purposes it might still be
    // useful.
    // Even if we make our own class, we would have to have a table to construct
    // the symbol from the string.
    return """
  Object invoke(String memberName,
                List positionalArguments,
                [Map<Symbol, dynamic> namedArguments]) {
    Function method;
    ${methodCases.join("\n    else ")}
    return Function.apply(method, positionalArguments, namedArguments);
  }
""";
  }

  String instanceMethodFilter(Capabilities capabilities) {
    String r = capabilities.instanceMethodsFilterRegexpString();
    return """
  RegExp instanceMethodFilter = new RegExp(r"$r");
""";
  }

  /// Returns the source code for the reflection free subclass of
  /// [InstanceMirror] which is specialized for a `reflectee` which
  /// is an instance of the class modeled by [classElement].  The
  /// generated code will provide support as specified by
  /// [capabilities].
  String _staticInstanceMirrorCode(ClassDomain classDomain) {
    // The `rest` of the code is the entire body of the static mirror class,
    // except for the declaration of `reflectee`, and a constructor.
    String rest = "";
    rest += instanceMethodFilter(classDomain.reflectorDomain.capabilities);
    rest += _staticInstanceMirrorInvokeCode(classDomain);
    rest += "  ClassMirror get type => "
        "new ${classDomain.staticClassMirrorName}();\n";
    // TODO(eernst): add code for other mirror methods than `invoke`.
    return """
class ${classDomain.staticInstanceMirrorName} extends InstanceMirrorUnimpl {
  final ${_classElementName(classDomain)} reflectee;
  ${classDomain.staticInstanceMirrorName}(this.reflectee);
$rest}
""";
  }

  /// Returns the result of transforming the given [source] code, which is
  /// assumed to be the contents of the file associated with the
  /// [targetLibrary], which is the library currently being transformed.
  /// [reflectableClasses] models the define/use relation where
  /// reflector classes declare material for use as metadata,
  /// and reflector-annotated classes use that material.
  /// [libraryToAssetMap] is used in the generation of `import` directives
  /// that enable reflector classes to see static mirror
  /// classes that it must be able to `reflect` which are declared in
  /// other libraries; [missingImports] lists the required imports which
  /// are not already present, i.e., the ones that must be added.
  /// [reflectableLibrary] is assumed to be the library that declares the
  /// class [Reflectable].
  ///
  /// TODO(eernst): The transformation has only been implemented
  /// partially at this time.
  ///
  /// TODO(eernst): Note that this function uses instances of [AstNode]
  /// and [Token] to get the correct offset into the [source] of specific
  /// constructs in the code.  This is potentially costly, because this
  /// (intermediate) parsing related information may have been evicted
  /// since parsing, and the source code will then be parsed again.
  /// However, we do not have an alternative unless we want to parse
  /// everything ourselves.  But it would be useful to be able to give
  /// barback a hint that this information should preferably be preserved.
  String _transformSource(
      ReflectionWorld world, LibraryElement targetLibrary, String source) {

    // Used to manage replacements of code snippets by other code snippets
    // in [source].
    SourceManager sourceManager = new SourceManager(source);
    sourceManager.insert(
        0, "// This file has been transformed by reflectable.\n");

    // Used to accumulate generated classes, maps, etc.
    String generatedSource = "";

    List<ClassDomain> reflectableClasses =
        world.annotatedClassesOfLibrary(targetLibrary).toList();

    // Transform selected existing elements in [targetLibrary].
    PrefixElement prefixElement = _transformSourceDirectives(
        world.reflectableLibrary, targetLibrary, sourceManager);
    world.reflectorsOfLibrary(targetLibrary).forEach((ReflectorDomain domain) {
      _transformReflectorClass(domain, sourceManager, prefixElement);
    });

    for (ClassDomain classDomain in reflectableClasses) {
      // Generate static mirror classes.
      generatedSource += _staticClassMirrorCode(classDomain) +
          "\n" +
          _staticInstanceMirrorCode(classDomain);
    }

    // If needed, add an import such that generated classes can see their
    // superclasses.  Note that we make no attempt at following the style guide,
    // e.g., by keeping the imports sorted.  Also add imports such that each
    // reflector class can see all the classes annotated with it
    // (such that the implementation of `reflect` etc. will work).
    String newImport = generatedSource.length == 0
        ? ""
        : "\nimport 'package:reflectable/src/mirrors_unimpl.dart';";
    AssetId targetId = resolver.getSourceAssetId(targetLibrary);
    for (ReflectorDomain domain in world.reflectors) {
      if (domain.reflector.library == targetLibrary) {
        for (LibraryElement importToAdd in domain.missingImports) {
          Uri importUri = resolver.getImportUri(importToAdd, from: targetId);
          newImport += "\nimport '$importUri';";
        }
      }
    }

    if (!newImport.isEmpty) {
      // Insert the import directive at the chosen location.
      int newImportIndex = _newImportIndex(targetLibrary);
      sourceManager.insert(newImportIndex, newImport);
    }
    return generatedSource.length == 0
        ? sourceManager.source
        : "${sourceManager.source}\n"
        "$generatedComment: Rest of file\n\n"
        "$generatedSource";
  }

  resetUsedNames() {
    namer = new Namer();
  }

  /// Performs the transformation which eliminates all imports of
  /// `package:reflectable/reflectable.dart` and instead provides a set of
  /// statically generated mirror classes.
  Future apply(
      AggregateTransform aggregateTransform, List<String> entryPoints) async {
    logger = aggregateTransform.logger;
    // The type argument in the return type is omitted because the
    // documentation on barback and on transformers do not specify it.
    Resolvers resolvers = new Resolvers(dartSdkDirectory);

    List<Asset> assets = await aggregateTransform.primaryInputs.toList();

    if (assets.isEmpty) {
      // It is a warning, not an error, to have nothing to transform.
      logger.warning("Warning: Nothing to transform");
      // Terminate with a non-failing status code to the OS.
      exit(0);
    }

    for (String entryPoint in entryPoints) {
      // Find the asset corresponding to [entryPoint]
      Asset entryPointAsset = assets.firstWhere(
          (Asset asset) => asset.id.path.endsWith(entryPoint),
          orElse: () => null);
      if (entryPointAsset == null) {
        aggregateTransform.logger
            .warning("Error: Missing entry point: $entryPoint");
        continue;
      }
      Transform wrappedTransform =
          new AggregateTransformWrapper(aggregateTransform, entryPointAsset);
      resetUsedNames(); // Each entry point has a closed world.

      resolver = await resolvers.get(wrappedTransform);
      LibraryElement reflectableLibrary =
          resolver.getLibraryByName("reflectable.reflectable");
      if (reflectableLibrary == null) {
        // Stop and do not consumePrimary, i.e., let the original source
        // pass through without changes.
        continue;
      }
      ReflectionWorld world = _computeWorld(reflectableLibrary);
      if (world == null) continue;
      // An entry `assetId -> entryPoint` in this map means that `entryPoint`
      // has been transforming `assetId`.
      // This is only for purposes of better diagnostic messages.
      Map<AssetId, String> transformedViaEntryPoint =
          new Map<AssetId, String>();

      Map<LibraryElement, String> libraryPaths =
          new Map<LibraryElement, String>();

      for (Asset asset in assets) {
        LibraryElement targetLibrary = resolver.getLibrary(asset.id);
        libraryPaths[targetLibrary] = asset.id.path;
      }
      for (Asset asset in assets) {
        LibraryElement targetLibrary = resolver.getLibrary(asset.id);
        if (targetLibrary == null) continue;

        List<ReflectorDomain> reflectablesInLibary =
            world.reflectorsOfLibrary(targetLibrary).toList();

        if (reflectablesInLibary.isNotEmpty) {
          if (transformedViaEntryPoint.containsKey(asset.id)) {
            // It is not safe to transform a library that contains a
            // reflector relative to multiple entry points, because each
            // entry point defines a set of libraries which amounts to the
            // complete program, and different sets of libraries correspond to
            // potentially different sets of static mirror classes as well as
            // potentially different sets of added import directives. Hence, we
            // must reject the transformation in cases where there is such a
            // clash.
            //
            // TODO(eernst): It would actually be safe to allow for multiple
            // transformations of the same library done relative to different
            // entry points _if_ the result of those transformations were the
            // same (for instance, if both of them left that library unchanged)
            // but we do not currently detect this case. This means that we
            // might be able to allow for the transformation of more packages
            // than the ones that we accept now, that is, it is a safe future
            // enhancement to detect such a case and allow it.
            String previousEntryPoint = transformedViaEntryPoint[asset.id];

            aggregateTransform.logger.error(
                "Error: $asset is transformed twice, "
                " both via $entryPoint and $previousEntryPoint.");
            continue;
          }
          transformedViaEntryPoint[asset.id] = entryPoint;
        }
        String source = await asset.readAsString();
        String transformedSource =
            _transformSource(world, targetLibrary, source);
        // Transform user provided code.
        aggregateTransform.consumePrimary(asset.id);
        wrappedTransform
            .addOutput(new Asset.fromString(asset.id, transformedSource));
      }
      resolver.release();
    }
  }
}

/// Wrapper of `AggregateTransform` of type `Transform`, allowing us to
/// get a `Resolver` for a given `AggregateTransform` with a given
/// selection of a primary entry point.
/// TODO(eernst): We will just use this temporarily; code_transformers
/// may be enhanced to support a variant of Resolvers.get that takes an
/// [AggregateTransform] and an [Asset] rather than a [Transform], in
/// which case we can drop this class and use that method.
class AggregateTransformWrapper implements Transform {
  final AggregateTransform _aggregateTransform;
  final Asset primaryInput;
  AggregateTransformWrapper(this._aggregateTransform, this.primaryInput);
  TransformLogger get logger => _aggregateTransform.logger;
  Future<Asset> getInput(AssetId id) => _aggregateTransform.getInput(id);
  Future<String> readInputAsString(AssetId id, {Encoding encoding}) {
    return _aggregateTransform.readInputAsString(id, encoding: encoding);
  }
  Stream<List<int>> readInput(AssetId id) => _aggregateTransform.readInput(id);
  Future<bool> hasInput(AssetId id) => _aggregateTransform.hasInput(id);
  void addOutput(Asset output) => _aggregateTransform.addOutput(output);
  void consumePrimary() => _aggregateTransform.consumePrimary(primaryInput.id);
}
