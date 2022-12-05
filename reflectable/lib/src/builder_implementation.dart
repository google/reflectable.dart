// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.builder_implementation;

// ignore_for_file:implementation_imports

import 'dart:developer' as developer;
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/source/source_resource.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as path;
import 'element_capability.dart' as ec;
import 'encoding_constants.dart' as constants;
import 'fixed_point.dart';
import 'incompleteness.dart';
import 'reflectable_class_constants.dart' as reflectable_class_constants;
import 'reflectable_errors.dart' as errors;

// ignore_for_file: omit_local_variable_types

/// Specifiers for warnings that may be suppressed; `allWarnings` disables all
/// warnings, and the remaining values are concerned with individual warnings.
/// Remember to update the explanatory text in [_findSuppressWarnings] whenever
/// this list is updated.
enum WarningKind {
  missingEntryPoint,
  badSuperclass,
  badNamePattern,
  badMetadata,
  badReflectorClass,
  unrecognizedReflector,
  unusedReflector
}

class _ReflectionWorld {
  final Resolver resolver;
  final List<LibraryElement> libraries;
  final AssetId generatedLibraryId;
  final List<_ReflectorDomain> reflectors;
  final LibraryElement reflectableLibrary;
  final LibraryElement entryPointLibrary;
  final _ImportCollector importCollector;

  /// Used to collect the names of covered members during `generateCode`, then
  /// used by `generateSymbolMap` to generate code for a mapping from symbols
  /// to the corresponding strings.
  final Set<String> memberNames = <String>{};

  _ReflectionWorld(
      this.resolver,
      this.libraries,
      this.generatedLibraryId,
      this.reflectors,
      this.reflectableLibrary,
      this.entryPointLibrary,
      this.importCollector);

  /// The inverse relation of `superinterfaces` union `superclass`, globally.
  Map<InterfaceElement, Set<InterfaceElement>> get subtypes {
    if (_subtypesCache != null) return _subtypesCache!;

    // Initialize [_subtypesCache], ready to be filled in.
    var subtypes = <InterfaceElement, Set<InterfaceElement>>{};

    void addSubtypeRelation(
        InterfaceElement supertype, InterfaceElement subtype) {
      Set<InterfaceElement>? subtypesOfSupertype = subtypes[supertype];
      if (subtypesOfSupertype == null) {
        subtypesOfSupertype = <InterfaceElement>{};
        subtypes[supertype] = subtypesOfSupertype;
      }
      subtypesOfSupertype.add(subtype);
    }

    // Fill in [_subtypesCache].
    for (LibraryElement library in libraries) {
      void addInterfaceElement(InterfaceElement interfaceElement) {
        InterfaceType? supertype = interfaceElement.supertype;
        if (interfaceElement.mixins.isEmpty) {
          var supertypeElement = supertype?.element;
          if (supertypeElement != null) {
            addSubtypeRelation(supertypeElement, interfaceElement);
          }
        } else {
          // Mixins must be applied to a superclass, so it is not null.
          var superclass = supertype!.element;
          // Iterate over all mixins in most-general-first order (so with
          // `class C extends B with M1, M2..` we visit `M1` then `M2`.
          for (InterfaceType mixin in interfaceElement.mixins) {
            var mixinElement = mixin.element;
            InterfaceElement? subClass =
                mixin == interfaceElement.mixins.last ? interfaceElement : null;
            String? name = subClass == null
                ? null
                : (interfaceElement is MixinApplication &&
                        interfaceElement.isMixinApplication
                    ? interfaceElement.name
                    : null);
            MixinApplication mixinApplication = MixinApplication(
                name, superclass, mixinElement, library, subClass);
            addSubtypeRelation(superclass, mixinApplication);
            addSubtypeRelation(mixinElement, mixinApplication);
            if (subClass != null) {
              addSubtypeRelation(mixinApplication, subClass);
            }
            superclass = mixinApplication;
          }
        }
        for (InterfaceType type in interfaceElement.interfaces) {
          addSubtypeRelation(type.element, interfaceElement);
        }
      }

      for (CompilationUnitElement unit in library.units) {
        for (var interfaceElement in unit.classes) {
          addInterfaceElement(interfaceElement);
        }
        for (var interfaceElement in unit.enums) {
          addInterfaceElement(interfaceElement);
        }
      }
    }
    return _subtypesCache =
        Map<InterfaceElement, Set<InterfaceElement>>.unmodifiable(subtypes);
  }

  Map<InterfaceElement, Set<InterfaceElement>>? _subtypesCache;

  /// Returns code which will create all the data structures (esp. mirrors)
  /// needed to enable the correct behavior for all [reflectors].
  Future<String> generateCode() async {
    var typedefs = <FunctionType, int>{};
    var typeVariablesInScope = <String>{}; // None at top level.
    String typedefsCode = '\n';
    List<String> reflectorsCode = [];
    for (_ReflectorDomain reflector in reflectors) {
      String reflectorCode =
          await reflector._generateCode(this, importCollector, typedefs);
      if (typedefs.isNotEmpty) {
        for (DartType dartType in typedefs.keys) {
          String body = await reflector._typeCodeOfTypeArgument(
              dartType, importCollector, typeVariablesInScope, typedefs,
              useNameOfGenericFunctionType: false);
          typedefsCode +=
              '\ntypedef ${_typedefName(typedefs[dartType]!)} = $body;';
        }
        typedefs.clear();
      }
      reflectorsCode
          .add('${await reflector._constConstructionCode(importCollector)}: '
              '$reflectorCode');
    }
    return 'final _data = <r.Reflectable, r.ReflectorData>'
        '${_formatAsMap(reflectorsCode)};$typedefsCode';
  }

  /// Returns code which defines a mapping from symbols for covered members
  /// to the corresponding strings. Note that the data needed for doing this
  /// is collected during the execution of `generateCode`, which means that
  /// this method must be called after `generateCode`.
  String generateSymbolMap() {
    if (reflectors.any((_ReflectorDomain reflector) =>
        reflector._capabilities._impliesMemberSymbols)) {
      // Generate the mapping when requested, even if it is empty.
      String mapping = _formatAsMap(
          memberNames.map((String name) => "const Symbol(r'$name'): r'$name'"));
      return mapping;
    } else {
      // The value `null` unambiguously indicates lack of capability.
      return 'null';
    }
  }
}

/// Similar to a `Set<T>` but also keeps track of the index of the first
/// insertion of each item.
class Enumerator<T extends Object> {
  final Map<T, int> _map = <T, int>{};
  int _count = 0;

  bool _contains(Object? t) => _map.containsKey(t);

  int get length => _count;

  /// Tries to insert [t]. If it was already there return false, else insert it
  /// and return true.
  bool add(T t) {
    if (_contains(t)) return false;
    _map[t] = _count;
    ++_count;
    return true;
  }

  /// Returns the index of a given item.
  int? indexOf(Object t) {
    return _map[t];
  }

  /// Returns all the items in the order they were inserted.
  Iterable<T> get items {
    return _map.keys;
  }

  /// Clears all elements from this [Enumerator].
  void clear() {
    _map.clear();
    _count = 0;
  }
}

/// Hybrid data structure holding [InterfaceElement]s and supporting data.
/// It holds three different data structures used to describe the set of
/// classes under transformation. It holds an [Enumerator] named
/// [interfaceElements] which is a set-like data structure that also enables
/// clients to obtain unique indices for each member; it holds a map
/// [elementToDomain] that maps each [InterfaceElement] to a corresponding
/// [_ClassDomain]; and it holds a relation [mixinApplicationSupers] that
/// maps each [InterfaceElement] which is a direct subclass of a mixin
/// application to its superclass. The latter is needed because the analyzer
/// representation of mixins and mixin applications makes it difficult to find
/// a superclass which is a mixin application (`InterfaceElement.supertype` is
/// the _syntactic_ superclass, that is, for `class C extends B with M..` it
/// is `B`, not the mixin application `B with M`). The three data structures
/// are bundled together in this class because they must remain consistent and
/// hence all operations on them should be expressed in one location, namely
/// this class. Note that this data structure can delegate all read-only
/// operations to the [interfaceElements], because they will not break
/// consistency, but for every mutating method we need to maintain the
/// invariants.
class _InterfaceElementEnhancedSet implements Set<InterfaceElement> {
  final _ReflectorDomain reflectorDomain;
  final Enumerator<InterfaceElement> interfaceElements =
      Enumerator<InterfaceElement>();
  final Map<InterfaceElement, _ClassDomain> elementToDomain =
      <InterfaceElement, _ClassDomain>{};
  final Map<InterfaceElement, MixinApplication> mixinApplicationSupers =
      <InterfaceElement, MixinApplication>{};
  bool _unmodifiable = false;

  _InterfaceElementEnhancedSet(this.reflectorDomain);

  void makeUnmodifiable() {
    // A very simple implementation, just enough to help spotting cases
    // where modification happens even though it is known to be a bug:
    // Check whether `_unmodifiable` is true whenever a mutating method
    // is called.
    _unmodifiable = true;
  }

  @override
  Iterable<T> map<T>(T Function(InterfaceElement) f) =>
      interfaceElements.items.map<T>(f);

  @override
  Set<R> cast<R>() {
    Iterable<Object?> self = this;
    return self is Set<R> ? self : Set.castFrom<InterfaceElement, R>(this);
  }

  @override
  Iterable<InterfaceElement> where(bool Function(InterfaceElement) f) {
    return interfaceElements.items.where(f);
  }

  @override
  Iterable<T> whereType<T>() sync* {
    for (var element in this) {
      if (element is T) {
        yield (element as T);
      }
    }
  }

  @override
  Iterable<T> expand<T>(Iterable<T> Function(InterfaceElement) f) {
    return interfaceElements.items.expand<T>(f);
  }

  @override
  void forEach(void Function(InterfaceElement) f) =>
      interfaceElements.items.forEach(f);

  @override
  InterfaceElement reduce(
      InterfaceElement Function(InterfaceElement, InterfaceElement) combine) {
    return interfaceElements.items.reduce(combine);
  }

  @override
  T fold<T>(T initialValue, T Function(T, InterfaceElement) combine) {
    return interfaceElements.items.fold<T>(initialValue, combine);
  }

  @override
  bool every(bool Function(InterfaceElement) f) =>
      interfaceElements.items.every(f);

  @override
  String join([String separator = '']) =>
      interfaceElements.items.join(separator);

  @override
  bool any(bool Function(InterfaceElement) f) => interfaceElements.items.any(f);

  @override
  List<InterfaceElement> toList({bool growable = true}) {
    return interfaceElements.items.toList(growable: growable);
  }

  @override
  int get length => interfaceElements.items.length;

  @override
  bool get isEmpty => interfaceElements.items.isEmpty;

  @override
  bool get isNotEmpty => interfaceElements.items.isNotEmpty;

  @override
  Iterable<InterfaceElement> take(int count) =>
      interfaceElements.items.take(count);

  @override
  Iterable<InterfaceElement> takeWhile(bool Function(InterfaceElement) test) {
    return interfaceElements.items.takeWhile(test);
  }

  @override
  Iterable<InterfaceElement> skip(int count) =>
      interfaceElements.items.skip(count);

  @override
  Iterable<InterfaceElement> skipWhile(bool Function(InterfaceElement) test) {
    return interfaceElements.items.skipWhile(test);
  }

  @override
  Iterable<InterfaceElement> followedBy(
      Iterable<InterfaceElement> other) sync* {
    yield* this;
    yield* other;
  }

  @override
  InterfaceElement get first => interfaceElements.items.first;

  @override
  InterfaceElement get last => interfaceElements.items.last;

  @override
  InterfaceElement get single => interfaceElements.items.single;

  @override
  InterfaceElement firstWhere(bool Function(InterfaceElement) test,
      {InterfaceElement Function()? orElse}) {
    return interfaceElements.items.firstWhere(test, orElse: orElse);
  }

  @override
  InterfaceElement lastWhere(bool Function(InterfaceElement) test,
      {InterfaceElement Function()? orElse}) {
    return interfaceElements.items.lastWhere(test, orElse: orElse);
  }

  @override
  InterfaceElement singleWhere(bool Function(InterfaceElement) test,
      {InterfaceElement Function()? orElse}) {
    return interfaceElements.items.singleWhere(test);
  }

  @override
  InterfaceElement elementAt(int index) =>
      interfaceElements.items.elementAt(index);

  @override
  Iterator<InterfaceElement> get iterator => interfaceElements.items.iterator;

  @override
  bool contains(Object? value) => interfaceElements.items.contains(value);

  @override
  bool add(InterfaceElement value) {
    assert(!_unmodifiable);
    bool result = interfaceElements.add(value);
    if (result) {
      assert(!elementToDomain.containsKey(value));
      elementToDomain[value] = _createClassDomain(value, reflectorDomain);
      if (value is MixinApplication) {
        var valueSubclass = value.subclass;
        if (valueSubclass != null) {
          // [value] is a mixin application which is the immediate superclass
          // of a class which is a regular class (not a mixin application). This
          // means that we must store it in `mixinApplicationSupers` such that
          // we can look it up during invocations of [superclassOf].
          assert(!mixinApplicationSupers.containsKey(valueSubclass));
          mixinApplicationSupers[valueSubclass] = value;
        }
      }
    }
    return result;
  }

  @override
  void addAll(Iterable<InterfaceElement> elements) => elements.forEach(add);

  @override
  bool remove(Object? value) {
    assert(!_unmodifiable);
    bool result = interfaceElements._contains(value);
    interfaceElements._map.remove(value);
    if (result) {
      assert(elementToDomain.containsKey(value));
      elementToDomain.remove(value);
      if (value is MixinApplication && value.subclass != null) {
        // [value] must have been stored in `mixinApplicationSupers`,
        // so for consistency we must remove it from there, too.
        assert(mixinApplicationSupers.containsKey(value.subclass));
        mixinApplicationSupers.remove(value.subclass);
      }
    }
    return result;
  }

  @override
  InterfaceElement? lookup(Object? object) {
    for (InterfaceElement classElement in interfaceElements._map.keys) {
      if (object == classElement) return classElement;
    }
    return null;
  }

  @override
  void removeAll(Iterable<Object?> elements) => elements.forEach(remove);

  @override
  void retainAll(Iterable<Object?> elements) {
    bool test(InterfaceElement element) => !elements.contains(element);
    removeWhere(test);
  }

  @override
  void removeWhere(bool Function(InterfaceElement) test) {
    var toRemove = <InterfaceElement>{};
    for (InterfaceElement classElement in interfaceElements.items) {
      if (test(classElement)) toRemove.add(classElement);
    }
    removeAll(toRemove);
  }

  @override
  void retainWhere(bool Function(InterfaceElement) test) {
    bool invertedTest(InterfaceElement element) => !test(element);
    removeWhere(invertedTest);
  }

  @override
  bool containsAll(Iterable<Object?> other) {
    return interfaceElements.items.toSet().containsAll(other);
  }

  @override
  Set<InterfaceElement> intersection(Set<Object?> other) {
    return interfaceElements.items.toSet().intersection(other);
  }

  @override
  Set<InterfaceElement> union(Set<InterfaceElement> other) {
    return interfaceElements.items.toSet().union(other);
  }

  @override
  Set<InterfaceElement> difference(Set<Object?> other) {
    return interfaceElements.items.toSet().difference(other);
  }

  @override
  void clear() {
    assert(!_unmodifiable);
    interfaceElements.clear();
    elementToDomain.clear();
  }

  @override
  Set<InterfaceElement> toSet() => this;

  /// Returns the superclass of the given [classElement] using the language
  /// semantics rather than the analyzer model (where the superclass is the
  /// syntactic one, i.e., `class C extends B with M..` has superclass `B`,
  /// not the mixin application `B with M`). This method will use the analyzer
  /// data to find the superclass, which means that it will _not_ refrain
  /// from returning a class which is not covered by any particular reflector.
  /// It is up to the caller to check that.
  InterfaceElement? superclassOf(InterfaceElement classElement) {
    // By construction of [MixinApplication]s, their `superclass` is correct.
    if (classElement is MixinApplication) return classElement.superclass;
    // For a regular class whose superclass is also not a mixin application,
    // the analyzer `supertype` is what we want. Note that this gets [null]
    // from [Object], which is intended: We consider that (non-existing) class
    // as covered, and use [null] to represent it; there is no clash with
    // returning [null] to indicate that a superclass is not covered, because
    // this method does not check coverage.
    if (classElement.mixins.isEmpty) {
      return classElement.supertype?.element;
    }
    // [classElement] is now known to be a regular class whose superclass
    // is a mixin application. For each [MixinApplication] `m` we store, if it
    // was created as a superclass of a regular (non mixin application) class
    // `C` then we have stored a mapping from `C` to `m` in the map
    // `mixinApplicationSupers`.
    assert(mixinApplicationSupers.containsKey(classElement));
    return mixinApplicationSupers[classElement];
  }

  /// Returns the _ClassDomain corresponding to the given [classElement],
  /// which must be a member of this [_InterfaceElementEnhancedSet].
  _ClassDomain domainOf(InterfaceElement classElement) {
    assert(elementToDomain.containsKey(classElement));
    return elementToDomain[classElement]!;
  }

  /// Returns the index of the given [classElement] if it is contained
  /// in this [_InterfaceElementEnhancedSet], otherwise [null].
  int? indexOf(Object classElement) {
    return interfaceElements.indexOf(classElement);
  }

  Iterable<_ClassDomain> get domains => elementToDomain.values;
}

/// Used to bundle a [DartType] with information about whether it should be
/// erased (such that, e.g., `List<int>` becomes `List`). The alternative would
/// be to construct a new [InterfaceType] with all-dynamic type arguments in
/// the cases where we need to have the erased type, but constructing such
/// new analyzer data seems to transgress yet another privacy boundary of the
/// analyzer, so we decided that we did not want to do that.
class ErasableDartType {
  final DartType dartType;
  final bool erased;
  ErasableDartType(this.dartType, {required this.erased});

  @override
  bool operator ==(other) =>
      other is ErasableDartType &&
      other.dartType == dartType &&
      other.erased == erased;

  @override
  int get hashCode => dartType.hashCode ^ erased.hashCode;

  @override
  String toString() => 'ErasableDartType($dartType, $erased)';
}

/// Models the shape of a parameter list, which enables invocation to detect
/// mismatches such that we can raise a suitable no-such-method error.
class ParameterListShape {
  final int numberOfPositionalParameters;
  final int numberOfOptionalPositionalParameters;
  final Set<String> namesOfNamedParameters;

  const ParameterListShape(this.numberOfPositionalParameters,
      this.numberOfOptionalPositionalParameters, this.namesOfNamedParameters);

  @override
  bool operator ==(other) => other is ParameterListShape
      ? numberOfPositionalParameters == other.numberOfPositionalParameters &&
          numberOfOptionalPositionalParameters ==
              other.numberOfOptionalPositionalParameters &&
          namesOfNamedParameters
              .difference(other.namesOfNamedParameters)
              .isEmpty
      : false;

  @override
  int get hashCode =>
      numberOfPositionalParameters.hashCode ^
      numberOfOptionalPositionalParameters.hashCode;

  String get code {
    String names = 'null';
    if (namesOfNamedParameters.isNotEmpty) {
      Iterable<String> symbols = namesOfNamedParameters.map((name) => '#$name');
      names = 'const ${_formatAsDynamicList(symbols)}';
    }
    return 'const [$numberOfPositionalParameters, '
        '$numberOfOptionalPositionalParameters, $names]';
  }
}

// To avoid name clashes, we allocate numbers for generated `typedef`s
// globally, by reading and updating this variable.
int typedefNumber = 1;

/// Information about the program parts that can be reflected by a given
/// Reflector.
class _ReflectorDomain {
  late final _ReflectionWorld _world;
  final Resolver _resolver;
  final AssetId _generatedLibraryId;
  final InterfaceElement _reflector;

  /// Do not use this, use [classes] which ensures that closure operations
  /// have been performed as requested in [_capabilities]. Exception: In
  /// `_computeWorld`, [_classes] is filled in with the set of directly
  /// covered classes during creation of this [_ReflectorDomain].
  /// NB: [_classes] should be final, but it is not possible because this
  /// would create a cycle of final fields, which cannot be initialized.
  late final _InterfaceElementEnhancedSet _classes;

  /// Used by [classes], only, to keep track of whether [_classes] has been
  /// properly initialized by means of closure operations.
  bool _classesInitialized = false;

  /// Returns the set of classes covered by `_reflector`, including the ones
  /// which are directly covered by carrying `_reflector` as metadata or being
  /// matched by a global quantifier, and including the ones which are reached
  /// via the closure operations requested in [_capabilities].
  Future<_InterfaceElementEnhancedSet> get classes async {
    if (!_classesInitialized) {
      if (_capabilities._impliesDownwardsClosure) {
        await _SubtypesFixedPoint(_world.subtypes).expand(_classes);
      }
      if (_capabilities._impliesUpwardsClosure) {
        await _SuperclassFixedPoint(await _capabilities._upwardsClosureBounds,
                _capabilities._impliesMixins)
            .expand(_classes);
      } else {
        // Even without an upwards closure we cover some superclasses, namely
        // mixin applications where the class applied as a mixin is covered (it
        // seems natural to cover applications of covered mixins and there is
        // no other way to request that, other than requesting a full upwards
        // closure which might add many more classes).
        _mixinApplicationsOfClasses(_classes).forEach(_classes.add);
      }
      if (_capabilities._impliesTypes &&
          _capabilities._impliesTypeAnnotations) {
        _AnnotationClassFixedPoint fix = _AnnotationClassFixedPoint(
            _resolver, _generatedLibraryId, _classes.domainOf);
        if (_capabilities._impliesTypeAnnotationClosure) {
          await fix.expand(_classes);
        } else {
          await fix.singleExpand(_classes);
        }
      }
      _classesInitialized = true;
    }
    return _classes;
  }

  final Enumerator<LibraryElement> _libraries = Enumerator<LibraryElement>();

  final _Capabilities _capabilities;

  _ReflectorDomain(this._resolver, this._generatedLibraryId, this._reflector,
      this._capabilities) {
    _classes = _InterfaceElementEnhancedSet(this);
  }

  final _instanceMemberCache =
      <InterfaceElement, Map<String, ExecutableElement>>{};

  /// Returns a string that evaluates to a closure invoking [constructor] with
  /// the given arguments.
  /// [importCollector] is used to record all the imports needed to make the
  /// constant.
  /// This is to provide something that can be called with [Function.apply].
  ///
  /// For example for a constructor Foo(x, {y: 3}):
  /// returns "(x, {y: 3}) => prefix1.Foo(x, y)", and records an import of
  /// the library of `Foo` associated with prefix1 in [importCollector].
  Future<String> _constructorCode(
      ConstructorElement constructor, _ImportCollector importCollector) async {
    FunctionType type = constructor.type;

    int requiredPositionalCount = type.normalParameterTypes.length;
    int optionalPositionalCount = type.optionalParameterTypes.length;

    List<String> parameterNames = type.parameters
        .map((ParameterElement parameter) => parameter.name)
        .toList();

    List<String> namedParameterNames = type.namedParameterTypes.keys.toList();

    // Special casing the `List` default constructor.
    //
    // After a bit of hesitation, we decided to special case `dart.core.List`.
    // The issue is that the default constructor for `List` has a representation
    // which is platform dependent and which is reflected imprecisely by the
    // analyzer model: The analyzer data claims that it is external, and that
    // its optional `length` argument has no default value. But it actually has
    // two different default values, one on the vm and one in dart2js generated
    // code. We handle this special case by ensuring that `length` is passed if
    // it differs from `null`, and otherwise we perform the invocation of the
    // constructor with no arguments; this will suppress the error in the case
    // where the caller specifies an explicit `null` argument, but otherwise
    // faithfully reproduce the behavior of non-reflective code, and that is
    // probably the closest we can get. We could specify a different default
    // argument (say, "Hello, world!") and then test for that value, but that
    // would suppress an error in a very-hard-to-explain case, so that's safer
    // in a sense, but too weird.
    if (constructor.library.isDartCore &&
        constructor.enclosingElement.name == 'List' &&
        constructor.name == '') {
      return '(bool b) => ([length]) => '
          'b ? (length == null ? [] : List.filled(length, null)) : null';
    }

    String positionals =
        Iterable.generate(requiredPositionalCount, (int i) => parameterNames[i])
            .join(', ');

    List<String> optionalsWithDefaultList = [];
    for (int i = 0; i < optionalPositionalCount; i++) {
      String code = await _extractDefaultValueCode(
          importCollector, constructor.parameters[requiredPositionalCount + i]);
      String defaultPart = code.isEmpty ? '' : ' = $code';
      optionalsWithDefaultList
          .add('${parameterNames[requiredPositionalCount + i]}$defaultPart');
    }
    String optionalsWithDefaults = optionalsWithDefaultList.join(', ');

    List<String> namedWithDefaultList = [];
    for (int i = 0; i < namedParameterNames.length; i++) {
      // Note that the use of `requiredPositionalCount + i` below relies
      // on a language design where no parameter list can include
      // both optional positional and named parameters, so if there are
      // any named parameters then all optional parameters are named.
      ParameterElement parameterElement =
          constructor.parameters[requiredPositionalCount + i];
      String code =
          await _extractDefaultValueCode(importCollector, parameterElement);
      String defaultPart = code.isEmpty ? '' : ' = $code';
      namedWithDefaultList.add('${parameterElement.name}$defaultPart');
    }
    String namedWithDefaults = namedWithDefaultList.join(', ');

    String optionalArguments = Iterable.generate(optionalPositionalCount,
        (int i) => parameterNames[i + requiredPositionalCount]).join(', ');
    String namedArguments =
        namedParameterNames.map((String name) => '$name: $name').join(', ');

    List<String> parameterParts = <String>[];
    List<String> argumentParts = <String>[];

    if (requiredPositionalCount != 0) {
      parameterParts.add(positionals);
      argumentParts.add(positionals);
    }
    if (optionalPositionalCount != 0) {
      parameterParts.add('[$optionalsWithDefaults]');
      argumentParts.add(optionalArguments);
    }
    if (namedParameterNames.isNotEmpty) {
      parameterParts.add('{$namedWithDefaults}');
      argumentParts.add(namedArguments);
    }

    String doRunArgument = 'b';
    while (parameterNames.contains(doRunArgument)) {
      doRunArgument = '${doRunArgument}b';
    }

    String prefix = importCollector._getPrefix(constructor.library);
    return ('(bool $doRunArgument) => (${parameterParts.join(', ')}) => '
        '$doRunArgument ? $prefix${await _nameOfConstructor(constructor)}'
        '(${argumentParts.join(', ')}) : null');
  }

  /// The code of the const-construction of this reflector.
  Future<String> _constConstructionCode(
      _ImportCollector importCollector) async {
    String prefix = importCollector._getPrefix(_reflector.library);
    if (_isPrivateName(_reflector.name)) {
      await _severe(
          'Cannot access private name `${_reflector.name}`', _reflector);
    }
    return 'const $prefix${_reflector.name}()';
  }

  /// Generate the code which will create a `ReflectorData` instance
  /// containing the mirrors and other reflection data which is needed for
  /// `_reflector` to behave correctly.
  Future<String> _generateCode(_ReflectionWorld world,
      _ImportCollector importCollector, Map<FunctionType, int> typedefs) async {
    // Library related collections.
    Enumerator<_LibraryDomain> libraries = Enumerator<_LibraryDomain>();
    Map<LibraryElement, _LibraryDomain> libraryMap =
        <LibraryElement, _LibraryDomain>{};
    Enumerator<TopLevelVariableElement> topLevelVariables =
        Enumerator<TopLevelVariableElement>();

    // Class related collections.
    Enumerator<FieldElement> fields = Enumerator<FieldElement>();
    Enumerator<TypeParameterElement> typeParameters =
        Enumerator<TypeParameterElement>();
    // Reflected types not in `classes`; appended to `ReflectorData.types`.
    Enumerator<ErasableDartType> reflectedTypes =
        Enumerator<ErasableDartType>();
    var instanceGetterNames = <String>{};
    var instanceSetterNames = <String>{};

    // Library and class related collections.
    Enumerator<ExecutableElement> members = Enumerator<ExecutableElement>();
    Enumerator<ParameterElement> parameters = Enumerator<ParameterElement>();
    Enumerator<ParameterListShape> parameterListShapes =
        Enumerator<ParameterListShape>();
    Map<ExecutableElement, ParameterListShape> parameterListShapeOf =
        <ExecutableElement, ParameterListShape>{};

    // Class element for [Object], needed as implicit upper bound. Initialized
    // if needed.
    InterfaceElement? objectInterfaceElement;

    /// Adds a library domain for [library] to [libraries], relying on checks
    /// for importability and insertion into [importCollector] to have taken
    /// place already.
    void uncheckedAddLibrary(LibraryElement library) {
      _LibraryDomain libraryDomain = _createLibraryDomain(library, this);
      libraries.add(libraryDomain);
      libraryMap[library] = libraryDomain;
      libraryDomain._declarations.forEach(members.add);
      libraryDomain._declaredParameters.forEach(parameters.add);
      libraryDomain._declaredVariables.forEach(topLevelVariables.add);
    }

    /// Used to add a library domain for [library] to [libraries], checking
    /// that it is importable and registering it with [importCollector].
    Future<void> addLibrary(LibraryElement library) async {
      if (!await _isImportableLibrary(
          library, _generatedLibraryId, _resolver)) {
        return;
      }
      importCollector._addLibrary(library);
      uncheckedAddLibrary(library);
    }

    // Fill in [libraries], [typeParameters], [members], [fields],
    // [parameters], [instanceGetterNames], and [instanceSetterNames].
    _libraries.items.forEach(uncheckedAddLibrary);
    for (var classElement in await classes) {
      LibraryElement classLibrary = classElement.library;
      if (!libraries.items.any((_LibraryDomain libraryDomain) =>
          libraryDomain._libraryElement == classLibrary)) {
        addLibrary(classLibrary);
      }
      classElement.typeParameters.forEach(typeParameters.add);
    }
    for (_ClassDomain classDomain in (await classes).domains) {
      // Gather the behavioral interface into [members]. Note that
      // this includes implicitly generated getters and setters, but
      // omits fields. Also note that this does not match the
      // semantics of the `declarations` method in a [ClassMirror].
      classDomain._declarations.forEach(members.add);

      // Add the behavioral interface from this class (redundantly, for
      // non-static members) and all superclasses (which matters) to
      // [members], such that it contains both the behavioral parts for
      // the target class and its superclasses, and the program structure
      // oriented parts for the target class (omitting those from its
      // superclasses).
      classDomain._instanceMembers.forEach(members.add);

      // Add all the formal parameters (as a single, global set) which
      // are declared by any of the methods in `classDomain._declarations`
      // as well as in `classDomain._instanceMembers`.
      classDomain._declaredParameters.forEach(parameters.add);
      classDomain._instanceParameters.forEach(parameters.add);

      // Gather the fields declared in the target class (not inherited
      // ones) in [fields], i.e., the elements missing from [members]
      // at this point, in order to support `declarations` in a
      // [ClassMirror].
      classDomain._declaredFields.forEach(fields.add);

      // Ensure that we include variables corresponding to the implicit
      // accessors that we have included into `members`.
      for (ExecutableElement element in members.items) {
        if (element is PropertyAccessorElement && element.isSynthetic) {
          PropertyInducingElement variable = element.variable;
          if (variable is FieldElement) {
            fields.add(variable);
          } else if (variable is TopLevelVariableElement) {
            topLevelVariables.add(variable);
          } else {
            await _severe(
                'This kind of variable is not yet supported'
                ' (${variable.runtimeType})',
                variable);
          }
        }
      }

      // Gather all getter and setter names based on [instanceMembers],
      // including both explicitly declared ones, implicitly generated ones
      // for fields, and the implicitly generated ones that correspond to
      // method tear-offs.
      for (var instanceMember in classDomain._instanceMembers) {
        if (instanceMember is PropertyAccessorElement) {
          // A getter or a setter, synthetic or declared.
          if (instanceMember.isGetter) {
            instanceGetterNames.add(instanceMember.name);
          } else {
            instanceSetterNames.add(instanceMember.name);
          }
        } else if (instanceMember is MethodElement) {
          instanceGetterNames.add(instanceMember.name);
        } else {
          // `instanceMember` is a ConstructorElement.
          // Even though a generative constructor has a false
          // `isStatic`, we do not wish to include them among
          // instanceGetterNames, so we do nothing here.
        }
      }
    }

    // Add classes used as bounds for type variables, if needed.
    if (_capabilities._impliesTypes && _capabilities._impliesTypeAnnotations) {
      Future<void> addClass(InterfaceElement classElement) async {
        (await classes).add(classElement);
        LibraryElement classLibrary = classElement.library;
        if (!libraries.items
            .any((domain) => domain._libraryElement == classLibrary)) {
          uncheckedAddLibrary(classLibrary);
        }
      }

      bool hasObject = false;
      bool mustHaveObject = false;
      var classesToAdd = <InterfaceElement>{};
      InterfaceElement? anyInterfaceElement;
      for (InterfaceElement classElement in await classes) {
        if (_typeForReflectable(classElement).isDartCoreObject) {
          hasObject = true;
          objectInterfaceElement = classElement;
          break;
        }
        if (classElement.typeParameters.isNotEmpty) {
          for (TypeParameterElement typeParameterElement
              in classElement.typeParameters) {
            var typeParameterElementBound = typeParameterElement.bound;
            if (typeParameterElementBound == null) {
              mustHaveObject = true;
              anyInterfaceElement = classElement;
            } else {
              if (typeParameterElementBound is InterfaceType) {
                Element? boundElement = typeParameterElementBound.element;
                if (boundElement is InterfaceElement) {
                  classesToAdd.add(boundElement);
                }
              }
            }
          }
        }
      }
      if (mustHaveObject && !hasObject) {
        // If `mustHaveObject` is true then `anyInterfaceElement` is non-null.
        var someInterfaceElement = anyInterfaceElement!;
        while (!_typeForReflectable(someInterfaceElement).isDartCoreObject) {
          var someInterfaceType = someInterfaceElement.supertype;
          someInterfaceElement = someInterfaceType!.element;
        }
        objectInterfaceElement = someInterfaceElement;
        await addClass(objectInterfaceElement);
      }
      for (var clazz in classesToAdd) {
        await addClass(clazz);
      }
    }

    // From this point, [classes] must be kept immutable.
    (await classes).makeUnmodifiable();

    // Record the names of covered members, if requested.
    if (_capabilities._impliesMemberSymbols) {
      for (var executableElement in members.items) {
        _world.memberNames.add(executableElement.name);
      }
    }

    // Record the method parameter list shapes, if requested.
    if (_capabilities._impliesParameterListShapes) {
      for (var element in members.items) {
        int count = 0;
        int optionalCount = 0;
        var names = <String>{};
        for (ParameterElement parameter in element.parameters) {
          if (!parameter.isNamed) count++;
          if (parameter.isOptionalPositional) optionalCount++;
          if (parameter.isNamed) names.add(parameter.name);
        }
        ParameterListShape shape =
            ParameterListShape(count, optionalCount, names);
        parameterListShapes.add(shape);
        parameterListShapeOf[element] = shape;
      }
    }

    // Find the offsets of fields in members, and of methods and functions
    // in members, of type variables in type mirrors, and of `reflectedTypes`
    // in types.
    final int fieldsOffset = topLevelVariables.length;
    final int methodsOffset = fieldsOffset + fields.length;
    final int typeParametersOffset = (await classes).length;
    final int reflectedTypesOffset = typeParametersOffset;

    // Generate code for creation of class mirrors.
    List<String> typeMirrorsList = [];
    if (_capabilities._impliesTypes || _capabilities._impliesInstanceInvoke) {
      for (_ClassDomain classDomain in (await classes).domains) {
        typeMirrorsList.add(await _classMirrorCode(
            classDomain,
            typeParameters,
            fields,
            fieldsOffset,
            methodsOffset,
            typeParametersOffset,
            members,
            parameterListShapes,
            parameterListShapeOf,
            reflectedTypes,
            reflectedTypesOffset,
            libraries,
            libraryMap,
            importCollector,
            typedefs));
      }
      for (TypeParameterElement typeParameterElement in typeParameters.items) {
        typeMirrorsList.add(await _typeParameterMirrorCode(
            typeParameterElement, importCollector, objectInterfaceElement));
      }
    }
    String classMirrorsCode = _formatAsList('m.TypeMirror', typeMirrorsList);

    // Generate code for creation of getter and setter closures.
    String gettersCode = _formatAsMap(instanceGetterNames.map(_gettingClosure));
    String settersCode = _formatAsMap(instanceSetterNames.map(_settingClosure));

    bool reflectedTypeRequested = _capabilities._impliesReflectedType;

    // Generate code for creation of member mirrors.
    List<String> topLevelVariablesList = [];
    for (TopLevelVariableElement element in topLevelVariables.items) {
      topLevelVariablesList.add(await _topLevelVariableMirrorCode(
          element,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs,
          reflectedTypeRequested));
    }
    List<String> fieldsList = [];
    for (FieldElement element in fields.items) {
      fieldsList.add(await _fieldMirrorCode(
          element,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs,
          reflectedTypeRequested));
    }
    String membersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      List<String> methodsList = [];
      for (ExecutableElement executableElement in members.items) {
        methodsList.add(await _methodMirrorCode(
            executableElement,
            topLevelVariables,
            fields,
            members,
            reflectedTypes,
            reflectedTypesOffset,
            parameters,
            importCollector,
            typedefs,
            reflectedTypeRequested));
      }
      Iterable<String> membersList = [
        ...topLevelVariablesList,
        ...fieldsList,
        ...methodsList,
      ];
      membersCode = _formatAsList('m.DeclarationMirror', membersList);
    }

    // Generate code for creation of parameter mirrors.
    String parameterMirrorsCode = 'null';
    if (_capabilities._impliesDeclarations) {
      List<String> parametersList = [];
      for (ParameterElement element in parameters.items) {
        parametersList.add(await _parameterMirrorCode(
            element,
            fields,
            members,
            reflectedTypes,
            reflectedTypesOffset,
            importCollector,
            typedefs,
            reflectedTypeRequested));
      }
      parameterMirrorsCode = _formatAsList('m.ParameterMirror', parametersList);
    }

    // Generate code for listing [Type] instances.
    List<String> typesCodeList = [];
    for (InterfaceElement classElement in await classes) {
      typesCodeList.add(_dynamicTypeCodeOfClass(classElement, importCollector));
    }
    for (ErasableDartType erasableDartType in reflectedTypes.items) {
      if (erasableDartType.erased) {
        var interfaceType = erasableDartType.dartType as InterfaceType;
        typesCodeList.add(
            _dynamicTypeCodeOfClass(interfaceType.element, importCollector));
      } else {
        typesCodeList.add(await _typeCodeOfClass(
            erasableDartType.dartType, importCollector, typedefs));
      }
    }
    String typesCode = _formatAsList('Type', typesCodeList);

    // Generate code for creation of library mirrors.
    String librariesCode;
    if (!_capabilities._supportsLibraries) {
      librariesCode = 'null';
    } else {
      List<String> librariesCodeList = [];
      for (_LibraryDomain library in libraries.items) {
        librariesCodeList.add(await _libraryMirrorCode(
            library,
            libraries.indexOf(library)!,
            members,
            parameterListShapes,
            parameterListShapeOf,
            topLevelVariables,
            methodsOffset,
            importCollector));
      }
      librariesCode = _formatAsList('m.LibraryMirror', librariesCodeList);
    }

    String parameterListShapesCode = _formatAsDynamicList(parameterListShapes
        .items
        .map((ParameterListShape shape) => shape.code));

    return 'r.ReflectorData($classMirrorsCode, $membersCode, '
        '$parameterMirrorsCode, $typesCode, $reflectedTypesOffset, '
        '$gettersCode, $settersCode, $librariesCode, '
        '$parameterListShapesCode)';
  }

  Future<int> _computeTypeIndexBase(Element? typeElement, bool isVoid,
      bool isDynamic, bool isNever, bool isClassType) async {
    if (_capabilities._impliesTypes) {
      if (isDynamic || isVoid || isNever) {
        // The mirror will report 'dynamic', 'void', 'Never',
        // and it will never use the index.
        return constants.noCapabilityIndex;
      }
      if (isClassType && (await classes).contains(typeElement)) {
        // Normal encoding of a class type which has been added to `classes`.
        return (await classes).indexOf(typeElement!)!;
      }
      // At this point [typeElement] may be a non-class type, or it may be a
      // class that has not been added to `classes`, say, an argument type
      // annotation in a setting where we do not have an
      // [ec.TypeAnnotationQuantifyCapability]. In both cases we fall through
      // because the relevant capability is absent.
    }
    return constants.noCapabilityIndex;
  }

  Future<int> _computeVariableTypeIndex(
      PropertyInducingElement element, int descriptor) async {
    if (!_capabilities._impliesTypes) return constants.noCapabilityIndex;
    var interfaceType = element.type;
    if (interfaceType is! InterfaceType) return constants.noCapabilityIndex;
    return await _computeTypeIndexBase(
        interfaceType.element,
        descriptor & constants.voidAttribute != 0,
        descriptor & constants.dynamicAttribute != 0,
        descriptor & constants.neverAttribute != 0,
        descriptor & constants.classTypeAttribute != 0);
  }

  Future<bool> _hasSupportedReflectedTypeArguments(DartType dartType) async {
    if (dartType is ParameterizedType) {
      for (DartType typeArgument in dartType.typeArguments) {
        if (!await _hasSupportedReflectedTypeArguments(typeArgument)) {
          return false;
        }
      }
      return true;
    } else if (dartType is VoidType) {
      return true;
    } else if (dartType is TypeParameterType || dartType.isDynamic) {
      return false;
    } else {
      await _severe('`reflectedTypeArguments` where an actual type argument '
          '(possibly nested) is $dartType');
      return false;
    }
  }

  Future<String> _computeReflectedTypeArguments(
      DartType dartType,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      _ImportCollector importCollector,
      Map<FunctionType, int> typedefs) async {
    if (dartType is InterfaceType) {
      List<TypeParameterElement> typeParameters =
          dartType.element.typeParameters;
      if (typeParameters.isEmpty) {
        // We have no formal type parameters, so there cannot be any actual
        // type arguments.
        return 'const <int>[]';
      } else {
        // We have some formal type parameters: `dartType` is a generic class.
        List<DartType> typeArguments = dartType.typeArguments;
        // This method is called with variable/parameter type annotations and
        // function return types, and they denote instantiated generic classes
        // rather than "original" generic classes; so they do have actual type
        // arguments when there are formal type parameters.
        assert(typeArguments.length == typeParameters.length);
        bool allTypeArgumentsSupported = true;
        for (var typeArgument in typeArguments) {
          if (!await _hasSupportedReflectedTypeArguments(typeArgument)) {
            allTypeArgumentsSupported = false;
            break;
          }
        }
        if (allTypeArgumentsSupported) {
          List<int?> typesIndices = [];
          for (DartType actualTypeArgument in typeArguments) {
            if (actualTypeArgument is InterfaceType ||
                actualTypeArgument is VoidType ||
                actualTypeArgument.isDynamic) {
              typesIndices.add(_dynamicTypeCodeIndex(
                  actualTypeArgument,
                  await classes,
                  reflectedTypes,
                  reflectedTypesOffset,
                  typedefs));
            } else {
              // TODO(eernst) clarify: Are `dynamic` et al `InterfaceType`s?
              // Otherwise this means "a case that we have not it considered".
              await _severe(
                  '`reflectedTypeArguments` where one actual type argument'
                  ' is $actualTypeArgument');
              typesIndices.add(0);
            }
          }
          return _formatAsConstList('int', typesIndices);
        } else {
          return 'null';
        }
      }
    } else {
      // If the type is not a ParameterizedType then it has no type arguments.
      return 'const <int>[]';
    }
  }

  Future<int> _computeReturnTypeIndex(
      ExecutableElement element, int descriptor) async {
    if (!_capabilities._impliesTypes) return constants.noCapabilityIndex;
    var interfaceType = element.returnType;
    if (interfaceType is! InterfaceType) return constants.noCapabilityIndex;
    int result = await _computeTypeIndexBase(
        interfaceType.element,
        descriptor & constants.voidReturnTypeAttribute != 0,
        descriptor & constants.dynamicReturnTypeAttribute != 0,
        descriptor & constants.neverReturnTypeAttribute != 0,
        descriptor & constants.classReturnTypeAttribute != 0);
    return result;
  }

  Future<int?> _computeOwnerIndex(
      ExecutableElement element, int descriptor) async {
    if (element.enclosingElement is InterfaceElement) {
      return (await classes).indexOf(element.enclosingElement);
    } else if (element.enclosingElement is CompilationUnitElement) {
      return _libraries.indexOf(element.library);
    }
    await _severe('Unexpected kind of request for owner');
    return 0;
  }

  Iterable<ExecutableElement> _gettersOfLibrary(_LibraryDomain library) sync* {
    yield* library._accessors
        .where((PropertyAccessorElement accessor) => accessor.isGetter);
    yield* library._declaredFunctions;
  }

  Iterable<PropertyAccessorElement> _settersOfLibrary(_LibraryDomain library) {
    return library._accessors
        .where((PropertyAccessorElement accessor) => accessor.isSetter);
  }

  Future<String> _typeParameterMirrorCode(
      TypeParameterElement typeParameterElement,
      _ImportCollector importCollector,
      InterfaceElement? objectInterfaceElement) async {
    int? upperBoundIndex = constants.noCapabilityIndex;
    if (_capabilities._impliesTypeAnnotations) {
      DartType? bound = typeParameterElement.bound;
      if (bound == null) {
        assert(objectInterfaceElement != null);
        // Missing bound should be reported as the semantic default: `Object`.
        // We use an ugly hack to obtain the [InterfaceElement] for `Object`.
        upperBoundIndex = (await classes).indexOf(objectInterfaceElement!);
        assert(upperBoundIndex != null);
      } else if (bound.isDynamic) {
        // We use [null] to indicate that this bound is [dynamic] ([void]
        // cannot be a bound, so the only special case is [dynamic]).
        upperBoundIndex = null;
      } else {
        if (bound is InterfaceType) {
          upperBoundIndex = (await classes).indexOf(bound.element);
        } else {
          upperBoundIndex = constants.noCapabilityIndex;
        }
      }
    }
    int? ownerIndex =
        (await classes).indexOf(typeParameterElement.enclosingElement!);
    // TODO(eernst) implement: Update when type variables support metadata.
    String metadataCode =
        _capabilities._supportsMetadata ? '<Object>[]' : 'null';
    return "r.TypeVariableMirrorImpl(r'${typeParameterElement.name}', "
        "r'${_qualifiedTypeParameterName(typeParameterElement)}', "
        '${await _constConstructionCode(importCollector)}, '
        '$upperBoundIndex, $ownerIndex, $metadataCode)';
  }

  Future<String> _classMirrorCode(
      _ClassDomain classDomain,
      Enumerator<TypeParameterElement> typeParameters,
      Enumerator<FieldElement> fields,
      int fieldsOffset,
      int methodsOffset,
      int typeParametersOffset,
      Enumerator<ExecutableElement> members,
      Enumerator<ParameterListShape> parameterListShapes,
      Map<ExecutableElement, ParameterListShape> parameterListShapeOf,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      Enumerator<_LibraryDomain> libraries,
      Map<LibraryElement, _LibraryDomain> libraryMap,
      _ImportCollector importCollector,
      Map<FunctionType, int> typedefs) async {
    int descriptor = _classDescriptor(classDomain._interfaceElement);

    // Fields go first in [memberMirrors], so they will get the
    // same index as in [fields].
    Iterable<int> fieldsIndices =
        classDomain._declaredFields.map((FieldElement element) {
      return fields.indexOf(element)! + fieldsOffset;
    });

    // All the elements in the behavioral interface go after the
    // fields in [memberMirrors], so they must get an offset of
    // `fields.length` on the index.
    Iterable<int> methodsIndices = classDomain._declarations
        .where(_executableIsntImplicitGetterOrSetter)
        .map((ExecutableElement element) {
      // TODO(eernst) implement: The "magic" default constructor in `Object`
      // (the one that ultimately allocates the memory for _every_ new
      // object) has no index, which creates the need to catch a `null`
      // here. Search for "magic" to find other occurrences of the same
      // issue. For now, we use the index [constants.noCapabilityIndex]
      // for this declaration, because it is not yet supported.
      // Need to find the correct solution, though!
      int? index = members.indexOf(element);
      return index == null
          ? constants.noCapabilityIndex
          : index + methodsOffset;
    });

    String declarationsCode = _capabilities._impliesDeclarations
        ? _formatAsConstList('int', [...fieldsIndices, ...methodsIndices])
        : 'const <int>[${constants.noCapabilityIndex}]';

    // All instance members belong to the behavioral interface, so they
    // also get an offset of `fields.length`.
    String instanceMembersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      instanceMembersCode = _formatAsConstList('int',
          classDomain._instanceMembers.map((ExecutableElement element) {
        // TODO(eernst) implement: The "magic" default constructor has
        // index: noCapabilityIndex; adjust this when support for it has
        // been implemented.
        int? index = members.indexOf(element);
        return index == null
            ? constants.noCapabilityIndex
            : index + methodsOffset;
      }));
    }

    // All static members belong to the behavioral interface, so they
    // also get an offset of `fields.length`.
    String staticMembersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      staticMembersCode = _formatAsConstList('int',
          classDomain._staticMembers.map((ExecutableElement element) {
        int? index = members.indexOf(element);
        return index == null
            ? constants.noCapabilityIndex
            : index + methodsOffset;
      }));
    }

    InterfaceElement interfaceElement = classDomain._interfaceElement;
    InterfaceElement? superclass =
        (await classes).superclassOf(interfaceElement);

    String superclassIndex = '${constants.noCapabilityIndex}';
    if (_capabilities._impliesTypeRelations) {
      // [Object]'s superclass is reported as `null`: it does not exist and
      // hence we cannot decide whether it's supported or unsupported.; by
      // convention we make it supported and report it in the same way as
      // 'dart:mirrors'. Other superclasses use `noCapabilityIndex` to
      // indicate missing support.
      superclassIndex = (interfaceElement is! MixinApplication &&
              _typeForReflectable(interfaceElement).isDartCoreObject)
          ? 'null'
          : ((await classes).contains(superclass))
              ? '${(await classes).indexOf(superclass!)}'
              : '${constants.noCapabilityIndex}';
    }

    String constructorsCode;
    if (interfaceElement is MixinApplication) {
      // There may be any number of constructors, but they are implicitly
      // induced forwarding constructors, so it won't help anybody to be
      // able to get to them. Also, we can't invoke them because the mixin
      // application is an abstract class.
      constructorsCode = 'const {}';
    } else {
      List<String> mapEntries = [];
      for (ConstructorElement constructor in classDomain._constructors) {
        var enclosingElement = constructor.enclosingElement;
        if (constructor.isFactory ||
            ((enclosingElement is ClassElement &&
                    !enclosingElement.isAbstract) &&
                enclosingElement is! EnumElement)) {
          String code = await _constructorCode(constructor, importCollector);
          mapEntries.add("r'${constructor.name}': $code");
        }
      }
      constructorsCode = _formatAsMap(mapEntries);
    }

    String staticGettersCode = 'const {}';
    String staticSettersCode = 'const {}';
    if (interfaceElement is! MixinApplication) {
      List<String> staticGettersCodeList = [];
      for (MethodElement method in classDomain._declaredMethods) {
        if (method.isStatic) {
          staticGettersCodeList.add(await _staticGettingClosure(
              importCollector, interfaceElement, method.name));
        }
      }
      for (PropertyAccessorElement accessor in classDomain._accessors) {
        if (accessor.isStatic && accessor.isGetter) {
          staticGettersCodeList.add(await _staticGettingClosure(
              importCollector, interfaceElement, accessor.name));
        }
      }
      staticGettersCode = _formatAsMap(staticGettersCodeList);
      List<String> staticSettersCodeList = [];
      for (PropertyAccessorElement accessor in classDomain._accessors) {
        if (accessor.isStatic && accessor.isSetter) {
          staticSettersCodeList.add(await _staticSettingClosure(
              importCollector, interfaceElement, accessor.name));
        }
      }
      staticSettersCode = _formatAsMap(staticSettersCodeList);
    }

    int? mixinIndex = constants.noCapabilityIndex;
    if (_capabilities._impliesTypeRelations) {
      var theClasses = await classes;
      if (interfaceElement is MixinApplication &&
          interfaceElement.isMixinApplication) {
        // Named mixin application (using the syntax `class B = A with M;`).
        mixinIndex = theClasses.indexOf(interfaceElement.mixins.last.element);
      } else if (interfaceElement is MixinApplication) {
        // Anonymous mixin application.
        mixinIndex = theClasses.indexOf(interfaceElement.mixin);
      } else {
        // No mixins, by convention we use the class itself.
        mixinIndex = theClasses.indexOf(interfaceElement);
      }
      // We may not have support for the given class, in which case we must
      // correct the `null` from `indexOf` to indicate missing capability.
      mixinIndex ??= constants.noCapabilityIndex;
    }

    int ownerIndex = _capabilities._supportsLibraries
        ? libraries.indexOf(libraryMap[interfaceElement.library]!)!
        : constants.noCapabilityIndex;

    String superinterfaceIndices =
        'const <int>[${constants.noCapabilityIndex}]';
    if (_capabilities._impliesTypeRelations) {
      superinterfaceIndices = _formatAsConstList(
          'int',
          interfaceElement.interfaces
              .map((InterfaceType type) => type.element)
              .where((await classes).contains)
              .map((await classes).indexOf));
    }

    String classMetadataCode;
    if (_capabilities._supportsMetadata) {
      classMetadataCode = await _extractMetadataCode(
          interfaceElement, _resolver, importCollector, _generatedLibraryId);
    } else {
      classMetadataCode = 'null';
    }

    int classIndex = (await classes).indexOf(interfaceElement)!;

    String parameterListShapesCode = 'null';
    if (_capabilities._impliesParameterListShapes) {
      Iterable<ExecutableElement> membersList = [
        ...classDomain._instanceMembers,
        ...classDomain._staticMembers,
      ];
      parameterListShapesCode =
          _formatAsMap(membersList.map((ExecutableElement element) {
        // shape != null: every method must have its shape in `..shapeOf`.
        ParameterListShape shape = parameterListShapeOf[element]!;
        // index != null: every shape must be in `..Shapes`.
        int index = parameterListShapes.indexOf(shape)!;
        return "r'${element.name}': $index";
      }));
    }

    if (interfaceElement.typeParameters.isEmpty) {
      return "r.NonGenericClassMirrorImpl(r'${classDomain._simpleName}', "
          "r'${_qualifiedName(interfaceElement)}', $descriptor, $classIndex, "
          '${await _constConstructionCode(importCollector)}, '
          '$declarationsCode, $instanceMembersCode, $staticMembersCode, '
          '$superclassIndex, $staticGettersCode, $staticSettersCode, '
          '$constructorsCode, $ownerIndex, $mixinIndex, '
          '$superinterfaceIndices, $classMetadataCode, '
          '$parameterListShapesCode)';
    } else {
      // We are able to match up a given instance with a given generic type
      // by checking that the instance `is` an instance of the fully dynamic
      // instance of that generic type (for the generic class `List`, that is
      // `List<dynamic>`), and not an instance of any of its immediate subtypes,
      // if any. [isCheckCode] is a function which will test that its argument
      // (1) `is` an instance of the fully dynamic instance of the generic
      // class modeled by [interfaceElement], and (2) that it is not an instance
      // of the fully dynamic instance of any of the classes that `extends` or
      // `implements` this [interfaceElement].
      List<String> isCheckList = [];
      if (interfaceElement.isPrivate ||
          interfaceElement is MixinElement ||
          (interfaceElement is ClassElement && interfaceElement.isAbstract) ||
          (interfaceElement is MixinApplication &&
              !interfaceElement.isMixinApplication) ||
          !await _isImportable(
              interfaceElement, _generatedLibraryId, _resolver)) {
        // Note that this location is dead code until we get support for
        // anonymous mixin applications using type arguments as generic
        // classes (currently, no classes will pass the tests above). See
        // https://github.com/dart-lang/sdk/issues/25344 for more details.
        // However, the result that we will return is well-defined, because
        // no object can be an instance of an anonymous mixin application.
        isCheckList.add('(o) => false');
      } else {
        String prefix = importCollector._getPrefix(interfaceElement.library);
        isCheckList.add('(o) { return o is $prefix${interfaceElement.name}');

        // Add 'is checks' to [list], based on [interfaceElement].
        Future<void> helper(
            List<String> list, InterfaceElement interfaceElement) async {
          Iterable<InterfaceElement> subtypes =
              _world.subtypes[interfaceElement] ?? <InterfaceElement>[];
          for (InterfaceElement subtype in subtypes) {
            if (subtype.isPrivate ||
                subtype is MixinElement ||
                (subtype is ClassElement && subtype.isAbstract) ||
                (subtype is MixinApplication && !subtype.isMixinApplication) ||
                !await _isImportable(subtype, _generatedLibraryId, _resolver)) {
              await helper(list, subtype);
            } else {
              String prefix = importCollector._getPrefix(subtype.library);
              list.add(' && o is! $prefix${subtype.name}');
            }
          }
        }

        await helper(isCheckList, interfaceElement);
        isCheckList.add('; }');
      }
      String isCheckCode = isCheckList.join();

      String typeParameterIndices = 'null';
      if (_capabilities._impliesDeclarations) {
        int indexOf(TypeParameterElement typeParameter) =>
            typeParameters.indexOf(typeParameter)! + typeParametersOffset;
        typeParameterIndices = _formatAsConstList(
            'int',
            interfaceElement.typeParameters
                .where(typeParameters.items.contains)
                .map(indexOf));
      }

      int? dynamicReflectedTypeIndex = _dynamicTypeCodeIndex(
          _typeForReflectable(interfaceElement),
          await classes,
          reflectedTypes,
          reflectedTypesOffset,
          typedefs);

      return "r.GenericClassMirrorImpl(r'${classDomain._simpleName}', "
          "r'${_qualifiedName(interfaceElement)}', $descriptor, $classIndex, "
          '${await _constConstructionCode(importCollector)}, '
          '$declarationsCode, $instanceMembersCode, $staticMembersCode, '
          '$superclassIndex, $staticGettersCode, $staticSettersCode, '
          '$constructorsCode, $ownerIndex, $mixinIndex, '
          '$superinterfaceIndices, $classMetadataCode, '
          '$parameterListShapesCode, $isCheckCode, '
          '$typeParameterIndices, $dynamicReflectedTypeIndex)';
    }
  }

  Future<String> _methodMirrorCode(
      ExecutableElement element,
      Enumerator<TopLevelVariableElement> topLevelVariables,
      Enumerator<FieldElement> fields,
      Enumerator<ExecutableElement> members,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      Enumerator<ParameterElement> parameters,
      _ImportCollector importCollector,
      Map<FunctionType, int> typedefs,
      bool reflectedTypeRequested) async {
    if (element is PropertyAccessorElement && element.isSynthetic) {
      // There is no type propagation, so we declare an `accessorElement`.
      PropertyAccessorElement accessorElement = element;
      PropertyInducingElement variable = accessorElement.variable;
      int variableMirrorIndex = variable is TopLevelVariableElement
          ? topLevelVariables.indexOf(variable)!
          : fields.indexOf(variable)!;
      int selfIndex = members.indexOf(accessorElement)! + fields.length;
      if (accessorElement.isGetter) {
        return 'r.ImplicitGetterMirrorImpl('
            '${await _constConstructionCode(importCollector)}, '
            '$variableMirrorIndex, $selfIndex)';
      } else {
        assert(accessorElement.isSetter);
        return 'r.ImplicitSetterMirrorImpl('
            '${await _constConstructionCode(importCollector)}, '
            '$variableMirrorIndex, $selfIndex)';
      }
    } else {
      // [element] is a method, a function, or an explicitly declared
      // getter or setter.
      int descriptor = _declarationDescriptor(element);
      int returnTypeIndex = await _computeReturnTypeIndex(element, descriptor);
      int ownerIndex = (await _computeOwnerIndex(element, descriptor)) ??
          constants.noCapabilityIndex;
      String reflectedTypeArgumentsOfReturnType = 'null';
      if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
        reflectedTypeArgumentsOfReturnType =
            await _computeReflectedTypeArguments(
                element.returnType,
                reflectedTypes,
                reflectedTypesOffset,
                importCollector,
                typedefs);
      }
      String parameterIndicesCode = _formatAsConstList('int',
          element.parameters.map((ParameterElement parameterElement) {
        return parameters.indexOf(parameterElement);
      }));
      int reflectedReturnTypeIndex = constants.noCapabilityIndex;
      if (reflectedTypeRequested) {
        reflectedReturnTypeIndex = _typeCodeIndex(element.returnType,
            await classes, reflectedTypes, reflectedTypesOffset, typedefs);
      }
      int dynamicReflectedReturnTypeIndex = constants.noCapabilityIndex;
      if (reflectedTypeRequested) {
        dynamicReflectedReturnTypeIndex = _dynamicTypeCodeIndex(
            element.returnType,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs);
      }
      String? metadataCode = _capabilities._supportsMetadata
          ? await _extractMetadataCode(
              element, _resolver, importCollector, _generatedLibraryId)
          : null;
      return "r.MethodMirrorImpl(r'${element.name}', $descriptor, "
          '$ownerIndex, $returnTypeIndex, $reflectedReturnTypeIndex, '
          '$dynamicReflectedReturnTypeIndex, '
          '$reflectedTypeArgumentsOfReturnType, $parameterIndicesCode, '
          '${await _constConstructionCode(importCollector)}, $metadataCode)';
    }
  }

  Future<String> _topLevelVariableMirrorCode(
      TopLevelVariableElement element,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      _ImportCollector importCollector,
      Map<FunctionType, int> typedefs,
      bool reflectedTypeRequested) async {
    int descriptor = _topLevelVariableDescriptor(element);
    var owner = element.library;
    var ownerIndex = _libraries.indexOf(owner) ?? constants.noCapabilityIndex;
    int classMirrorIndex = await _computeVariableTypeIndex(element, descriptor);
    int? reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.noCapabilityIndex;
    int? dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.noCapabilityIndex;
    String reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
          element.type,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs);
    }
    String? metadataCode;
    if (_capabilities._supportsMetadata) {
      metadataCode = await _extractMetadataCode(
          element, _resolver, importCollector, _generatedLibraryId);
    } else {
      // We encode 'without capability' as `null` for metadata, because
      // it is a `List<Object>`, which has no other natural encoding.
      metadataCode = null;
    }
    return "r.VariableMirrorImpl(r'${element.name}', $descriptor, "
        '$ownerIndex, ${await _constConstructionCode(importCollector)}, '
        '$classMirrorIndex, $reflectedTypeIndex, '
        '$dynamicReflectedTypeIndex, $reflectedTypeArguments, '
        '$metadataCode)';
  }

  Future<String> _fieldMirrorCode(
      FieldElement element,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      _ImportCollector importCollector,
      Map<FunctionType, int> typedefs,
      bool reflectedTypeRequested) async {
    int descriptor = _fieldDescriptor(element);
    int ownerIndex = (await classes).indexOf(element.enclosingElement) ??
        constants.noCapabilityIndex;
    int classMirrorIndex = await _computeVariableTypeIndex(element, descriptor);
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.noCapabilityIndex;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.noCapabilityIndex;
    String reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
          element.type,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs);
    }
    String? metadataCode;
    if (_capabilities._supportsMetadata) {
      metadataCode = await _extractMetadataCode(
          element, _resolver, importCollector, _generatedLibraryId);
    } else {
      // We encode 'without capability' as `null` for metadata, because
      // it is a `List<Object>`, which has no other natural encoding.
      metadataCode = null;
    }
    return "r.VariableMirrorImpl(r'${element.name}', $descriptor, "
        '$ownerIndex, ${await _constConstructionCode(importCollector)}, '
        '$classMirrorIndex, $reflectedTypeIndex, '
        '$dynamicReflectedTypeIndex, $reflectedTypeArguments, $metadataCode)';
  }

  /// Returns the index into `ReflectorData.types` of the [Type] object
  /// corresponding to [dartType]. It may refer to a covered class, in which
  /// case [classes] is used to find it, or it may be outside the set of
  /// covered classes, in which case [reflectedTypes] may already contain it;
  /// otherwise it is not represented anywhere so far, and it is added to
  /// [reflectedTypes]; [reflectedTypesOffset] is used to adjust the index
  /// as computed by [reflectedTypes], because the elements in there will be
  /// added to `ReflectorData.types` after the elements of [classes] have been
  /// added.
  int _typeCodeIndex(
      DartType dartType,
      _InterfaceElementEnhancedSet classes,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      Map<FunctionType, int> typedefs) {
    // The types `dynamic` and `void` are handled via `...Attribute` bits.
    if (dartType.isDynamic) return constants.noCapabilityIndex;
    if (dartType is VoidType) return constants.noCapabilityIndex;
    if (dartType is InterfaceType) {
      if (dartType.typeArguments.isEmpty) {
        // A plain, non-generic class, may be handled already.
        InterfaceElement interfaceElement = dartType.element;
        if (classes.contains(interfaceElement)) {
          return classes.indexOf(interfaceElement)!;
        }
      }
      // An instantiation of a generic class, or a non-generic class which is
      // not present in `classes`: Use `reflectedTypes`, possibly adding it.
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is VoidType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(ErasableDartType(dartType, erased: false));
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is FunctionType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      int index =
          reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
      if (dartType.typeFormals.isNotEmpty) {
        typedefs[dartType] = index;
      }
      return index;
    }
    // We only handle the kinds of types already covered above. In particular,
    // we cannot produce code to return a value for `void`.
    return constants.noCapabilityIndex;
  }

  /// Returns the index into `ReflectorData.types` of the [Type] object
  /// corresponding to the fully dynamic instantiation of [dartType]. The
  /// fully dynamic instantiation replaces any existing type arguments by
  /// `dynamic`; for a non-generic class it makes no difference. This erased
  /// [Type] object may refer to a covered class, in which case [classes] is
  /// used to find it, or it may be outside the set of covered classes, in
  /// which case [reflectedTypes] may already contain it; otherwise it is not
  /// represented anywhere so far, and it is added to [reflectedTypes];
  /// [reflectedTypesOffset] is used to adjust the index as computed by
  /// [reflectedTypes], because the elements in there will be added to
  /// `ReflectorData.types` after the elements of [classes] have been added.
  int _dynamicTypeCodeIndex(
      DartType dartType,
      _InterfaceElementEnhancedSet classes,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      Map<FunctionType, int> typedefs) {
    // The types `void` and `dynamic` are handled via the `...Attribute` bits.
    if (dartType is VoidType || dartType.isDynamic) {
      return constants.noCapabilityIndex;
    }
    if (dartType is InterfaceType) {
      InterfaceElement interfaceElement = dartType.element;
      if (classes.contains(interfaceElement)) {
        return classes.indexOf(interfaceElement)!;
      }
      // [dartType] is not present in `classes`, so we must use `reflectedTypes`
      // and iff it has type arguments we must specify that it should be erased
      // (if there are no type arguments we will use "not erased": erasure
      // makes no difference and we don't want to have two identical copies).
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: dartType.typeArguments.isNotEmpty);
      reflectedTypes.add(erasableDartType);
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is VoidType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(ErasableDartType(dartType, erased: false));
      return reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
    } else if (dartType is FunctionType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      int index =
          reflectedTypes.indexOf(erasableDartType)! + reflectedTypesOffset;
      if (dartType.typeFormals.isNotEmpty) {
        // TODO(eernst) clarify: Maybe we should create an "erased" version
        // of `dartType` in this case, and adjust `erased:` above?
        typedefs[dartType] = index;
      }
      return index;
    }
    // We only handle the kinds of types already covered above.
    return constants.noCapabilityIndex;
  }

  /// Returns true iff the given [type] is not and does not contain a free
  /// type variable. [typeVariablesInScope] gives the names of type variables
  /// which are in scope (and hence not free in the relevant context).
  bool _hasNoFreeTypeVariables(DartType type,
      [Set<String>? typeVariablesInScope]) {
    if (type is TypeParameterType &&
        (typeVariablesInScope == null ||
            !typeVariablesInScope
                .contains(type.getDisplayString(withNullability: false)))) {
      return false;
    }
    if (type is InterfaceType) {
      if (type.typeArguments.isEmpty) return true;
      return type.typeArguments
          .every((type) => _hasNoFreeTypeVariables(type, typeVariablesInScope));
    }
    // Possible kinds of types at this point (apart from several types
    // indicating an error that we do not expect here): `BottomTypeImpl`,
    // `DynamicTypeImpl`, `FunctionTypeImpl`, `VoidTypeImpl`. None of these
    // have type variables.
    return true;
  }

  /// Returns a string containing a type expression that in the generated
  /// library will serve as a type argument with the same meaning as the
  /// [dartType] has where it occurs. The [importCollector] is used to
  /// find the library prefixes needed in order to obtain values from other
  /// libraries. [typeVariablesInScope] is used to allow generation of
  /// type expressions containing type variables which are in scope because
  /// they were introduced by an enclosing generic function type. [typedefs]
  /// is a mapping from generic function types which have had a `typedef`
  /// declaration allocated for them to their indices; it may be extended
  /// as well as used by this function. [useNameOfGenericFunctionType]
  /// is used to decide whether the output should be a simple `typedef`
  /// name or a fully spelled-out generic function type (and it has no
  /// effect when [dartType] is not a generic function type).
  Future<String> _typeCodeOfTypeArgument(
      DartType dartType,
      _ImportCollector importCollector,
      Set<String> typeVariablesInScope,
      Map<FunctionType, int> typedefs,
      {bool useNameOfGenericFunctionType = true}) async {
    Future<String> fail() async {
      var element = dartType is InterfaceType ? dartType.element : null;
      log.warning(await _formatDiagnosticMessage(
          'Attempt to generate code for an '
          'unsupported kind of type: $dartType (${dartType.runtimeType}). '
          'Generating `dynamic`.',
          element,
          _resolver));
      return 'dynamic';
    }

    if (dartType.isDynamic) return 'dynamic';
    if (dartType is InterfaceType) {
      InterfaceElement interfaceElement = dartType.element;
      if ((interfaceElement is MixinApplication &&
              interfaceElement.declaredName == null) ||
          interfaceElement.isPrivate) {
        return await fail();
      }
      String prefix = importCollector._getPrefix(interfaceElement.library);
      if (interfaceElement.typeParameters.isEmpty) {
        return '$prefix${interfaceElement.name}';
      } else {
        if (dartType.typeArguments.every(
            (type) => _hasNoFreeTypeVariables(type, typeVariablesInScope))) {
          List<String> argumentList = [];
          for (DartType typeArgument in dartType.typeArguments) {
            argumentList.add(await _typeCodeOfTypeArgument(
                typeArgument, importCollector, typeVariablesInScope, typedefs,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType));
          }
          String arguments = argumentList.join(', ');
          return '$prefix${interfaceElement.name}<$arguments>';
        } else {
          return await fail();
        }
      }
    } else if (dartType is VoidType) {
      return 'void';
    } else if (dartType is FunctionType) {
      final Element? dartTypeElement = dartType.alias?.element;
      if (dartTypeElement is TypeAliasElement) {
        String prefix = importCollector._getPrefix(dartTypeElement.library);
        return '$prefix${dartTypeElement.name}';
      } else {
        // Generic function types need separate `typedef`s.
        if (dartType.typeFormals.isNotEmpty) {
          if (useNameOfGenericFunctionType) {
            // Requested: just the name of the typedef; get it and return.
            int dartTypeNumber = typedefs.containsKey(dartType)
                ? typedefs[dartType]!
                : typedefNumber++;
            return _typedefName(dartTypeNumber);
          } else {
            // Requested: the spelled-out generic function type; continue.
            typeVariablesInScope
                .addAll(dartType.typeFormals.map((element) => element.name));
          }
        }
        String returnType = await _typeCodeOfTypeArgument(dartType.returnType,
            importCollector, typeVariablesInScope, typedefs,
            useNameOfGenericFunctionType: useNameOfGenericFunctionType);
        String typeArguments = '';
        if (dartType.typeFormals.isNotEmpty) {
          Iterable<String> typeArgumentList = dartType.typeFormals.map(
              (TypeParameterElement typeParameter) => typeParameter.toString());
          typeArguments = '<${typeArgumentList.join(', ')}>';
        }
        String argumentTypes = '';
        if (dartType.normalParameterTypes.isNotEmpty) {
          List<String> normalParameterTypeList = [];
          for (DartType parameterType in dartType.normalParameterTypes) {
            normalParameterTypeList.add(await _typeCodeOfTypeArgument(
                parameterType, importCollector, typeVariablesInScope, typedefs,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType));
          }
          argumentTypes = normalParameterTypeList.join(', ');
        }
        if (dartType.optionalParameterTypes.isNotEmpty) {
          List<String> optionalParameterTypeList = [];
          for (DartType parameterType in dartType.optionalParameterTypes) {
            optionalParameterTypeList.add(await _typeCodeOfTypeArgument(
                parameterType, importCollector, typeVariablesInScope, typedefs,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType));
          }
          String connector = argumentTypes.isEmpty ? '' : ', ';
          argumentTypes = '$argumentTypes$connector'
              '[${optionalParameterTypeList.join(', ')}]';
        }
        if (dartType.namedParameterTypes.isNotEmpty) {
          Map<String, DartType> parameterMap = dartType.namedParameterTypes;
          List<String> namedParameterTypeList = [];
          for (String name in parameterMap.keys) {
            DartType parameterType = parameterMap[name]!;
            String typeCode = await _typeCodeOfTypeArgument(
                parameterType, importCollector, typeVariablesInScope, typedefs,
                useNameOfGenericFunctionType: useNameOfGenericFunctionType);
            namedParameterTypeList.add('$typeCode $name');
          }
          String connector = argumentTypes.isEmpty ? '' : ', ';
          argumentTypes = '$argumentTypes$connector'
              '{${namedParameterTypeList.join(', ')}}';
        }
        return '$returnType Function$typeArguments($argumentTypes)';
      }
    } else if (dartType is TypeParameterType &&
        typeVariablesInScope
            .contains(dartType.getDisplayString(withNullability: false))) {
      return dartType.getDisplayString(withNullability: false);
    } else {
      return fail();
    }
  }

  /// Returns a string containing code that in the generated library will
  /// evaluate to a [Type] value like the value we would have obtained by
  /// evaluating the [typeDefiningElement] as an expression in the library
  /// where it occurs. [importCollector] is used to find the library prefixes
  /// needed in order to obtain values from other libraries.
  Future<String> _typeCodeOfClass(DartType dartType,
      _ImportCollector importCollector, Map<FunctionType, int> typedefs) async {
    var typeVariablesInScope = <String>{}; // None at this level.
    if (dartType.isDynamic) return 'dynamic';
    if (dartType is InterfaceType) {
      InterfaceElement interfaceElement = dartType.element;
      if ((interfaceElement is MixinApplication &&
              interfaceElement.declaredName == null) ||
          interfaceElement.isPrivate) {
        // The test for an anonymous mixin application above may be dead code:
        // Currently no test uses an anonymous mixin application to reach this
        // point. But code coverage is not easy to achieve in this case:
        // An anonymous mixin application cannot be the type of an instance,
        // and it cannot be denoted by an expression and hence it cannot be a
        // type annotation.
        //
        // However, if the situation should arise the following approach will
        // work for the anonymous mixin application as well as for the private
        // class.
        return "const r.FakeType(r'${_qualifiedName(interfaceElement)}')";
      }
      String prefix = importCollector._getPrefix(interfaceElement.library);
      if (interfaceElement.typeParameters.isEmpty) {
        return '$prefix${interfaceElement.name}';
      } else {
        if (dartType.typeArguments.every(_hasNoFreeTypeVariables)) {
          String typeArgumentCode = await _typeCodeOfTypeArgument(
              dartType, importCollector, typeVariablesInScope, typedefs,
              useNameOfGenericFunctionType: true);
          return 'const m.TypeValue<$typeArgumentCode>().type';
        } else {
          String arguments = dartType.typeArguments
              .map((DartType typeArgument) => typeArgument.toString())
              .join(', ');
          return 'const r.FakeType('
              "r'${_qualifiedName(interfaceElement)}<$arguments>')";
        }
      }
    } else if (dartType is VoidType) {
      return 'const m.TypeValue<void>().type';
    } else if (dartType is FunctionType) {
      // A function type is inherently not private, so we ignore privacy.
      // Note that some function types are _claimed_ to be private in analyzer
      // 0.36.4, so it is a bug to test for it.
      final Element? dartTypeElement = dartType.alias?.element;
      if (dartTypeElement is TypeAliasElement) {
        String prefix = importCollector._getPrefix(dartTypeElement.library);
        return '$prefix${dartTypeElement.name}';
      } else {
        if (dartType.typeFormals.isNotEmpty) {
          // `dartType` is a generic function type, so we must use a
          // separately generated `typedef` to obtain a `Type` for it.
          return await _typeCodeOfTypeArgument(
              dartType, importCollector, typeVariablesInScope, typedefs,
              useNameOfGenericFunctionType: true);
        } else {
          String typeArgumentCode = await _typeCodeOfTypeArgument(
              dartType, importCollector, typeVariablesInScope, typedefs);
          return 'const m.TypeValue<$typeArgumentCode>().type';
        }
      }
    } else {
      var element = dartType is InterfaceType ? dartType.element : null;
      log.warning(await _formatDiagnosticMessage(
          'Attempt to generate code for an '
          'unsupported kind of type: $dartType (${dartType.runtimeType}). '
          'Generating `dynamic`.',
          element,
          _resolver));
      return 'dynamic';
    }
  }

  /// Returns a string containing code that in the generated library will
  /// evaluate to a [Type] value like the value we would have obtained by
  /// evaluating the [typeDefiningElement] as an expression in the library
  /// where it occurs, except that all type arguments are stripped such
  /// that we get the fully dynamic instantiation if it is a generic class.
  /// [importCollector] is used to find the library prefixes needed in order
  /// to obtain values from other libraries.
  String _dynamicTypeCodeOfClass(TypeDefiningElement typeDefiningElement,
      _ImportCollector importCollector) {
    DartType? type = typeDefiningElement is InterfaceElement
        ? _typeForReflectable(typeDefiningElement)
        : null;
    if (type?.isDynamic ?? true) return 'dynamic';
    if (type is InterfaceType) {
      InterfaceElement interfaceElement = type.element;
      if ((interfaceElement is MixinApplication &&
              interfaceElement.declaredName == null) ||
          interfaceElement.isPrivate) {
        return "const r.FakeType(r'${_qualifiedName(interfaceElement)}')";
      }
      String prefix = importCollector._getPrefix(interfaceElement.library);
      return '$prefix${interfaceElement.name}';
    } else if (type is VoidType) {
      return 'const m.TypeValue<void>().type';
    } else {
      // This may be dead code: There is no test which reaches this point,
      // and it is not obvious how we could encounter any [type] which is not
      // an [InterfaceType], given that it is a member of `classes`. However,
      // the following treatment is benign, and nicer than crashing if there
      // is some exception that we have overlooked.
      return "const r.FakeType(r'${_qualifiedName(typeDefiningElement)}')";
    }
  }

  Future<String> _libraryMirrorCode(
      _LibraryDomain libraryDomain,
      int libraryIndex,
      Enumerator<ExecutableElement> members,
      Enumerator<ParameterListShape> parameterListShapes,
      Map<ExecutableElement, ParameterListShape> parameterListShapeOf,
      Enumerator<TopLevelVariableElement> variables,
      int methodsOffset,
      _ImportCollector importCollector) async {
    LibraryElement library = libraryDomain._libraryElement;

    List<String> gettersCodeList = [];
    for (ExecutableElement getter in _gettersOfLibrary(libraryDomain)) {
      gettersCodeList.add(
          await _topLevelGettingClosure(importCollector, library, getter.name));
    }
    String gettersCode = _formatAsMap(gettersCodeList);

    List<String> settersCodeList = [];
    for (PropertyAccessorElement setter in _settersOfLibrary(libraryDomain)) {
      settersCodeList.add(
          await _topLevelSettingClosure(importCollector, library, setter.name));
    }
    String settersCode = _formatAsMap(settersCodeList);

    // Fields go first in [memberMirrors], so they will get the
    // same index as in [fields].
    Iterable<int> variableIndices =
        libraryDomain._declaredVariables.map((TopLevelVariableElement element) {
      return variables.indexOf(element)!;
    });

    // All the elements in the behavioral interface go after the
    // fields in [memberMirrors], so they must get an offset of
    // `fields.length` on the index.
    Iterable<int> methodIndices = libraryDomain._declarations
        .where(_executableIsntImplicitGetterOrSetter)
        .map((ExecutableElement element) {
      int index = members.indexOf(element)!;
      return index + methodsOffset;
    });

    String declarationsCode = 'const <int>[${constants.noCapabilityIndex}]';
    if (_capabilities._impliesDeclarations) {
      Iterable<int> declarationsIndices = [
        ...variableIndices,
        ...methodIndices,
      ];
      declarationsCode = _formatAsConstList('int', declarationsIndices);
    }

    // TODO(sigurdm) clarify: Find out how to get good uri's in a
    // builder.
    String uriCode =
        (_capabilities._supportsUri || _capabilities._supportsLibraries)
            ? "Uri.parse(r'reflectable://$libraryIndex/$library')"
            : 'null';

    String metadataCode;
    if (_capabilities._supportsMetadata) {
      metadataCode = await _extractMetadataCode(
          library, _resolver, importCollector, _generatedLibraryId);
    } else {
      metadataCode = 'null';
    }

    String parameterListShapesCode = 'null';
    if (_capabilities._impliesParameterListShapes) {
      parameterListShapesCode = _formatAsMap(
          libraryDomain._declarations.map((ExecutableElement element) {
        // shape != null: every method has a shape in `..shapeOf`.
        ParameterListShape shape = parameterListShapeOf[element]!;
        // index != null: every shape is in `..Shapes`.
        int index = parameterListShapes.indexOf(shape)!;
        return "r'${element.name}': $index";
      }));
    }

    return "r.LibraryMirrorImpl(r'${library.name}', $uriCode, "
        '${await _constConstructionCode(importCollector)}, '
        '$declarationsCode, $gettersCode, $settersCode, $metadataCode, '
        '$parameterListShapesCode)';
  }

  Future<String> _parameterMirrorCode(
      ParameterElement element,
      Enumerator<FieldElement> fields,
      Enumerator<ExecutableElement> members,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      _ImportCollector importCollector,
      Map<FunctionType, int> typedefs,
      bool reflectedTypeRequested) async {
    int descriptor = _parameterDescriptor(element);
    int ownerIndex =
        members.indexOf(element.enclosingElement!)! + fields.length;
    int classMirrorIndex = constants.noCapabilityIndex;
    if (_capabilities._impliesTypes) {
      if (descriptor & constants.dynamicAttribute != 0 ||
          descriptor & constants.voidAttribute != 0) {
        // This parameter will report its type as [dynamic]/[void], and it
        // will never use `classMirrorIndex`. Keep noCapabilityIndex.
      } else if (descriptor & constants.classTypeAttribute != 0) {
        // Normal encoding of a class type. If that class has been added
        // to `classes` we use its `indexOf`; otherwise (if we do not have an
        // [ec.TypeAnnotationQuantifyCapability]) we must indicate that the
        // capability is absent.
        var elementType = element.type;
        if (elementType is InterfaceType) {
          var elementTypeElement = elementType.element;
          classMirrorIndex = (await classes).contains(elementTypeElement)
              ? (await classes).indexOf(elementTypeElement)!
              : constants.noCapabilityIndex;
        } else {
          classMirrorIndex = constants.noCapabilityIndex;
        }
      }
    }
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.noCapabilityIndex;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.noCapabilityIndex;
    String reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
          element.type,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs);
    }
    String metadataCode = 'null';
    if (_capabilities._supportsMetadata) {
      // TODO(eernst): 'dart:*' is not considered valid. To survive, we
      // return the empty metadata for elements from 'dart:*'. Issue 173.
      if (_isPlatformLibrary(element.library!)) {
        metadataCode = 'const []';
      } else {
        var node =
            await _getDeclarationAst(element, _resolver) as FormalParameter?;
        // The node may be null because the element is synthetic, and
        // then it has no metadata.
        if (node == null) {
          metadataCode = 'const []';
        } else {
          metadataCode = await _extractMetadataCode(
              element, _resolver, importCollector, _generatedLibraryId);
        }
      }
    }
    String code = await _extractDefaultValueCode(importCollector, element);
    String defaultValueCode = code.isEmpty ? 'null' : code;
    String parameterSymbolCode = descriptor & constants.namedAttribute != 0
        ? '#${element.name}'
        : 'null';

    return "r.ParameterMirrorImpl(r'${element.name}', $descriptor, "
        '$ownerIndex, ${await _constConstructionCode(importCollector)}, '
        '$classMirrorIndex, $reflectedTypeIndex, $dynamicReflectedTypeIndex, '
        '$reflectedTypeArguments, $metadataCode, $defaultValueCode, '
        '$parameterSymbolCode)';
  }

  /// Given an [importCollector] and a [parameterElement], returns '' if there
  /// is no default value, otherwise returns code for an expression that
  /// evaluates to said default value.
  Future<String> _extractDefaultValueCode(_ImportCollector importCollector,
      ParameterElement parameterElement) async {
    // TODO(eernst): 'dart:*' is not considered valid. To survive, we return
    // '' for all declarations from there. Issue 173.
    if (_isPlatformLibrary(parameterElement.library!)) return '';
    var parameterNode = await _getDeclarationAst(parameterElement, _resolver)
        as FormalParameter?;
    // The node can be null because the declaration is synthetic, e.g.,
    // the parameter of an induced setter; they have no default value.
    if (parameterNode is DefaultFormalParameter &&
        parameterNode.defaultValue != null) {
      return await _extractConstantCode(parameterNode.defaultValue!,
          importCollector, _generatedLibraryId, _resolver);
    } else if (parameterElement is DefaultFieldFormalParameterElementImpl) {
      Expression? defaultValue = parameterElement.constantInitializer;
      if (defaultValue != null) {
        return await _extractConstantCode(
            defaultValue, importCollector, _generatedLibraryId, _resolver);
      }
    }
    return '';
  }
}

DartType _typeForReflectable(InterfaceElement interfaceElement) {
  // TODO(eernst): This getter is used to inspect subclass relationships,
  // so there is no need to handle type parameters/arguments. So we might
  // be able to improve performance by working on classes as such.
  var typeArguments = List<DartType>.filled(
      interfaceElement.typeParameters.length,
      interfaceElement.library.typeProvider.dynamicType);
  return interfaceElement.instantiate(
      typeArguments: typeArguments, nullabilitySuffix: NullabilitySuffix.star);
}

/// Auxiliary class used by `classes`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SubtypesFixedPoint extends FixedPoint<InterfaceElement> {
  final Map<InterfaceElement, Set<InterfaceElement>> subtypes;

  _SubtypesFixedPoint(this.subtypes);

  /// Returns all the immediate subtypes of the given [classMirror].
  @override
  Future<Iterable<InterfaceElement>> successors(
      final InterfaceElement interfaceElement) async {
    Iterable<InterfaceElement>? interfaceElements = subtypes[interfaceElement];
    return interfaceElements ?? <InterfaceElement>[];
  }
}

/// Auxiliary class used by `classes`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SuperclassFixedPoint extends FixedPoint<InterfaceElement> {
  final Map<InterfaceElement, bool> upwardsClosureBounds;
  final bool mixinsRequested;

  _SuperclassFixedPoint(this.upwardsClosureBounds, this.mixinsRequested);

  /// Returns the direct superclass of [element] if it satisfies the given
  /// bounds: If there are any elements in [upwardsClosureBounds] only
  /// classes which are subclasses of an upper bound specified there are
  /// returned (for each bound, if it maps to true then `excludeUpperBound`
  /// was specified, in which case only proper subclasses are returned).
  /// If [mixinsRequested], when considering a superclass which was created as
  /// a mixin application, the class which was applied as a mixin
  /// is also returned (without consulting [upwardsClosureBounds], because a
  /// class used as a mixin cannot have other superclasses than [Object]).
  /// TODO(eernst) implement: When mixins can have nontrivial superclasses
  /// we may or may not wish to enforce the bounds even for mixins.
  @override
  Future<Iterable<InterfaceElement>> successors(
      InterfaceElement element) async {
    // A mixin application is handled by its regular subclasses.
    if (element is MixinApplication) return [];
    // If upper bounds not satisfied then there are no successors.
    if (!_includedByUpwardsClosure(element)) return [];

    InterfaceType? workingSuperType = element.supertype;
    if (workingSuperType == null) {
      return []; // "Superclass of [Object]", ignore.
    }
    var workingSuperclass = workingSuperType.element;

    List<InterfaceElement> result = [];

    if (_includedByUpwardsClosure(workingSuperclass)) {
      result.add(workingSuperclass);
    }

    // Create the chain of mixin applications between [interfaceElement] and the
    // next non-mixin-application class that it extends. If [mixinsRequested]
    // then for each mixin application add the class [mixinClass] which was
    // applied as a mixin (it is then considered as yet another superclass).
    // Note that we iterate from the most general to more special mixins,
    // that is, for `class C extends B with M1, M2..` we visit `M1` before
    // `M2`, which makes the right `superclass` available at each step. We
    // must provide the immediate subclass of each [MixinApplication] when
    // is a regular class (not a mixin application), otherwise [null], which
    // is done with [subClass].
    InterfaceElement superclass = workingSuperclass;
    for (InterfaceType mixin in element.mixins) {
      var mixinClass = mixin.element;
      if (mixinsRequested) result.add(mixinClass);
      InterfaceElement? subClass =
          mixin == element.mixins.last ? element : null;
      String? name = subClass == null
          ? null
          : (element is MixinApplication && element.isMixinApplication
              ? element.name
              : null);
      InterfaceElement mixinApplication = MixinApplication(
          name, superclass, mixinClass, element.library, subClass);
      // We have already ensured that `workingSuperclass` is a
      // subclass of a bound (if any); the value of `superclass` is
      // either `workingSuperclass` or one of its superclasses created
      // by mixin application. Since there is no way to denote these
      // mixin applications directly, they must also be subclasses
      // of a bound, so these mixin applications must be added
      // unconditionally.
      result.add(mixinApplication);
      superclass = mixinApplication;
    }
    return result;
  }

  bool _includedByUpwardsClosure(InterfaceElement interfaceElement) {
    bool helper(InterfaceElement interfaceElement, bool direct) {
      bool isSuperclassOfInterfaceElement(InterfaceElement bound) {
        if (interfaceElement == bound) {
          // If `!direct` then the desired subclass relation exists.
          // If `direct` then the original `interfaceElement` is equal to
          // `bound`, so we must return false if `excludeUpperBound`.
          return !direct || !upwardsClosureBounds[bound]!;
        }
        var interfaceElementSupertype = interfaceElement.supertype;
        if (interfaceElementSupertype == null) return false;
        return helper(interfaceElementSupertype.element, false);
      }

      return upwardsClosureBounds.keys.any(isSuperclassOfInterfaceElement);
    }

    return upwardsClosureBounds.isEmpty || helper(interfaceElement, true);
  }
}

/// Auxiliary function used by `classes`. Its `expand` method
/// expands its argument to a fixed point, based on the `successors` method.
Set<InterfaceElement> _mixinApplicationsOfClasses(
    Set<InterfaceElement> classes) {
  var mixinApplications = <InterfaceElement>{};
  for (InterfaceElement interfaceElement in classes) {
    // Mixin-applications are handled when they are created.
    if (interfaceElement is MixinApplication) continue;
    InterfaceType? supertype = interfaceElement.supertype;
    if (supertype == null) continue; // "Superclass of [Object]", ignore.
    var superclass = supertype.element;
    // Note that we iterate from the most general mixin to more specific ones,
    // that is, with `class C extends B with M1, M2..` we visit `M1` before
    // `M2`; this ensures that the right `superclass` is available for each
    // new [MixinApplication] created.  We must provide the immediate subclass
    // of each [MixinApplication] when it is a regular class (not a mixin
    // application), otherwise [null], which is done with [subClass].
    for (var mixin in interfaceElement.mixins) {
      var mixinClass = mixin.element;
      InterfaceElement? subClass =
          mixin == interfaceElement.mixins.last ? interfaceElement : null;
      String? name = subClass == null
          ? null
          : (interfaceElement is MixinApplication &&
                  interfaceElement.isMixinApplication
              ? interfaceElement.name
              : null);
      InterfaceElement mixinApplication = MixinApplication(
          name, superclass, mixinClass, interfaceElement.library, subClass);
      mixinApplications.add(mixinApplication);
      superclass = mixinApplication;
    }
  }
  return mixinApplications;
}

/// Auxiliary type used by [_AnnotationClassFixedPoint].
typedef _ElementToDomain = _ClassDomain Function(InterfaceElement);

/// Auxiliary class used by `classes`. Its `expand` method
/// expands its argument to a fixed point, based on the `successors` method.
/// It uses [resolver] in a check for "importability" of some private core
/// classes (that we must avoid attempting to use because they are unavailable
/// to user programs). [generatedLibraryId] must refer to the asset where the
/// generated code will be stored; it is used in the same check.
class _AnnotationClassFixedPoint extends FixedPoint<InterfaceElement> {
  final Resolver resolver;
  final AssetId generatedLibraryId;
  final _ElementToDomain elementToDomain;

  _AnnotationClassFixedPoint(
      this.resolver, this.generatedLibraryId, this.elementToDomain);

  /// Returns the classes that occur as return types of covered methods or in
  /// type annotations of covered variables and parameters of covered methods,
  @override
  Future<Iterable<InterfaceElement>> successors(
      InterfaceElement interfaceElement) async {
    if (!await _isImportable(interfaceElement, generatedLibraryId, resolver)) {
      return [];
    }
    _ClassDomain classDomain = elementToDomain(interfaceElement);

    // Mixin-applications do not add further methods and fields.
    if (classDomain._interfaceElement is MixinApplication) return [];

    List<InterfaceElement> result = [];

    // Traverse type annotations to find successors. Note that we cannot
    // abstract the many redundant elements below, because `yield` cannot
    // occur in a local function.
    for (FieldElement fieldElement in classDomain._declaredFields) {
      var fieldType = fieldElement.type;
      if (fieldType is InterfaceType) {
        result.add(fieldType.element);
      }
    }
    for (ParameterElement parameterElement in classDomain._declaredParameters) {
      var parameterType = parameterElement.type;
      if (parameterType is InterfaceType) {
        result.add(parameterType.element);
      }
    }
    for (ParameterElement parameterElement in classDomain._instanceParameters) {
      var parameterType = parameterElement.type;
      if (parameterType is InterfaceType) {
        result.add(parameterType.element);
      }
    }
    for (ExecutableElement executableElement in classDomain._declaredMethods) {
      var executableReturnType = executableElement.returnType;
      if (executableReturnType is InterfaceType) {
        result.add(executableReturnType.element);
      }
    }
    for (ExecutableElement executableElement in classDomain._instanceMembers) {
      var executableReturnType = executableElement.returnType;
      if (executableReturnType is InterfaceType) {
        result.add(executableReturnType.element);
      }
    }
    return result;
  }
}

final RegExp _identifierRegExp = RegExp(r'^[A-Za-z$_][A-Za-z$_0-9]*$');

// Auxiliary function used by `_generateCode`.
String _gettingClosure(String getterName) {
  String closure;
  if (_identifierRegExp.hasMatch(getterName)) {
    // Starts with letter, not an operator.
    closure = '(dynamic instance) => instance.$getterName';
  } else if (getterName == '[]=') {
    closure = '(dynamic instance) => (x, v) => instance[x] = v';
  } else if (getterName == '[]') {
    closure = '(dynamic instance) => (x) => instance[x]';
  } else if (getterName == 'unary-') {
    closure = '(dynamic instance) => () => -instance';
  } else if (getterName == '~') {
    closure = '(dynamic instance) => () => ~instance';
  } else {
    closure = '(dynamic instance) => (x) => instance $getterName x';
  }
  return "r'$getterName': $closure";
}

// Auxiliary function used by `_generateCode`.
String _settingClosure(String setterName) {
  assert(setterName.substring(setterName.length - 1) == '=');
  String name = setterName.substring(0, setterName.length - 1);
  return "r'$setterName': (dynamic instance, value) => instance.$name = value";
}

// Auxiliary function used by `_generateCode`.
Future<String> _staticGettingClosure(_ImportCollector importCollector,
    InterfaceElement interfaceElement, String getterName) async {
  String className = interfaceElement.name;
  String prefix = importCollector._getPrefix(interfaceElement.library);
  // Operators cannot be static.
  if (_isPrivateName(getterName)) {
    await _severe('Cannot access private name $getterName', interfaceElement);
  }
  if (_isPrivateName(className)) {
    await _severe('Cannot access private name $className', interfaceElement);
  }
  return "r'$getterName': () => $prefix$className.$getterName";
}

// Auxiliary function used by `_generateCode`.
Future<String> _staticSettingClosure(_ImportCollector importCollector,
    InterfaceElement interfaceElement, String setterName) async {
  assert(setterName.substring(setterName.length - 1) == '=');
  // The [setterName] includes the '=', remove it.
  String name = setterName.substring(0, setterName.length - 1);
  String className = interfaceElement.name;
  String prefix = importCollector._getPrefix(interfaceElement.library);
  if (_isPrivateName(setterName)) {
    await _severe('Cannot access private name $setterName', interfaceElement);
  }
  if (_isPrivateName(className)) {
    await _severe('Cannot access private name $className', interfaceElement);
  }
  return "r'$setterName': (dynamic value) => $prefix$className.$name = value";
}

// Auxiliary function used by `_generateCode`.
Future<String> _topLevelGettingClosure(_ImportCollector importCollector,
    LibraryElement library, String getterName) async {
  String prefix = importCollector._getPrefix(library);
  // Operators cannot be top-level.
  if (_isPrivateName(getterName)) {
    await _severe('Cannot access private name $getterName', library);
  }
  return "r'$getterName': () => $prefix$getterName";
}

// Auxiliary function used by `_generateCode`.
Future<String> _topLevelSettingClosure(_ImportCollector importCollector,
    LibraryElement library, String setterName) async {
  assert(setterName.substring(setterName.length - 1) == '=');
  // The [setterName] includes the '=', remove it.
  String name = setterName.substring(0, setterName.length - 1);
  String prefix = importCollector._getPrefix(library);
  if (_isPrivateName(name)) {
    await _severe('Cannot access private name $name', library);
  }
  return "r'$setterName': (dynamic value) => $prefix$name = value";
}

// Auxiliary function used by `_typeCodeIndex`.
String _typedefName(int id) => 'typedef$id';

/// Information about reflectability for a given library.
class _LibraryDomain {
  /// Element describing the target library.
  final LibraryElement _libraryElement;

  /// Fields declared by [_libraryElement] and included for reflection support,
  /// according to the reflector described by the [_reflectorDomain];
  /// obtained by filtering `_libraryElement.fields`.
  final Iterable<TopLevelVariableElement> _declaredVariables;

  /// Methods which are declared by [_libraryElement] and included for
  /// reflection support, according to the reflector described by
  /// [_reflectorDomain]; obtained by filtering `_libraryElement.functions`.
  final Iterable<FunctionElement> _declaredFunctions;

  /// Formal parameters declared by one of the [_declaredFunctions].
  final Iterable<ParameterElement> _declaredParameters;

  /// Getters and setters possessed by [_libraryElement] and included for
  /// reflection support, according to the reflector described by
  /// [_reflectorDomain]; obtained by filtering `_libraryElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors, implicitly
  /// created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> _accessors;

  /// The reflector domain that holds [this] object as one of its
  /// library domains.
  final _ReflectorDomain _reflectorDomain;

  _LibraryDomain(
      this._libraryElement,
      this._declaredVariables,
      this._declaredFunctions,
      this._declaredParameters,
      this._accessors,
      this._reflectorDomain);

  /// Returns the declared methods, accessors and constructors in
  /// [_interfaceElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations => [
        ..._declaredFunctions,
        ..._accessors,
      ];

  @override
  String toString() {
    return 'LibraryDomain($_libraryElement)';
  }

  @override
  bool operator ==(Object other) {
    if (other is _LibraryDomain) {
      return _libraryElement == other._libraryElement &&
          _reflectorDomain == other._reflectorDomain;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => _libraryElement.hashCode ^ _reflectorDomain.hashCode;
}

/// Information about reflectability for a given class.
class _ClassDomain {
  /// Element describing the target class.
  final InterfaceElement _interfaceElement;

  /// Fields declared by [_interfaceElement] and included for reflection support,
  /// according to the reflector described by the [_reflectorDomain];
  /// obtained by filtering `_interfaceElement.fields`.
  final Iterable<FieldElement> _declaredFields;

  /// Methods which are declared by [_interfaceElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `_interfaceElement.methods`.
  final Iterable<MethodElement> _declaredMethods;

  /// Formal parameters declared by one of the [_declaredMethods].
  final Iterable<ParameterElement> _declaredParameters;

  /// Getters and setters possessed by [_interfaceElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `_interfaceElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors,
  /// implicitly created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> _accessors;

  /// Constructors declared by [_interfaceElement] and included for reflection
  /// support, according to the reflector described by [_reflectorDomain];
  /// obtained by filtering `_interfaceElement.constructors`.
  final Iterable<ConstructorElement> _constructors;

  /// The reflector domain that holds [this] object as one of its
  /// class domains.
  final _ReflectorDomain _reflectorDomain;

  _ClassDomain(
      this._interfaceElement,
      this._declaredFields,
      this._declaredMethods,
      this._declaredParameters,
      this._accessors,
      this._constructors,
      this._reflectorDomain);

  String get _simpleName {
    // TODO(eernst) clarify: Decide whether this should be simplified
    // by adding a method implementation to `MixinApplication`.
    var interfaceElement = _interfaceElement;
    if (interfaceElement is MixinApplication &&
        interfaceElement.isMixinApplication) {
      // This is the case `class B = A with M;`.
      return interfaceElement.name;
    } else if (interfaceElement is MixinApplication) {
      // This is the case `class B extends A with M1, .. Mk {..}`
      // where `interfaceElement` denotes one of the mixin applications
      // that constitute the superclass chain between `B` and `A`, both
      // excluded.
      List<InterfaceType> mixins = interfaceElement.mixins;
      var superclassType = interfaceElement.supertype as InterfaceType;
      var superclassTypeElement = superclassType.element;
      String superclassName = _qualifiedName(superclassTypeElement);
      StringBuffer name = StringBuffer(superclassName);
      bool firstSeparator = true;
      for (InterfaceType mixin in mixins) {
        name.write(firstSeparator ? ' with ' : ', ');
        name.write(_qualifiedName(mixin.element));
        firstSeparator = false;
      }
      return name.toString();
    } else {
      // This is a regular class, i.e., we can use its declared name.
      return interfaceElement.name;
    }
  }

  /// Returns the declared methods, accessors and constructors in
  /// [_interfaceElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations => [
        // TODO(sigurdm) feature: Include type variables (if we keep them).
        ..._declaredMethods,
        ..._accessors,
        ..._constructors,
      ];

  /// Finds all instance members by going through the class hierarchy.
  Iterable<ExecutableElement> get _instanceMembers {
    Map<String, ExecutableElement> helper(InterfaceElement interfaceElement) {
      var member = _reflectorDomain._instanceMemberCache[interfaceElement];
      if (member != null) return member;
      Map<String, ExecutableElement> result = <String, ExecutableElement>{};

      void addIfCapable(String name, ExecutableElement member) {
        if (member.isPrivate) return;
        // If [member] is a synthetic accessor created from a field, search for
        // the metadata on the original field.
        List<ElementAnnotation> metadata =
            (member is PropertyAccessorElement && member.isSynthetic)
                ? member.variable.metadata
                : member.metadata;
        List<ElementAnnotation>? getterMetadata;
        if (_reflectorDomain._capabilities._impliesCorrespondingSetters &&
            member is PropertyAccessorElement &&
            !member.isSynthetic &&
            member.isSetter) {
          PropertyAccessorElement? correspondingGetter =
              member.correspondingGetter;
          getterMetadata = correspondingGetter?.metadata;
        }
        if (_reflectorDomain._capabilities.supportsInstanceInvoke(
            member.library.typeSystem, member.name, metadata, getterMetadata)) {
          result[name] = member;
        }
      }

      void addTypeIfCapable(InterfaceType type) {
        helper(type.element).forEach(addIfCapable);
      }

      void addIfCapableConcreteInstance(ExecutableElement member) {
        if (!member.isAbstract && !member.isStatic) {
          addIfCapable(member.name, member);
        }
      }

      Map<String, ExecutableElement> cacheResult(
          Map<String, ExecutableElement> result) {
        result = Map.unmodifiable(result);
        _reflectorDomain._instanceMemberCache[interfaceElement] = result;
        return result;
      }

      if (interfaceElement is MixinApplication) {
        helper(interfaceElement.superclass).forEach(addIfCapable);
        helper(interfaceElement.mixin).forEach(addIfCapable);
        return cacheResult(result);
      }
      var superclassType = interfaceElement.supertype;
      if (superclassType is InterfaceType) {
        var superclassElement = superclassType.element;
        helper(superclassElement).forEach(addIfCapable);
      }
      interfaceElement.mixins.forEach(addTypeIfCapable);
      interfaceElement.methods.forEach(addIfCapableConcreteInstance);
      interfaceElement.accessors.forEach(addIfCapableConcreteInstance);

      return cacheResult(result);
    }

    return helper(_interfaceElement).values;
  }

  /// Finds all parameters of instance members.
  Iterable<ParameterElement> get _instanceParameters {
    List<ParameterElement> result = <ParameterElement>[];
    if (_reflectorDomain._capabilities._impliesDeclarations) {
      for (ExecutableElement executableElement in _instanceMembers) {
        result.addAll(executableElement.parameters);
      }
    }
    return result;
  }

  /// Finds all static members.
  Iterable<ExecutableElement> get _staticMembers {
    List<ExecutableElement> result = <ExecutableElement>[];
    if (_interfaceElement is MixinApplication) return result;

    void possiblyAddMethod(MethodElement method) {
      if (method.isStatic &&
          !method.isPrivate &&
          _reflectorDomain._capabilities.supportsStaticInvoke(
              method.library.typeSystem, method.name, method.metadata, null)) {
        result.add(method);
      }
    }

    void possiblyAddAccessor(PropertyAccessorElement accessor) {
      if (!accessor.isStatic || accessor.isPrivate) return;
      // If [member] is a synthetic accessor created from a field, search for
      // the metadata on the original field.
      List<ElementAnnotation> metadata =
          accessor.isSynthetic ? accessor.variable.metadata : accessor.metadata;
      List<ElementAnnotation>? getterMetadata;
      if (_reflectorDomain._capabilities._impliesCorrespondingSetters &&
          accessor.isSetter &&
          !accessor.isSynthetic) {
        PropertyAccessorElement? correspondingGetter =
            accessor.correspondingGetter;
        getterMetadata = correspondingGetter?.metadata;
      }
      if (_reflectorDomain._capabilities.supportsStaticInvoke(
          accessor.library.typeSystem,
          accessor.name,
          metadata,
          getterMetadata)) {
        result.add(accessor);
      }
    }

    _interfaceElement.methods.forEach(possiblyAddMethod);
    _interfaceElement.accessors.forEach(possiblyAddAccessor);
    return result;
  }

  @override
  String toString() {
    return 'ClassDomain($_interfaceElement)';
  }
}

/// A wrapper around a list of Capabilities.
/// Supports queries about the methods supported by the set of capabilities.
class _Capabilities {
  final List<ec.ReflectCapability> _capabilities;
  _Capabilities(this._capabilities);

  bool _supportsName(ec.NamePatternCapability capability, String methodName) {
    RegExp regexp = RegExp(capability.namePattern);
    return regexp.hasMatch(methodName);
  }

  bool _supportsMeta(
      TypeSystem typeSystem,
      ec.MetadataQuantifiedCapability capability,
      Iterable<DartObject>? metadata) {
    if (metadata == null) return false;
    bool result = false;
    DartType capabilityType = _typeForReflectable(capability.metadataType);
    for (var metadatum in metadata) {
      if (typeSystem.isSubtypeOf(metadatum.type!, capabilityType)) {
        result = true;
        break;
      }
    }
    return result;
  }

  bool _supportsInstanceInvoke(
      TypeSystem typeSystem,
      List<ec.ReflectCapability> capabilities,
      String methodName,
      Iterable<DartObject> metadata,
      Iterable<DartObject>? getterMetadata) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.InstanceInvokeCapability &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if (capability is ec.InstanceInvokeMetaCapability &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
      }
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
    }

    // Check if we can retry, using the corresponding getter.
    if (_isSetterName(methodName) && getterMetadata != null) {
      return _supportsInstanceInvoke(typeSystem, capabilities,
          _setterNameToGetterName(methodName), getterMetadata, null);
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsNewInstance(
      TypeSystem typeSystem,
      Iterable<ec.ReflectCapability> capabilities,
      String constructorName,
      Iterable<DartObject> metadata) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.NamePatternCapability) {
        if ((capability is ec.InvokingCapability ||
                capability is ec.NewInstanceCapability) &&
            _supportsName(capability, constructorName)) {
          return true;
        }
      }
      if (capability is ec.MetadataQuantifiedCapability) {
        if ((capability is ec.InvokingMetaCapability ||
                capability is ec.NewInstanceMetaCapability) &&
            _supportsMeta(typeSystem, capability, metadata)) {
          return true;
        }
      }
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
    }

    // All options exhausted, give up.
    return false;
  }

  // TODO(sigurdm) future: Find a way to cache these. Perhaps take an
  // element instead of name+metadata.
  bool supportsInstanceInvoke(
      TypeSystem typeSystem,
      String methodName,
      Iterable<ElementAnnotation> metadata,
      Iterable<ElementAnnotation>? getterMetadata) {
    return _supportsInstanceInvoke(
        typeSystem,
        _capabilities,
        methodName,
        _getEvaluatedMetadata(metadata),
        getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata));
  }

  bool supportsNewInstance(
      TypeSystem typeSystem,
      String constructorName,
      Iterable<ElementAnnotation> metadata,
      LibraryElement libraryElement,
      Resolver resolver) {
    return _supportsNewInstance(typeSystem, _capabilities, constructorName,
        _getEvaluatedMetadata(metadata));
  }

  bool _supportsTopLevelInvoke(
      TypeSystem typeSystem,
      List<ec.ReflectCapability> capabilities,
      String methodName,
      Iterable<DartObject> metadata,
      Iterable<DartObject>? getterMetadata) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if ((capability is ec.TopLevelInvokeCapability) &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if ((capability is ec.TopLevelInvokeMetaCapability) &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
      }
      // Quantifying capabilities do not influence the availability
      // of reflection support for top-level invocation.
    }

    // Check if we can retry, using the corresponding getter.
    if (_isSetterName(methodName) && getterMetadata != null) {
      return _supportsTopLevelInvoke(typeSystem, capabilities,
          _setterNameToGetterName(methodName), getterMetadata, null);
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsStaticInvoke(
      TypeSystem typeSystem,
      List<ec.ReflectCapability> capabilities,
      String methodName,
      Iterable<DartObject> metadata,
      Iterable<DartObject>? getterMetadata) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.StaticInvokeCapability &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if (capability is ec.StaticInvokeMetaCapability &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
      }
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
    }

    // Check if we can retry, using the corresponding getter.
    if (_isSetterName(methodName) && getterMetadata != null) {
      return _supportsStaticInvoke(typeSystem, capabilities,
          _setterNameToGetterName(methodName), getterMetadata, null);
    }

    // All options exhausted, give up.
    return false;
  }

  bool supportsTopLevelInvoke(
      TypeSystem typeSystem,
      String methodName,
      Iterable<ElementAnnotation> metadata,
      Iterable<ElementAnnotation>? getterMetadata) {
    return _supportsTopLevelInvoke(
        typeSystem,
        _capabilities,
        methodName,
        _getEvaluatedMetadata(metadata),
        getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata));
  }

  bool supportsStaticInvoke(
      TypeSystem typeSystem,
      String methodName,
      Iterable<ElementAnnotation> metadata,
      Iterable<ElementAnnotation>? getterMetadata) {
    return _supportsStaticInvoke(
        typeSystem,
        _capabilities,
        methodName,
        _getEvaluatedMetadata(metadata),
        getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata));
  }

  late final bool _supportsMetadata = _capabilities.any(
      (ec.ReflectCapability capability) => capability is ec.MetadataCapability);

  late final bool _supportsUri = _capabilities
      .any((ec.ReflectCapability capability) => capability is ec.UriCapability);

  /// Returns [true] iff these [Capabilities] specify reflection support
  /// where the set of classes must be downwards closed, i.e., extra classes
  /// must be added beyond the ones that are directly covered by the given
  /// metadata and global quantifiers, such that coverage on a class `C`
  /// implies coverage of every class `D` such that `D` is a subtype of `C`.
  late final bool _impliesDownwardsClosure = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability == ec.subtypeQuantifyCapability);

  /// Returns [true] iff these [Capabilities] specify reflection support where
  /// the set of included classes must be upwards closed, i.e., extra classes
  /// must be added beyond the ones that are directly included as reflectable
  /// because we must support operations like `superclass`.
  late final bool _impliesUpwardsClosure = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability is ec.SuperclassQuantifyCapability);

  /// Returns [true] iff these [Capabilities] specify that classes which have
  /// been used for mixin application for an included class must themselves
  /// be included (if you have `class B extends A with M ..` then the class `M`
  /// will be included if `_impliesMixins`).
  bool get _impliesMixins => _impliesTypeRelations;

  /// Returns [true] iff these [Capabilities] specify that classes which have
  /// been used for mixin application for an included class must themselves
  /// be included (if you have `class B extends A with M ..` then the class `M`
  /// will be included if `_impliesMixins`).
  late final bool _impliesTypeRelations = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability is ec.TypeRelationsCapability);

  /// Returns [true] iff these [Capabilities] specify that type annotations
  /// modeled by mirrors should also get support for their base level [Type]
  /// values, e.g., they should support `myVariableMirror.reflectedType`.
  /// The relevant kinds of mirrors are variable mirrors, parameter mirrors,
  /// and (for the return type) method mirrors.
  late final bool _impliesReflectedType = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability == ec.reflectedTypeCapability);

  /// Maps each upper bound specified for the upwards closure to whether the
  /// bound itself is excluded, as indicated by `excludeUpperBound` in the
  /// corresponding capability. Intended usage: the `keys` of this map
  /// provides a listing of the upper bounds, and the map itself may then
  /// be consulted for each key (`if (myClosureBounds[key]) ..`) in order to
  /// take `excludeUpperBound` into account.
  Future<Map<InterfaceElement, bool>> get _upwardsClosureBounds async {
    Map<InterfaceElement, bool> result = {};
    for (ec.ReflectCapability capability in _capabilities) {
      if (capability is ec.SuperclassQuantifyCapability) {
        Element? element = capability.upperBound;
        if (element == null) continue; // Means [Object], trivially satisfied.
        if (element is InterfaceElement) {
          result[element] = capability.excludeUpperBound;
        } else {
          await _severe('Unexpected kind of upper bound specified '
              'for a `SuperclassQuantifyCapability`: $element.');
        }
      }
    }
    return result;
  }

  late final bool _impliesDeclarations =
      _capabilities.any((ec.ReflectCapability capability) {
    return capability is ec.DeclarationsCapability;
  });

  late final bool _impliesMemberSymbols =
      _capabilities.any((ec.ReflectCapability capability) {
    return capability == ec.delegateCapability;
  });

  bool get _impliesParameterListShapes {
    // If we have a capability for declarations then we also have it for
    // types, and in that case the strategy where we traverse the parameter
    // mirrors to gather the argument list shape (and cache it in the method
    // mirror) will work. It may be a bit slower, but we have a general
    // preference for space over time in this library: Reflection will never
    // be full speed.
    return !_impliesDeclarations;
  }

  late final bool _impliesTypes =
      _capabilities.any((ec.ReflectCapability capability) {
    return capability is ec.TypeCapability;
  });

  /// Returns true iff `_capabilities` contain any of the types of capability
  /// which are concerned with instance method invocation. The purpose of
  /// this predicate is to determine whether it is required to have class
  /// mirrors for instance invocation support. Note that it does not include
  /// `newInstance..` capabilities nor `staticInvoke..` capabilities, because
  /// they are simply absent if there are no class mirrors (so we cannot call
  /// them and then get a "cannot do this without a class mirror" error in the
  /// implementation).
  late final bool _impliesInstanceInvoke =
      _capabilities.any((ec.ReflectCapability capability) {
    return capability is ec.InstanceInvokeCapability ||
        capability is ec.InstanceInvokeMetaCapability;
  });

  late final bool _impliesTypeAnnotations = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability is ec.TypeAnnotationQuantifyCapability);

  late final bool _impliesTypeAnnotationClosure = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability is ec.TypeAnnotationQuantifyCapability &&
          capability.transitive == true);

  late final bool _impliesCorrespondingSetters = _capabilities.any(
      (ec.ReflectCapability capability) =>
          capability == ec.correspondingSetterQuantifyCapability);

  late final bool _supportsLibraries = _capabilities.any(
      (ec.ReflectCapability capability) => capability is ec.LibraryCapability);
}

/// Collects the libraries that needs to be imported, and gives each library
/// a unique prefix.
class _ImportCollector {
  final _mapping = <LibraryElement, String>{};
  int _count = 0;

  /// Returns the prefix associated with [library]. Iff it is non-empty
  /// it includes the period.
  String _getPrefix(LibraryElement library) {
    if (library.isDartCore) return '';
    String? prefix = _mapping[library];
    if (prefix != null) return prefix;
    prefix = 'prefix$_count.';
    _count++;
    _mapping[library] = prefix;
    return prefix;
  }

  /// Adds [library] to the collected libraries and generate a prefix for it if
  /// it has not been encountered before.
  void _addLibrary(LibraryElement library) {
    if (library.isDartCore) return;
    String? prefix = _mapping[library];
    if (prefix != null) return;
    prefix = 'prefix$_count.';
    _count++;
    _mapping[library] = prefix;
  }

  Iterable<LibraryElement> get _libraries => _mapping.keys;
}

// TODO(eernst) future: Keep in mind, with reference to
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

/// Keeps track of the number of entry points seen. Used to determine when the
/// transformation job is complete during `pub build..` or stand-alone
/// transformation, such that it is time to give control to the debugger.
/// Only in use when `const bool.fromEnvironment('reflectable.pause.at.exit')`.
int _processedEntryPointCount = 0;

class BuilderImplementation {
  late final Resolver _resolver;
  var _libraries = <LibraryElement>[];
  final _librariesByName = <String, LibraryElement>{};
  late final bool _formatted;
  late final List<WarningKind> _suppressedWarnings;

  bool _warningEnabled(WarningKind kind) {
    // TODO(eernst) implement: No test reaches this point.
    // The mock_tests should be extended to exercise all warnings and errors
    // that the builder can encounter.
    return !_suppressedWarnings.contains(kind);
  }

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
  bool _equalsClassReflectable(InterfaceElement type) {
    FieldElement? idField = type.getField('thisClassId');
    if (idField == null || !idField.isStatic) return false;
    DartObject? constantValue = idField.computeConstantValue();
    return constantValue?.toStringValue() == reflectable_class_constants.id;
  }

  /// Returns the InterfaceElement in the target program which corresponds to class
  /// [Reflectable].
  Future<InterfaceElement?> _findReflectableInterfaceElement(
      LibraryElement reflectableLibrary) async {
    for (CompilationUnitElement unit in reflectableLibrary.units) {
      for (InterfaceElement type in unit.classes) {
        if (type.name == reflectable_class_constants.name &&
            _equalsClassReflectable(type)) {
          return type;
        }
      }
      // No need to check `unit.enums`: [Reflectable] is not an enum.
    }
    // Class [Reflectable] was not found in the target program.
    return null;
  }

  /// Returns true iff [possibleSubtype] is a direct subclass of [type].
  bool _isDirectSubclassOf(
      ParameterizedType possibleSubtype, InterfaceType type) {
    if (possibleSubtype is InterfaceType) {
      InterfaceType? superclass = possibleSubtype.superclass;
      // Even if `superclass == null` (superclass of Object), the equality
      // test will produce the correct result.
      return type.element == superclass?.element;
    } else {
      return false;
    }
  }

  /// Returns true iff [possibleSubtype] is a subclass of [type], including the
  /// reflexive and transitive cases.
  bool _isSubclassOf(ParameterizedType possibleSubtype, InterfaceType type) {
    if (possibleSubtype is! InterfaceType) return false;
    if (possibleSubtype.element == type.element) return true;
    InterfaceType? superclass = possibleSubtype.superclass;
    if (superclass == null) return false;
    return _isSubclassOf(superclass, type);
  }

  /// Returns the metadata class in [elementAnnotation] if it is an
  /// instance of a direct subclass of [focusClass], otherwise returns
  /// `null`.  Uses [errorReporter] to report an error if it is a subclass
  /// of [focusClass] which is not a direct subclass of [focusClass],
  /// because such a class is not supported as a Reflector.
  Future<InterfaceElement?> _getReflectableAnnotation(
      ElementAnnotation elementAnnotation, InterfaceElement focusClass) async {
    if (elementAnnotation.element == null) {
      // This behavior is based on the assumption that a `null` element means
      // "there is no annotation here".
      return null;
    }

    /// Checks that the inheritance hierarchy placement of [type]
    /// conforms to the constraints relative to [classReflectable],
    /// which is intended to refer to the class Reflectable defined
    /// in package:reflectable/reflectable.dart.
    Future<bool> checkInheritance(
        ParameterizedType type, InterfaceType classReflectable) async {
      if (!_isSubclassOf(type, classReflectable)) {
        // Not a subclass of [classReflectable] at all.
        return false;
      }
      if (!_isDirectSubclassOf(type, classReflectable)) {
        // Instance of [classReflectable], or of indirect subclass
        // of [classReflectable]: Not supported, report an error.
        await _severe(
            errors.metadataNotDirectSubclass, elementAnnotation.element);
        return false;
      }
      // A direct subclass of [classReflectable], all OK.
      return true;
    }

    Element? element = elementAnnotation.element;
    if (element is ConstructorElement) {
      var enclosingType = _typeForReflectable(element.enclosingElement);
      var focusClassType = _typeForReflectable(focusClass);
      bool isOk = enclosingType is ParameterizedType &&
          focusClassType is InterfaceType &&
          await checkInheritance(enclosingType, focusClassType);
      if (isOk) {
        if (enclosingType is InterfaceType) {
          return enclosingType.element;
        } else {
          return null;
        }
      } else {
        return null;
      }
    } else if (element is PropertyAccessorElement) {
      PropertyInducingElement variable = element.variable;
      DartObject? constantValue = variable.computeConstantValue();
      // Handle errors during evaluation. In general `constantValue` is
      // null for (1) non-const variables, (2) variables without an
      // initializer, and (3) unresolved libraries; (3) should not occur
      // because of the approach we use to get the resolver; we will not
      // see (1) because we have checked the type of `variable`; and (2)
      // would mean that the value is actually null, which we will also
      // reject as irrelevant.
      if (constantValue == null) return null;
      var constantValueType = constantValue.type;
      var focusClassType = _typeForReflectable(focusClass);
      bool isOk = constantValueType is ParameterizedType &&
          focusClassType is InterfaceType &&
          await checkInheritance(constantValueType, focusClassType);
      // When `isOK` is true, result.value.type.element is a InterfaceElement.
      if (isOk) {
        if (constantValueType is InterfaceType) {
          return constantValueType.element;
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    // Otherwise [element] is some other construct which is not supported.
    await _fine(
        'Ignoring metadata in a form ($elementAnnotation) '
        'which is not yet supported.',
        elementAnnotation.element);
    return null;
  }

  /// Adds a warning to the log, using the source code location of `target`
  /// to identify the relevant location where the error occurs.
  Future<void> _warn(WarningKind kind, String message,
      [Element? target]) async {
    if (_warningEnabled(kind)) {
      if (target != null) {
        log.warning(await _formatDiagnosticMessage(message, target, _resolver));
      } else {
        log.warning(message);
      }
    }
  }

  /// Finds all GlobalQuantifyCapability and GlobalQuantifyMetaCapability
  /// annotations on imports of [reflectableLibrary], and record the arguments
  /// of these annotations by modifying [globalPatterns] and [globalMetadata].
  Future<void> _findGlobalQuantifyAnnotations(
      Map<RegExp, List<InterfaceElement>> globalPatterns,
      Map<InterfaceElement, List<InterfaceElement>> globalMetadata) async {
    LibraryElement reflectableLibrary =
        _librariesByName['reflectable.reflectable']!;
    LibraryElement capabilityLibrary =
        _librariesByName['reflectable.capability']!;
    var reflectableClass = reflectableLibrary.getClass('Reflectable')!;
    var typeType = reflectableLibrary.typeProvider.typeType;
    InterfaceElement typeTypeClass = typeType.element;

    ConstructorElement globalQuantifyCapabilityConstructor = capabilityLibrary
        .getClass('GlobalQuantifyCapability')!
        .getNamedConstructor('')!;
    ConstructorElement globalQuantifyMetaCapabilityConstructor =
        capabilityLibrary
            .getClass('GlobalQuantifyMetaCapability')!
            .getNamedConstructor('')!;

    for (LibraryElement library in _libraries) {
      for (LibraryImportElement import in library.libraryImports) {
        if (import.importedLibrary?.id != reflectableLibrary.id) continue;
        for (ElementAnnotation metadatum in import.metadata) {
          var metadatumElement = metadatum.element?.declaration;
          if (metadatumElement == globalQuantifyCapabilityConstructor) {
            DartObject? value = _getEvaluatedMetadatum(metadatum);
            if (value != null) {
              String? pattern =
                  value.getField('classNamePattern')?.toStringValue();
              if (pattern == null) {
                await _warn(WarningKind.badNamePattern,
                    'The classNamePattern must be a string', metadatumElement);
                continue;
              }
              var valueType =
                  value.getField('(super)')?.getField('reflector')?.type;
              var reflector =
                  valueType is InterfaceType ? valueType.element : null;
              if (reflector == null) {
                await _warn(
                    WarningKind.badSuperclass,
                    'The reflector must be a direct subclass of Reflectable.',
                    metadatumElement);
                continue;
              } else {
                var reflectorSupertype = reflector.supertype;
                if (reflectorSupertype is InterfaceType &&
                    reflectorSupertype.element != reflectableClass) {
                  await _warn(
                      WarningKind.badSuperclass,
                      'The reflector must be a direct subclass of '
                      'Reflectable. Found ${reflector.name}.',
                      metadatumElement);
                  continue;
                }
              }
              globalPatterns
                  .putIfAbsent(RegExp(pattern), () => <InterfaceElement>[])
                  .add(reflector);
            }
          } else if (metadatumElement ==
              globalQuantifyMetaCapabilityConstructor) {
            DartObject? constantValue = metadatum.computeConstantValue();
            if (constantValue != null) {
              var metadataType = constantValue.getField('metadataType');
              var metadataFieldType = metadataType?.toTypeValue();
              var metadataFieldValue = metadataFieldType is InterfaceType
                  ? metadataFieldType.element
                  : null;
              var metadataTypeType = metadataType?.type;
              if (metadataFieldValue == null) {
                var message = 'The metadata must be a Type.';
                await _warn(WarningKind.badMetadata, message, metadatumElement);
                continue;
              } else if (metadataTypeType is InterfaceType &&
                  metadataTypeType.element != typeTypeClass) {
                var typeName = metadataTypeType.element.name;
                var message = 'The metadata must be a Type. Found $typeName.';
                await _warn(WarningKind.badMetadata, message, metadatumElement);
                continue;
              }
              var reflectorType = constantValue
                  .getField('(super)')
                  ?.getField('reflector')
                  ?.type;
              var reflector =
                  reflectorType is InterfaceType ? reflectorType.element : null;
              if (reflector == null) {
                await _warn(
                    WarningKind.badSuperclass,
                    'The reflector must be a direct subclass of Reflectable.',
                    metadatumElement);
                continue;
              } else {
                var reflectorSupertype = reflector.supertype;
                if (reflectorType is InterfaceType &&
                    reflectorSupertype is InterfaceType &&
                    reflectorSupertype.element != reflectableClass) {
                  await _warn(
                      WarningKind.badSuperclass,
                      'The reflector must be a direct subclass of '
                      'Reflectable. Found ${reflector.name}.',
                      metadatumElement);
                  continue;
                }
              }
              globalMetadata
                  .putIfAbsent(metadataFieldValue, () => <InterfaceElement>[])
                  .add(reflector);
            }
          }
        }
      }
    }
  }

  /// Returns true iff [potentialReflectorClass] is a proper reflector class,
  /// which means that it is a direct subclass of [Reflectable], which must be
  /// provided as [reflectableClass], and it has a single nameless constructor
  /// that does not take any arguments. In case we extend this list of
  /// general reflector well-formedness requirements, this is the method to
  /// update accordingly. The rest of the builder can then rely on every
  /// reflector class to be well-formed, and just have assertions rather than
  /// emitting error messages about it.
  Future<bool> _isReflectorClass(InterfaceElement potentialReflectorClass,
      InterfaceElement reflectableClass) async {
    if (potentialReflectorClass == reflectableClass) return false;
    DartType potentialReflectorType =
        _typeForReflectable(potentialReflectorClass);
    DartType reflectableType = _typeForReflectable(reflectableClass);
    if (potentialReflectorType is! ParameterizedType ||
        reflectableType is! InterfaceType) return false;
    if (!_isSubclassOf(potentialReflectorType, reflectableType)) {
      // Not a subclass of [classReflectable] at all.
      return false;
    }
    if (!_isDirectSubclassOf(potentialReflectorType, reflectableType) &&
        potentialReflectorType != reflectableType) {
      // Instance of [classReflectable], or of indirect subclass
      // of [classReflectable]: Not supported, warn about having such a class
      // at all, even though we don't know for sure it is used as a reflector.
      await _warn(
          WarningKind.badReflectorClass,
          'An indirect subclass of `Reflectable` will not work as a reflector.'
          '\nIt is not recommended to have such a class at all.',
          potentialReflectorClass);
      return false;
    }

    Future<void> constructorFail() async {
      await _severe(
          'A reflector class must have exactly one '
          'constructor which is `const`, has \n'
          'the empty name, takes zero arguments, and '
          'uses at most one superinitializer.\n'
          'Please correct `$potentialReflectorClass` to match this.',
          potentialReflectorClass);
    }

    if (potentialReflectorClass.constructors.length != 1) {
      // We "own" the direct subclasses of `Reflectable` so when they are
      // malformed as reflector classes we raise an error.
      await constructorFail();
      return false;
    }
    ConstructorElement constructor = potentialReflectorClass.constructors[0];
    if (constructor.parameters.isNotEmpty || !constructor.isConst) {
      // We still "own" `potentialReflectorClass`.
      await constructorFail();
      return false;
    }

    var constructorDeclarationNode =
        await _getDeclarationAst(constructor, _resolver);
    if (constructorDeclarationNode == null ||
        constructorDeclarationNode is! ConstructorDeclaration) return false;
    NodeList<ConstructorInitializer> initializers =
        constructorDeclarationNode.initializers;
    if (initializers.length > 1) {
      await constructorFail();
      return false;
    }

    // Do we care about type parameters? We don't expect any, but if someone
    // thinks they are incredibly useful in a case that we haven't foreseen
    // then we might as well allow it. It should work. Hence, no checks.

    // A direct subclass of [classReflectable], all OK.
    return true;
  }

  /// Returns a [_ReflectionWorld] instantiated with all the reflectors seen by
  /// [_resolver] and all classes annotated by them. The [reflectableLibrary]
  /// must be the element representing 'package:reflectable/reflectable.dart',
  /// the [entryPoint] must be the element representing the entry point under
  /// transformation, and [dataId] must represent the entry point as well,
  /// and it is used to decide whether it is possible to import other libraries
  /// from the entry point. If the transformation is guaranteed to have no
  /// effect the return value is [null].
  Future<_ReflectionWorld?> _computeWorld(LibraryElement reflectableLibrary,
      LibraryElement entryPoint, AssetId dataId) async {
    final InterfaceElement? classReflectable =
        await _findReflectableInterfaceElement(reflectableLibrary);
    final allReflectors = <InterfaceElement>{};

    // If class `Reflectable` is absent the transformation must be a no-op.
    if (classReflectable == null) {
      log.info('Ignoring entry point $entryPoint that does not '
          'include the class `Reflectable`.');
      return null;
    }

    // The world will be built from the library arguments plus these two.
    final domains = <InterfaceElement, _ReflectorDomain>{};
    final importCollector = _ImportCollector();

    // Maps each pattern to the list of reflectors associated with it via
    // a [GlobalQuantifyCapability].
    var globalPatterns = <RegExp, List<InterfaceElement>>{};

    // Maps each [Type] to the list of reflectors associated with it via
    // a [GlobalQuantifyMetaCapability].
    var globalMetadata = <InterfaceElement, List<InterfaceElement>>{};

    final LibraryElement? capabilityLibrary =
        _librariesByName['reflectable.capability'];

    if (capabilityLibrary == null) {
      log.info('Ignoring entry point $entryPoint that does not '
          'include the library reflectable.capability');
      return null;
    }

    /// Gets the [ReflectorDomain] associated with [reflector], or creates
    /// it if none exists.
    Future<_ReflectorDomain> getReflectorDomain(
        InterfaceElement reflector) async {
      var domain = domains[reflector];
      if (domain == null) {
        LibraryElement reflectorLibrary = reflector.library;
        _Capabilities capabilities =
            await _capabilitiesOf(capabilityLibrary, reflector);
        assert(await _isImportableLibrary(reflectorLibrary, dataId, _resolver));
        importCollector._addLibrary(reflectorLibrary);
        domain = _ReflectorDomain(_resolver, dataId, reflector, capabilities);
        domains[reflector] = domain;
      }
      return domain;
    }

    /// Adds [library] to the supported libraries of [reflector].
    Future<void> addLibrary(
        LibraryElement library, InterfaceElement reflector) async {
      _ReflectorDomain domain = await getReflectorDomain(reflector);
      if (domain._capabilities._supportsLibraries) {
        assert(await _isImportableLibrary(library, dataId, _resolver));
        importCollector._addLibrary(library);
        domain._libraries.add(library);
      }
    }

    /// Adds a [_ClassDomain] representing [type] to the supported classes of
    /// [reflector]; also adds the enclosing library of [type] to the
    /// supported libraries.
    Future<void> addClassDomain(
        InterfaceElement type, InterfaceElement reflector) async {
      if (!await _isImportable(type, dataId, _resolver)) {
        await _fine('Ignoring unrepresentable class ${type.name}', type);
      } else {
        _ReflectorDomain domain = await getReflectorDomain(reflector);
        if (!domain._classes.contains(type)) {
          if (type is MixinApplication && type.isMixinApplication) {
            // Iterate over all mixins in most-general-first order (so with
            // `class C extends B with M1, M2..` we visit `M1` then `M2`.
            var superclass = type.supertype!.element;
            for (var mixin in type.mixins) {
              var mixinElement = mixin.element;
              var subClass = mixin == type.mixins.last ? type : null;
              String? name = subClass == null ? null : type.name;
              MixinApplication mixinApplication = MixinApplication(
                  name, superclass, mixinElement, type.library, subClass);
              domain._classes.add(mixinApplication);
              superclass = mixinApplication;
            }
          } else {
            domain._classes.add(type);
          }
          await addLibrary(type.library, reflector);
          // We need to ensure that the [importCollector] has indeed added
          // `type.library` (if we have no library capability `addLibrary` will
          // not do that), because it may be needed in import directives in the
          // generated library, even in cases where the transformed program
          // will not get library support.
          // TODO(eernst) clarify: Maybe the following statement could be moved
          // out of the `if` in `addLibrary` such that we don't have to have
          // an extra copy of it here.
          importCollector._addLibrary(type.library);
        }
      }
    }

    /// Runs through [metadata] and finds all reflectors as well as
    /// objects that are associated with reflectors via
    /// [GlobalQuantifyMetaCapability] or [GlobalQuantifyCapability].
    /// [qualifiedName] is the name of the library or class annotated by
    /// [metadata].
    Future<Iterable<InterfaceElement>> getReflectors(
        String? qualifiedName, List<ElementAnnotation> metadata) async {
      List<InterfaceElement> result = <InterfaceElement>[];

      for (ElementAnnotation metadatum in metadata) {
        DartObject? value = _getEvaluatedMetadatum(metadatum);

        // Test if the type of this metadata is associated with any reflectors
        // via GlobalQuantifyMetaCapability.
        if (value != null) {
          var valueType = value.type;
          if (valueType is InterfaceType) {
            List<InterfaceElement>? reflectors =
                globalMetadata[valueType.element];
            if (reflectors != null) {
              for (InterfaceElement reflector in reflectors) {
                result.add(reflector);
              }
            }
          }
        }

        // Test if the annotation is a reflector.
        InterfaceElement? reflector =
            await _getReflectableAnnotation(metadatum, classReflectable);
        if (reflector != null) result.add(reflector);
      }

      // Add All reflectors associated with a
      // pattern, via GlobalQuantifyCapability, that matches the qualified
      // name of the class or library.
      globalPatterns
          .forEach((RegExp pattern, List<InterfaceElement> reflectors) {
        if (qualifiedName != null && pattern.hasMatch(qualifiedName)) {
          for (InterfaceElement reflector in reflectors) {
            result.add(reflector);
          }
        }
      });
      return result;
    }

    // Populate [globalPatterns] and [globalMetadata].
    await _findGlobalQuantifyAnnotations(globalPatterns, globalMetadata);

    // Visits all libraries and all classes in the given entry point,
    // gets their reflectors, and adds them to the domain of that
    // reflector.
    for (LibraryElement library in _libraries) {
      for (InterfaceElement reflector
          in await getReflectors(library.name, library.metadata)) {
        assert(await _isImportableLibrary(library, dataId, _resolver));
        await addLibrary(library, reflector);
      }

      for (CompilationUnitElement unit in library.units) {
        for (InterfaceElement type in unit.classes) {
          for (InterfaceElement reflector
              in await getReflectors(_qualifiedName(type), type.metadata)) {
            await addClassDomain(type, reflector);
          }
          if (!allReflectors.contains(type) &&
              await _isReflectorClass(type, classReflectable)) {
            allReflectors.add(type);
          }
        }
        for (EnumElement type in unit.enums) {
          for (InterfaceElement reflector
              in await getReflectors(_qualifiedName(type), type.metadata)) {
            await addClassDomain(type, reflector);
          }
          // An enum is never a reflector class, hence no `_isReflectorClass`.
        }
        for (FunctionElement function in unit.functions) {
          for (InterfaceElement reflector in await getReflectors(
              _qualifiedFunctionName(function), function.metadata)) {
            // We just add the library here, the function itself will be
            // supported using `invoke` and `declarations` of that library
            // mirror.
            await addLibrary(library, reflector);
          }
        }
      }
    }

    var usedReflectors = <InterfaceElement>{};
    for (var domain in domains.values) {
      usedReflectors.add(domain._reflector);
    }
    for (InterfaceElement reflector
        in allReflectors.difference(usedReflectors)) {
      await _warn(WarningKind.unusedReflector,
          'This reflector does not match anything', reflector);
      // Ensure that there is an empty domain for `reflector` in `domains`.
      await getReflectorDomain(reflector);
    }

    // Create the world and tie the knot: A [_ReflectionWorld] refers to all its
    // [_ReflectorDomain]s, and each of them refer back. Such a cycle cannot be
    // defined during construction, so `_world` is non-final and left unset by
    // the constructor, and we need to close the cycle here.
    _ReflectionWorld world = _ReflectionWorld(
        _resolver,
        _libraries,
        dataId,
        domains.values.toList(),
        reflectableLibrary,
        entryPoint,
        importCollector);
    for (var domain in domains.values) {
      domain._world = world;
    }
    return world;
  }

  /// Returns the [ReflectCapability] denoted by the given initializer
  /// [expression] reporting diagnostic messages for [messageTarget].
  Future<ec.ReflectCapability?> _capabilityOfExpression(
      LibraryElement capabilityLibrary,
      Expression expression,
      LibraryElement containingLibrary,
      Element messageTarget) async {
    EvaluationResult evaluated =
        _evaluateConstant(containingLibrary, expression);

    if (!evaluated.isValid) {
      await _severe(
          'Invalid constant `$expression` in capability list.', messageTarget);
      // We do not terminate immediately at `_severe` so we need to
      // return something that will not generate too much noise for the
      // receiver.
      return ec.invokingCapability; // Error default.
    }

    DartObject? constant = evaluated.value;

    if (constant == null) {
      // This could be because it is an argument to a `const` constructor,
      // but we do not support that.
      await _severe('Unsupported constant `$expression` in capability list.',
          messageTarget);
      return ec.invokingCapability; // Error default.
    }

    DartType dartType = constant.type!;
    // We insist that the type must be a class, and we insist that it must
    // be in the given `capabilityLibrary` (because we could never know
    // how to interpret the meaning of a user-written capability class, so
    // users cannot write their own capability classes).
    var dartTypeElement = (dartType as InterfaceType).element;
    if (dartTypeElement is! ClassElement) {
      var typeString = dartType.getDisplayString(withNullability: false);
      await _severe(
          errors.applyTemplate(
              errors.superArgumentNonClass, {'type': typeString}),
          dartTypeElement);
      return null; // Error default.
    }
    if (dartTypeElement.library != capabilityLibrary) {
      await _severe(
          errors.applyTemplate(errors.superArgumentWrongLibrary,
              {'library': '$capabilityLibrary', 'element': '$dartTypeElement'}),
          dartTypeElement);
      return null; // Error default.
    }

    /// Extracts the namePattern String from an instance of a subclass of
    /// NamePatternCapability.
    Future<String?> extractNamePattern(DartObject constant) async {
      var constantSuper = constant.getField('(super)');
      var constantSuperNamePattern = constantSuper?.getField('namePattern');
      var constantSuperNamePatternString =
          constantSuperNamePattern?.toStringValue();
      if (constantSuper == null ||
          constantSuperNamePattern == null ||
          constantSuperNamePatternString == null) {
        await _warn(WarningKind.badNamePattern,
            'Could not extract namePattern from capability.', messageTarget);
        return null;
      }
      return constantSuperNamePatternString;
    }

    /// Extracts the metadata property from an instance of a subclass of
    /// MetadataCapability represented by [constant], reporting any diagnostic
    /// messages as referring to [messageTarget].
    Future<InterfaceElement?> extractMetadata(DartObject constant) async {
      var constantSuper = constant.getField('(super)');
      var constantSuperMetadataType = constantSuper?.getField('metadataType');
      if (constantSuper == null || constantSuperMetadataType == null) {
        await _warn(WarningKind.badMetadata,
            'Could not extract metadata type from capability.', messageTarget);
        return null;
      }
      var metadataFieldType = constantSuperMetadataType.toTypeValue();
      Object? metadataFieldValue =
          metadataFieldType is InterfaceType ? metadataFieldType.element : null;
      if (metadataFieldValue is InterfaceElement) return metadataFieldValue;
      await _warn(
          WarningKind.badMetadata,
          'Metadata specification in capability must be a class `Type`.',
          messageTarget);
      return null;
    }

    switch (dartTypeElement.name) {
      case 'NameCapability':
        return ec.nameCapability;
      case 'ClassifyCapability':
        return ec.classifyCapability;
      case 'MetadataCapability':
        return ec.metadataCapability;
      case 'TypeRelationsCapability':
        return ec.typeRelationsCapability;
      case '_ReflectedTypeCapability':
        return ec.reflectedTypeCapability;
      case 'LibraryCapability':
        return ec.libraryCapability;
      case 'DeclarationsCapability':
        return ec.declarationsCapability;
      case 'UriCapability':
        return ec.uriCapability;
      case 'LibraryDependenciesCapability':
        return ec.libraryDependenciesCapability;
      case 'InstanceInvokeCapability':
        var namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.InstanceInvokeCapability(namePattern);
      case 'InstanceInvokeMetaCapability':
        var metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.InstanceInvokeMetaCapability(metadata);
      case 'StaticInvokeCapability':
        var namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.StaticInvokeCapability(namePattern);
      case 'StaticInvokeMetaCapability':
        var metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.StaticInvokeMetaCapability(metadata);
      case 'TopLevelInvokeCapability':
        var namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.TopLevelInvokeCapability(namePattern);
      case 'TopLevelInvokeMetaCapability':
        var metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.TopLevelInvokeMetaCapability(metadata);
      case 'NewInstanceCapability':
        var namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.NewInstanceCapability(namePattern);
      case 'NewInstanceMetaCapability':
        var metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.NewInstanceMetaCapability(metadata);
      case 'TypeCapability':
        return ec.TypeCapability();
      case 'InvokingCapability':
        var namePattern = await extractNamePattern(constant);
        if (namePattern == null) return null;
        return ec.InvokingCapability(namePattern);
      case 'InvokingMetaCapability':
        var metadata = await extractMetadata(constant);
        if (metadata == null) return null;
        return ec.InvokingMetaCapability(metadata);
      case 'TypingCapability':
        return ec.TypingCapability();
      case '_DelegateCapability':
        return ec.delegateCapability;
      case '_SubtypeQuantifyCapability':
        return ec.subtypeQuantifyCapability;
      case 'SuperclassQuantifyCapability':
        var constantUpperBound = constant.getField('upperBound');
        var constantExcludeUpperBound = constant.getField('excludeUpperBound');
        if (constantUpperBound == null || constantExcludeUpperBound == null) {
          return null;
        }
        var constantUpperBoundType = constantUpperBound.toTypeValue()!;
        if (constantUpperBoundType is! InterfaceType) return null;
        return ec.SuperclassQuantifyCapability(constantUpperBoundType.element,
            excludeUpperBound: constantExcludeUpperBound.toBoolValue()!);
      case 'TypeAnnotationQuantifyCapability':
        var constantTransitive = constant.getField('transitive');
        if (constantTransitive == null) return null;
        return ec.TypeAnnotationQuantifyCapability(
            transitive: constantTransitive.toBoolValue()!);
      case '_CorrespondingSetterQuantifyCapability':
        return ec.correspondingSetterQuantifyCapability;
      case '_AdmitSubtypeCapability':
        // TODO(eernst) implement: support for the admit subtype feature.
        await _severe(
            '_AdmitSubtypeCapability not yet supported!', messageTarget);
        return ec.admitSubtypeCapability;
      default:
        // We have checked that [element] is declared in 'capability.dart',
        // and it is a compile time error to use a non-const value in the
        // superinitializer of a const constructor, and we have tested
        // for all classes in that library which can provide a const value,
        // so we should not reach this point.
        await _severe('Unexpected capability $dartTypeElement');
        return null; // Error default.
    }
  }

  /// Returns the list of Capabilities given as a superinitializer by the
  /// reflector.
  Future<_Capabilities> _capabilitiesOf(
      LibraryElement capabilityLibrary, InterfaceElement reflector) async {
    List<ConstructorElement> constructors = reflector.constructors;

    // Well-formedness for each reflector class is checked by
    // `_isReflectorClass`, so we do not report errors here. But errors will
    // not terminate the program, so we need to decide on how to handle
    // erroneous reflectors here. We choose to pretend that they have no
    // capabilities. An error message has already been issued, so that should
    // not be too surprising for the programmer.
    if (constructors.length != 1) {
      return _Capabilities(<ec.ReflectCapability>[]);
    }
    ConstructorElement constructorElement = constructors[0];
    if (!constructorElement.isConst ||
        !constructorElement.isDefaultConstructor) {
      return _Capabilities(<ec.ReflectCapability>[]);
    }

    ConstructorDeclaration constructorDeclarationNode =
        await _getDeclarationAst(constructorElement, _resolver)
            as ConstructorDeclaration;
    NodeList<ConstructorInitializer> initializers =
        constructorDeclarationNode.initializers;

    if (initializers.isEmpty) {
      // Degenerate case: Without initializers, we will obtain a reflector
      // without any capabilities, which is not useful in practice. We do
      // have this degenerate case in tests "just because we can", and
      // there is no technical reason to prohibit it, so we will handle
      // it here.
      return _Capabilities(<ec.ReflectCapability>[]);
    }
    if (initializers.length != 1) {
      await _severe('Encountered a reflector whose constructor has '
          'an unexpected initializer list. It must be of the form '
          '`super(...)` or `super.fromList(...)`');
      return _Capabilities(<ec.ReflectCapability>[]);
    }

    // Main case: the initializer is exactly one element. We must
    // handle two cases: `super(..)` and `super.fromList(<_>[..])`.
    var superInvocation = initializers[0];

    if (superInvocation is! SuperConstructorInvocation) {
      return _Capabilities(<ec.ReflectCapability>[]);
    }

    Future<ec.ReflectCapability?> capabilityOfExpression(
        Expression expression) async {
      return await _capabilityOfExpression(
          capabilityLibrary, expression, reflector.library, constructorElement);
    }

    Future<ec.ReflectCapability?> capabilityOfCollectionElement(
        CollectionElement collectionElement) async {
      if (collectionElement is Expression) {
        return await capabilityOfExpression(collectionElement);
      } else {
        await _severe('Not supported! '
            'Encountered a collection element which is not an expression: '
            '$collectionElement');
        return null;
      }
    }

    var superInvocationConstructorName = superInvocation.constructorName;
    if (superInvocationConstructorName == null) {
      // Subcase: `super(..)` where 0..k arguments are accepted for some
      // k that we need not worry about here.
      List<ec.ReflectCapability> capabilities = [];
      for (var argument in superInvocation.argumentList.arguments) {
        var currentCapability = await capabilityOfCollectionElement(argument);
        if (currentCapability != null) capabilities.add(currentCapability);
      }
      return _Capabilities(capabilities);
    }
    assert(superInvocationConstructorName.name == 'fromList');

    // Subcase: `super.fromList(const <..>[..])`.
    NodeList<Expression> arguments = superInvocation.argumentList.arguments;
    assert(arguments.length == 1);
    Expression listLiteral = arguments[0];
    List<ec.ReflectCapability> capabilities = [];
    if (listLiteral is! ListLiteral) {
      await _severe('Encountered a reflector using super.fromList(...) '
          'with an argument that is not a list literal, '
          'which is not supported');
    } else {
      for (var collectionElement in listLiteral.elements) {
        var currentCapability =
            await capabilityOfCollectionElement(collectionElement);
        if (currentCapability != null) capabilities.add(currentCapability);
      }
    }
    return _Capabilities(capabilities);
  }

  /// Generates code for a new entry-point file that will initialize the
  /// reflection data according to [world], and invoke the main of
  /// [entrypointLibrary] located at [originalEntryPointFilename]. The code is
  /// generated to be located at [generatedLibraryId].
  Future<String> _generateNewEntryPoint(_ReflectionWorld world,
      AssetId generatedLibraryId, String originalEntryPointFilename) async {
    // Notice it is important to generate the code before printing the
    // imports because generating the code can add further imports.
    String code = await world.generateCode();

    List<String> imports = <String>[];
    for (LibraryElement library in world.importCollector._libraries) {
      Uri uri = library == world.entryPointLibrary
          ? Uri.parse(originalEntryPointFilename)
          : await _getImportUri(library, _resolver, generatedLibraryId);
      String prefix = world.importCollector._getPrefix(library);
      if (prefix.isNotEmpty) {
        imports
            .add("import '$uri' as ${prefix.substring(0, prefix.length - 1)};");
      }
    }
    imports.sort();

    String languageVersionComment =
        world.entryPointLibrary.isNonNullableByDefault
        ? '// @dart = 2.9\n' : '';
    String result = '''
// This file has been generated by the reflectable package.
// https://github.com/dart-lang/reflectable.
$languageVersionComment
import 'dart:core';
${imports.join('\n')}

// ignore_for_file: camel_case_types
// ignore_for_file: implementation_imports
// ignore_for_file: prefer_adjacent_string_concatenation
// ignore_for_file: prefer_collection_literals
// ignore_for_file: unnecessary_const

// ignore:unused_import
import 'package:reflectable/mirrors.dart' as m;
// ignore:unused_import
import 'package:reflectable/src/reflectable_builder_based.dart' as r;
// ignore:unused_import
import 'package:reflectable/reflectable.dart' as r show Reflectable;

$code

final _memberSymbolMap = ${world.generateSymbolMap()};

void initializeReflectable() {
  r.data = _data;
  r.memberSymbolMap = _memberSymbolMap;
}
''';
    if (_formatted) {
      DartFormatter formatter = DartFormatter();
      result = formatter.format(result);
    }
    return result;
  }

  /// Perform the build which produces a set of statically generated
  /// mirror classes, as requested using reflectable capabilities.
  Future<String> buildMirrorLibrary(
      Resolver resolver,
      AssetId inputId,
      AssetId generatedLibraryId,
      LibraryElement inputLibrary,
      List<LibraryElement> visibleLibraries,
      bool formatted,
      List<WarningKind> suppressedWarnings) async {
    _formatted = formatted;
    _suppressedWarnings = suppressedWarnings;

    // The [_resolver] provides all the static information.
    _resolver = resolver;
    _libraries = visibleLibraries;

    for (LibraryElement library in _libraries) {
      _librariesByName[library.name] = library;
    }
    LibraryElement? reflectableLibrary =
        _librariesByName['reflectable.reflectable'];

    if (reflectableLibrary == null) {
      // Stop and let the original source pass through without changes.
      log.info('Ignoring entry point $inputId that does not '
          "include the library 'package:reflectable/reflectable.dart'");
      if (const bool.fromEnvironment('reflectable.pause.at.exit')) {
        _processedEntryPointCount++;
      }
      return '// No output from reflectable, '
          "'package:reflectable/reflectable.dart' not used.";
    } else {
      reflectableLibrary = await _resolvedLibraryOf(reflectableLibrary);

      if (const bool.fromEnvironment('reflectable.print.entry.point')) {
        print("Starting build for '$inputId'.");
      }

      _ReflectionWorld? world =
          await _computeWorld(reflectableLibrary, inputLibrary, inputId);
      if (world == null) {
        // Errors have already been reported during `_computeWorld`.
        if (const bool.fromEnvironment('reflectable.pause.at.exit')) {
          _processedEntryPointCount++;
        }
        return '// No output from reflectable, stopped with error.';
      } else {
        if (inputLibrary.entryPoint == null) {
          log.info('Entry point: $inputId has no `main`. Skipping.');
          if (const bool.fromEnvironment('reflectable.pause.at.exit')) {
            _processedEntryPointCount++;
          }
          return '// No output from reflectable, there is no `main`.';
        } else {
          String outputContents = await _generateNewEntryPoint(
              world, generatedLibraryId, path.basename(inputId.path));
          if (const bool.fromEnvironment('reflectable.pause.at.exit')) {
            _processedEntryPointCount++;
          }
          if (const bool.fromEnvironment('reflectable.pause.at.exit')) {
            if (_processedEntryPointCount ==
                const int.fromEnvironment('reflectable.pause.at.exit.count')) {
              print('Build complete, pausing at exit.');
              developer.debugger();
            }
          }
          return outputContents;
        }
      }
    }
  }

  /// Returns a constant resolved version of the given [libraryElement].
  Future<LibraryElement> _resolvedLibraryOf(
      LibraryElement libraryElement) async {
    for (LibraryElement libraryElement2 in _libraries) {
      if (libraryElement.identifier == libraryElement2.identifier) {
        return libraryElement2;
      }
    }
    // This can occur when the library is not used.
    await _fine('Could not resolve library $libraryElement');
    return libraryElement;
  }
}

bool _accessorIsntImplicitGetterOrSetter(PropertyAccessorElement accessor) {
  return !accessor.isSynthetic || (!accessor.isGetter && !accessor.isSetter);
}

bool _executableIsntImplicitGetterOrSetter(ExecutableElement executable) {
  if (executable is PropertyAccessorElement) {
    return _accessorIsntImplicitGetterOrSetter(executable);
  } else {
    return true;
  }
}

/// Returns an integer encoding of the kind and attributes of the given
/// class.
int _classDescriptor(InterfaceElement element) {
  int result = constants.clazz;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element is MixinElement ||
      element is ClassElement && element.isAbstract) {
    result |= constants.abstractAttribute;
  }
  if (element is EnumElement) result |= constants.enumAttribute;
  if (element is MixinApplication) {
    result |= constants.nonNullableAttribute;
    return result;
  }
  DartType thisType = element.thisType;
  LibraryElement library = element.library;
  if (library.typeSystem.isNullable(thisType)) {
    result |= constants.nullableAttribute;
  }
  if (library.typeSystem.isNonNullable(thisType)) {
    result |= constants.nonNullableAttribute;
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// variable.
int _topLevelVariableDescriptor(TopLevelVariableElement element) {
  int result = constants.field;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isConst) {
    result |= constants.constAttribute;
    // We will get `false` from `element.isFinal` in this case, but with
    // a mirror from 'dart:mirrors' it is considered to be "implicitly
    // final", so we follow that and ignore `element.isFinal`.
    result |= constants.finalAttribute;
  } else {
    if (element.isFinal) result |= constants.finalAttribute;
  }
  if (element.isStatic) result |= constants.staticAttribute;
  DartType declaredType = element.type;
  if (declaredType is VoidType) result |= constants.voidAttribute;
  if (declaredType.isDynamic) result |= constants.dynamicAttribute;
  if (declaredType is NeverType) result |= constants.neverAttribute;
  if (declaredType is InterfaceType) {
    Element? elementType = declaredType.element;
    if (elementType is InterfaceElement) {
      result |= constants.classTypeAttribute;
    }
    result |= constants.topLevelAttribute;
  }
  LibraryElement library = element.library;
  if (library.typeSystem.isNullable(declaredType)) {
    result |= constants.nullableAttribute;
  }
  if (library.typeSystem.isNonNullable(declaredType)) {
    result |= constants.nonNullableAttribute;
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// field.
int _fieldDescriptor(FieldElement element) {
  int result = constants.field;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isConst) {
    result |= constants.constAttribute;
    // We will get `false` from `element.isFinal` in this case, but with
    // a mirror from 'dart:mirrors' it is considered to be "implicitly
    // final", so we follow that and ignore `element.isFinal`.
    result |= constants.finalAttribute;
  } else {
    if (element.isFinal) result |= constants.finalAttribute;
  }
  if (element.isStatic) result |= constants.staticAttribute;
  DartType declaredType = element.type;
  if (declaredType is VoidType) result |= constants.voidAttribute;
  if (declaredType.isDynamic) result |= constants.dynamicAttribute;
  if (declaredType is NeverType) result |= constants.neverAttribute;
  if (declaredType is InterfaceType) {
    Element? elementType = declaredType.element;
    if (elementType is InterfaceElement) {
      result |= constants.classTypeAttribute;
      if (elementType.typeParameters.isNotEmpty) {
        result |= constants.genericTypeAttribute;
      }
    }
  }
  LibraryElement library = element.library;
  if (library.typeSystem.isNullable(declaredType)) {
    result |= constants.nullableAttribute;
  }
  if (library.typeSystem.isNonNullable(declaredType)) {
    result |= constants.nonNullableAttribute;
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// parameter.
int _parameterDescriptor(ParameterElement element) {
  int result = constants.parameter;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isConst) result |= constants.constAttribute;
  if (element.isFinal) result |= constants.finalAttribute;
  if (element.defaultValueCode != null) {
    result |= constants.hasDefaultValueAttribute;
  }
  if (element.isOptional) result |= constants.optionalAttribute;
  if (element.isNamed) result |= constants.namedAttribute;
  DartType declaredType = element.type;
  if (declaredType is VoidType) result |= constants.voidAttribute;
  if (declaredType.isDynamic) result |= constants.dynamicAttribute;
  if (declaredType is NeverType) result |= constants.neverAttribute;
  if (declaredType is InterfaceType) {
    Element? elementType = declaredType.element;
    if (elementType is InterfaceElement) {
      result |= constants.classTypeAttribute;
      if (elementType.typeParameters.isNotEmpty) {
        result |= constants.genericTypeAttribute;
      }
    }
  }
  LibraryElement? library = element.library;
  if (library != null) {
    if (library.typeSystem.isNullable(declaredType)) {
      result |= constants.nullableAttribute;
    }
    if (library.typeSystem.isNonNullable(declaredType)) {
      result |= constants.nonNullableAttribute;
    }
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// method/constructor/getter/setter.
int _declarationDescriptor(ExecutableElement element) {
  int result = 0;

  void handleReturnType(ExecutableElement element) {
    var returnType = element.returnType;
    if (returnType.isVoid) {
      result |= constants.voidReturnTypeAttribute;
    }
    if (returnType.isDynamic) {
      result |= constants.dynamicReturnTypeAttribute;
    }
    if (returnType is VoidType) {
      result |= constants.neverReturnTypeAttribute;
    }
    if (returnType is InterfaceType) {
      Element? elementReturnType = returnType.element;
      if (elementReturnType is InterfaceElement) {
        result |= constants.classReturnTypeAttribute;
        if (elementReturnType.typeParameters.isNotEmpty) {
          result |= constants.genericReturnTypeAttribute;
        }
      }
    }
  }

  if (element is PropertyAccessorElement) {
    result |= element.isGetter ? constants.getter : constants.setter;
    handleReturnType(element);
  } else if (element is ConstructorElement) {
    if (element.isFactory) {
      result |= constants.factoryConstructor;
    } else {
      result |= constants.generativeConstructor;
    }
    if (element.isConst) result |= constants.constAttribute;
    if (element.redirectedConstructor != null) {
      result |= constants.redirectingConstructorAttribute;
    }
  } else if (element is MethodElement) {
    result |= constants.method;
    handleReturnType(element);
  } else {
    assert(element is FunctionElement);
    result |= constants.function;
    handleReturnType(element);
  }
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isStatic) result |= constants.staticAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  // TODO(eernst): Work around issue in analyzer, cf. #39051.
  // When resolved, only the inner `if` is needed.
  if (element is! ConstructorElement) {
    if (element.isAbstract) result |= constants.abstractAttribute;
  }
  if (element.enclosingElement is! InterfaceElement) {
    result |= constants.topLevelAttribute;
  }
  return result;
}

Future<String> _nameOfConstructor(ConstructorElement element) async {
  String name = element.name == ''
      ? element.enclosingElement.name
      : '${element.enclosingElement.name}.${element.name}';
  if (_isPrivateName(name)) {
    await _severe('Cannot access private name $name', element);
  }
  return name;
}

String _formatAsList(String typeName, Iterable parts) =>
    '<$typeName>[${parts.join(', ')}]';

String _formatAsConstList(String typeName, Iterable parts) =>
    'const <$typeName>[${parts.join(', ')}]';

String _formatAsDynamicList(Iterable parts) => '[${parts.join(', ')}]';

String _formatAsDynamicSet(Iterable parts) => '{${parts.join(', ')}}';

String _formatAsMap(Iterable parts) => '{${parts.join(', ')}}';

/// Returns a [String] containing code that will evaluate to the same
/// value when evaluated in the generated file as the given [expression]
/// would evaluate to in [originatingLibrary].
Future<String> _extractConstantCode(
    Expression expression,
    _ImportCollector importCollector,
    AssetId generatedLibraryId,
    Resolver resolver) async {
  Future<String> typeAnnotationHelper(TypeAnnotation typeName) async {
    var interfaceType = typeName.type;
    if (interfaceType is InterfaceType) {
      LibraryElement library = interfaceType.element.library;
      String prefix = importCollector._getPrefix(library);
      return '$prefix$typeName';
    } else {
      await _severe(
        'Not yet supported! '
        'Encountered unexpected kind of type annotation: '
        '$typeName',
      );
      return '$typeName';
    }
  }

  Future<String> helper(Expression expression) async {
    if (expression is ListLiteral) {
      List<String> elements = [];
      for (CollectionElement collectionElement in expression.elements) {
        if (collectionElement is Expression) {
          Expression subExpression = collectionElement;
          elements.add(await helper(subExpression));
        } else {
          // TODO(eernst) implement: `if` and `spread` elements of list.
          await _severe('Not yet supported! '
              'Encountered list literal element which is not an expression: '
              '$collectionElement');
          elements.add('');
        }
      }
      var expressionTypeArguments = expression.typeArguments;
      if (expressionTypeArguments == null ||
          expressionTypeArguments.arguments.isEmpty) {
        return 'const ${_formatAsDynamicList(elements)}';
      } else {
        assert(expressionTypeArguments.arguments.length == 1);
        String typeArgument =
            await typeAnnotationHelper(expressionTypeArguments.arguments[0]);
        return 'const <$typeArgument>${_formatAsDynamicList(elements)}';
      }
    } else if (expression is SetOrMapLiteral) {
      if (expression.isMap) {
        List<String> elements = [];
        for (CollectionElement collectionElement in expression.elements) {
          if (collectionElement is MapLiteralEntry) {
            String key = await helper(collectionElement.key);
            String value = await helper(collectionElement.value);
            elements.add('$key: $value');
          } else {
            // TODO(eernst) implement: `if` and `spread` elements of a map.
            await _severe('Not yet supported! '
                'Encountered map literal element which is not a map entry: '
                '$collectionElement');
            elements.add('');
          }
        }
        var expressionTypeArguments = expression.typeArguments;
        if (expressionTypeArguments == null ||
            expressionTypeArguments.arguments.isEmpty) {
          return 'const ${_formatAsMap(elements)}';
        } else {
          assert(expressionTypeArguments.arguments.length == 2);
          String keyType =
              await typeAnnotationHelper(expressionTypeArguments.arguments[0]);
          String valueType =
              await typeAnnotationHelper(expressionTypeArguments.arguments[1]);
          return 'const <$keyType, $valueType>${_formatAsMap(elements)}';
        }
      } else if (expression.isSet) {
        List<String> elements = [];
        for (CollectionElement collectionElement in expression.elements) {
          if (collectionElement is Expression) {
            Expression subExpression = collectionElement;
            elements.add(await helper(subExpression));
          } else {
            // TODO(eernst) implement: `if` and `spread` elements of a set.
            await _severe('Not yet supported! '
                'Encountered set literal element which is not an expression: '
                '$collectionElement');
            elements.add('');
          }
        }
        var expressionTypeArguments = expression.typeArguments;
        if (expressionTypeArguments == null ||
            expressionTypeArguments.arguments.isEmpty) {
          return 'const ${_formatAsDynamicSet(elements)}';
        } else {
          assert(expressionTypeArguments.arguments.length == 1);
          String typeArgument =
              await typeAnnotationHelper(expressionTypeArguments.arguments[0]);
          return 'const <$typeArgument>${_formatAsDynamicSet(elements)}';
        }
      } else {
        unreachableError('SetOrMapLiteral is neither a set nor a map');
      }
    } else if (expression is InstanceCreationExpression) {
      String constructor = expression.constructorName.toSource();
      if (_isPrivateName(constructor)) {
        await _severe('Cannot access private name $constructor, '
            'needed for expression $expression');
        return '';
      }
      LibraryElement libraryOfConstructor =
          expression.constructorName.staticElement!.library;
      if (await _isImportableLibrary(
          libraryOfConstructor, generatedLibraryId, resolver)) {
        importCollector._addLibrary(libraryOfConstructor);
        String prefix = importCollector._getPrefix(libraryOfConstructor);
        // TODO(sigurdm) implement: Named arguments.
        List<String> argumentList = [];
        for (Expression argument in expression.argumentList.arguments) {
          argumentList.add(await helper(argument));
        }
        String arguments = argumentList.join(', ');
        // TODO(sigurdm) feature: Type arguments.
        if (_isPrivateName(constructor)) {
          await _severe('Cannot access private name $constructor, '
              'needed for expression $expression');
          return '';
        }
        return 'const $prefix$constructor($arguments)';
      } else {
        await _severe('Cannot access library $libraryOfConstructor, '
            'needed for expression $expression');
        return '';
      }
    } else if (expression is Identifier) {
      if (Identifier.isPrivateName(expression.name)) {
        Element? staticElement = expression.staticElement;
        if (staticElement is PropertyAccessorElement) {
          VariableElement variable = staticElement.variable;
          var variableDeclaration =
              await _getDeclarationAst(variable, resolver);
          if (variableDeclaration == null ||
              variableDeclaration is! VariableDeclaration) {
            await _severe('Cannot handle private identifier $expression');
            return '';
          }
          // A constant variable _does_ have an initializer.
          return await helper(variableDeclaration.initializer!);
        } else {
          await _severe('Cannot handle private identifier $expression');
          return '';
        }
      } else {
        Element? element = expression.staticElement;
        if (element == null) {
          // TODO(eernst): This can occur; but how could `expression` be
          // unresolved? Issue 173.
          await _fine('Encountered unresolved identifier $expression'
              ' in constant; using null');
          return 'null';
        } else if (element.library == null) {
          return '${element.name}';
        } else {
          var elementLibrary = element.library;
          if (elementLibrary != null &&
              await _isImportableLibrary(
                  elementLibrary, generatedLibraryId, resolver)) {
            importCollector._addLibrary(elementLibrary);
            String prefix = importCollector._getPrefix(elementLibrary);
            Element? enclosingElement = element.enclosingElement;
            if (enclosingElement is InterfaceElement) {
              prefix += '${enclosingElement.name}.';
            }
            var elementName = element.name;
            if (elementName != null && _isPrivateName(elementName)) {
              await _severe('Cannot access private name $elementName, '
                  'needed for expression $expression');
            }
            return '$prefix$elementName';
          } else {
            await _severe('Cannot access library $elementLibrary, '
                'needed for expression $expression');
            return '';
          }
        }
      }
    } else if (expression is BinaryExpression) {
      String a = await helper(expression.leftOperand);
      String op = expression.operator.lexeme;
      String b = await helper(expression.rightOperand);
      return '$a $op $b';
    } else if (expression is ConditionalExpression) {
      String condition = await helper(expression.condition);
      String a = await helper(expression.thenExpression);
      String b = await helper(expression.elseExpression);
      return '$condition ? $a : $b';
    } else if (expression is ParenthesizedExpression) {
      String nested = await helper(expression.expression);
      return '($nested)';
    } else if (expression is PropertyAccess) {
      String target = await helper(expression.realTarget);
      String selector = expression.propertyName.token.lexeme;
      return '$target.$selector';
    } else if (expression is MethodInvocation) {
      // We only handle 'identical(a, b)'.
      assert(expression.target == null);
      assert(expression.methodName.token.lexeme == 'identical');
      var arguments = expression.argumentList.arguments;
      assert(arguments.length == 2);
      String a = await helper(arguments[0]);
      String b = await helper(arguments[1]);
      return 'identical($a, $b)';
    } else if (expression is NamedExpression) {
      String value = await _extractConstantCode(
          expression.expression, importCollector, generatedLibraryId, resolver);
      return '${expression.name} $value';
    } else {
      assert(expression is IntegerLiteral ||
          expression is BooleanLiteral ||
          expression is StringLiteral ||
          expression is NullLiteral ||
          expression is SymbolLiteral ||
          expression is DoubleLiteral ||
          expression is TypedLiteral);
      return expression.toSource();
    }
  }

  return await helper(expression);
}

/// The names of the libraries that can be accessed with a 'dart:x' import uri.
const Set<String> sdkLibraryNames = <String>{
  'async',
  'collection',
  'convert',
  'core',
  'developer',
  'indexed_db',
  'io',
  'isolate',
  'js',
  'math',
  'mirrors',
  'profiler',
  'svg',
  'typed_data',
  'ui',
  'web_audio',
  'web_gl',
  'web_sql'
};

// Helper for _extractMetadataCode.
CompilationUnit? _definingCompilationUnit(
    ResolvedLibraryResult resolvedLibrary) {
  var definingUnit = resolvedLibrary.element.definingCompilationUnit;
  var units = resolvedLibrary.units;
  for (var unit in units) {
    if (unit.unit.declaredElement == definingUnit) {
      return unit.unit;
    }
  }
  return null;
}

// Helper for _extractMetadataCode.
NodeList<Annotation>? _getLibraryMetadata(CompilationUnit? unit) {
  if (unit != null) {
    var directive = unit.directives[0];
    if (directive is LibraryDirective) {
      return directive.metadata;
    }
  }
  return null;
}

// Helper for _extractMetadataCode.
NodeList<Annotation>? _getOtherMetadata(AstNode? node, Element element) {
  if (node == null || node is EnumConstantDeclaration) {
    // `node` can be null with members of subclasses of `Element` from
    // 'dart:html', and individual enum values cannot have metadata.
    return null;
  }

  // The `element.node` of a field is the [VariableDeclaration] that is nested
  // in a [VariableDeclarationList] that is nested in a [FieldDeclaration]. The
  // metadata is stored on the [FieldDeclaration].
  //
  // Similarly, the `element.node` of a [TopLevelVariableElement] is a
  // [VariableDeclaration] nested in a [VariableDeclarationList] nested in a
  // [TopLevelVariableDeclaration], which stores the metadata.
  if (element is FieldElement || element is TopLevelVariableElement) {
    node = node.parent!.parent!;
  }

  // We can obtain the `metadata` via two methods in unrelated classes.
  if (node is AnnotatedNode) {
    // One source is an annotated node, which includes most declarations
    // and directives.
    return node.metadata;
  } else {
    // Insist that the only other source is a formal parameter.
    var formalParameter = node as FormalParameter;
    return formalParameter.metadata;
  }
}

/// Returns a String with the code used to build the metadata of [element].
///
/// Also adds any necessary imports to [importCollector].
Future<String> _extractMetadataCode(Element element, Resolver resolver,
    _ImportCollector importCollector, AssetId dataId) async {
  // Synthetic accessors do not have metadata. Only their associated fields.
  if ((element is PropertyAccessorElement ||
          element is ConstructorElement ||
          element is MixinApplication) &&
      element.isSynthetic) {
    return 'const []';
  }

  // TODO(eernst): 'dart:*' is not considered valid. To survive, we return
  // the empty metadata for elements from 'dart:*'. Issue 173.
  if (_isPlatformLibrary(element.library)) {
    return 'const []';
  }

  NodeList<Annotation>? metadata;
  var resolvedLibrary = await _getResolvedLibrary(element.library!, resolver);
  if (element is LibraryElement && resolvedLibrary != null) {
    metadata = _getLibraryMetadata(_definingCompilationUnit(resolvedLibrary));
  } else {
    // The declaration is null if the element is synthetic.
    metadata = _getOtherMetadata(
        resolvedLibrary?.getElementDeclaration(element)?.node, element);
  }
  if (metadata == null || metadata.isEmpty) return 'const []';

  List<String> metadataParts = <String>[];
  for (Annotation annotationNode in metadata) {
    // TODO(sigurdm) diagnostic: Emit a warning/error if the element is not
    // in the global public scope of the library.
    var annotationNodeElement = annotationNode.element;
    if (annotationNodeElement == null) {
      // Some internal constants (mainly in dart:html) cannot be resolved by
      // the analyzer. Ignore them.
      // TODO(sigurdm) clarify: Investigate this, and see if these constants can
      // somehow be included.
      await _fine('Ignoring unresolved metadata $annotationNode', element);
      continue;
    }

    if (!await _isImportable(annotationNodeElement, dataId, resolver)) {
      // Private constants, and constants made of classes in internal libraries
      // cannot be represented.
      // Skip them.
      // TODO(sigurdm) clarify: Investigate this, and see if these constants can
      // somehow be included.
      await _fine('Ignoring unrepresentable metadata $annotationNode', element);
      continue;
    }
    LibraryElement annotationLibrary = annotationNodeElement.library!;
    importCollector._addLibrary(annotationLibrary);
    String prefix = importCollector._getPrefix(annotationLibrary);
    var annotationNodeArguments = annotationNode.arguments;
    if (annotationNodeArguments != null) {
      // A const constructor.
      String name =
          await _extractNameWithoutPrefix(annotationNode.name, element);
      List<String> argumentList = [];
      for (Expression argument in annotationNodeArguments.arguments) {
        argumentList.add(await _extractConstantCode(
            argument, importCollector, dataId, resolver));
      }
      String arguments = argumentList.join(', ');
      if (_isPrivateName(name)) {
        await _severe('Cannot access private name $name', element);
      }
      metadataParts.add('const $prefix$name($arguments)');
    } else {
      // A field reference.
      if (_isPrivateName(annotationNode.name.name)) {
        await _severe(
            'Cannot access private name ${annotationNode.name}', element);
      }
      String name =
          await _extractNameWithoutPrefix(annotationNode.name, element);
      if (_isPrivateName(name)) {
        await _severe('Cannot access private name $name', element);
      }
      metadataParts.add('$prefix$name');
    }
  }

  return _formatAsConstList('Object', metadataParts);
}

/// Extract the plain name from [identifier] by stripping off the
/// library import prefix at front, if any.
Future<String> _extractNameWithoutPrefix(
    Identifier identifier, Element errorTarget) async {
  String name;
  if (identifier is SimpleIdentifier) {
    name = identifier.token.lexeme;
  } else if (identifier is PrefixedIdentifier) {
    // The identifier is of the form `p.id` where `p` is a library
    // prefix, or it is on the form `C.id` where `C` is a class and
    // `id` a named constructor.
    if (identifier.prefix.staticElement is PrefixElement) {
      // We will replace the library prefix by the appropriate prefix for
      // code in the generated library, so we omit the prefix specified in
      // client code.
      name = identifier.identifier.token.lexeme;
    } else {
      // We must preserve the prefix which is a class name.
      name = identifier.name;
    }
  } else {
    await _severe('This kind of identifier is not yet supported: $identifier',
        errorTarget);
    name = identifier.name;
  }
  return name;
}

/// Returns the top level variables declared in the given [libraryElement],
/// filtering them such that the returned ones are those that are supported
/// by [capabilities].
Iterable<TopLevelVariableElement> _extractDeclaredVariables(Resolver resolver,
    LibraryElement libraryElement, _Capabilities capabilities) sync* {
  for (CompilationUnitElement unit in libraryElement.units) {
    for (TopLevelVariableElement variable in unit.topLevelVariables) {
      if (variable.isPrivate || variable.isSynthetic) continue;
      // TODO(eernst) clarify: Do we want to subsume variables under invoke?
      if (capabilities.supportsTopLevelInvoke(variable.library.typeSystem,
          variable.name, variable.metadata, null)) {
        yield variable;
      }
    }
  }
}

/// Returns the top level functions declared in the given [libraryElement],
/// filtering them such that the returned ones are those that are supported
/// by [capabilities].
Iterable<FunctionElement> _extractDeclaredFunctions(Resolver resolver,
    LibraryElement libraryElement, _Capabilities capabilities) sync* {
  for (CompilationUnitElement unit in libraryElement.units) {
    for (FunctionElement function in unit.functions) {
      if (function.isPrivate) continue;
      if (capabilities.supportsTopLevelInvoke(function.library.typeSystem,
          function.name, function.metadata, null)) {
        yield function;
      }
    }
  }
}

/// Returns the parameters declared in the given [declaredFunctions] as well
/// as the setters from the given [accessors].
Iterable<ParameterElement> _extractDeclaredFunctionParameters(
    Resolver resolver,
    Iterable<FunctionElement> declaredFunctions,
    Iterable<ExecutableElement> accessors) {
  List<ParameterElement> result = <ParameterElement>[];
  for (FunctionElement declaredFunction in declaredFunctions) {
    result.addAll(declaredFunction.parameters);
  }
  for (ExecutableElement accessor in accessors) {
    if (accessor is PropertyAccessorElement && accessor.isSetter) {
      result.addAll(accessor.parameters);
    }
  }
  return result;
}

typedef CapabilityChecker = bool Function(
    TypeSystem,
    String methodName,
    Iterable<ElementAnnotation> metadata,
    Iterable<ElementAnnotation>? getterMetadata);

/// Returns the declared fields in the given [interfaceElement], filtered such
/// that the returned ones are the ones that are supported by [capabilities].
Iterable<FieldElement> _extractDeclaredFields(Resolver resolver,
    InterfaceElement interfaceElement, _Capabilities capabilities) {
  return interfaceElement.fields.where((FieldElement field) {
    if (field.isPrivate) return false;
    CapabilityChecker capabilityChecker = field.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    return !field.isSynthetic &&
        capabilityChecker(interfaceElement.library.typeSystem, field.name,
            field.metadata, null);
  });
}

/// Returns the declared methods in the given [interfaceElement], filtered such
/// that the returned ones are the ones that are supported by [capabilities].
Iterable<MethodElement> _extractDeclaredMethods(Resolver resolver,
    InterfaceElement interfaceElement, _Capabilities capabilities) {
  return interfaceElement.methods.where((MethodElement method) {
    if (method.isPrivate) return false;
    CapabilityChecker capabilityChecker = method.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    return capabilityChecker(
        method.library.typeSystem, method.name, method.metadata, null);
  });
}

/// Returns the declared parameters in the given [declaredMethods] and
/// [declaredConstructors], as well as the ones from the setters in
/// [accessors].
List<ParameterElement> _extractDeclaredParameters(
    Iterable<MethodElement> declaredMethods,
    Iterable<ConstructorElement> declaredConstructors,
    Iterable<PropertyAccessorElement> accessors) {
  List<ParameterElement> result = <ParameterElement>[];
  for (MethodElement declaredMethod in declaredMethods) {
    result.addAll(declaredMethod.parameters);
  }
  for (ConstructorElement declaredConstructor in declaredConstructors) {
    result.addAll(declaredConstructor.parameters);
  }
  for (PropertyAccessorElement accessor in accessors) {
    if (accessor.isSetter) {
      result.addAll(accessor.parameters);
    }
  }
  return result;
}

/// Returns the accessors from the given [libraryElement], filtered such that
/// the returned ones are the ones that are supported by [capabilities].
Iterable<PropertyAccessorElement> _extractLibraryAccessors(Resolver resolver,
    LibraryElement libraryElement, _Capabilities capabilities) sync* {
  for (CompilationUnitElement unit in libraryElement.units) {
    for (PropertyAccessorElement accessor in unit.accessors) {
      if (accessor.isPrivate) continue;
      List<ElementAnnotation> metadata;
      List<ElementAnnotation>? getterMetadata;
      if (accessor.isSynthetic) {
        metadata = accessor.variable.metadata;
        getterMetadata = metadata;
      } else {
        metadata = accessor.metadata;
        if (capabilities._impliesCorrespondingSetters &&
            accessor.isSetter &&
            !accessor.isSynthetic) {
          PropertyAccessorElement? correspondingGetter =
              accessor.correspondingGetter;
          getterMetadata = correspondingGetter?.metadata;
        }
      }
      if (capabilities.supportsTopLevelInvoke(accessor.library.typeSystem,
          accessor.name, metadata, getterMetadata)) {
        yield accessor;
      }
    }
  }
}

/// Returns the [PropertyAccessorElement]s which are the accessors
/// of the given [interfaceElement], including both the declared ones
/// and the implicitly generated ones corresponding to fields. This
/// is the set of accessors that corresponds to the behavioral interface
/// of the corresponding instances, as opposed to the source code oriented
/// interface, e.g., `declarations`. But the latter can be computed from
/// here, by filtering out the accessors whose `isSynthetic` is true
/// and adding the fields.
Iterable<PropertyAccessorElement> _extractAccessors(Resolver resolver,
    InterfaceElement interfaceElement, _Capabilities capabilities) {
  return interfaceElement.accessors.where((PropertyAccessorElement accessor) {
    if (accessor.isPrivate) return false;
    // TODO(eernst) implement: refactor treatment of `getterMetadata`
    // such that we avoid passing in `null` at all call sites except one,
    // when we might as well move the processing to that single call site (such
    // as here, but also in `_extractLibraryAccessors()`, etc).
    CapabilityChecker capabilityChecker = accessor.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    List<ElementAnnotation> metadata =
        accessor.isSynthetic ? accessor.variable.metadata : accessor.metadata;
    List<ElementAnnotation>? getterMetadata;
    if (capabilities._impliesCorrespondingSetters &&
        accessor.isSetter &&
        !accessor.isSynthetic) {
      PropertyAccessorElement? correspondingGetter =
          accessor.correspondingGetter;
      getterMetadata = correspondingGetter?.metadata;
    }
    return capabilityChecker(
        accessor.library.typeSystem, accessor.name, metadata, getterMetadata);
  });
}

/// Returns the declared constructors from [interfaceElement], filtered such that
/// the returned ones are the ones that are supported by [capabilities].
Iterable<ConstructorElement> _extractDeclaredConstructors(
    Resolver resolver,
    LibraryElement libraryElement,
    InterfaceElement interfaceElement,
    _Capabilities capabilities) {
  return interfaceElement.constructors.where((ConstructorElement constructor) {
    if (constructor.isPrivate) return false;
    return capabilities.supportsNewInstance(constructor.library.typeSystem,
        constructor.name, constructor.metadata, libraryElement, resolver);
  });
}

_LibraryDomain _createLibraryDomain(
    LibraryElement library, _ReflectorDomain domain) {
  Iterable<TopLevelVariableElement> declaredVariablesOfLibrary =
      _extractDeclaredVariables(domain._resolver, library, domain._capabilities)
          .toList();
  Iterable<FunctionElement> declaredFunctionsOfLibrary =
      _extractDeclaredFunctions(domain._resolver, library, domain._capabilities)
          .toList();
  Iterable<PropertyAccessorElement> accessorsOfLibrary =
      _extractLibraryAccessors(domain._resolver, library, domain._capabilities)
          .toList();
  Iterable<ParameterElement> declaredParametersOfLibrary =
      _extractDeclaredFunctionParameters(
              domain._resolver, declaredFunctionsOfLibrary, accessorsOfLibrary)
          .toList();
  return _LibraryDomain(
      library,
      declaredVariablesOfLibrary,
      declaredFunctionsOfLibrary,
      declaredParametersOfLibrary,
      accessorsOfLibrary,
      domain);
}

_ClassDomain _createClassDomain(
    InterfaceElement type, _ReflectorDomain domain) {
  if (type is MixinApplication) {
    Iterable<FieldElement> declaredFieldsOfClass = _extractDeclaredFields(
            domain._resolver, type.mixin, domain._capabilities)
        .where((FieldElement e) => !e.isStatic)
        .toList();
    Iterable<MethodElement> declaredMethodsOfClass = _extractDeclaredMethods(
            domain._resolver, type.mixin, domain._capabilities)
        .where((MethodElement e) => !e.isStatic)
        .toList();
    Iterable<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
        _extractAccessors(domain._resolver, type.mixin, domain._capabilities)
            .toList();
    Iterable<ConstructorElement> declaredConstructorsOfClass =
        <ConstructorElement>[];
    Iterable<ParameterElement> declaredParametersOfClass =
        _extractDeclaredParameters(declaredMethodsOfClass,
            declaredConstructorsOfClass, declaredAndImplicitAccessorsOfClass);

    return _ClassDomain(
        type,
        declaredFieldsOfClass,
        declaredMethodsOfClass,
        declaredParametersOfClass,
        declaredAndImplicitAccessorsOfClass,
        declaredConstructorsOfClass,
        domain);
  }

  List<FieldElement> declaredFieldsOfClass =
      _extractDeclaredFields(domain._resolver, type, domain._capabilities)
          .toList();
  List<MethodElement> declaredMethodsOfClass =
      _extractDeclaredMethods(domain._resolver, type, domain._capabilities)
          .toList();
  List<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
      _extractAccessors(domain._resolver, type, domain._capabilities).toList();
  List<ConstructorElement> declaredConstructorsOfClass =
      _extractDeclaredConstructors(
              domain._resolver, type.library, type, domain._capabilities)
          .toList();
  List<ParameterElement> declaredParametersOfClass = _extractDeclaredParameters(
      declaredMethodsOfClass,
      declaredConstructorsOfClass,
      declaredAndImplicitAccessorsOfClass);
  return _ClassDomain(
      type,
      declaredFieldsOfClass,
      declaredMethodsOfClass,
      declaredParametersOfClass,
      declaredAndImplicitAccessorsOfClass,
      declaredConstructorsOfClass,
      domain);
}

/// Answers true iff [element] can be imported into [generatedLibraryId].
// TODO(sigurdm) implement: Make a test that tries to reflect on native/private
// classes.
Future<bool> _isImportable(
    Element element, AssetId generatedLibraryId, Resolver resolver) async {
  return await _isImportableLibrary(
      element.library!, generatedLibraryId, resolver);
}

/// Answers true iff [library] can be imported into [generatedLibraryId].
Future<bool> _isImportableLibrary(LibraryElement library,
    AssetId generatedLibraryId, Resolver resolver) async {
  Uri importUri = await _getImportUri(library, resolver, generatedLibraryId);
  return importUri.scheme != 'dart' || sdkLibraryNames.contains(importUri.path);
}

/// Gets a URI which would be appropriate for importing the file represented by
/// [assetId]. This function returns null if we cannot determine a uri for
/// [assetId]. Note that [assetId] may represent a non-importable file such as
/// a part.
Future<String?> _assetIdToUri(AssetId assetId, AssetId from,
    Element messageTarget, Resolver resolver) async {
  if (!assetId.path.startsWith('lib/')) {
    // Cannot do absolute imports of non lib-based assets.
    if (assetId.package != from.package) {
      await _severe(await _formatDiagnosticMessage(
          'Attempt to generate non-lib import from different package',
          messageTarget,
          resolver));
      return null;
    }
    return Uri(
            path: path.url
                .relative(assetId.path, from: path.url.dirname(from.path)))
        .toString();
  }

  return Uri.parse('package:${assetId.package}/${assetId.path.substring(4)}')
      .toString();
}

Future<Uri> _getImportUri(
    LibraryElement lib, Resolver resolver, AssetId from) async {
  var source = lib.source;
  var uri = source.uri;
  if (uri.scheme == 'asset') {
    // This can occur if the library is not accessed via a package uri
    // but instead is given as a path (outside a package, e.g., in `example`
    // of the current package.
    // For instance `asset:reflectable/example/example_lib.dart`.
    String package = uri.pathSegments[0];
    String path = uri.path.substring(package.length + 1);
    return Uri(
        path: await _assetIdToUri(AssetId(package, path), from, lib, resolver));
  }
  if (source is FileSource || source is InSummarySource) {
    return uri;
  }
  // Should not encounter any other source types.
  await _severe('Unable to resolve URI for ${source.runtimeType}');
  return Uri.parse('package:${from.package}/${from.path}');
}

/// Modelling a mixin application as a [ClassElement].
///
/// We need to model mixin applications separately, because the analyzer uses
/// a model where the superclass (that is, `ClassElement.supertype`) is the
/// syntactic superclass (for `class C extends B with M..` it is `B`, not the
/// mixin application `B with M`) rather than the semantic one (`B with M`).
/// The [declaredName] is used in the case `class B = A with M..;` in
/// which case it is `B`; with other mixin applications it is [null].
/// We model the superclass of this mixin application with [superclass],
/// which may be a regular [ClassElement] or a [MixinApplication]; the
/// [mixin] is the class which was applied as a mixin to create this mixin
/// application; the [library] is the enclosing library of the mixin
/// application; and the [subclass] is the class `C` that caused this mixin
/// application to be created because it is the immediate superclass of `C`;
/// [subclass] is only use when it is _not_ a [MixinApplication], so when it
/// would have been a [MixinApplication] it is left as [null].
///
/// This class is only used to mark the synthetic mixin application classes,
/// so most of the class is left unimplemented.
class MixinApplication implements ClassElement {
  final String? declaredName;
  final InterfaceElement superclass;
  final InterfaceElement mixin;
  final InterfaceElement? subclass;

  @override
  final LibraryElement library;

  MixinApplication(this.declaredName, this.superclass, this.mixin, this.library,
      this.subclass);

  @override
  String get name {
    if (declaredName != null) return declaredName!;
    if (superclass is MixinApplication) {
      return '${superclass.name}, ${_qualifiedName(mixin)}';
    } else {
      return '${_qualifiedName(superclass)} with ${_qualifiedName(mixin)}';
    }
  }

  @override
  int get nameLength => name.length;

  @override
  String get displayName => name;

  @override
  List<InterfaceType> get interfaces => <InterfaceType>[];

  @override
  List<ElementAnnotation> get metadata => <ElementAnnotation>[];

  @override
  bool get isSynthetic => declaredName == null;

  @override
  InterfaceType instantiate({
    required List<DartType> typeArguments,
    required NullabilitySuffix nullabilitySuffix,
  }) =>
      InterfaceTypeImpl(
          element: this,
          typeArguments: typeArguments,
          nullabilitySuffix: nullabilitySuffix);

  @override
  InterfaceType? get supertype {
    if (superclass is MixinApplication) return superclass.supertype;
    return _typeForReflectable(superclass) as InterfaceType;
  }

  @override
  List<InterfaceType> get mixins {
    List<InterfaceType> result = <InterfaceType>[];
    if (superclass is MixinApplication) {
      result.addAll(superclass.mixins);
    }
    result.add(_typeForReflectable(mixin) as InterfaceType);
    return result;
  }

  @override
  Source get librarySource => library.source;

  @override
  AnalysisSession? get session => mixin.session;

  @override
  Source get source => mixin.source;

  @override
  int get nameOffset => -1;

  /// Returns true iff this class was declared using the syntax
  /// `class B = A with M;`, i.e., if it is an explicitly named mixin
  /// application.
  @override
  bool get isMixinApplication => declaredName != null;

  @override
  bool get isAbstract {
    var mixin = this.mixin;
    return !isMixinApplication ||
        mixin is MixinElement ||
        mixin is ClassElement && mixin.isAbstract;
  }

  // This seems to be the defined behaviour according to dart:mirrors.
  @override
  bool get isPrivate => false;

  @override
  List<TypeParameterElement> get typeParameters => <TypeParameterElement>[];

  @override
  ElementKind get kind => ElementKind.CLASS;

  @override
  ElementLocation? get location => null;

  @override
  bool operator ==(Object other) {
    return other is MixinApplication &&
        superclass == other.superclass &&
        mixin == other.mixin &&
        library == other.library &&
        subclass == other.subclass;
  }

  @override
  int get hashCode => superclass.hashCode ^ mixin.hashCode ^ library.hashCode;

  @override
  String toString() => 'MixinApplication($superclass, $mixin)';

  // Let the compiler generate forwarders for all remaining methods: Instances
  // of this class are only ever passed around locally in this library, so
  // we will never need to support any members that we don't use locally.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    log.severe('Missing MixinApplication member: ${invocation.memberName}');
  }
}

bool _isSetterName(String name) => name.endsWith('=');

String _setterNameToGetterName(String name) {
  assert(_isSetterName(name));
  return name.substring(0, name.length - 1);
}

String _qualifiedName(Element? element) {
  var elementLibrary = element?.library;
  if (element == null || elementLibrary == null) return 'null';
  return '${elementLibrary.name}.${element.name}';
}

String _qualifiedFunctionName(FunctionElement functionElement) {
  return '${functionElement.library.name}.${functionElement.name}';
}

String _qualifiedTypeParameterName(TypeParameterElement? typeParameterElement) {
  if (typeParameterElement == null) return 'null';
  return '${_qualifiedName(typeParameterElement.enclosingElement!)}.'
      '${typeParameterElement.name}';
}

bool _isPrivateName(String name) {
  return name.startsWith('_') || name.contains('._');
}

EvaluationResult _evaluateConstant(
    LibraryElement library, Expression expression) {
  return ConstantEvaluator((library as LibraryElementImpl).source, library)
      .evaluate(expression);
}

/// Returns the result of evaluating [elementAnnotation].
DartObject? _getEvaluatedMetadatum(ElementAnnotation elementAnnotation) =>
    elementAnnotation.computeConstantValue();

/// Returns the result of evaluating [metadata].
///
/// Returns the result of evaluating each of the element annotations
/// in [metadata] using [_getEvaluatedMetadatum].
Iterable<DartObject> _getEvaluatedMetadata(
    Iterable<ElementAnnotation>? metadata) {
  if (metadata == null) return [];
  var result = <DartObject>[];
  for (var annotation in metadata) {
    var evaluatedMetadatum = _getEvaluatedMetadatum(annotation);
    if (evaluatedMetadatum != null) result.add(evaluatedMetadatum);
  }
  return result;
}

/// Determine whether the given library is a platform library.
///
/// TODO(eernst): This function is only needed until a solution is found to the
/// problem that platform libraries are considered invalid when obtained from
/// `getResolvedLibraryByElement`, such that subsequent use will throw.
/// Issue 173.
bool _isPlatformLibrary(LibraryElement? libraryElement) =>
    libraryElement?.source.uri.scheme == 'dart';

/// Adds a severe error to the log, using the source code location of `target`
/// to identify the relevant location where the error occurs.
Future<void> _severe(String message,
    [Element? target, Resolver? resolver]) async {
  if (target != null && resolver != null) {
    log.severe(await _formatDiagnosticMessage(message, target, resolver));
  } else {
    log.severe(message);
  }
}

/// Adds a 'fine' message to the log, using the source code location of `target`
/// to identify the relevant location where the issue occurs.
Future<void> _fine(String message,
    [Element? target, Resolver? resolver]) async {
  if (target != null && resolver != null) {
    log.fine(await _formatDiagnosticMessage(message, target, resolver));
  } else {
    log.fine(message);
  }
}

/// Returns a string containing the given [message] and identifying the
/// associated source code location as the location of the given [target].
Future<String> _formatDiagnosticMessage(
    String message, Element? target, Resolver resolver) async {
  Source? source = target?.source;
  if (source == null) return message;
  String locationString = '';
  int? nameOffset = target?.nameOffset;
  // TODO(eernst): 'dart:*' is not considered valid. To survive, we return
  // a message with no location info when `element` is from 'dart:*'. Issue 173.
  var targetLibrary = target?.library;
  if (targetLibrary != null &&
      nameOffset != null &&
      !_isPlatformLibrary(targetLibrary)) {
    final resolvedLibrary = await _getResolvedLibrary(targetLibrary, resolver);
    if (resolvedLibrary != null) {
      final targetDeclaration = resolvedLibrary.getElementDeclaration(target!);
      final unit = targetDeclaration?.resolvedUnit?.unit;
      final location = unit?.lineInfo.getLocation(nameOffset);
      if (location != null) {
        locationString = '${location.lineNumber}:${location.columnNumber}';
      }
    }
  }
  return '${source.fullName}:$locationString: $message';
}

// Emits a warning-level log message which will be preserved by `pub run`
// (as opposed to stdout and stderr which are swallowed). If given, [target]
// is used to indicate a source code location.
// ignore:unused_element
Future<void> _emitMessage(String message,
    [Element? target, Resolver? resolver]) async {
  var formattedMessage = (target != null && resolver != null)
      ? await _formatDiagnosticMessage(message, target, resolver)
      : message;
  log.warning(formattedMessage);
}

/// Return [AstNode] of declaration of [element], null if synthetic.
Future<AstNode?> _getDeclarationAst(Element element, Resolver resolver) =>
    resolver.astNodeFor(element, resolve: true);

/// Return the [ResolvedLibraryResult] of the given [library].
///
/// Uses the [resolver] to resolve the library from the asset ID of the
/// given [library], thus avoiding an `InconsistentAnalysisException`
/// which will be thrown if we use `library.session` directly.
Future<ResolvedLibraryResult?> _getResolvedLibrary(
    LibraryElement library, Resolver resolver) async {
  final freshLibrary =
      await resolver.libraryFor(await resolver.assetIdForElement(library));
  final freshSession = freshLibrary.session;
  var someResult = await freshSession.getResolvedLibraryByElement(freshLibrary);
  if (someResult is ResolvedLibraryResult) {
    return someResult;
  } else {
    log.severe('Internal error: Inconsistent analysis session!');
    return null;
  }
}
