// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.builder_implementation;

import 'dart:developer' as developer;
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/constant/evaluation.dart';
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

class ReflectionWorld {
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

  ReflectionWorld(
      this.resolver,
      this.libraries,
      this.generatedLibraryId,
      this.reflectors,
      this.reflectableLibrary,
      this.entryPointLibrary,
      this.importCollector);

  /// The inverse relation of `superinterfaces` union `superclass`, globally.
  Map<ClassElement, Set<ClassElement>> get subtypes {
    if (_subtypesCache != null) return _subtypesCache;

    // Initialize [_subtypesCache], ready to be filled in.
    Map<ClassElement, Set<ClassElement>> subtypes =
        <ClassElement, Set<ClassElement>>{};

    void addSubtypeRelation(ClassElement supertype, ClassElement subtype) {
      Set<ClassElement> subtypesOfSupertype = subtypes[supertype];
      if (subtypesOfSupertype == null) {
        subtypesOfSupertype = <ClassElement>{};
        subtypes[supertype] = subtypesOfSupertype;
      }
      subtypesOfSupertype.add(subtype);
    }

    // Fill in [_subtypesCache].
    for (LibraryElement library in libraries) {
      void addClassElement(ClassElement classElement) {
        InterfaceType supertype = classElement.supertype;
        if (classElement.mixins.isEmpty) {
          if (supertype?.element != null) {
            addSubtypeRelation(supertype.element, classElement);
          }
        } else {
          // Mixins must be applied to a superclass, so it is not null.
          ClassElement superclass = supertype.element;
          // Iterate over all mixins in most-general-first order (so with
          // `class C extends B with M1, M2..` we visit `M1` then `M2`.
          for (InterfaceType mixin in classElement.mixins) {
            ClassElement mixinElement = mixin.element;
            ClassElement subClass =
                mixin == classElement.mixins.last ? classElement : null;
            String name = subClass == null
                ? null
                : (classElement.isMixinApplication ? classElement.name : null);
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
        for (InterfaceType type in classElement.interfaces) {
          if (type.element != null) {
            addSubtypeRelation(type.element, classElement);
          }
        }
      }

      for (CompilationUnitElement unit in library.units) {
        unit.types.forEach(addClassElement);
        unit.enums.forEach(addClassElement);
      }
    }
    _subtypesCache =
        Map<ClassElement, Set<ClassElement>>.unmodifiable(subtypes);
    return _subtypesCache;
  }

  Map<ClassElement, Set<ClassElement>> _subtypesCache;

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
              '\ntypedef ${_typedefName(typedefs[dartType])} = $body;';
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
      return '$mapping';
    } else {
      // The value `null` unambiguously indicates lack of capability.
      return 'null';
    }
  }
}

/// Similar to a `Set<T>` but also keeps track of the index of the first
/// insertion of each item.
class Enumerator<T> {
  final Map<T, int> _map = <T, int>{};
  int _count = 0;

  bool _contains(Object t) => _map.containsKey(t);

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
  int indexOf(Object t) {
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

/// Hybrid data structure holding [ClassElement]s and supporting data.
/// It holds three different data structures used to describe the set of
/// classes under transformation. It holds an [Enumerator] named
/// [classElements] which as a set-like data structure that also enables
/// clients to obtain unique indices for each member; it holds a map
/// [elementToDomain] that maps each [ClassElement] to a corresponding
/// [_ClassDomain]; and it holds a relation [mixinApplicationSupers] that
/// maps each [ClassElement] which is a direct subclass of a mixin application
/// to its superclass. The latter is needed because the analyzer representation
/// of mixins and mixin applications makes it difficult to find a superclass
/// which is a mixin application (`ClassElement.supertype` is the _syntactic_
/// superclass, that is, for `class C extends B with M..` it is `B`, not the
/// mixin application `B with M`). The three data structures are bundled
/// together in this class because they must remain consistent and hence all
/// operations on them should be expressed in one location, namely this class.
/// Note that this data structure can delegate all read-only operations to
/// the [classElements], because they will not break consistency, but for every
/// mutating method we need to maintain the invariants.
class ClassElementEnhancedSet implements Set<ClassElement> {
  final _ReflectorDomain reflectorDomain;
  final Enumerator<ClassElement> classElements = Enumerator<ClassElement>();
  final Map<ClassElement, _ClassDomain> elementToDomain =
      <ClassElement, _ClassDomain>{};
  final Map<ClassElement, MixinApplication> mixinApplicationSupers =
      <ClassElement, MixinApplication>{};
  bool _unmodifiable = false;

  ClassElementEnhancedSet(this.reflectorDomain);

  void makeUnmodifiable() {
    // A very simple implementation, just enough to help spotting cases
    // where modification happens even though it is known to be a bug:
    // Check whether `_unmodifiable` is true whenever a mutating method
    // is called.
    _unmodifiable = true;
  }

  @override
  Iterable<T> map<T>(T Function(ClassElement) f) =>
      classElements.items.map<T>(f);

  @override
  Set<R> cast<R>() {
    Iterable<Object> self = this;
    return self is Set<R> ? self : Set.castFrom<ClassElement, R>(this);
  }

  @override
  Iterable<ClassElement> where(bool Function(ClassElement) f) {
    return classElements.items.where(f);
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
  Iterable<T> expand<T>(Iterable<T> Function(ClassElement) f) {
    return classElements.items.expand<T>(f);
  }

  @override
  void forEach(void Function(ClassElement) f) => classElements.items.forEach(f);

  @override
  ClassElement reduce(
      ClassElement Function(ClassElement, ClassElement) combine) {
    return classElements.items.reduce(combine);
  }

  @override
  T fold<T>(T initialValue, T Function(T, ClassElement) combine) {
    return classElements.items.fold<T>(initialValue, combine);
  }

  @override
  bool every(bool Function(ClassElement) f) => classElements.items.every(f);

  @override
  String join([String separator = '']) => classElements.items.join(separator);

  @override
  bool any(bool Function(ClassElement) f) => classElements.items.any(f);

  @override
  List<ClassElement> toList({bool growable = true}) {
    return classElements.items.toList(growable: growable);
  }

  @override
  int get length => classElements.items.length;

  @override
  bool get isEmpty => classElements.items.isEmpty;

  @override
  bool get isNotEmpty => classElements.items.isNotEmpty;

  @override
  Iterable<ClassElement> take(int count) => classElements.items.take(count);

  @override
  Iterable<ClassElement> takeWhile(bool Function(ClassElement) test) {
    return classElements.items.takeWhile(test);
  }

  @override
  Iterable<ClassElement> skip(int count) => classElements.items.skip(count);

  @override
  Iterable<ClassElement> skipWhile(bool Function(ClassElement) test) {
    return classElements.items.skipWhile(test);
  }

  @override
  Iterable<ClassElement> followedBy(Iterable<ClassElement> other) sync* {
    yield* this;
    yield* other;
  }

  @override
  ClassElement get first => classElements.items.first;

  @override
  ClassElement get last => classElements.items.last;

  @override
  ClassElement get single => classElements.items.single;

  @override
  ClassElement firstWhere(bool Function(ClassElement) test,
      {ClassElement Function() orElse}) {
    return classElements.items.firstWhere(test, orElse: orElse);
  }

  @override
  ClassElement lastWhere(bool Function(ClassElement) test,
      {ClassElement Function() orElse}) {
    return classElements.items.lastWhere(test, orElse: orElse);
  }

  @override
  ClassElement singleWhere(bool Function(ClassElement) test,
      {ClassElement Function() orElse}) {
    return classElements.items.singleWhere(test);
  }

  @override
  ClassElement elementAt(int index) => classElements.items.elementAt(index);

  @override
  Iterator<ClassElement> get iterator => classElements.items.iterator;

  @override
  bool contains(Object value) => classElements.items.contains(value);

  @override
  bool add(ClassElement value) {
    assert(!_unmodifiable);
    bool result = classElements.add(value);
    if (result) {
      assert(!elementToDomain.containsKey(value));
      elementToDomain[value] = _createClassDomain(value, reflectorDomain);
      if (value is MixinApplication && value.subclass != null) {
        // [value] is a mixin application which is the immediate superclass
        // of a class which is a regular class (not a mixin application). This
        // means that we must store it in `mixinApplicationSupers` such that
        // we can look it up during invocations of [superclassOf].
        assert(!mixinApplicationSupers.containsKey(value.subclass));
        mixinApplicationSupers[value.subclass] = value;
      }
    }
    return result;
  }

  @override
  void addAll(Iterable<ClassElement> elements) => elements.forEach(add);

  @override
  bool remove(Object value) {
    assert(!_unmodifiable);
    bool result = classElements._contains(value);
    classElements._map.remove(value);
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
  ClassElement lookup(Object object) {
    for (ClassElement classElement in classElements._map.keys) {
      if (object == classElement) return classElement;
    }
    return null;
  }

  @override
  void removeAll(Iterable<Object> elements) => elements.forEach(remove);

  @override
  void retainAll(Iterable<Object> elements) {
    bool test(ClassElement element) => !elements.contains(element);
    removeWhere(test);
  }

  @override
  void removeWhere(bool Function(ClassElement) test) {
    var toRemove = <ClassElement>{};
    for (ClassElement classElement in classElements.items) {
      if (test(classElement)) toRemove.add(classElement);
    }
    removeAll(toRemove);
  }

  @override
  void retainWhere(bool Function(ClassElement) test) {
    bool inverted_test(ClassElement element) => !test(element);
    removeWhere(inverted_test);
  }

  @override
  bool containsAll(Iterable<Object> other) {
    return classElements.items.toSet().containsAll(other);
  }

  @override
  Set<ClassElement> intersection(Set<Object> other) {
    return classElements.items.toSet().intersection(other);
  }

  @override
  Set<ClassElement> union(Set<ClassElement> other) {
    return classElements.items.toSet().union(other);
  }

  @override
  Set<ClassElement> difference(Set<Object> other) {
    return classElements.items.toSet().difference(other);
  }

  @override
  void clear() {
    assert(!_unmodifiable);
    classElements.clear();
    elementToDomain.clear();
  }

  @override
  Set<ClassElement> toSet() => this;

  /// Returns the superclass of the given [classElement] using the language
  /// semantics rather than the analyzer model (where the superclass is the
  /// syntactic one, i.e., `class C extends B with M..` has superclass `B`,
  /// not the mixin application `B with M`). This method will use the analyzer
  /// data to find the superclass, which means that it will _not_ refrain
  /// from returning a class which is not covered by any particular reflector.
  /// It is up to the caller to check that.
  ClassElement superclassOf(ClassElement classElement) {
    // By construction of [MixinApplication]s, their `superclass` is correct.
    if (classElement is MixinApplication) return classElement.superclass;
    // For a regular class whose superclass is also not a mixin application,
    // the analyzer `supertype` is what we want. Note that this gets [null]
    // from [Object], which is intended: We consider that (non-existing) class
    // as covered, and use [null] to represent it; there is no clash with
    // returning [null] to indicate that a superclass is not covered, because
    // this method does not check coverage.
    if (classElement.mixins.isEmpty) return classElement.supertype?.element;
    // [classElement] is now known to be a regular class whose superclass
    // is a mixin application. For each [MixinApplication] `m` we store, if it
    // was created as a superclass of a regular (non mixin application) class
    // `C` then we have stored a mapping from `C` to `m` in the map
    // `mixinApplicationSupers`.
    assert(mixinApplicationSupers.containsKey(classElement));
    return mixinApplicationSupers[classElement];
  }

  /// Returns the _ClassDomain corresponding to the given [classElement],
  /// which must be a member of this [ClassElementEnhancedSet].
  _ClassDomain domainOf(ClassElement classElement) {
    assert(elementToDomain.containsKey(classElement));
    return elementToDomain[classElement];
  }

  /// Returns the index of the given [classElement] if it is contained
  /// in this [ClassElementEnhancedSet], otherwise [null].
  int indexOf(Object classElement) {
    return classElements.indexOf(classElement);
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
  ErasableDartType(this.dartType, {this.erased});

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
  ReflectionWorld _world; // Non-final due to cycle, do not modify.
  final Resolver _resolver;
  final AssetId _generatedLibraryId;
  final ClassElement _reflector;

  /// Do not use this, use [classes] which ensures that closure operations
  /// have been performed as requested in [_capabilities]. Exception: In
  /// `_computeWorld`, [_classes] is filled in with the set of directly
  /// covered classes during creation of this [_ReflectorDomain].
  /// NB: [_classes] should be final, but it is not possible because this
  /// would create a cycle of final fields, which cannot be initialized.
  ClassElementEnhancedSet _classes;

  /// Used by [classes], only, to keep track of whether [_classes] has been
  /// properly initialized by means of closure operations.
  bool _classesInitialized = false;

  /// Returns the set of classes covered by `_reflector`, including the ones
  /// which are directly covered by carrying `_reflector` as metadata or being
  /// matched by a global quantifier, and including the ones which are reached
  /// via the closure operations requested in [_capabilities].
  Future<ClassElementEnhancedSet> get classes async {
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
    _classes = ClassElementEnhancedSet(this);
  }

  final _instanceMemberCache = <ClassElement, Map<String, ExecutableElement>>{};

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
      return '(b) => ([length]) => '
          'b ? (length == null ? List() : List(length)) : null';
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
      parameterParts.add('{${namedWithDefaults}}');
      argumentParts.add(namedArguments);
    }

    String doRunArgument = 'b';
    while (parameterNames.contains(doRunArgument)) {
      doRunArgument = doRunArgument + 'b';
    }

    String prefix = importCollector._getPrefix(constructor.library);
    return ('($doRunArgument) => (${parameterParts.join(', ')}) => '
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
  Future<String> _generateCode(ReflectionWorld world,
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
    ClassElement objectClassElement;

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
    (await classes).forEach((ClassElement classElement) {
      LibraryElement classLibrary = classElement.library;
      if (!libraries.items.any((_LibraryDomain libraryDomain) =>
          libraryDomain._libraryElement == classLibrary)) {
        addLibrary(classLibrary);
      }
      classElement.typeParameters.forEach(typeParameters.add);
    });
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
      classDomain._instanceMembers.forEach((ExecutableElement instanceMember) {
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
      });
    }

    // Add classes used as bounds for type variables, if needed.
    if (_capabilities._impliesTypes && _capabilities._impliesTypeAnnotations) {
      Future<void> addClass(ClassElement classElement) async {
        (await classes).add(classElement);
        LibraryElement classLibrary = classElement.library;
        if (!libraries.items
            .any((domain) => domain._libraryElement == classLibrary)) {
          uncheckedAddLibrary(classLibrary);
        }
      }

      bool hasObject = false;
      bool mustHaveObject = false;
      var classesToAdd = <ClassElement>{};
      ClassElement anyClassElement;
      for (ClassElement classElement in await classes) {
        if (_typeForReflectable(classElement).isObject) {
          hasObject = true;
          objectClassElement = classElement;
          break;
        }
        if (classElement.typeParameters.isNotEmpty) {
          for (TypeParameterElement typeParameterElement
              in classElement.typeParameters) {
            if (typeParameterElement.bound == null) {
              mustHaveObject = true;
              anyClassElement = classElement;
            } else {
              Element boundElement = typeParameterElement.bound.element;
              if (boundElement is ClassElement) {
                classesToAdd.add(boundElement);
              }
            }
          }
        }
      }
      if (mustHaveObject && !hasObject) {
        while (!_typeForReflectable(anyClassElement).isObject) {
          anyClassElement = anyClassElement.supertype.element;
        }
        objectClassElement = anyClassElement;
        await addClass(objectClassElement);
      }
      for (var clazz in classesToAdd) {
        await addClass(clazz);
      }
    }

    // From this point, [classes] must be kept immutable.
    (await classes).makeUnmodifiable();

    // Record the names of covered members, if requested.
    if (_capabilities._impliesMemberSymbols) {
      members.items.forEach((ExecutableElement executableElement) =>
          _world.memberNames.add(executableElement.name));
    }

    // Record the method parameter list shapes, if requested.
    if (_capabilities._impliesParameterListShapes) {
      members.items.forEach((ExecutableElement element) {
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
      });
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
            typeParameterElement, importCollector, objectClassElement));
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
      Iterable<String> membersList = () sync* {
        yield* topLevelVariablesList;
        yield* fieldsList;
        yield* methodsList;
      }();
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
    for (ClassElement classElement in await classes) {
      typesCodeList.add(_dynamicTypeCodeOfClass(classElement, importCollector));
    }
    for (ErasableDartType erasableDartType in reflectedTypes.items) {
      if (erasableDartType.erased) {
        typesCodeList.add(_dynamicTypeCodeOfClass(
            erasableDartType.dartType.element, importCollector));
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
            libraries.indexOf(library),
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

  Future<int> _computeTypeIndexBase(Element typeElement, bool isVoid,
      bool isDynamic, bool isClassType) async {
    if (_capabilities._impliesTypes) {
      if (isDynamic || isVoid) {
        // The mirror will report 'dynamic' or 'void' as its `returnType`
        // and it will never use the index.
        return null;
      }
      if (isClassType && (await classes).contains(typeElement)) {
        // Normal encoding of a class type which has been added to `classes`.
        return (await classes).indexOf(typeElement);
      }
      // At this point [typeElement] may be a non-class type, or it may be a
      // class that has not been added to `classes`, say, an argument type
      // annotation in a setting where we do not have an
      // [ec.TypeAnnotationQuantifyCapability]. In both cases we fall through
      // because the relevant capability is absent.
    }
    return constants.NO_CAPABILITY_INDEX;
  }

  Future<int> _computeVariableTypeIndex(
      PropertyInducingElement element, int descriptor) async {
    if (!_capabilities._impliesTypes) return constants.NO_CAPABILITY_INDEX;
    return await _computeTypeIndexBase(
        element.type.element,
        false, // No field has type `void`.
        descriptor & constants.dynamicAttribute != 0,
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
          List<int> typesIndices = [];
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
    if (!_capabilities._impliesTypes) return constants.NO_CAPABILITY_INDEX;
    int result = await _computeTypeIndexBase(
        element.returnType.element,
        descriptor & constants.voidReturnTypeAttribute != 0,
        descriptor & constants.dynamicReturnTypeAttribute != 0,
        descriptor & constants.classReturnTypeAttribute != 0);
    return result;
  }

  Future<int> _computeOwnerIndex(
      ExecutableElement element, int descriptor) async {
    if (element.enclosingElement is ClassElement) {
      return (await classes).indexOf(element.enclosingElement);
    } else if (element.enclosingElement is CompilationUnitElement) {
      return _libraries.indexOf(element.enclosingElement.enclosingElement);
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
      ClassElement objectClassElement) async {
    int upperBoundIndex = constants.NO_CAPABILITY_INDEX;
    if (_capabilities._impliesTypeAnnotations) {
      DartType bound = typeParameterElement.bound;
      if (bound == null) {
        assert(objectClassElement != null);
        // Missing bound should be reported as the semantic default: `Object`.
        // We use an ugly hack to obtain the [ClassElement] for `Object`.
        upperBoundIndex = (await classes).indexOf(objectClassElement);
        assert(upperBoundIndex != null);
      } else if (bound.isDynamic) {
        // We use [null] to indicate that this bound is [dynamic] ([void]
        // cannot be a bound, so the only special case is [dynamic]).
        upperBoundIndex = null;
      } else {
        upperBoundIndex =
            (await classes).indexOf(typeParameterElement.bound.element);
      }
    }
    int ownerIndex =
        (await classes).indexOf(typeParameterElement.enclosingElement);
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
    int descriptor = _classDescriptor(classDomain._classElement);

    // Fields go first in [memberMirrors], so they will get the
    // same index as in [fields].
    Iterable<int> fieldsIndices =
        classDomain._declaredFields.map((FieldElement element) {
      return fields.indexOf(element) + fieldsOffset;
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
      // issue. For now, we use the index [constants.NO_CAPABILITY_INDEX]
      // for this declaration, because it is not yet supported.
      // Need to find the correct solution, though!
      int index = members.indexOf(element);
      return index == null
          ? constants.NO_CAPABILITY_INDEX
          : index + methodsOffset;
    });

    String declarationsCode = _capabilities._impliesDeclarations
        ? _formatAsConstList('int', () sync* {
            yield* fieldsIndices;
            yield* methodsIndices;
          }())
        : 'const <int>[${constants.NO_CAPABILITY_INDEX}]';

    // All instance members belong to the behavioral interface, so they
    // also get an offset of `fields.length`.
    String instanceMembersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      instanceMembersCode = _formatAsConstList('int',
          classDomain._instanceMembers.map((ExecutableElement element) {
        // TODO(eernst) implement: The "magic" default constructor has
        // index: NO_CAPABILITY_INDEX; adjust this when support for it has
        // been implemented.
        int index = members.indexOf(element);
        return index == null
            ? constants.NO_CAPABILITY_INDEX
            : index + methodsOffset;
      }));
    }

    // All static members belong to the behavioral interface, so they
    // also get an offset of `fields.length`.
    String staticMembersCode = 'null';
    if (_capabilities._impliesDeclarations) {
      staticMembersCode = _formatAsConstList('int',
          classDomain._staticMembers.map((ExecutableElement element) {
        int index = members.indexOf(element);
        return index == null
            ? constants.NO_CAPABILITY_INDEX
            : index + methodsOffset;
      }));
    }

    ClassElement classElement = classDomain._classElement;
    ClassElement superclass = (await classes).superclassOf(classElement);

    String superclassIndex = '${constants.NO_CAPABILITY_INDEX}';
    if (_capabilities._impliesTypeRelations) {
      // [Object]'s superclass is reported as `null`: it does not exist and
      // hence we cannot decide whether it's supported or unsupported.; by
      // convention we make it supported and report it in the same way as
      // 'dart:mirrors'. Other superclasses use `NO_CAPABILITY_INDEX` to
      // indicate missing support.
      superclassIndex = (classElement is! MixinApplication &&
              _typeForReflectable(classElement).isObject)
          ? 'null'
          : ((await classes).contains(superclass))
              ? '${(await classes).indexOf(superclass)}'
              : '${constants.NO_CAPABILITY_INDEX}';
    }

    String constructorsCode;
    if (classElement is MixinApplication) {
      constructorsCode = 'const {}';
    } else {
      List<String> mapEntries = [];
      for (ConstructorElement constructor in classDomain._constructors) {
        if (constructor.isFactory || !constructor.enclosingElement.isAbstract) {
          String code = await _constructorCode(constructor, importCollector);
          mapEntries.add("r'${constructor.name}': $code");
        }
      }
      constructorsCode = _formatAsMap(mapEntries);
    }

    String staticGettersCode = 'const {}';
    String staticSettersCode = 'const {}';
    if (classElement is! MixinApplication) {
      List<String> staticGettersCodeList = [];
      for (MethodElement method in classDomain._declaredMethods) {
        if (method.isStatic) {
          staticGettersCodeList.add(await _staticGettingClosure(
              importCollector, classElement, method.name));
        }
      }
      for (PropertyAccessorElement accessor in classDomain._accessors) {
        if (accessor.isStatic && accessor.isGetter) {
          staticGettersCodeList.add(await _staticGettingClosure(
              importCollector, classElement, accessor.name));
        }
      }
      staticGettersCode = _formatAsMap(staticGettersCodeList);
      List<String> staticSettersCodeList = [];
      for (PropertyAccessorElement accessor in classDomain._accessors) {
        if (accessor.isStatic && accessor.isSetter) {
          staticSettersCodeList.add(await _staticSettingClosure(
              importCollector, classElement, accessor.name));
        }
      }
      staticSettersCode = _formatAsMap(staticSettersCodeList);
    }

    int mixinIndex = constants.NO_CAPABILITY_INDEX;
    if (_capabilities._impliesTypeRelations) {
      mixinIndex = classElement.isMixinApplication
          // Named mixin application (using the syntax `class B = A with M;`).
          ? (await classes).indexOf(classElement.mixins.last.element)
          : (classElement is MixinApplication
              // Anonymous mixin application.
              ? (await classes).indexOf(classElement.mixin)
              // No mixins, by convention we use the class itself.
              : (await classes).indexOf(classElement));
      // We may not have support for the given class, in which case we must
      // correct the `null` from `indexOf` to indicate missing capability.
      mixinIndex ??= constants.NO_CAPABILITY_INDEX;
    }

    int ownerIndex = _capabilities._supportsLibraries
        ? libraries.indexOf(libraryMap[classElement.library])
        : constants.NO_CAPABILITY_INDEX;

    String superinterfaceIndices =
        'const <int>[${constants.NO_CAPABILITY_INDEX}]';
    if (_capabilities._impliesTypeRelations) {
      superinterfaceIndices = _formatAsConstList(
          'int',
          classElement.interfaces
              .map((InterfaceType type) => type.element)
              .where((await classes).contains)
              .map((await classes).indexOf));
    }

    String classMetadataCode;
    if (_capabilities._supportsMetadata) {
      classMetadataCode = await _extractMetadataCode(
          classElement, _resolver, importCollector, _generatedLibraryId);
    } else {
      classMetadataCode = 'null';
    }

    int classIndex = (await classes).indexOf(classElement);

    String parameterListShapesCode = 'null';
    if (_capabilities._impliesParameterListShapes) {
      Iterable<ExecutableElement> membersList = () sync* {
        yield* classDomain._instanceMembers;
        yield* classDomain._staticMembers;
      }();
      parameterListShapesCode =
          _formatAsMap(membersList.map((ExecutableElement element) {
        ParameterListShape shape = parameterListShapeOf[element];
        assert(
            shape != null); // Every method must have its shape in `..shapeOf`.
        int index = parameterListShapes.indexOf(shape);
        assert(index != null); // Every shape must be in `..Shapes`.
        return "r'${element.name}': $index";
      }));
    }

    if (classElement.typeParameters.isEmpty) {
      return "r.NonGenericClassMirrorImpl(r'${classDomain._simpleName}', "
          "r'${_qualifiedName(classElement)}', $descriptor, $classIndex, "
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
      // class modeled by [classElement], and (2) that it is not an instance
      // of the fully dynamic instance of any of the classes that `extends` or
      // `implements` this [classElement].
      List<String> isCheckList = [];
      if (classElement.isPrivate ||
          classElement.isAbstract ||
          (classElement is MixinApplication &&
              !classElement.isMixinApplication) ||
          !await _isImportable(classElement, _generatedLibraryId, _resolver)) {
        // Note that this location is dead code until we get support for
        // anonymous mixin applications using type arguments as generic
        // classes (currently, no classes will pass the tests above). See
        // https://github.com/dart-lang/sdk/issues/25344 for more details.
        // However, the result that we will return is well-defined, because
        // no object can be an instance of an anonymous mixin application.
        isCheckList.add('(o) => false');
      } else {
        String prefix = importCollector._getPrefix(classElement.library);
        isCheckList.add('(o) { return o is $prefix${classElement.name}');

        // Add 'is checks' to [list], based on [classElement].
        Future<void> helper(
            List<String> list, ClassElement classElement) async {
          Iterable<ClassElement> subtypes =
              _world.subtypes[classElement] ?? <ClassElement>[];
          for (ClassElement subtype in subtypes) {
            if (subtype.isPrivate ||
                subtype.isAbstract ||
                (subtype is MixinApplication && !subtype.isMixinApplication) ||
                !await _isImportable(subtype, _generatedLibraryId, _resolver)) {
              await helper(list, subtype);
            } else {
              String prefix = importCollector._getPrefix(subtype.library);
              list.add(' && o is! $prefix${subtype.name}');
            }
          }
        }

        await helper(isCheckList, classElement);
        isCheckList.add('; }');
      }
      String isCheckCode = isCheckList.join();

      String typeParameterIndices = 'null';
      if (_capabilities._impliesDeclarations) {
        int indexOf(TypeParameterElement typeParameter) =>
            typeParameters.indexOf(typeParameter) + typeParametersOffset;
        typeParameterIndices = _formatAsConstList(
            'int',
            classElement.typeParameters
                .where(typeParameters.items.contains)
                .map(indexOf));
      }

      int dynamicReflectedTypeIndex = _dynamicTypeCodeIndex(
          _typeForReflectable(classElement),
          await classes,
          reflectedTypes,
          reflectedTypesOffset,
          typedefs);

      return "r.GenericClassMirrorImpl(r'${classDomain._simpleName}', "
          "r'${_qualifiedName(classElement)}', $descriptor, $classIndex, "
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
          ? topLevelVariables.indexOf(variable)
          : fields.indexOf(variable);
      assert(variableMirrorIndex != null);
      int selfIndex = members.indexOf(accessorElement) + fields.length;
      assert(selfIndex != null);
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
      int ownerIndex = await _computeOwnerIndex(element, descriptor);
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
      int reflectedReturnTypeIndex = constants.NO_CAPABILITY_INDEX;
      if (reflectedTypeRequested) {
        reflectedReturnTypeIndex = _typeCodeIndex(element.returnType,
            await classes, reflectedTypes, reflectedTypesOffset, typedefs);
      }
      int dynamicReflectedReturnTypeIndex = constants.NO_CAPABILITY_INDEX;
      if (reflectedTypeRequested) {
        dynamicReflectedReturnTypeIndex = _dynamicTypeCodeIndex(
            element.returnType,
            await classes,
            reflectedTypes,
            reflectedTypesOffset,
            typedefs);
      }
      String metadataCode = _capabilities._supportsMetadata
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
    int ownerIndex =
        _libraries.indexOf(element.enclosingElement.enclosingElement);
    int classMirrorIndex = await _computeVariableTypeIndex(element, descriptor);
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.NO_CAPABILITY_INDEX;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.NO_CAPABILITY_INDEX;
    String reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
          element.type,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs);
    }
    String metadataCode;
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
    int ownerIndex = (await classes).indexOf(element.enclosingElement);
    int classMirrorIndex = await _computeVariableTypeIndex(element, descriptor);
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.NO_CAPABILITY_INDEX;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.NO_CAPABILITY_INDEX;
    String reflectedTypeArguments = 'null';
    if (reflectedTypeRequested && _capabilities._impliesTypeRelations) {
      reflectedTypeArguments = await _computeReflectedTypeArguments(
          element.type,
          reflectedTypes,
          reflectedTypesOffset,
          importCollector,
          typedefs);
    }
    String metadataCode;
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
      ClassElementEnhancedSet classes,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      Map<FunctionType, int> typedefs) {
    // The type `dynamic` is handled via the `dynamicAttribute` bit.
    if (dartType.isDynamic) return null;
    if (dartType is InterfaceType) {
      if (dartType.typeArguments.isEmpty) {
        // A plain, non-generic class, may be handled already.
        ClassElement classElement = dartType.element;
        if (classes.contains(classElement)) {
          return classes.indexOf(classElement);
        }
      }
      // An instantiation of a generic class, or a non-generic class which is
      // not present in `classes`: Use `reflectedTypes`, possibly adding it.
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      return reflectedTypes.indexOf(erasableDartType) + reflectedTypesOffset;
    } else if (dartType is VoidType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(ErasableDartType(dartType, erased: false));
      return reflectedTypes.indexOf(erasableDartType) + reflectedTypesOffset;
    } else if (dartType is FunctionType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      int index =
          reflectedTypes.indexOf(erasableDartType) + reflectedTypesOffset;
      if (dartType.typeFormals.isNotEmpty) {
        typedefs[dartType] = index;
      }
      return index;
    }
    // We only handle the kinds of types already covered above. In particular,
    // we cannot produce code to return a value for `void`.
    return constants.NO_CAPABILITY_INDEX;
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
      ClassElementEnhancedSet classes,
      Enumerator<ErasableDartType> reflectedTypes,
      int reflectedTypesOffset,
      Map<FunctionType, int> typedefs) {
    // The type `dynamic` is handled via the `dynamicAttribute` bit.
    if (dartType.isDynamic) return null;
    if (dartType is InterfaceType) {
      ClassElement classElement = dartType.element;
      if (classes.contains(classElement)) {
        return classes.indexOf(classElement);
      }
      // [dartType] is not present in `classes`, so we must use `reflectedTypes`
      // and iff it has type arguments we must specify that it should be erased
      // (if there are no type arguments we will use "not erased": erasure
      // makes no difference and we don't want to have two identical copies).
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: dartType.typeArguments.isNotEmpty);
      reflectedTypes.add(erasableDartType);
      return reflectedTypes.indexOf(erasableDartType) + reflectedTypesOffset;
    } else if (dartType is VoidType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(ErasableDartType(dartType, erased: false));
      return reflectedTypes.indexOf(erasableDartType) + reflectedTypesOffset;
    } else if (dartType is FunctionType) {
      ErasableDartType erasableDartType =
          ErasableDartType(dartType, erased: false);
      reflectedTypes.add(erasableDartType);
      int index =
          reflectedTypes.indexOf(erasableDartType) + reflectedTypesOffset;
      if (dartType.typeFormals.isNotEmpty) {
        // TODO(eernst) clarify: Maybe we should create an "erased" version
        // of `dartType` in this case, and adjust `erased:` above?
        typedefs[dartType] = index;
      }
      return index;
    }
    // We only handle the kinds of types already covered above.
    return constants.NO_CAPABILITY_INDEX;
  }

  /// Returns true iff the given [type] is not and does not contain a free
  /// type variable. [typeVariablesInScope] gives the names of type variables
  /// which are in scope (and hence not free in the relevant context).
  bool _hasNoFreeTypeVariables(DartType type,
      [Set<String> typeVariablesInScope]) {
    if (type is TypeParameterType &&
        (typeVariablesInScope == null ||
            !typeVariablesInScope.contains(type.getDisplayString()))) {
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
      log.warning(await _formatDiagnosticMessage(
          'Attempt to generate code for an '
          'unsupported kind of type: $dartType (${dartType.runtimeType}). '
          'Generating `dynamic`.',
          dartType.element));
      return 'dynamic';
    }

    if (dartType.isDynamic) return 'dynamic';
    if (dartType is InterfaceType) {
      ClassElement classElement = dartType.element;
      if ((classElement is MixinApplication &&
              classElement.declaredName == null) ||
          classElement.isPrivate) {
        return await fail();
      }
      String prefix = importCollector._getPrefix(classElement.library);
      if (classElement.typeParameters.isEmpty) {
        return '$prefix${classElement.name}';
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
          return '$prefix${classElement.name}<$arguments>';
        } else {
          return await fail();
        }
      }
    } else if (dartType is VoidType) {
      return 'void';
    } else if (dartType is FunctionType) {
      if (dartType is FunctionTypeAliasElement) {
        FunctionTypeAliasElement element = dartType.element;
        String prefix = importCollector._getPrefix(element.library);
        return '$prefix${element.name}';
      } else {
        // Generic function types need separate `typedef`s.
        if (dartType.typeFormals.isNotEmpty) {
          if (useNameOfGenericFunctionType) {
            // Requested: just the name of the typedef; get it and return.
            int dartTypeNumber = typedefs.containsKey(dartType)
                ? typedefs[dartType]
                : typedefNumber++;
            return _typedefName(dartTypeNumber);
          } else {
            // Requested: the spelled-out generic function type; continue.
            (typeVariablesInScope ??= <String>{})
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
            DartType parameterType = parameterMap[name];
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
        typeVariablesInScope != null &&
        typeVariablesInScope.contains(dartType.getDisplayString())) {
      return dartType.getDisplayString();
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
      ClassElement classElement = dartType.element;
      if ((classElement is MixinApplication &&
              classElement.declaredName == null) ||
          classElement.isPrivate) {
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
        return "const r.FakeType(r'${_qualifiedName(classElement)}')";
      }
      String prefix = importCollector._getPrefix(classElement.library);
      if (classElement.typeParameters.isEmpty) {
        return '$prefix${classElement.name}';
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
              "r'${_qualifiedName(classElement)}<$arguments>')";
        }
      }
    } else if (dartType is VoidType) {
      return 'const m.TypeValue<void>().type';
    } else if (dartType is FunctionType) {
      // A function type is inherently not private, so we ignore privacy.
      // Note that some function types are _claimed_ to be private in analyzer
      // 0.36.4, so it is a bug to test for it.
      if (dartType.element is FunctionTypeAliasElement) {
        FunctionTypeAliasElement element = dartType.element;
        String prefix = importCollector._getPrefix(element.library);
        return '$prefix${element.name}';
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
      log.warning(await _formatDiagnosticMessage(
          'Attempt to generate code for an '
          'unsupported kind of type: $dartType (${dartType.runtimeType}). '
          'Generating `dynamic`.',
          dartType.element));
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
    DartType type = typeDefiningElement is ClassElement
        ? _typeForReflectable(typeDefiningElement)
        : null;
    if (type?.isDynamic ?? true) return 'dynamic';
    if (type is InterfaceType) {
      ClassElement classElement = type.element;
      if ((classElement is MixinApplication &&
              classElement.declaredName == null) ||
          classElement.isPrivate) {
        return "const r.FakeType(r'${_qualifiedName(classElement)}')";
      }
      String prefix = importCollector._getPrefix(classElement.library);
      return '$prefix${classElement.name}';
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
      return variables.indexOf(element);
    });

    // All the elements in the behavioral interface go after the
    // fields in [memberMirrors], so they must get an offset of
    // `fields.length` on the index.
    Iterable<int> methodIndices = libraryDomain._declarations
        .where(_executableIsntImplicitGetterOrSetter)
        .map((ExecutableElement element) {
      int index = members.indexOf(element);
      return index + methodsOffset;
    });

    String declarationsCode = 'const <int>[${constants.NO_CAPABILITY_INDEX}]';
    if (_capabilities._impliesDeclarations) {
      Iterable<int> declarationsIndices = () sync* {
        yield* variableIndices;
        yield* methodIndices;
      }();
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
        ParameterListShape shape = parameterListShapeOf[element];
        assert(shape != null); // Every method has a shape in `..shapeOf`.
        int index = parameterListShapes.indexOf(shape);
        assert(index != null); // Every shape is in `..Shapes`.
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
    int ownerIndex = members.indexOf(element.enclosingElement) + fields.length;
    int classMirrorIndex;
    if (_capabilities._impliesTypes) {
      if (descriptor & constants.dynamicAttribute != 0) {
        // This parameter will report its type as [dynamic], and it
        // will never use `classMirrorIndex`.
        classMirrorIndex = null;
      } else if (descriptor & constants.classTypeAttribute != 0) {
        // Normal encoding of a class type. If that class has been added
        // to `classes` we use its `indexOf`; otherwise (if we do not have an
        // [ec.TypeAnnotationQuantifyCapability]) we must indicate that the
        // capability is absent.
        classMirrorIndex = (await classes).contains(element.type.element)
            ? (await classes).indexOf(element.type.element)
            : constants.NO_CAPABILITY_INDEX;
      }
    } else {
      classMirrorIndex = constants.NO_CAPABILITY_INDEX;
    }
    int reflectedTypeIndex = reflectedTypeRequested
        ? _typeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.NO_CAPABILITY_INDEX;
    int dynamicReflectedTypeIndex = reflectedTypeRequested
        ? _dynamicTypeCodeIndex(element.type, await classes, reflectedTypes,
            reflectedTypesOffset, typedefs)
        : constants.NO_CAPABILITY_INDEX;
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
      if (_isPlatformLibrary(element.library)) {
        metadataCode = 'const []';
      } else {
        var resolvedLibrary =
            await element.session.getResolvedLibraryByElement(element.library);
        var declaration = resolvedLibrary.getElementDeclaration(element);
        // The declaration may be null because the element is synthetic, and
        // then it has no metadata.
        FormalParameter node = declaration?.node;
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
    if (_isPlatformLibrary(parameterElement.library)) return '';
    var resolvedLibrary = await parameterElement.session
        .getResolvedLibraryByElement(parameterElement.library);
    var declaration = resolvedLibrary.getElementDeclaration(parameterElement);
    // The declaration can be null because the declaration is synthetic, e.g.,
    // the parameter of an induced setter; they have no default value.
    if (declaration == null) return '';
    FormalParameter parameterNode = declaration.node;
    if (parameterNode is DefaultFormalParameter &&
        parameterNode.defaultValue != null) {
      return await _extractConstantCode(parameterNode.defaultValue,
          importCollector, _generatedLibraryId, _resolver);
    } else if (parameterElement is DefaultFieldFormalParameterElementImpl) {
      Expression defaultValue = parameterElement.constantInitializer;
      if (defaultValue != null) {
        return await _extractConstantCode(
            defaultValue, importCollector, _generatedLibraryId, _resolver);
      }
    }
    return '';
  }
}

DartType _typeForReflectable(ClassElement classElement) {
  // TODO(eernst): This getter is used to inspect subclass relationships,
  // so there is no need to handle type parameters/arguments. So we might
  // be able to improve performance by working on classes as such.
  var typeArguments = List<DartType>.filled(classElement.typeParameters.length,
      classElement.library.typeProvider.dynamicType);
  return classElement.instantiate(
      typeArguments: typeArguments, nullabilitySuffix: NullabilitySuffix.star);
}

/// Auxiliary class used by `classes`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SubtypesFixedPoint extends FixedPoint<ClassElement> {
  final Map<ClassElement, Set<ClassElement>> subtypes;

  _SubtypesFixedPoint(this.subtypes);

  /// Returns all the immediate subtypes of the given [classMirror].
  @override
  Future<Iterable<ClassElement>> successors(
      final ClassElement classElement) async {
    Iterable<ClassElement> classElements = subtypes[classElement];
    return classElements ?? <ClassElement>[];
  }
}

/// Auxiliary class used by `classes`. Its `expand` method expands
/// its argument to a fixed point, based on the `successors` method.
class _SuperclassFixedPoint extends FixedPoint<ClassElement> {
  final Map<ClassElement, bool> upwardsClosureBounds;
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
  Future<Iterable<ClassElement>> successors(ClassElement element) async {
    // A mixin application is handled by its regular subclasses.
    if (element is MixinApplication) return [];
    // If upper bounds not satisfied then there are no successors.
    if (!_includedByUpwardsClosure(element)) return [];

    InterfaceType workingSuperType = element.supertype;
    if (workingSuperType == null) {
      return []; // "Superclass of [Object]", ignore.
    }
    ClassElement workingSuperclass = workingSuperType.element;

    List<ClassElement> result = [];

    if (_includedByUpwardsClosure(workingSuperclass)) {
      result.add(workingSuperclass);
    }

    // Create the chain of mixin applications between [classElement] and the
    // next non-mixin-application class that it extends. If [mixinsRequested]
    // then for each mixin application add the class [mixinClass] which was
    // applied as a mixin (it is then considered as yet another superclass).
    // Note that we iterate from the most general to more special mixins,
    // that is, for `class C extends B with M1, M2..` we visit `M1` before
    // `M2`, which makes the right `superclass` available at each step. We
    // must provide the immediate subclass of each [MixinApplication] when
    // is a regular class (not a mixin application), otherwise [null], which
    // is done with [subClass].
    ClassElement superclass = workingSuperclass;
    for (InterfaceType mixin in element.mixins) {
      ClassElement mixinClass = mixin.element;
      if (mixinsRequested) result.add(mixinClass);
      ClassElement subClass = mixin == element.mixins.last ? element : null;
      String name = subClass == null
          ? null
          : (element.isMixinApplication ? element.name : null);
      ClassElement mixinApplication = MixinApplication(
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

  bool _includedByUpwardsClosure(ClassElement classElement) {
    bool helper(ClassElement classElement, bool direct) {
      bool isSuperclassOfClassElement(ClassElement bound) {
        if (classElement == bound) {
          // If `!direct` then the desired subclass relation exists.
          // If `direct` then the original `classElement` is equal to
          // `bound`, so we must return false if `excludeUpperBound`.
          return !direct || !upwardsClosureBounds[bound];
        }
        if (classElement.supertype == null) return false;
        return helper(classElement.supertype.element, false);
      }

      return upwardsClosureBounds.keys.any(isSuperclassOfClassElement);
    }

    return upwardsClosureBounds.isEmpty || helper(classElement, true);
  }
}

/// Auxiliary function used by `classes`. Its `expand` method
/// expands its argument to a fixed point, based on the `successors` method.
Set<ClassElement> _mixinApplicationsOfClasses(Set<ClassElement> classes) {
  var mixinApplications = <ClassElement>{};
  for (ClassElement classElement in classes) {
    // Mixin-applications are handled when they are created.
    if (classElement is MixinApplication) continue;
    InterfaceType supertype = classElement.supertype;
    if (supertype == null) continue; // "Superclass of [Object]", ignore.
    ClassElement superclass = supertype.element;
    // Note that we iterate from the most general mixin to more specific ones,
    // that is, with `class C extends B with M1, M2..` we visit `M1` before
    // `M2`; this ensures that the right `superclass` is available for each
    // new [MixinApplication] created.  We must provide the immediate subclass
    // of each [MixinApplication] when it is a regular class (not a mixin
    // application), otherwise [null], which is done with [subClass].
    classElement.mixins.forEach((InterfaceType mixin) {
      ClassElement mixinClass = mixin.element;
      ClassElement subClass =
          mixin == classElement.mixins.last ? classElement : null;
      String name = subClass == null
          ? null
          : (classElement.isMixinApplication ? classElement.name : null);
      ClassElement mixinApplication = MixinApplication(
          name, superclass, mixinClass, classElement.library, subClass);
      mixinApplications.add(mixinApplication);
      superclass = mixinApplication;
    });
  }
  return mixinApplications;
}

/// Auxiliary type used by [_AnnotationClassFixedPoint].
typedef ElementToDomain = _ClassDomain Function(ClassElement);

/// Auxiliary class used by `classes`. Its `expand` method
/// expands its argument to a fixed point, based on the `successors` method.
/// It uses [resolver] in a check for "importability" of some private core
/// classes (that we must avoid attempting to use because they are unavailable
/// to user programs). [generatedLibraryId] must refer to the asset where the
/// generated code will be stored; it is used in the same check.
class _AnnotationClassFixedPoint extends FixedPoint<ClassElement> {
  final Resolver resolver;
  final AssetId generatedLibraryId;
  final ElementToDomain elementToDomain;

  _AnnotationClassFixedPoint(
      this.resolver, this.generatedLibraryId, this.elementToDomain);

  /// Returns the classes that occur as return types of covered methods or in
  /// type annotations of covered variables and parameters of covered methods,
  @override
  Future<Iterable<ClassElement>> successors(ClassElement classElement) async {
    if (!await _isImportable(classElement, generatedLibraryId, resolver)) {
      return [];
    }
    _ClassDomain classDomain = elementToDomain(classElement);

    // Mixin-applications do not add further methods and fields.
    if (classDomain._classElement is MixinApplication) return [];

    List<ClassElement> result = [];

    // Traverse type annotations to find successors. Note that we cannot
    // abstract the many redundant elements below, because `yield` cannot
    // occur in a local function.
    for (FieldElement fieldElement in classDomain._declaredFields) {
      Element fieldType = fieldElement.type.element;
      if (fieldType is ClassElement) result.add(fieldType);
    }
    for (ParameterElement parameterElement in classDomain._declaredParameters) {
      Element parameterType = parameterElement.type.element;
      if (parameterType is ClassElement) result.add(parameterType);
    }
    for (ParameterElement parameterElement in classDomain._instanceParameters) {
      Element parameterType = parameterElement.type.element;
      if (parameterType is ClassElement) result.add(parameterType);
    }
    for (ExecutableElement executableElement in classDomain._declaredMethods) {
      Element returnType = executableElement.returnType.element;
      if (returnType is ClassElement) result.add(returnType);
    }
    for (ExecutableElement executableElement in classDomain._instanceMembers) {
      Element returnType = executableElement.returnType.element;
      if (returnType is ClassElement) result.add(returnType);
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
    closure = '(dynamic instance) => instance.${getterName}';
  } else if (getterName == '[]=') {
    closure = '(dynamic instance) => (x, v) => instance[x] = v';
  } else if (getterName == '[]') {
    closure = '(dynamic instance) => (x) => instance[x]';
  } else if (getterName == 'unary-') {
    closure = '(dynamic instance) => () => -instance';
  } else if (getterName == '~') {
    closure = '(dynamic instance) => () => ~instance';
  } else {
    closure = '(dynamic instance) => (x) => instance ${getterName} x';
  }
  return "r'${getterName}': $closure";
}

// Auxiliary function used by `_generateCode`.
String _settingClosure(String setterName) {
  assert(setterName.substring(setterName.length - 1) == '=');
  String name = setterName.substring(0, setterName.length - 1);
  return "r'$setterName': (dynamic instance, value) => instance.$name = value";
}

// Auxiliary function used by `_generateCode`.
Future<String> _staticGettingClosure(_ImportCollector importCollector,
    ClassElement classElement, String getterName) async {
  String className = classElement.name;
  String prefix = importCollector._getPrefix(classElement.library);
  // Operators cannot be static.
  if (_isPrivateName(getterName)) {
    await _severe('Cannot access private name $getterName', classElement);
  }
  if (_isPrivateName(className)) {
    await _severe('Cannot access private name $className', classElement);
  }
  return "r'${getterName}': () => $prefix$className.$getterName";
}

// Auxiliary function used by `_generateCode`.
Future<String> _staticSettingClosure(_ImportCollector importCollector,
    ClassElement classElement, String setterName) async {
  assert(setterName.substring(setterName.length - 1) == '=');
  // The [setterName] includes the '=', remove it.
  String name = setterName.substring(0, setterName.length - 1);
  String className = classElement.name;
  String prefix = importCollector._getPrefix(classElement.library);
  if (_isPrivateName(setterName)) {
    await _severe('Cannot access private name $setterName', classElement);
  }
  if (_isPrivateName(className)) {
    await _severe('Cannot access private name $className', classElement);
  }
  return "r'$setterName': (value) => $prefix$className.$name = value";
}

// Auxiliary function used by `_generateCode`.
Future<String> _topLevelGettingClosure(_ImportCollector importCollector,
    LibraryElement library, String getterName) async {
  String prefix = importCollector._getPrefix(library);
  // Operators cannot be top-level.
  if (_isPrivateName(getterName)) {
    await _severe('Cannot access private name $getterName', library);
  }
  return "r'${getterName}': () => $prefix$getterName";
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
  return "r'$setterName': (value) => $prefix$name = value";
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
  /// [_classElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations sync* {
    yield* _declaredFunctions;
    yield* _accessors;
  }

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
  final ClassElement _classElement;

  /// Fields declared by [_classElement] and included for reflection support,
  /// according to the reflector described by the [_reflectorDomain];
  /// obtained by filtering `_classElement.fields`.
  final Iterable<FieldElement> _declaredFields;

  /// Methods which are declared by [_classElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `_classElement.methods`.
  final Iterable<MethodElement> _declaredMethods;

  /// Formal parameters declared by one of the [_declaredMethods].
  final Iterable<ParameterElement> _declaredParameters;

  /// Getters and setters possessed by [_classElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `_classElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors,
  /// implicitly created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> _accessors;

  /// Constructors declared by [_classElement] and included for reflection
  /// support, according to the reflector described by [_reflectorDomain];
  /// obtained by filtering `_classElement.constructors`.
  final Iterable<ConstructorElement> _constructors;

  /// The reflector domain that holds [this] object as one of its
  /// class domains.
  final _ReflectorDomain _reflectorDomain;

  _ClassDomain(
      this._classElement,
      this._declaredFields,
      this._declaredMethods,
      this._declaredParameters,
      this._accessors,
      this._constructors,
      this._reflectorDomain);

  String get _simpleName {
    // TODO(eernst) clarify: Decide whether this should be simplified
    // by adding a method implementation to `MixinApplication`.
    if (_classElement.isMixinApplication) {
      // This is the case `class B = A with M;`.
      return _classElement.name;
    } else if (_classElement is MixinApplication) {
      // This is the case `class B extends A with M1, .. Mk {..}`
      // where `_classElement` denotes one of the mixin applications
      // that constitute the superclass chain between `B` and `A`, both
      // excluded.
      List<InterfaceType> mixins = _classElement.mixins;
      ClassElement superclass = _classElement.supertype?.element;
      String superclassName =
          superclass == null ? 'null' : _qualifiedName(superclass);
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
      return _classElement.name;
    }
  }

  /// Returns the declared methods, accessors and constructors in
  /// [_classElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations {
    // TODO(sigurdm) feature: Include type variables (if we keep them).
    return () sync* {
      yield* _declaredMethods;
      yield* _accessors;
      yield* _constructors;
    }();
  }

  /// Finds all instance members by going through the class hierarchy.
  Iterable<ExecutableElement> get _instanceMembers {
    Map<String, ExecutableElement> helper(ClassElement classElement) {
      if (_reflectorDomain._instanceMemberCache[classElement] != null) {
        return _reflectorDomain._instanceMemberCache[classElement];
      }
      Map<String, ExecutableElement> result = <String, ExecutableElement>{};

      void addIfCapable(String name, ExecutableElement member) {
        if (member.isPrivate) return;
        // If [member] is a synthetic accessor created from a field, search for
        // the metadata on the original field.
        List<ElementAnnotation> metadata =
            (member is PropertyAccessorElement && member.isSynthetic)
                ? member.variable.metadata
                : member.metadata;
        List<ElementAnnotation> getterMetadata;
        if (_reflectorDomain._capabilities._impliesCorrespondingSetters &&
            member is PropertyAccessorElement &&
            !member.isSynthetic &&
            member.isSetter) {
          PropertyAccessorElement correspondingGetter =
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

      if (classElement is MixinApplication) {
        helper(classElement.superclass).forEach(addIfCapable);
        helper(classElement.mixin).forEach(addIfCapable);
        return result;
      }
      ClassElement superclass = classElement.supertype?.element;
      if (superclass != null) helper(superclass).forEach(addIfCapable);
      classElement.mixins.forEach(addTypeIfCapable);
      classElement.methods.forEach(addIfCapableConcreteInstance);
      classElement.accessors.forEach(addIfCapableConcreteInstance);
      _reflectorDomain._instanceMemberCache[classElement] =
          Map.unmodifiable(result);
      return result;
    }

    return helper(_classElement).values;
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
    if (_classElement is MixinApplication) return result;

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
      List<ElementAnnotation> getterMetadata;
      if (_reflectorDomain._capabilities._impliesCorrespondingSetters &&
          accessor.isSetter &&
          !accessor.isSynthetic) {
        PropertyAccessorElement correspondingGetter =
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

    _classElement.methods.forEach(possiblyAddMethod);
    _classElement.accessors.forEach(possiblyAddAccessor);
    return result;
  }

  @override
  String toString() {
    return 'ClassDomain($_classElement)';
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
      Iterable<DartObject> metadata) {
    if (metadata == null) return false;
    bool result = false;
    DartType capabilityType = _typeForReflectable(capability.metadataType);
    for (var metadatum in metadata) {
      if (typeSystem.isSubtypeOf(metadatum.type, capabilityType)) {
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
      Iterable<DartObject> getterMetadata) {
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
      if ((capability is ec.InvokingCapability ||
              capability is ec.NewInstanceCapability) &&
          _supportsName(capability, constructorName)) {
        return true;
      }
      if ((capability is ec.InvokingMetaCapability ||
              capability is ec.NewInstanceMetaCapability) &&
          _supportsMeta(typeSystem, capability, metadata)) {
        return true;
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
      Iterable<ElementAnnotation> getterMetadata) {
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
      Iterable<DartObject> getterMetadata) {
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
      Iterable<DartObject> getterMetadata) {
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
      Iterable<ElementAnnotation> getterMetadata) {
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
      Iterable<ElementAnnotation> getterMetadata) {
    return _supportsStaticInvoke(
        typeSystem,
        _capabilities,
        methodName,
        _getEvaluatedMetadata(metadata),
        getterMetadata == null ? null : _getEvaluatedMetadata(getterMetadata));
  }

  bool get _supportsMetadata {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability is ec.MetadataCapability);
  }

  bool get _supportsUri {
    return _capabilities.any(
        (ec.ReflectCapability capability) => capability is ec.UriCapability);
  }

  /// Returns [true] iff these [Capabilities] specify reflection support
  /// where the set of classes must be downwards closed, i.e., extra classes
  /// must be added beyond the ones that are directly covered by the given
  /// metadata and global quantifiers, such that coverage on a class `C`
  /// implies coverage of every class `D` such that `D` is a subtype of `C`.
  bool get _impliesDownwardsClosure {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.subtypeQuantifyCapability);
  }

  /// Returns [true] iff these [Capabilities] specify reflection support where
  /// the set of included classes must be upwards closed, i.e., extra classes
  /// must be added beyond the ones that are directly included as reflectable
  /// because we must support operations like `superclass`.
  bool get _impliesUpwardsClosure {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability is ec.SuperclassQuantifyCapability);
  }

  /// Returns [true] iff these [Capabilities] specify that classes which have
  /// been used for mixin application for an included class must themselves
  /// be included (if you have `class B extends A with M ..` then the class `M`
  /// will be included if `_impliesMixins`).
  bool get _impliesMixins => _impliesTypeRelations;

  /// Returns [true] iff these [Capabilities] specify that classes which have
  /// been used for mixin application for an included class must themselves
  /// be included (if you have `class B extends A with M ..` then the class `M`
  /// will be included if `_impliesMixins`).
  bool get _impliesTypeRelations {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability is ec.TypeRelationsCapability);
  }

  /// Returns [true] iff these [Capabilities] specify that type annotations
  /// modeled by mirrors should also get support for their base level [Type]
  /// values, e.g., they should support `myVariableMirror.reflectedType`.
  /// The relevant kinds of mirrors are variable mirrors, parameter mirrors,
  /// and (for the return type) method mirrors.
  bool get _impliesReflectedType {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.reflectedTypeCapability);
  }

  /// Maps each upper bound specified for the upwards closure to whether the
  /// bound itself is excluded, as indicated by `excludeUpperBound` in the
  /// corresponding capability. Intended usage: the `keys` of this map
  /// provides a listing of the upper bounds, and the map itself may then
  /// be consulted for each key (`if (myClosureBounds[key]) ..`) in order to
  /// take `excludeUpperBound` into account.
  Future<Map<ClassElement, bool>> get _upwardsClosureBounds async {
    Map<ClassElement, bool> result = {};
    for (ec.ReflectCapability capability in _capabilities) {
      if (capability is ec.SuperclassQuantifyCapability) {
        Element element = capability.upperBound;
        if (element == null) continue; // Means [Object], trivially satisfied.
        if (element is ClassElement) {
          result[element] = capability.excludeUpperBound;
        } else {
          await _severe('Unexpected kind of upper bound specified '
              'for a `SuperclassQuantifyCapability`: $element.');
        }
      }
    }
    return result;
  }

  bool get _impliesDeclarations {
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability is ec.DeclarationsCapability;
    });
  }

  bool get _impliesMemberSymbols {
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability == ec.delegateCapability;
    });
  }

  bool get _impliesParameterListShapes {
    // If we have a capability for declarations then we also have it for
    // types, and in that case the strategy where we traverse the parameter
    // mirrors to gather the argument list shape (and cache it in the method
    // mirror) will work. It may be a bit slower, but we have a general
    // preference for space over time in this library: Reflection will never
    // be full speed.
    return !_impliesDeclarations;
  }

  bool get _impliesTypes {
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability is ec.TypeCapability;
    });
  }

  /// Returns true iff `_capabilities` contain any of the types of capability
  /// which are concerned with instance method invocation. The purpose of
  /// this predicate is to determine whether it is required to have class
  /// mirrors for instance invocation support. Note that it does not include
  /// `newInstance..` capabilities nor `staticInvoke..` capabilities, because
  /// they are simply absent if there are no class mirrors (so we cannot call
  /// them and then get a "cannot do this without a class mirror" error in the
  /// implementation).
  bool get _impliesInstanceInvoke {
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability is ec.InstanceInvokeCapability ||
          capability is ec.InstanceInvokeMetaCapability;
    });
  }

  bool get _impliesTypeAnnotations {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability is ec.TypeAnnotationQuantifyCapability);
  }

  bool get _impliesTypeAnnotationClosure {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability is ec.TypeAnnotationQuantifyCapability &&
        capability.transitive == true);
  }

  bool get _impliesCorrespondingSetters {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.correspondingSetterQuantifyCapability);
  }

  bool get _supportsLibraries {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability is ec.LibraryCapability);
  }
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
    String prefix = _mapping[library];
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
    String prefix = _mapping[library];
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
  Resolver _resolver;
  var _libraries = <LibraryElement>[];
  final _librariesByName = <String, LibraryElement>{};
  bool _formatted;
  List<WarningKind> _suppressedWarnings;

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
  bool _equalsClassReflectable(ClassElement type) {
    FieldElement idField = type.getField('thisClassId');
    if (idField == null || !idField.isStatic) return false;
    if (idField is VariableElement) {
      DartObject constantValue = idField.computeConstantValue();
      return constantValue?.toStringValue() == reflectable_class_constants.id;
    }
    // Not a const field, or failed the `id` test: cannot be the right class.
    return false;
  }

  /// Returns the ClassElement in the target program which corresponds to class
  /// [Reflectable].
  Future<ClassElement> _findReflectableClassElement(
      LibraryElement reflectableLibrary) async {
    for (CompilationUnitElement unit in reflectableLibrary.units) {
      for (ClassElement type in unit.types) {
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
      InterfaceType superclass = possibleSubtype.superclass;
      // Even if `superclass == null` (superclass of Object), the equality
      // test will produce the correct result.
      return type == superclass;
    } else {
      return false;
    }
  }

  /// Returns true iff [possibleSubtype] is a subclass of [type], including the
  /// reflexive and transitive cases.
  bool _isSubclassOf(ParameterizedType possibleSubtype, InterfaceType type) {
    if (possibleSubtype == type) return true;
    if (possibleSubtype is InterfaceType) {
      InterfaceType superclass = possibleSubtype.superclass;
      if (superclass == null) return false;
      return _isSubclassOf(superclass, type);
    } else {
      return false;
    }
  }

  /// Returns the metadata class in [elementAnnotation] if it is an
  /// instance of a direct subclass of [focusClass], otherwise returns
  /// `null`.  Uses [errorReporter] to report an error if it is a subclass
  /// of [focusClass] which is not a direct subclass of [focusClass],
  /// because such a class is not supported as a Reflector.
  Future<ClassElement> _getReflectableAnnotation(
      ElementAnnotation elementAnnotation, ClassElement focusClass) async {
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
            errors.METADATA_NOT_DIRECT_SUBCLASS, elementAnnotation.element);
        return false;
      }
      // A direct subclass of [classReflectable], all OK.
      return true;
    }

    Element element = elementAnnotation.element;
    if (element is ConstructorElement) {
      bool isOk = await checkInheritance(
          _typeForReflectable(element.enclosingElement),
          _typeForReflectable(focusClass));
      return isOk
          ? _typeForReflectable(element.enclosingElement).element
          : null;
    } else if (element is PropertyAccessorElement) {
      PropertyInducingElement variable = element.variable;
      if (variable is VariableElement) {
        DartObject constantValue = variable.computeConstantValue();
        // Handle errors during evaluation. In general `constantValue` is
        // null for (1) non-const variables, (2) variables without an
        // initializer, and (3) unresolved libraries; (3) should not occur
        // because of the approach we use to get the resolver; we will not
        // see (1) because we have checked the type of `variable`; and (2)
        // would mean that the value is actually null, which we will also
        // reject as irrelevant.
        if (constantValue == null) return null;
        bool isOk = await checkInheritance(
            constantValue.type, _typeForReflectable(focusClass));
        // When `isOK` is true, result.value.type.element is a ClassElement.
        return isOk ? constantValue.type.element : null;
      } else {
        await _fine('Ignoring unsupported metadata form ${element}', element);
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
  Future<void> _warn(WarningKind kind, String message, [Element target]) async {
    if (_warningEnabled(kind)) {
      if (target != null) {
        log.warning(await _formatDiagnosticMessage(message, target));
      } else {
        log.warning(message);
      }
    }
  }

  /// Finds all GlobalQuantifyCapability and GlobalQuantifyMetaCapability
  /// annotations on imports of [reflectableLibrary], and record the arguments
  /// of these annotations by modifying [globalPatterns] and [globalMetadata].
  Future<void> _findGlobalQuantifyAnnotations(
      Map<RegExp, List<ClassElement>> globalPatterns,
      Map<ClassElement, List<ClassElement>> globalMetadata) async {
    LibraryElement reflectableLibrary =
        _librariesByName['reflectable.reflectable'];
    LibraryElement capabilityLibrary =
        _librariesByName['reflectable.capability'];
    ClassElement reflectableClass = reflectableLibrary.getType('Reflectable');
    ClassElement typeClass = reflectableLibrary.typeProvider.typeType.element;

    ConstructorElement globalQuantifyCapabilityConstructor = capabilityLibrary
        .getType('GlobalQuantifyCapability')
        .getNamedConstructor('');
    ConstructorElement globalQuantifyMetaCapabilityConstructor =
        capabilityLibrary
            .getType('GlobalQuantifyMetaCapability')
            .getNamedConstructor('');

    for (LibraryElement library in _libraries) {
      for (ImportElement import in library.imports) {
        if (import.importedLibrary?.id != reflectableLibrary.id) continue;
        for (ElementAnnotation metadatum in import.metadata) {
          if (metadatum.element == globalQuantifyCapabilityConstructor) {
            DartObject value = _getEvaluatedMetadatum(metadatum);
            if (value != null) {
              String pattern =
                  value.getField('classNamePattern').toStringValue();
              if (pattern == null) {
                await _warn(WarningKind.badNamePattern,
                    'The classNamePattern must be a string', metadatum.element);
                continue;
              }
              ClassElement reflector =
                  value.getField('(super)').getField('reflector').type.element;
              if (reflector == null ||
                  reflector.supertype.element != reflectableClass) {
                String found =
                    reflector == null ? '' : ' Found ${reflector.name}';
                await _warn(
                    WarningKind.badSuperclass,
                    'The reflector must be a direct subclass of Reflectable.' +
                        found,
                    metadatum.element);
                continue;
              }
              globalPatterns
                  .putIfAbsent(RegExp(pattern), () => <ClassElement>[])
                  .add(reflector);
            }
          } else if (metadatum.element ==
              globalQuantifyMetaCapabilityConstructor) {
            DartObject constantValue = metadatum.computeConstantValue();
            if (constantValue != null) {
              Object metadataFieldValue =
                  constantValue.getField('metadataType').toTypeValue().element;
              if (metadataFieldValue == null ||
                  constantValue.getField('metadataType').type.element !=
                      typeClass) {
                await _warn(
                    WarningKind.badMetadata,
                    'The metadata must be a Type. '
                    'Found ${constantValue.getField('metadataType').type.element.name}',
                    metadatum.element);
                continue;
              }
              ClassElement reflector = constantValue
                  .getField('(super)')
                  .getField('reflector')
                  .type
                  .element;
              if (reflector == null ||
                  reflector.supertype.element != reflectableClass) {
                String found =
                    reflector == null ? '' : ' Found ${reflector.name}';
                await _warn(
                    WarningKind.badSuperclass,
                    'The reflector must be a direct subclass of Reflectable.' +
                        found,
                    metadatum.element);
                continue;
              }
              if (metadataFieldValue is ClassElement) {
                globalMetadata
                    .putIfAbsent(metadataFieldValue, () => <ClassElement>[])
                    .add(reflector);
              } else {
                // TODO(eernst): We don't support non-class `Type` values.
                // However, it might be (weirdly) useful to allow `dynamic` in
                // order to cover _everything_ that has an annotation at all,
                // and maybe other things like function types as metadata.
                var typeName =
                    constantValue.getField('metadataType').type.element.name;
                await _warn(
                    WarningKind.badMetadata,
                    'The metadata must be a class type. '
                    'Found $typeName',
                    metadatum.element);
                continue;
              }
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
  Future<bool> _isReflectorClass(ClassElement potentialReflectorClass,
      ClassElement reflectableClass) async {
    if (potentialReflectorClass == reflectableClass) return false;
    InterfaceType potentialReflectorType =
        _typeForReflectable(potentialReflectorClass);
    InterfaceType reflectableType = _typeForReflectable(reflectableClass);
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

    final resolvedLibrary = await constructor.session
        .getResolvedLibraryByElement(constructor.library);
    final declaration = resolvedLibrary.getElementDeclaration(constructor);
    if (declaration == null) return false;
    ConstructorDeclaration constructorDeclarationNode = declaration.node;
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

  /// Returns a [ReflectionWorld] instantiated with all the reflectors seen by
  /// [_resolver] and all classes annotated by them. The [reflectableLibrary]
  /// must be the element representing 'package:reflectable/reflectable.dart',
  /// the [entryPoint] must be the element representing the entry point under
  /// transformation, and [dataId] must represent the entry point as well,
  /// and it is used to decide whether it is possible to import other libraries
  /// from the entry point. If the transformation is guaranteed to have no
  /// effect the return value is [null].
  Future<ReflectionWorld> _computeWorld(LibraryElement reflectableLibrary,
      LibraryElement entryPoint, AssetId dataId) async {
    final ClassElement classReflectable =
        await _findReflectableClassElement(reflectableLibrary);
    final allReflectors = <ClassElement>{};

    // If class `Reflectable` is absent the transformation must be a no-op.
    if (classReflectable == null) {
      log.info('Ignoring entry point $entryPoint that does not '
          'include the class `Reflectable`.');
      return null;
    }

    // The world will be built from the library arguments plus these two.
    final domains = <ClassElement, _ReflectorDomain>{};
    final importCollector = _ImportCollector();

    // Maps each pattern to the list of reflectors associated with it via
    // a [GlobalQuantifyCapability].
    var globalPatterns = <RegExp, List<ClassElement>>{};

    // Maps each [Type] to the list of reflectors associated with it via
    // a [GlobalQuantifyMetaCapability].
    var globalMetadata = <ClassElement, List<ClassElement>>{};

    final LibraryElement capabilityLibrary =
        _librariesByName['reflectable.capability'];

    /// Gets the [ReflectorDomain] associated with [reflector], or creates
    /// it if none exists.
    Future<_ReflectorDomain> getReflectorDomain(ClassElement reflector) async {
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
        LibraryElement library, ClassElement reflector) async {
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
        ClassElement type, ClassElement reflector) async {
      if (!await _isImportable(type, dataId, _resolver)) {
        await _fine('Ignoring unrepresentable class ${type.name}', type);
      } else {
        _ReflectorDomain domain = await getReflectorDomain(reflector);
        if (!domain._classes.contains(type)) {
          if (type.isMixinApplication) {
            // Iterate over all mixins in most-general-first order (so with
            // `class C extends B with M1, M2..` we visit `M1` then `M2`.
            ClassElement superclass = type.supertype.element;
            for (InterfaceType mixin in type.mixins) {
              ClassElement mixinElement = mixin.element;
              ClassElement subClass = mixin == type.mixins.last ? type : null;
              String name = subClass == null
                  ? null
                  : (type.isMixinApplication ? type.name : null);
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
    Future<Iterable<ClassElement>> getReflectors(
        String qualifiedName, List<ElementAnnotation> metadata) async {
      List<ClassElement> result = <ClassElement>[];

      for (ElementAnnotationImpl metadatum in metadata) {
        DartObject value = _getEvaluatedMetadatum(metadatum);

        // Test if the type of this metadata is associated with any reflectors
        // via GlobalQuantifyMetaCapability.
        if (value != null) {
          List<ClassElement> reflectors = globalMetadata[value.type.element];
          if (reflectors != null) {
            for (ClassElement reflector in reflectors) {
              result.add(reflector);
            }
          }
        }

        // Test if the annotation is a reflector.
        ClassElement reflector =
            await _getReflectableAnnotation(metadatum, classReflectable);
        if (reflector != null) result.add(reflector);
      }

      // Add All reflectors associated with a
      // pattern, via GlobalQuantifyCapability, that matches the qualified
      // name of the class or library.
      globalPatterns.forEach((RegExp pattern, List<ClassElement> reflectors) {
        if (pattern.hasMatch(qualifiedName)) {
          for (ClassElement reflector in reflectors) {
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
      for (ClassElement reflector
          in await getReflectors(library.name, library.metadata)) {
        assert(await _isImportableLibrary(library, dataId, _resolver));
        await addLibrary(library, reflector);
      }

      for (CompilationUnitElement unit in library.units) {
        for (ClassElement type in unit.types) {
          for (ClassElement reflector
              in await getReflectors(_qualifiedName(type), type.metadata)) {
            await addClassDomain(type, reflector);
          }
          if (!allReflectors.contains(type) &&
              await _isReflectorClass(type, classReflectable)) {
            allReflectors.add(type);
          }
        }
        for (ClassElement type in unit.enums) {
          for (ClassElement reflector
              in await getReflectors(_qualifiedName(type), type.metadata)) {
            await addClassDomain(type, reflector);
          }
          // An enum is never a reflector class, hence no `_isReflectorClass`.
        }
        for (FunctionElement function in unit.functions) {
          for (ClassElement reflector in await getReflectors(
              _qualifiedFunctionName(function), function.metadata)) {
            // We just add the library here, the function itself will be
            // supported using `invoke` and `declarations` of that library
            // mirror.
            await addLibrary(library, reflector);
          }
        }
      }
    }

    var usedReflectors = <ClassElement>{};
    for (var domain in domains.values) {
      usedReflectors.add(domain._reflector);
    }
    for (ClassElement reflector in allReflectors.difference(usedReflectors)) {
      await _warn(WarningKind.unusedReflector,
          'This reflector does not match anything', reflector);
      // Ensure that there is an empty domain for `reflector` in `domains`.
      await getReflectorDomain(reflector);
    }

    // Create the world and tie the knot: A [ReflectionWorld] refers to all its
    // [_ReflectorDomain]s, and each of them refer back. Such a cycle cannot be
    // defined during construction, so `_world` is non-final and left unset by
    // the constructor, and we need to close the cycle here.
    ReflectionWorld world = ReflectionWorld(
        _resolver,
        _libraries,
        dataId,
        domains.values.toList(),
        reflectableLibrary,
        entryPoint,
        importCollector);
    domains.values.forEach((_ReflectorDomain domain) => domain._world = world);
    return world;
  }

  /// Returns the [ReflectCapability] denoted by the given initializer
  /// [expression] reporting diagnostic messages for [messageTarget].
  Future<ec.ReflectCapability> _capabilityOfExpression(
      LibraryElement capabilityLibrary,
      Expression expression,
      LibraryElement containingLibrary,
      Element messageTarget) async {
    EvaluationResult evaluated =
        _evaluateConstant(containingLibrary, expression);

    if (evaluated == null || !evaluated.isValid) {
      await _severe(
          'Invalid constant `$expression` in capability list.', messageTarget);
      // We do not terminate immediately at `_severe` so we need to
      // return something that will not generate too much noise for the
      // receiver.
      return ec.invokingCapability; // Error default.
    }

    DartObject constant = evaluated.value;

    if (constant == null) {
      // This could be because it is an argument to a `const` constructor,
      // but we do not support that.
      await _severe('Unsupported constant `$expression` in capability list.',
          messageTarget);
      return ec.invokingCapability; // Error default.
    }

    ParameterizedType dartType = constant.type;
    // We insist that the type must be a class, and we insist that it must
    // be in the given `capabilityLibrary` (because we could never know
    // how to interpret the meaning of a user-written capability class, so
    // users cannot write their own capability classes).
    if (dartType.element is! ClassElement) {
      await _severe(
          errors.applyTemplate(errors.SUPER_ARGUMENT_NON_CLASS,
              {'type': dartType.getDisplayString()}),
          dartType.element);
      return ec.invokingCapability; // Error default.
    }
    ClassElement classElement = dartType.element;
    if (classElement.library != capabilityLibrary) {
      await _severe(
          errors.applyTemplate(errors.SUPER_ARGUMENT_WRONG_LIBRARY,
              {'library': '$capabilityLibrary', 'element': '$classElement'}),
          classElement);
      return ec.invokingCapability; // Error default.
    }

    /// Extracts the namePattern String from an instance of a subclass of
    /// NamePatternCapability.
    Future<String> extractNamePattern(DartObject constant) async {
      if (constant.getField('(super)') == null ||
          constant.getField('(super)').getField('namePattern') == null ||
          constant
                  .getField('(super)')
                  .getField('namePattern')
                  .toStringValue() ==
              null) {
        await _warn(WarningKind.badNamePattern,
            'Could not extract namePattern from capability.', messageTarget);
        return '';
      }
      return constant
          .getField('(super)')
          .getField('namePattern')
          .toStringValue();
    }

    /// Extracts the metadata property from an instance of a subclass of
    /// MetadataCapability represented by [constant], reporting any diagnostic
    /// messages as referring to [messageTarget].
    Future<ClassElement> extractMetaData(DartObject constant) async {
      if (constant.getField('(super)') == null ||
          constant.getField('(super)').getField('metadataType') == null) {
        await _warn(WarningKind.badMetadata,
            'Could not extract metadata type from capability.', messageTarget);
        return null;
      }
      Object metadataFieldValue = constant
          .getField('(super)')
          .getField('metadataType')
          .toTypeValue()
          .element;
      if (metadataFieldValue is ClassElement) return metadataFieldValue;
      await _warn(
          WarningKind.badMetadata,
          'Metadata specification in capability must be a `Type`.',
          messageTarget);
      return null;
    }

    switch (classElement.name) {
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
        return ec.InstanceInvokeCapability(await extractNamePattern(constant));
      case 'InstanceInvokeMetaCapability':
        return ec.InstanceInvokeMetaCapability(await extractMetaData(constant));
      case 'StaticInvokeCapability':
        return ec.StaticInvokeCapability(await extractNamePattern(constant));
      case 'StaticInvokeMetaCapability':
        return ec.StaticInvokeMetaCapability(await extractMetaData(constant));
      case 'TopLevelInvokeCapability':
        return ec.TopLevelInvokeCapability(await extractNamePattern(constant));
      case 'TopLevelInvokeMetaCapability':
        return ec.TopLevelInvokeMetaCapability(await extractMetaData(constant));
      case 'NewInstanceCapability':
        return ec.NewInstanceCapability(await extractNamePattern(constant));
      case 'NewInstanceMetaCapability':
        return ec.NewInstanceMetaCapability(await extractMetaData(constant));
      case 'TypeCapability':
        return ec.TypeCapability();
      case 'InvokingCapability':
        return ec.InvokingCapability(await extractNamePattern(constant));
      case 'InvokingMetaCapability':
        return ec.InvokingMetaCapability(await extractMetaData(constant));
      case 'TypingCapability':
        return ec.TypingCapability();
      case '_DelegateCapability':
        return ec.delegateCapability;
      case '_SubtypeQuantifyCapability':
        return ec.subtypeQuantifyCapability;
      case 'SuperclassQuantifyCapability':
        return ec.SuperclassQuantifyCapability(
            constant.getField('upperBound').toTypeValue().element,
            excludeUpperBound:
                constant.getField('excludeUpperBound').toBoolValue());
      case 'TypeAnnotationQuantifyCapability':
        return ec.TypeAnnotationQuantifyCapability(
            transitive: constant.getField('transitive').toBoolValue());
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
        await _severe('Unexpected capability $classElement');
        return ec.invokingCapability; // Error default.
    }
  }

  /// Returns the list of Capabilities given as a superinitializer by the
  /// reflector.
  Future<_Capabilities> _capabilitiesOf(
      LibraryElement capabilityLibrary, ClassElement reflector) async {
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

    final resolvedLibrary = await constructorElement.session
        .getResolvedLibraryByElement(constructorElement.library);
    final declaration =
        resolvedLibrary.getElementDeclaration(constructorElement);
    ConstructorDeclaration constructorDeclarationNode = declaration.node;
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
    assert(initializers.length == 1);

    // Main case: the initializer is exactly one element. We must
    // handle two cases: `super(..)` and `super.fromList(<_>[..])`.
    SuperConstructorInvocation superInvocation = initializers[0];

    Future<ec.ReflectCapability> capabilityOfExpression(
        Expression expression) async {
      return await _capabilityOfExpression(
          capabilityLibrary, expression, reflector.library, constructorElement);
    }

    Future<ec.ReflectCapability> capabilityOfCollectionElement(
        CollectionElement collectionElement) async {
      if (collectionElement is Expression) {
        return await capabilityOfExpression(collectionElement);
      } else {
        await _severe('Not yet supported! '
            'Encountered a collection element which is not an expression: '
            '$collectionElement');
        return null;
      }
    }

    if (superInvocation.constructorName == null) {
      // Subcase: `super(..)` where 0..k arguments are accepted for some
      // k that we need not worry about here.
      List<ec.ReflectCapability> capabilities = [];
      for (var argument in superInvocation.argumentList.arguments) {
        capabilities.add(await capabilityOfCollectionElement(argument));
      }
      return _Capabilities(capabilities);
    }
    assert(superInvocation.constructorName.name == 'fromList');

    // Subcase: `super.fromList(const <..>[..])`.
    NodeList<Expression> arguments = superInvocation.argumentList.arguments;
    assert(arguments.length == 1);
    ListLiteral listLiteral = arguments[0];
    List<ec.ReflectCapability> capabilities = [];
    for (var collectionElement in listLiteral.elements) {
      capabilities.add(await capabilityOfCollectionElement(collectionElement));
    }
    return _Capabilities(capabilities);
  }

  /// Generates code for a new entry-point file that will initialize the
  /// reflection data according to [world], and invoke the main of
  /// [entrypointLibrary] located at [originalEntryPointFilename]. The code is
  /// generated to be located at [generatedLibraryId].
  Future<String> _generateNewEntryPoint(ReflectionWorld world,
      AssetId generatedLibraryId, String originalEntryPointFilename) async {
    // Notice it is important to generate the code before printing the
    // imports because generating the code can add further imports.
    String code = await world.generateCode();

    List<String> imports = <String>[];
    for (LibraryElement library in world.importCollector._libraries) {
      Uri uri = library == world.entryPointLibrary
          ? Uri.parse(originalEntryPointFilename)
          : await _getImportUri(library, generatedLibraryId);
      String prefix = world.importCollector._getPrefix(library);
      if (prefix.isNotEmpty) {
        imports
            .add("import '$uri' as ${prefix.substring(0, prefix.length - 1)};");
      }
    }
    imports.sort();

    String result = '''
// This file has been generated by the reflectable package.
// https://github.com/dart-lang/reflectable.

import 'dart:core';
${imports.join('\n')}

// ignore_for_file: prefer_adjacent_string_concatenation
// ignore_for_file: prefer_collection_literals
// ignore_for_file: unnecessary_const
// ignore_for_file: implementation_imports

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
      if (library.name != null) _librariesByName[library.name] = library;
    }
    LibraryElement reflectableLibrary =
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

      ReflectionWorld world =
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
int _classDescriptor(ClassElement element) {
  int result = constants.clazz;
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isAbstract) result |= constants.abstractAttribute;
  if (element.isEnum) result |= constants.enumAttribute;
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
  if (element.type.isDynamic) {
    result |= constants.dynamicAttribute;
  }
  Element elementType = element.type.element;
  if (elementType is ClassElement) {
    result |= constants.classTypeAttribute;
  }
  result |= constants.topLevelAttribute;
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
  if (element.type.isDynamic) {
    result |= constants.dynamicAttribute;
  }
  Element elementType = element.type.element;
  if (elementType is ClassElement) {
    result |= constants.classTypeAttribute;
    if (elementType.typeParameters.isNotEmpty) {
      result |= constants.genericTypeAttribute;
    }
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
  if (element.isOptional) {
    result |= constants.optionalAttribute;
  }
  if (element.isNamed) {
    result |= constants.namedAttribute;
  }
  if (element.type.isDynamic) {
    result |= constants.dynamicAttribute;
  }
  Element elementType = element.type.element;
  if (elementType is ClassElement) {
    result |= constants.classTypeAttribute;
    if (elementType.typeParameters.isNotEmpty) {
      result |= constants.genericTypeAttribute;
    }
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// method/constructor/getter/setter.
int _declarationDescriptor(ExecutableElement element) {
  int result;

  void handleReturnType(ExecutableElement element) {
    if (element.returnType.isDynamic) {
      result |= constants.dynamicReturnTypeAttribute;
    }
    if (element.returnType.isVoid) {
      result |= constants.voidReturnTypeAttribute;
    }
    Element elementReturnType = element.returnType.element;
    if (elementReturnType is ClassElement) {
      result |= constants.classReturnTypeAttribute;
      if (elementReturnType.typeParameters.isNotEmpty) {
        result |= constants.genericReturnTypeAttribute;
      }
    }
  }

  if (element is PropertyAccessorElement) {
    result = element.isGetter ? constants.getter : constants.setter;
    handleReturnType(element);
  } else if (element is ConstructorElement) {
    if (element.isFactory) {
      result = constants.factoryConstructor;
    } else {
      result = constants.generativeConstructor;
    }
    if (element.isConst) result |= constants.constAttribute;
    if (element.redirectedConstructor != null) {
      result |= constants.redirectingConstructorAttribute;
    }
  } else if (element is MethodElement) {
    result = constants.method;
    handleReturnType(element);
  } else {
    assert(element is FunctionElement);
    result = constants.function;
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
  if (element.enclosingElement is! ClassElement) {
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
    '<${typeName}>[${parts.join(', ')}]';

String _formatAsConstList(String typeName, Iterable parts) =>
    'const <${typeName}>[${parts.join(', ')}]';

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
  String typeAnnotationHelper(TypeAnnotation typeName) {
    LibraryElement library = typeName.type.element.library;
    String prefix = importCollector._getPrefix(library);
    return '$prefix$typeName';
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
      if (expression.typeArguments == null ||
          expression.typeArguments.arguments.isEmpty) {
        return 'const ${_formatAsDynamicList(elements)}';
      } else {
        assert(expression.typeArguments.arguments.length == 1);
        String typeArgument =
            typeAnnotationHelper(expression.typeArguments.arguments[0]);
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
        if (expression.typeArguments == null ||
            expression.typeArguments.arguments.isEmpty) {
          return 'const ${_formatAsMap(elements)}';
        } else {
          assert(expression.typeArguments.arguments.length == 2);
          String keyType =
              typeAnnotationHelper(expression.typeArguments.arguments[0]);
          String valueType =
              typeAnnotationHelper(expression.typeArguments.arguments[1]);
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
        if (expression.typeArguments == null ||
            expression.typeArguments.arguments.isEmpty) {
          return 'const ${_formatAsDynamicSet(elements)}';
        } else {
          assert(expression.typeArguments.arguments.length == 1);
          String typeArgument =
              typeAnnotationHelper(expression.typeArguments.arguments[0]);
          return 'const <$typeArgument>${_formatAsDynamicSet(elements)}';
        }
      } else {
        unreachableError('SetOrMapLiteral is neither a set nor a map');
        return '';
      }
    } else if (expression is InstanceCreationExpression) {
      String constructor = expression.constructorName.toSource();
      if (_isPrivateName(constructor)) {
        await _severe('Cannot access private name $constructor, '
            'needed for expression $expression');
        return '';
      }
      LibraryElement libraryOfConstructor = expression.staticElement.library;
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
        Element staticElement = expression.staticElement;
        if (staticElement is PropertyAccessorElement) {
          VariableElement variable = staticElement.variable;
          var resolvedLibrary = await variable.session
              .getResolvedLibraryByElement(variable.library);
          var declaration = resolvedLibrary.getElementDeclaration(variable);
          if (declaration == null || declaration.node == null) {
            await _severe('Cannot handle private identifier $expression');
            return '';
          }
          VariableDeclaration variableDeclaration = declaration.node;
          return await helper(variableDeclaration.initializer);
        } else {
          await _severe('Cannot handle private identifier $expression');
          return '';
        }
      } else {
        Element element = expression.staticElement;
        if (element == null) {
          // TODO(eernst): This can occur; but how could `expression` be
          // unresolved? Issue 173.
          await _fine('Encountered unresolved identifier $expression'
              ' in constant; using null');
          return 'null';
        } else if (element.library == null) {
          return '${element.name}';
        } else if (await _isImportableLibrary(
            element.library, generatedLibraryId, resolver)) {
          importCollector._addLibrary(element.library);
          String prefix = importCollector._getPrefix(element.library);
          Element enclosingElement = element.enclosingElement;
          if (enclosingElement is ClassElement) {
            prefix += '${enclosingElement.name}.';
          }
          if (_isPrivateName(element.name)) {
            await _severe('Cannot access private name ${element.name}, '
                'needed for expression $expression');
          }
          return '$prefix${element.name}';
        } else {
          await _severe('Cannot access library ${element.library}, '
              'needed for expression $expression');
          return '';
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
      String target = await helper(expression.target);
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
  'html',
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
CompilationUnit _definingCompilationUnit(
    ResolvedLibraryResult resolvedLibrary) {
  var definingUnit = resolvedLibrary.element.definingCompilationUnit;
  for (var unit in resolvedLibrary.units) {
    if (unit.unit.declaredElement == definingUnit) {
      return unit.unit;
    }
  }
  return null;
}

// Helper for _extractMetadataCode.
NodeList<Annotation> _getLibraryMetadata(
    ResolvedLibraryResult resolvedLibrary) {
  var unit = _definingCompilationUnit(resolvedLibrary);
  if (unit != null) {
    var directive = unit.directives[0];
    if (directive is LibraryDirective) {
      return directive.metadata;
    }
  }
  return null;
}

// Helper for _extractMetadataCode.
NodeList<Annotation> _getOtherMetadata(
    ResolvedLibraryResult resolvedLibrary, Element element) {
  var declaration = resolvedLibrary.getElementDeclaration(element);
  // `declaration` can be null if element is synthetic.
  AstNode node = declaration?.node;
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
    node = node.parent.parent;
  }

  // We can obtain the `metadata` via two methods in unrelated classes.
  if (node is AnnotatedNode) {
    // One source is an annotated node, which includes most declarations
    // and directives.
    return node.metadata;
  } else {
    // Insist that the only other source is a formal parameter.
    FormalParameter formalParameter = node;
    return formalParameter.metadata;
  }
}

/// Returns a String with the code used to build the metadata of [element].
///
/// Also adds any neccessary imports to [importCollector].
Future<String> _extractMetadataCode(Element element, Resolver resolver,
    _ImportCollector importCollector, AssetId dataId) async {
  if (element.metadata == null) return 'const []';

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

  NodeList<Annotation> metadata;
  var resolvedLibrary =
      await element.session.getResolvedLibraryByElement(element.library);
  if (element is LibraryElement) {
    metadata = _getLibraryMetadata(resolvedLibrary);
  } else {
    metadata = _getOtherMetadata(resolvedLibrary, element);
  }
  if (metadata == null || metadata.isEmpty) return 'const []';

  List<String> metadataParts = <String>[];
  for (Annotation annotationNode in metadata) {
    // TODO(sigurdm) diagnostic: Emit a warning/error if the element is not
    // in the global public scope of the library.
    if (annotationNode.element == null) {
      // Some internal constants (mainly in dart:html) cannot be resolved by
      // the analyzer. Ignore them.
      // TODO(sigurdm) clarify: Investigate this, and see if these constants can
      // somehow be included.
      await _fine('Ignoring unresolved metadata $annotationNode', element);
      continue;
    }

    if (!await _isImportable(annotationNode.element, dataId, resolver)) {
      // Private constants, and constants made of classes in internal libraries
      // cannot be represented.
      // Skip them.
      // TODO(sigurdm) clarify: Investigate this, and see if these constants can
      // somehow be included.
      await _fine('Ignoring unrepresentable metadata $annotationNode', element);
      continue;
    }
    LibraryElement annotationLibrary = annotationNode.element.library;
    importCollector._addLibrary(annotationLibrary);
    String prefix = importCollector._getPrefix(annotationLibrary);
    if (annotationNode.arguments != null) {
      // A const constructor.
      String name =
          await _extractNameWithoutPrefix(annotationNode.name, element);
      List<String> argumentList = [];
      for (Expression argument in annotationNode.arguments.arguments) {
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
    Iterable<ElementAnnotation> getterMetadata);

/// Returns the declared fields in the given [classElement], filtered such
/// that the returned ones are the ones that are supported by [capabilities].
Iterable<FieldElement> _extractDeclaredFields(
    Resolver resolver, ClassElement classElement, _Capabilities capabilities) {
  return classElement.fields.where((FieldElement field) {
    if (field.isPrivate) return false;
    CapabilityChecker capabilityChecker = field.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    return !field.isSynthetic &&
        capabilityChecker(
            classElement.library.typeSystem, field.name, field.metadata, null);
  });
}

/// Returns the declared methods in the given [classElement], filtered such
/// that the returned ones are the ones that are supported by [capabilities].
Iterable<MethodElement> _extractDeclaredMethods(
    Resolver resolver, ClassElement classElement, _Capabilities capabilities) {
  return classElement.methods.where((MethodElement method) {
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
      List<ElementAnnotation> metadata, getterMetadata;
      if (accessor.isSynthetic) {
        metadata = accessor.variable.metadata;
        getterMetadata = metadata;
      } else {
        metadata = accessor.metadata;
        if (capabilities._impliesCorrespondingSetters &&
            accessor.isSetter &&
            !accessor.isSynthetic) {
          PropertyAccessorElement correspondingGetter =
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
/// of the given [classElement], including both the declared ones
/// and the implicitly generated ones corresponding to fields. This
/// is the set of accessors that corresponds to the behavioral interface
/// of the corresponding instances, as opposed to the source code oriented
/// interface, e.g., `declarations`. But the latter can be computed from
/// here, by filtering out the accessors whose `isSynthetic` is true
/// and adding the fields.
Iterable<PropertyAccessorElement> _extractAccessors(
    Resolver resolver, ClassElement classElement, _Capabilities capabilities) {
  return classElement.accessors.where((PropertyAccessorElement accessor) {
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
    List<ElementAnnotation> getterMetadata;
    if (capabilities._impliesCorrespondingSetters &&
        accessor.isSetter &&
        !accessor.isSynthetic) {
      PropertyAccessorElement correspondingGetter =
          accessor.correspondingGetter;
      getterMetadata = correspondingGetter?.metadata;
    }
    return capabilityChecker(
        accessor.library.typeSystem, accessor.name, metadata, getterMetadata);
  });
}

/// Returns the declared constructors from [classElement], filtered such that
/// the returned ones are the ones that are supported by [capabilities].
Iterable<ConstructorElement> _extractDeclaredConstructors(
    Resolver resolver,
    LibraryElement libraryElement,
    ClassElement classElement,
    _Capabilities capabilities) {
  return classElement.constructors.where((ConstructorElement constructor) {
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
      _extractLibraryAccessors(domain._resolver, library, domain._capabilities);
  Iterable<ParameterElement> declaredParametersOfLibrary =
      _extractDeclaredFunctionParameters(
          domain._resolver, declaredFunctionsOfLibrary, accessorsOfLibrary);
  return _LibraryDomain(
      library,
      declaredVariablesOfLibrary,
      declaredFunctionsOfLibrary,
      declaredParametersOfLibrary,
      accessorsOfLibrary,
      domain);
}

_ClassDomain _createClassDomain(ClassElement type, _ReflectorDomain domain) {
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
      element.library, generatedLibraryId, resolver);
}

/// Answers true iff [library] can be imported into [generatedLibraryId].
Future<bool> _isImportableLibrary(LibraryElement library,
    AssetId generatedLibraryId, Resolver resolver) async {
  Uri importUri = await _getImportUri(library, generatedLibraryId);
  return importUri.scheme != 'dart' || sdkLibraryNames.contains(importUri.path);
}

/// Gets a URI which would be appropriate for importing the file represented by
/// [assetId]. This function returns null if we cannot determine a uri for
/// [assetId]. Note that [assetId] may represent a non-importable file such as
/// a part.
Future<String> _assetIdToUri(
    AssetId assetId, AssetId from, Element messageTarget) async {
  if (!assetId.path.startsWith('lib/')) {
    // Cannot do absolute imports of non lib-based assets.
    if (assetId.package != from.package) {
      await _severe(await _formatDiagnosticMessage(
          'Attempt to generate non-lib import from different package',
          messageTarget));
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

Future<Uri> _getImportUri(LibraryElement lib, AssetId from) async {
  var source = lib.source;
  var uri = source.uri;
  if (uri.scheme == 'asset') {
    // This can occur if the library is not accessed via a package uri
    // but instead is given as a path (outside a package, e.g., in `example`
    // of the current package.
    // For instance `asset:reflectable/example/example_lib.dart`.
    String package = uri.pathSegments[0];
    String path = uri.path.substring(package.length + 1);
    return Uri(path: await _assetIdToUri(AssetId(package, path), from, lib));
  }
  if (source is FileSource || source is InSummarySource) {
    return uri;
  }
  // Should not encounter any other source types.
  await _severe('Unable to resolve URI for ${source.runtimeType}');
  return Uri.parse(
      'package:${from?.package ?? "unknown"}/${from?.path ?? "unknown"}');
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
  final String declaredName;
  final ClassElement superclass;
  final ClassElement mixin;
  final ClassElement subclass;

  @override
  final LibraryElement library;

  MixinApplication(this.declaredName, this.superclass, this.mixin, this.library,
      this.subclass);

  @override
  String get name {
    if (declaredName != null) return declaredName;
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

  // The `InterfaceTypeImpl` may well call methods on this `MixinApplication`
  // whose body is unimplemented, but it still provides a slightly better
  // service than leaving this method unimplemented. We are then allowed to
  // take one more step, which may be enough.
  @override
  InterfaceType get type => InterfaceTypeImpl(
      element: this,
      typeArguments: [],
      nullabilitySuffix: NullabilitySuffix.star);

  @override
  InterfaceType instantiate({
    List<DartType> typeArguments,
    NullabilitySuffix nullabilitySuffix,
  }) =>
      InterfaceTypeImpl(
          element: this,
          typeArguments: typeArguments,
          nullabilitySuffix: nullabilitySuffix);

  @override
  InterfaceType get supertype {
    if (superclass is MixinApplication) return superclass.supertype;
    ClassElement superClass = superclass;
    return superClass == null ? null : _typeForReflectable(superClass);
  }

  @override
  List<InterfaceType> get mixins {
    List<InterfaceType> result = <InterfaceType>[];
    if (superclass != null && superclass is MixinApplication) {
      result.addAll(superclass.mixins);
    }
    result.add(_typeForReflectable(mixin));
    return result;
  }

  @override
  Source get librarySource => library.source;

  @override
  AnalysisSession get session => mixin.session;

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
  bool get isAbstract => !isMixinApplication || mixin.isAbstract;

  // This seems to be the defined behaviour according to dart:mirrors.
  @override
  bool get isPrivate => false;

  @override
  bool get isEnum => false;

  @override
  List<TypeParameterElement> get typeParameters => <TypeParameterElement>[];

  @override
  ElementKind get kind => ElementKind.CLASS;

  @override
  ElementLocation get location => null;

  @override
  bool operator ==(Object object) {
    return object is MixinApplication &&
        superclass == object.superclass &&
        mixin == object.mixin &&
        library == object.library &&
        subclass == object.subclass;
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

String _qualifiedName(Element element) {
  return element == null ? 'null' : '${element.library.name}.${element.name}';
}

String _qualifiedFunctionName(FunctionElement functionElement) {
  return functionElement == null
      ? 'null'
      : '${functionElement.library.name}.${functionElement.name}';
}

String _qualifiedTypeParameterName(TypeParameterElement typeParameterElement) {
  if (typeParameterElement == null) return 'null';
  return '${_qualifiedName(typeParameterElement.enclosingElement)}.'
      '${typeParameterElement.name}';
}

bool _isPrivateName(String name) {
  return name.startsWith('_') || name.contains('._');
}

EvaluationResult _evaluateConstant(
    LibraryElement library, Expression expression) {
  return ConstantEvaluator(library.source, library.typeProvider)
      .evaluate(expression);
}

/// Returns the result of evaluating [elementAnnotation].
DartObject _getEvaluatedMetadatum(ElementAnnotation elementAnnotation) =>
    elementAnnotation.computeConstantValue();

/// Returns the result of evaluating [metadata].
///
/// Returns the result of evaluating each of the element annotations
/// in [metadata] using [_getEvaluatedMetadatum].
Iterable<DartObject> _getEvaluatedMetadata(
    Iterable<ElementAnnotation> metadata) {
  return metadata.map(
      (ElementAnnotation annotation) => _getEvaluatedMetadatum(annotation));
}

/// Determine whether the given library is a platform library.
///
/// TODO(eernst): This function is only needed until a solution is found to the
/// problem that platform libraries are considered invalid when obtained from
/// `getResolvedLibraryByElement`, such that subsequent use will throw.
/// Issue 173.
bool _isPlatformLibrary(LibraryElement libraryElement) =>
    libraryElement.source.uri.scheme == 'dart';

/// Adds a severe error to the log, using the source code location of `target`
/// to identify the relevant location where the error occurs.
Future<void> _severe(String message, [Element target]) async {
  if (target != null) {
    log.severe(await _formatDiagnosticMessage(message, target));
  } else {
    log.severe(message);
  }
}

/// Adds a 'fine' message to the log, using the source code location of `target`
/// to identify the relevant location where the issue occurs.
Future<void> _fine(String message, [Element target]) async {
  if (target != null) {
    log.fine(await _formatDiagnosticMessage(message, target));
  } else {
    log.fine(message);
  }
}

/// Returns a string containing the given [message] and identifying the
/// associated source code location as the location of the given [target].
Future<String> _formatDiagnosticMessage(String message, Element target) async {
  Source source = target?.source;
  if (source == null) return message;
  String locationString = '';
  int nameOffset = target?.nameOffset;
  // TODO(eernst): 'dart:*' is not considered valid. To survive, we return
  // a message with no location info when `element` is from 'dart:*'. Issue 173.
  if (nameOffset != null && !_isPlatformLibrary(target.library)) {
    final resolvedLibrary =
        await target.session.getResolvedLibraryByElement(target.library);
    final targetDeclaration = resolvedLibrary.getElementDeclaration(target);
    final unit = targetDeclaration.resolvedUnit.unit;
    final location = unit.lineInfo?.getLocation(nameOffset);
    if (location != null) {
      locationString = '${location.lineNumber}:${location.columnNumber}';
    }
  }
  return '${source.fullName}:$locationString: $message';
}

// Emits a warning-level log message which will be preserved by `pub run`
// (as opposed to stdout and stderr which are swallowed). If given, [target]
// is used to indicate a source code location.
// ignore:unused_element
Future<void> _emitMessage(String message, [Element target]) async {
  var formattedMessage = target != null
      ? await _formatDiagnosticMessage(message, target)
      : message;
  log.warning(formattedMessage);
}
