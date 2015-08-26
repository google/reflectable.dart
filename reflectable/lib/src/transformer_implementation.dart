// (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.transformer_implementation;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:path/path.dart' as path;
import 'element_capability.dart' as ec;
import 'encoding_constants.dart' as constants;
import "reflectable_class_constants.dart" as reflectable_class_constants;
import 'transformer_errors.dart' as errors;

class ReflectionWorld {
  final List<_ReflectorDomain> reflectors = new List<_ReflectorDomain>();
  final LibraryElement reflectableLibrary;
  final _ImportCollector importCollector = new _ImportCollector();

  ReflectionWorld(this.reflectableLibrary);

  Iterable<_ReflectorDomain> reflectorsOfLibrary(LibraryElement library) {
    return reflectors.where((_ReflectorDomain domain) {
      return domain._reflector.library == library;
    });
  }

  Iterable<_ClassDomain> annotatedClassesOfLibrary(LibraryElement library) {
    return reflectors
        .expand((_ReflectorDomain domain) => domain._annotatedClasses)
        .where((_ClassDomain classDomain) {
      return classDomain._classElement.library == library;
    });
  }

  String generateCode(
      Resolver resolver, TransformLogger logger, AssetId dataId) {
    return _formatAsMap(reflectors.map((_ReflectorDomain reflector) {
      return "${reflector._constConstructionCode(importCollector)}: "
          "${reflector._generateCode(resolver, importCollector, logger, dataId)}";
    }));
  }
}

/// Similar to a `Set<T>` but also keeps track of the index of the first
/// insertion of each item.
class Enumerator<T> {
  final Map<T, int> _map = new Map<T, int>();
  int _count = 0;

  bool _contains(T t) => _map.containsKey(t);

  get length => _count;

  /// Tries to insert [t]. If it was already there return false, else insert it
  /// and return true.
  bool add(T t) {
    if (_contains(t)) return false;
    _map[t] = _count;
    ++_count;
    return true;
  }

  /// Returns the index of a given item.
  int indexOf(T t) {
    return _map[t];
  }

  /// Returns all the items in the order they were inserted.
  Iterable<T> get items {
    return _map.keys;
  }
}

/// Information about the program parts that can be reflected by a given
/// Reflector.
class _ReflectorDomain {
  final ClassElement _reflector;

  Iterable<_ClassDomain> get _annotatedClasses => _classMap.values;

  Set<LibraryElement> _libraries = new Set<LibraryElement>();

  final Map<ClassElement, _ClassDomain> _classMap =
      new Map<ClassElement, _ClassDomain>();

  final _Capabilities _capabilities;

  _ReflectorDomain(this._reflector, this._capabilities) {}

  // TODO(eernst) future: Perhaps reconsider what the best strategy
  // for caching is.
  Map<ClassElement, Map<String, ExecutableElement>> _instanceMemberCache =
      new Map<ClassElement, Map<String, ExecutableElement>>();

  Map<ClassElement, Map<String, ExecutableElement>> _staticMemberCache =
      new Map<ClassElement, Map<String, ExecutableElement>>();

  /// Returns a string that evaluates to a closure invoking [constructor] with
  /// the given arguments.
  /// [importCollector] is used to record all the imports needed to make the
  /// constant.
  /// This is to provide something that can be called with [Function.apply].
  ///
  /// For example for a constructor Foo(x, {y: 3}):
  /// returns "(x, {y: 3}) => new prefix1.Foo(x, y)", and records an import of
  /// the library of `Foo` associated with prefix1 in [importCollector].
  String _constructorCode(
      ConstructorElement constructor, _ImportCollector importCollector) {
    FunctionType type = constructor.type;

    int requiredPositionalCount = type.normalParameterTypes.length;
    int optionalPositionalCount = type.optionalParameterTypes.length;

    List<String> parameterNames = type.parameters
        .map((ParameterElement parameter) => parameter.name)
        .toList();

    List<String> NamedParameterNames = type.namedParameterTypes.keys.toList();

    String positionals = new Iterable.generate(
        requiredPositionalCount, (int i) => parameterNames[i]).join(", ");

    String optionalsWithDefaults =
        new Iterable.generate(optionalPositionalCount, (int i) {
      String defaultValueCode =
          constructor.parameters[requiredPositionalCount + i].defaultValueCode;
      String defaultValueString =
          defaultValueCode == null ? "" : " = $defaultValueCode";
      return "${parameterNames[i + requiredPositionalCount]}"
          "$defaultValueString";
    }).join(", ");

    String namedWithDefaults =
        new Iterable.generate(NamedParameterNames.length, (int i) {
      // TODO(#8) future: Recreate default values.
      // TODO(#8) implement: Until that is done, recognize
      // unhandled cases, and emit error/warning.
      String defaultValueCode =
          constructor.parameters[requiredPositionalCount + i].defaultValueCode;
      String defaultValueString =
          defaultValueCode == null ? "" : ": $defaultValueCode";
      return "${NamedParameterNames[i]}$defaultValueString";
    }).join(", ");

    String optionalArguments = new Iterable.generate(optionalPositionalCount,
        (int i) => parameterNames[i + requiredPositionalCount]).join(", ");
    String namedArguments =
        NamedParameterNames.map((String name) => "$name: $name").join(", ");

    List<String> parameterParts = new List<String>();
    List<String> argumentParts = new List<String>();

    if (requiredPositionalCount != 0) {
      parameterParts.add(positionals);
      argumentParts.add(positionals);
    }
    if (optionalPositionalCount != 0) {
      parameterParts.add("[$optionalsWithDefaults]");
      argumentParts.add(optionalArguments);
    }
    if (NamedParameterNames.isNotEmpty) {
      parameterParts.add("{${namedWithDefaults}}");
      argumentParts.add(namedArguments);
    }

    String prefix = importCollector._getPrefix(constructor.library);
    return ('(${parameterParts.join(', ')}) => '
        'new $prefix.${_nameOfDeclaration(constructor)}'
        '(${argumentParts.join(", ")})');
  }

  /// The code of the const-construction of this reflector.
  String _constConstructionCode(_ImportCollector importCollector) {
    String prefix = importCollector._getPrefix(_reflector.library);
    return "const $prefix.${_reflector.name}()";
  }

  String _generateCode(Resolver resolver, _ImportCollector importCollector,
      TransformLogger logger, AssetId dataId) {
    Enumerator<ClassElement> classes = new Enumerator<ClassElement>();
    Enumerator<ExecutableElement> members = new Enumerator<ExecutableElement>();
    Enumerator<FieldElement> fields = new Enumerator<FieldElement>();
    Enumerator<ParameterElement> parameters =
        new Enumerator<ParameterElement>();
    Enumerator<LibraryElement> libraries = new Enumerator<LibraryElement>();

    Set<String> instanceGetterNames = new Set<String>();
    Set<String> instanceSetterNames = new Set<String>();

    // Fill in [libraries], [classes], [members], [fields], [parameters],
    // [instanceGetterNames], and [instanceSetterNames].
    for (LibraryElement library in _libraries) {
      libraries.add(library);
    }

    for (_ClassDomain classDomain in _annotatedClasses) {
      // Gather all annotated classes.
      classes.add(classDomain._classElement);

      // Gather the behavioral interface into [members]. Note that
      // this includes implicitly generated getters and setters, but
      // omits fields. Also note that this does not match the
      // semantics of the `declarations` method in a [ClassMirror].
      classDomain._declarations.forEach(members.add);

      // Add the behavioral interface from this class (redundantly) and
      // all superclasses (which matters) to [members], such that it
      // contains both the behavioral parts for the target class and its
      // superclasses, and the program structure oriented parts for the
      // target class (omitting those from its superclasses).
      classDomain._instanceMembers.forEach(members.add);

      // Add all the formal parameters (as a single, global set) which
      // are declared by any of the methods in `classDomain._declarations`.
      classDomain._declaredParameters.forEach(parameters.add);

      // Gather the fields declared in the target class (not inherited
      // ones) in [fields], i.e., the elements missing from [members]
      // at this point, in order to support `declarations` in a
      // [ClassMirror].
      classDomain._declaredFields.forEach(fields.add);

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

    String gettingClosure(String getterName) {
      String closure;
      if (getterName.startsWith(new RegExp(r"[A-Za-z$_]"))) {
        // Starts with letter, not an operator.
        closure = "(dynamic instance) => instance.${getterName}";
      } else if (getterName == "[]=") {
        closure = "(dynamic instance) => (x, v) => instance[x] = v";
      } else if (getterName == "[]") {
        closure = "(dynamic instance) => (x) => instance[x]";
      } else {
        closure = "(dynamic instance) => (x) => instance ${getterName} x";
      }
      return 'r"${getterName}": $closure';
    }

    String _topLevelGettingClosure(LibraryElement library, String getterName) {
      String prefix = importCollector._getPrefix(library);
      // Operators cannot be top-level.
      return 'r"${getterName}": () => $prefix.$getterName';
    }

    String _topLevelSettingClosure(LibraryElement library, String setterName) {
      assert(setterName.substring(setterName.length - 1) == "=");
      // The [setterName] includes the "=", remove it.
      String name = setterName.substring(0, setterName.length - 1);
      String prefix = importCollector._getPrefix(library);
      return 'r"$setterName": (value) => $prefix.$name = value';
    }

    String staticGettingClosure(ClassElement classElement, String getterName) {
      String className = classElement.name;
      String prefix = importCollector._getPrefix(classElement.library);
      // Operators cannot be static.
      return 'r"${getterName}": () => $prefix.$className.$getterName';
    }

    String settingClosure(String setterName) {
      assert(setterName.substring(setterName.length - 1) == "=");
      // The [setterName] includes the "=", remove it.
      String name = setterName.substring(0, setterName.length - 1);

      return 'r"$setterName": (dynamic instance, value) => '
          'instance.$name = value';
    }

    String _staticSettingClosure(ClassElement classElement, String setterName) {
      assert(setterName.substring(setterName.length - 1) == "=");
      // The [setterName] includes the "=", remove it.
      String name = setterName.substring(0, setterName.length - 1);
      String className = classElement.name;
      String prefix = importCollector._getPrefix(classElement.library);
      return 'r"$setterName": (value) => $prefix.$className.$name = value';
    }

    // Compute `includedClasses`, i.e., the set of classes which are
    // annotated, or the upwards-closed completion of that set.
    Set<_ClassDomain> includedClasses = new Set<_ClassDomain>();
    includedClasses.addAll(_annotatedClasses);
    if (_capabilities._impliesParameterTypes) {
      parameters.items.forEach((ParameterElement parameterElement) {
        Element parameterType = parameterElement.type.element;
        if (parameterType is ClassElement) {
          includedClasses.add(_createClassDomain(parameterType, this));
          classes.add(parameterType);
        }
      });
    }
    if (_capabilities._impliesFieldTypes) {
      fields.items.forEach((FieldElement fieldElement) {
        Element fieldType = fieldElement.type.element;
        if (fieldType is ClassElement) {
          includedClasses.add(_createClassDomain(fieldType, this));
          classes.add(fieldType);
        }
      });
    }
    if (_capabilities._impliesUpwardsClosure) {
      Set<_ClassDomain> workingSetOfClasses = includedClasses;
      while (true) {
        // Invariant for `workingSetOfClasses`: Every class from
        // `includedClasses` for which it is possible that its superclass
        // is not yet in `includedClasses` must be a member of
        // `workingSetOfClasses`.
        Set<_ClassDomain> additionalClasses = new Set<_ClassDomain>();
        workingSetOfClasses.forEach((_ClassDomain workingClass) {
          InterfaceType workingSuperType = workingClass._classElement.supertype;
          if (workingSuperType != null) {
            ClassElement workingSuperClass = workingSuperType.element;
            bool isNew = !includedClasses.any((_ClassDomain classDomain) {
              return classDomain._classElement == workingSuperClass;
            });
            if (isNew) {
              additionalClasses
                  .add(_createClassDomain(workingSuperClass, this));
            }
          }
        });
        if (additionalClasses.isEmpty) break;
        includedClasses.addAll(additionalClasses);
        additionalClasses.forEach((_ClassDomain classDomain) {
          classes.add(classDomain._classElement);
        });
        workingSetOfClasses = additionalClasses;
      }
    }

    // Generate the class mirrors.
    int classIndex = 0;
    String classMirrorsCode =
        _formatAsList(includedClasses.map((_ClassDomain classDomain) {
      // Fields go first in [memberMirrors], so they will get the
      // same index as in [fields].
      Iterable<int> fieldsIndices =
          classDomain._declaredFields.map((FieldElement element) {
        return fields.indexOf(element);
      });

      // All the elements in the behavioral interface go after the
      // fields in [memberMirrors], so they must get an offset of
      // `fields.length` on the index.
      Iterable<int> methodsIndices = classDomain._declarations
          .where(_executableIsntImplicitGetterOrSetter)
          .map((ExecutableElement element) {
        // TODO(eernst) implement: The "magic" default constructor in `Object`
        // (the one that ultimately allocates the memory for _every_ new object)
        // has no index, which creates the need to catch a `null` here.
        // Search for "magic" to find other occurrences of the same issue.
        // For now, we provide the index [constants.NO_CAPABILITY_INDEX]
        // for this declaration, because it is not yet supported.
        // Need to find the correct solution, though!
        int index = members.indexOf(element);
        return index == null
            ? constants.NO_CAPABILITY_INDEX
            : index + fields.length;
      });

      String declarationsCode = "<int>[${constants.NO_CAPABILITY_INDEX}]";
      if (_capabilities._impliesDeclarations) {
        List<int> declarationsIndices = <int>[]
          ..addAll(fieldsIndices)
          ..addAll(methodsIndices);
        declarationsCode = _formatAsList(declarationsIndices);
      }

      // All instance members belong to the behavioral interface, so they
      // also get an offset of `fields.length`.
      String instanceMembersCode = _formatAsList(
          classDomain._instanceMembers.map((ExecutableElement element) {
        // TODO(eernst) implement: The "magic" default constructor has
        // index: NO_CAPABILITY_INDEX; adjust this when support for it has been
        // implemented.
        int index = members.indexOf(element);
        return index == null
            ? constants.NO_CAPABILITY_INDEX
            : index + fields.length;
      }));

      // All static members belong to the behavioral interface, so they
      // also get an offset of `fields.length`.
      String staticMembersCode = _formatAsList(
          classDomain._staticMembers.map((ExecutableElement element) {
        int index = members.indexOf(element);
        return index == null ? -1 : index + fields.length;
      }));

      InterfaceType superType = classDomain._classElement.supertype;
      ClassElement superclass = superType == null ? null : superType.element;
      String superclassIndex;
      if (superclass == null) {
        superclassIndex = null;
      } else {
        int index = classes.indexOf(superclass);
        if (index == null) {
          index = constants.NO_CAPABILITY_INDEX;
        }
        superclassIndex = "$index";
      }

      String constructorsCode;

      if (classDomain._classElement.isAbstract) {
        constructorsCode = '{}';
      } else {
        constructorsCode = _formatAsMap(
            classDomain._constructors.map((ConstructorElement constructor) {
          String code = _constructorCode(constructor, importCollector);
          return 'r"${constructor.name}": $code';
        }));
      }

      String classMetadataCode;
      if (_capabilities._supportsMetadata) {
        classMetadataCode = _extractMetadataCode(classDomain._classElement,
            resolver, importCollector, logger, dataId);
      } else {
        classMetadataCode = "null";
      }

      String staticGettersCode = _formatAsMap([
        classDomain._declaredMethods
            .where((ExecutableElement element) => element.isStatic),
        classDomain._declaredAndImplicitAccessors.where(
            (PropertyAccessorElement element) =>
                element.isStatic && element.isGetter)
      ].expand((x) => x).map((ExecutableElement element) =>
          staticGettingClosure(classDomain._classElement, element.name)));
      String staticSettersCode = _formatAsMap(classDomain
          ._declaredAndImplicitAccessors
          .where((PropertyAccessorElement element) =>
              element.isStatic && element.isSetter)
          .map((PropertyAccessorElement element) =>
              _staticSettingClosure(classDomain._classElement, element.name)));

      int ownerIndex = _capabilities.supportsLibraries
          ? libraries.indexOf(classDomain._classElement.library)
          : constants.NO_CAPABILITY_INDEX;

      String result = 'new r.ClassMirrorImpl(r"${classDomain._simpleName}", '
          'r"${classDomain._qualifiedName}", $classIndex, '
          '${_constConstructionCode(importCollector)}, '
          '$declarationsCode, $instanceMembersCode, $staticMembersCode, '
          '$superclassIndex, $staticGettersCode, $staticSettersCode, '
          '$constructorsCode, $ownerIndex, $classMetadataCode)';
      classIndex++;
      return result;
    }));

    String gettersCode = _formatAsMap(instanceGetterNames.map(gettingClosure));
    String settersCode = _formatAsMap(instanceSetterNames.map(settingClosure));

    Iterable<String> methodsList =
        members.items.map((ExecutableElement element) {
      if (element is PropertyAccessorElement && element.isSynthetic) {
        // There is no type propagation, so we declare an `accessorElement`.
        PropertyAccessorElement accessorElement = element;
        int variableMirrorIndex = fields.indexOf(accessorElement.variable);
        // The `indexOf` is non-null: `accessorElement` came from `members`.
        int selfIndex = members.indexOf(accessorElement) + fields.length;
        if (accessorElement.isGetter) {
          return 'new r.ImplicitGetterMirrorImpl('
              '${_constConstructionCode(importCollector)}, '
              '$variableMirrorIndex, $selfIndex)';
        } else {
          assert(accessorElement.isSetter);
          return 'new r.ImplicitSetterMirrorImpl('
              '${_constConstructionCode(importCollector)}, '
              '$variableMirrorIndex, $selfIndex)';
        }
      } else {
        int descriptor = _declarationDescriptor(element);
        int returnTypeIndex = classes._contains(element.returnType.element)
            ? classes.indexOf(element.returnType.element)
            : -1;
        int ownerIndex = classes.indexOf(element.enclosingElement);
        String parameterIndicesCode = _formatAsList(
            element.parameters.map((ParameterElement parameterElement) {
          return parameters.indexOf(parameterElement);
        }));
        String metadataCode = _capabilities._supportsMetadata
            ? _extractMetadataCode(
                element, resolver, importCollector, logger, dataId)
            : null;
        return 'new r.MethodMirrorImpl(r"${element.name}", $descriptor, '
            '$ownerIndex, $returnTypeIndex, $parameterIndicesCode, '
            '${_constConstructionCode(importCollector)}, $metadataCode)';
      }
    });

    Iterable<String> fieldsList = fields.items.map((FieldElement element) {
      int descriptor = _fieldDescriptor(element);
      int ownerIndex = classes.indexOf(element.enclosingElement);
      int classMirrorIndex = classes._contains(element.type.element)
          ? classes.indexOf(element.type.element)
          : constants.NO_CAPABILITY_INDEX;
      String metadataCode;
      if (_capabilities._supportsMetadata) {
        metadataCode = _extractMetadataCode(
            element, resolver, importCollector, logger, dataId);
      } else {
        metadataCode = null;
      }
      return 'new r.VariableMirrorImpl(r"${element.name}", $descriptor, '
          '$ownerIndex, ${_constConstructionCode(importCollector)}, '
          '$classMirrorIndex, $metadataCode)';
    });

    List<String> membersList = <String>[]
      ..addAll(fieldsList)
      ..addAll(methodsList);
    String membersCode = _formatAsList(membersList);

    String typesCode =
        _formatAsList(classes.items.map((ClassElement classElement) {
      String prefix = importCollector._getPrefix(classElement.library);
      return "$prefix.${classElement.name}";
    }));

    String librariesCode;
    if (!_capabilities.supportsLibraries) {
      librariesCode = "null";
    } else {
      librariesCode =
          _formatAsList(libraries.items.map((LibraryElement library) {
        String gettersCode = _formatAsMap(
            gettersOfLibrary(library).map((PropertyAccessorElement getter) {
          return _topLevelGettingClosure(library, getter.name);
        }));
        String settersCode = _formatAsMap(
            settersOfLibrary(library).map((PropertyAccessorElement setter) {
          return _topLevelSettingClosure(library, setter.name);
        }));

        // TODO(sigurdm) clarify: Find out how to get good uri's in a
        // transformer.
        // TODO(sigurdm) implement: Check for `uriCapability`.
        String uriCode = "null";

        String metadataCode;
        if (_capabilities._supportsMetadata) {
          metadataCode = _extractMetadataCode(
              library, resolver, importCollector, logger, dataId);
        } else {
          metadataCode = "null";
        }

        return 'new r.LibraryMirrorImpl(r"${library.name}", $uriCode, '
            '$gettersCode, $settersCode, $metadataCode)';
      }));
    }

    Iterable<String> parametersList =
        parameters.items.map((ParameterElement element) {
      int descriptor = _parameterDescriptor(element);
      int ownerIndex = members.indexOf(element.enclosingElement);
      int classMirrorIndex = classes._contains(element.type.element)
          ? classes.indexOf(element.type.element)
          : constants.NO_CAPABILITY_INDEX;
      String metadataCode;
      metadataCode = _capabilities._supportsMetadata ? "<Object>[]" : "null";
      // TODO(eernst) implement: Detect and, if possible, handle the case
      // where it is incorrect to move element.defaultValueCode out of its
      // original scope. If we cannot solve the problem we should issue
      // a warning (it's worse than `new UndefinedClass()`, because it
      // might "work" with a different semantics at runtime, rather than just
      // failing if ever executed).
      return 'new r.ParameterMirrorImpl(r"${element.name}", $descriptor, '
          '$ownerIndex, ${_constConstructionCode(importCollector)}, '
          '$classMirrorIndex, $metadataCode, ${element.defaultValueCode})';
    });
    String parameterMirrorsCode = _formatAsList(parametersList);

    return "new r.ReflectorData($classMirrorsCode, $membersCode, "
        "$parameterMirrorsCode, $typesCode, $gettersCode, $settersCode, "
        "$librariesCode)";
  }

  Iterable<PropertyAccessorElement> gettersOfLibrary(LibraryElement library) {
    return library.units.map((CompilationUnitElement part) {
      Iterable<Element> getters = <Iterable<Element>>[
        part.accessors
            .where((PropertyAccessorElement accessor) => accessor.isGetter),
        part.functions,
        part.topLevelVariables
      ].expand((Iterable<Element> elements) => elements);
      return getters.where((Element getter) =>
          _capabilities.supportsTopLevelInvoke(getter.name, getter.metadata));
    }).expand((Iterable<Element> x) => x);
  }

  Iterable<PropertyAccessorElement> settersOfLibrary(LibraryElement library) {
    return library.units.map((CompilationUnitElement part) {
      Iterable setters = <Iterable<Element>>[
        part.accessors
            .where((PropertyAccessorElement accessor) => accessor.isSetter),
        part.topLevelVariables
            .where((TopLevelVariableElement variable) => !variable.isFinal)
      ].expand((Iterable<Element> elements) => elements);
      return setters.where((Element setter) =>
          _capabilities.supportsTopLevelInvoke(setter.name, setter.metadata));
    }).expand((Iterable<Element> x) => x);
  }
}

/// Information about reflectability for a given class.
class _ClassDomain {
  /// Element describing the target class.
  final ClassElement _classElement;

  /// Fields declared by [classElement] and included for reflection support,
  /// according to the reflector described by the [reflectorDomain];
  /// obtained by filtering `classElement.fields`.
  final Iterable<FieldElement> _declaredFields;

  /// Methods which are declared by [classElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `classElement.methods`.
  final Iterable<MethodElement> _declaredMethods;

  /// Formal parameters declared by one of the [_declaredMethods].
  final Iterable<ParameterElement> _declaredParameters;

  /// Getters and setters possessed by [classElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `classElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors,
  /// implicitly created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> _declaredAndImplicitAccessors;

  /// Constructors declared by [classElement] and included for reflection
  /// support, according to the reflector described by [reflectorDomain];
  /// obtained by filtering `classElement.constructors`.
  final Iterable<ConstructorElement> _constructors;

  /// The reflector domain that holds [this] object as one of its
  /// class domains.
  final _ReflectorDomain _reflectorDomain;

  _ClassDomain(
      this._classElement,
      this._declaredFields,
      this._declaredMethods,
      this._declaredParameters,
      this._declaredAndImplicitAccessors,
      this._constructors,
      this._reflectorDomain);

  String get _simpleName => _classElement.name;
  String get _qualifiedName {
    return "${_classElement.library.name}.${_classElement.name}";
  }

  /// Returns the declared methods, accessors and constructors in
  /// [_classElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get _declarations {
    // TODO(sigurdm) feature: Include type variables (if we keep them).
    return [_declaredMethods, _declaredAndImplicitAccessors, _constructors]
        .expand((x) => x);
  }

  /// Finds all instance members by going through the class hierarchy.
  Iterable<ExecutableElement> get _instanceMembers {
    Map<String, ExecutableElement> helper(ClassElement classElement) {
      if (_reflectorDomain._instanceMemberCache[classElement] != null) {
        return _reflectorDomain._instanceMemberCache[classElement];
      }
      Map<String, ExecutableElement> result =
          new Map<String, ExecutableElement>();

      void addIfCapable(ExecutableElement member) {
        if (member.isPrivate) return;
        // If [member] is a synthetic accessor created from a field, search for
        // the metadata on the original field.
        List<ElementAnnotation> metadata = (member is PropertyAccessorElement &&
            member.isSynthetic) ? member.variable.metadata : member.metadata;
        if (_reflectorDomain._capabilities
            .supportsInstanceInvoke(member.name, metadata)) {
          result[member.name] = member;
        }
      }

      if (classElement.supertype != null) {
        helper(classElement.supertype.element)
            .forEach((String name, ExecutableElement member) {
          addIfCapable(member);
        });
      }
      for (InterfaceType mixin in classElement.mixins) {
        helper(mixin.element).forEach((String name, ExecutableElement member) {
          addIfCapable(member);
        });
      }
      for (MethodElement member in classElement.methods) {
        if (member.isAbstract || member.isStatic) continue;
        addIfCapable(member);
      }
      for (PropertyAccessorElement member in classElement.accessors) {
        if (member.isAbstract || member.isStatic) continue;
        addIfCapable(member);
      }
      return result;
    }

    return helper(_classElement).values;
  }

  /// Finds all static members.
  Iterable<ExecutableElement> get _staticMembers {
    Map<String, ExecutableElement> helper(ClassElement classElement) {
      if (_reflectorDomain._staticMemberCache[classElement] != null) {
        return _reflectorDomain._staticMemberCache[classElement];
      }
      Map<String, ExecutableElement> result =
          new Map<String, ExecutableElement>();

      void addIfCapable(ExecutableElement member) {
        if (member.isPrivate) return;
        // If [member] is a synthetic accessor created from a field, search for
        // the metadata on the original field.
        List<ElementAnnotation> metadata = (member is PropertyAccessorElement &&
            member.isSynthetic) ? member.variable.metadata : member.metadata;
        if (_reflectorDomain._capabilities
            .supportsInstanceInvoke(member.name, metadata)) {
          result[member.name] = member;
        }
      }

      for (MethodElement member in classElement.methods) {
        if (member.isAbstract || !member.isStatic) continue;
        addIfCapable(member);
      }
      for (PropertyAccessorElement member in classElement.accessors) {
        if (member.isAbstract || !member.isStatic) continue;
        addIfCapable(member);
      }
      return result;
    }

    return helper(_classElement).values;
  }

  String toString() {
    return "ClassDomain($_classElement)";
  }

  bool operator ==(Object other) {
    if (other is _ClassDomain) {
      return _classElement == other._classElement &&
          _reflectorDomain == other._reflectorDomain;
    } else {
      return false;
    }
  }

  int get hashCode => _classElement.hashCode ^ _reflectorDomain.hashCode;
}

/// A wrapper around a list of Capabilities.
/// Supports queries about the methods supported by the set of capabilities.
class _Capabilities {
  List<ec.ReflectCapability> _capabilities;
  _Capabilities(this._capabilities);

  bool _supportsName(ec.NamePatternCapability capability, String methodName) {
    RegExp regexp = new RegExp(capability.namePattern);
    return regexp.hasMatch(methodName);
  }

  bool _supportsMeta(ec.MetadataQuantifiedCapability capability,
      Iterable<DartObject> metadata) {
    if (metadata == null) return false;
    return metadata
        .map((DartObject o) => o.type.element)
        .contains(capability.metadataType);
  }

  bool _supportsInstanceInvoke(List<ec.ReflectCapability> capabilities,
      String methodName, Iterable<DartObjectImpl> metadata) {
    bool supportsTarget(ec.ReflecteeQuantifyCapability capability) {
      // TODO(eernst) implement: correct this; will need something
      // like this, which will cover the case where we have applied
      // the trivial subtype:
      return _supportsInstanceInvoke(
          capability.capabilities, methodName, metadata);
    }

    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.InstanceInvokeCapability &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if (capability is ec.InstanceInvokeMetaCapability &&
          _supportsMeta(capability, metadata)) {
        return true;
      }
      // Handle reflectee based capabilities.
      if ((capability is ec.AdmitSubtypeCapability ||
              capability is ec.SubtypeQuantifyCapability) &&
          supportsTarget(capability)) {
        return true;
      }
      // Handle globally quantified capabilities.
      // TODO(eernst) feature: We probably need to refactor a lot of stuff
      // to get this right, so the first approach will simply be to
      // discover the relevant capabilities, and indicate that they
      // are not yet supported.
      if (capability is ec.GlobalQuantifyCapability ||
          capability is ec.GlobalQuantifyMetaCapability) {
        throw new UnimplementedError("Global quantification not yet supported");
      }
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsNewInstance(Iterable<ec.ReflectCapability> capabilities,
      String constructorName, Iterable<DartObjectImpl> metadata) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if ((capability is ec.InvokingCapability ||
              capability is ec.NewInstanceCapability) &&
          _supportsName(capability, constructorName)) {
        return true;
      }
      if ((capability is ec.InvokingMetaCapability ||
              capability is ec.NewInstanceMetaCapability) &&
          _supportsMeta(capability, metadata)) {
        return true;
      }
      // Handle reflectee based capabilities.
      // TODO(eernst) feature: Support reflectee based capabilities.
    }

    // All options exhausted, give up.
    return false;
  }

  Iterable<DartObjectImpl> _getEvaluatedMetadata(
      List<ElementAnnotation> metadata) {
    return metadata.map((ElementAnnotationImpl elementAnnotation) {
      EvaluationResultImpl evaluation = elementAnnotation.evaluationResult;
      assert(evaluation != null);
      return evaluation.value;
    });
  }

  // TODO(sigurdm) future: Find a way to cache these. Perhaps take an
  // element instead of name+metadata.
  bool supportsInstanceInvoke(
      String methodName, List<ElementAnnotation> metadata) {
    var v = _supportsInstanceInvoke(
        _capabilities, methodName, _getEvaluatedMetadata(metadata));
    return v;
  }

  bool supportsNewInstance(
      String constructorName, List<ElementAnnotation> metadata) {
    var result = _supportsNewInstance(
        _capabilities, constructorName, _getEvaluatedMetadata(metadata));
    return result;
  }

  bool _supportsTopLevelInvoke(List<ec.ReflectCapability> capabilities,
      String methodName, Iterable<DartObject> metadata) {
    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if ((capability is ec.TopLevelInvokeCapability) &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if ((capability is ec.TopLevelInvokeMetaCapability) &&
          _supportsMeta(capability, metadata)) {
        return true;
      }

      // Handle globally quantified capabilities.
      // TODO(eernst) feature: We probably need to refactor a lot of stuff
      // to get this right, so the first approach will simply be to
      // discover the relevant capabilities, and indicate that they
      // are not yet supported.
      if (capability is ec.GlobalQuantifyCapability ||
          capability is ec.GlobalQuantifyMetaCapability) {
        throw new UnimplementedError("Global quantification not yet supported");
      }
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsStaticInvoke(List<ec.ReflectCapability> capabilities,
      String methodName, Iterable<DartObject> metadata) {
    bool supportsTarget(ec.ReflecteeQuantifyCapability capability) {
      // TODO(eernst) implement: Correct this; will need something
      // like this, which will cover the case where we have applied
      // the trivial subtype:
      return _supportsStaticInvoke(
          capability.capabilities, methodName, metadata);
    }

    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if (capability is ec.StaticInvokeCapability &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if (capability is ec.StaticInvokeMetaCapability &&
          _supportsMeta(capability, metadata)) {
        return true;
      }
      // Handle reflectee based capabilities.
      if ((capability is ec.AdmitSubtypeCapability ||
              capability is ec.SubtypeQuantifyCapability) &&
          supportsTarget(capability)) {
        return true;
      }
      // Handle globally quantified capabilities.
      // TODO(eernst) feature: We probably need to refactor a lot of stuff
      // to get this right, so the first approach will simply be to
      // discover the relevant capabilities, and indicate that they
      // are not yet supported.
      if (capability is ec.GlobalQuantifyCapability ||
          capability is ec.GlobalQuantifyMetaCapability) {
        throw new UnimplementedError("Global quantification not yet supported");
      }
    }

    // All options exhausted, give up.
    return false;
  }

  bool supportsTopLevelInvoke(
      String methodName, List<ElementAnnotation> metadata) {
    return _supportsTopLevelInvoke(
        _capabilities, methodName, _getEvaluatedMetadata(metadata));
  }

  bool supportsStaticInvoke(
      String methodName, List<ElementAnnotation> metadata) {
    return _supportsStaticInvoke(
        _capabilities, methodName, _getEvaluatedMetadata(metadata));
  }

  bool get _supportsMetadata {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.metadataCapability);
  }

  // Returns [true] iff these [Capabilities] specify reflection support where
  // the set of included classes must be upwards closed, i.e., extra classes
  // must be added beyond the ones that are directly included as reflectable
  // because we must support operations like `superclass`.
  bool get _impliesUpwardsClosure {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.typeRelationsCapability);
  }

  bool get _impliesDeclarations {
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability == ec.declarationsCapability;
    });
  }

  bool get _impliesParameterTypes {
    if (!_impliesDeclarations) return false;
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability is ec.TypeCapability;
    });
  }

  bool get supportsLibraries {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.libraryCapability);
  }

  bool get _impliesFieldTypes => _impliesParameterTypes;
}

/// Collects the libraries that needs to be imported, and gives each library
/// a unique prefix.
class _ImportCollector {
  Map<LibraryElement, String> _mapping = new Map<LibraryElement, String>();
  int _count = 0;

  /// Returns the prefix associated with [library].
  String _getPrefix(LibraryElement library) {
    String prefix = _mapping[library];
    if (prefix != null) return prefix;
    prefix = "prefix$_count";
    _count++;
    _mapping[library] = prefix;
    return prefix;
  }

  /// Adds [library] to the collected libraries and generate a prefix for it if
  /// it has not been encountered before.
  void _addLibrary(LibraryElement library) {
    String prefix = _mapping[library];
    if (prefix != null) return;
    prefix = "prefix$_count";
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

class TransformerImplementation {
  TransformLogger _logger;
  Resolver _resolver;

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
      // TODO(eernst) clarify: The documentation in
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
        _logger.error(errors.METADATA_NOT_DIRECT_SUBCLASS,
            span: _resolver.getSourceSpan(elementAnnotation.element));
        return false;
      }
      // A direct subclass of [classReflectable], all OK.
      return true;
    }

    Element element = elementAnnotation.element;
    // TODO(eernst) future: Currently we only handle constructor expressions
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
        if (result.value == null) return null; // Errors during evaluation.
        bool isOk = checkInheritance(result.value.type, focusClass.type);
        return isOk ? result.value.type.element : null;
      } else {
        // Not a const top level variable, not relevant.
        return null;
      }
    }
    // Otherwise [element] is some other construct which is not supported.
    //
    // TODO(eernst) clarify: We need to consider whether there could be some
    // other syntactic constructs that are incorrectly assumed by programmers
    // to be usable with Reflectable.  Currently, such constructs will silently
    // have no effect; it might be better to emit a diagnostic message (a
    // hint?) in order to notify the programmer that "it does not work".
    // The trade-off is that such constructs may have been written by
    // programmers who are doing something else, intentionally.  To emit a
    // diagnostic message, we must check whether there is a Reflectable
    // somewhere inside this syntactic construct, and then emit the message
    // in cases that we "consider likely to be misunderstood".
    return null;
  }

  _warn(String message, Element element) {
    _logger.warning(message,
        asset: _resolver.getSourceAssetId(element),
        span: _resolver.getSourceSpan(element));
  }

  /// Finds all GlobalQuantifyCapability and GlobalQuantifyMetaCapability
  /// annotations on imports of [reflectableLibrary], and record the arguments
  /// of these annotations by modifying [globalPatterns] and [globalMetadata].
  void _findGlobalQuantifyAnnotations(
      Map<RegExp, List<ClassElement>> globalPatterns,
      Map<ClassElement, List<ClassElement>> globalMetadata) {
    LibraryElement reflectableLibrary =
        _resolver.getLibraryByName("reflectable.reflectable");
    LibraryElement capabilityLibrary =
        _resolver.getLibraryByName("reflectable.capability");
    ClassElement reflectableClass = reflectableLibrary.getType("Reflectable");
    ClassElement typeClass =
        _resolver.getLibraryByUri(Uri.parse("dart:core")).getType("Type");

    ConstructorElement globalQuantifyCapabilityConstructor = capabilityLibrary
        .getType("GlobalQuantifyCapability")
        .getNamedConstructor("");
    ConstructorElement globalQuantifyMetaCapabilityConstructor =
        capabilityLibrary
            .getType("GlobalQuantifyMetaCapability")
            .getNamedConstructor("");

    for (LibraryElement library in _resolver.libraries) {
      for (ImportElement import in library.imports) {
        for (ElementAnnotationImpl metadatum in import.metadata) {
          if (metadatum.element == globalQuantifyCapabilityConstructor) {
            EvaluationResultImpl evaluation = metadatum.evaluationResult;
            if (evaluation != null && evaluation.value != null) {
              DartObjectImpl value = evaluation.value;
              String pattern = value.fields["classNamePattern"].stringValue;
              if (pattern == null) {
                // TODO(sigurdm) implement: Create a span for the annotation
                // rather than the import.
                _warn("The classNamePattern must be a string", import);
                continue;
              }
              ClassElement reflector =
                  value.fields["(super)"].fields["reflector"].type.element;
              if (reflector == null ||
                  reflector.type.element.supertype.element !=
                      reflectableClass) {
                String found =
                    reflector == null ? "" : " Found ${reflector.name}";
                _warn(
                    "The reflector must be a direct subclass of Reflectable." +
                        found,
                    import);
                continue;
              }
              globalPatterns
                  .putIfAbsent(
                      new RegExp(pattern), () => new List<ClassElement>())
                  .add(reflector);
            }
          } else if (metadatum.element ==
              globalQuantifyMetaCapabilityConstructor) {
            EvaluationResultImpl evaluation = metadatum.evaluationResult;
            if (evaluation != null && evaluation.value != null) {
              DartObjectImpl value = evaluation.value;
              Object metadataFieldValue = value.fields["metadataType"].value;
              if (metadataFieldValue == null ||
                  value.fields["metadataType"].type.element != typeClass) {
                // TODO(sigurdm) implement: Create a span for the annotation.
                _warn(
                    "The metadata must be a Type. "
                    "Found ${value.fields["metadataType"].type.element.name}",
                    import);
                continue;
              }
              ClassElement reflector =
                  value.fields["(super)"].fields["reflector"].type.element;
              if (reflector == null ||
                  reflector.type.element.supertype.element !=
                      reflectableClass) {
                String found =
                    reflector == null ? "" : " Found ${reflector.name}";
                _warn(
                    "The reflector must be a direct subclass of Reflectable." +
                        found,
                    import);
                continue;
              }
              globalMetadata
                  .putIfAbsent(
                      metadataFieldValue, () => new List<ClassElement>())
                  .add(reflector);
            }
          }
        }
      }
    }
  }

  /// Returns a [ReflectionWorld] instantiated with all the reflectors seen by
  /// [resolver] and all classes annotated by them.
  ReflectionWorld _computeWorld(LibraryElement reflectableLibrary) {
    ReflectionWorld world = new ReflectionWorld(reflectableLibrary);
    Map<ClassElement, _ReflectorDomain> domains =
        new Map<ClassElement, _ReflectorDomain>();
    ClassElement focusClass = _findReflectableClassElement(reflectableLibrary);
    if (focusClass == null) {
      return null;
    }
    LibraryElement capabilityLibrary =
        _resolver.getLibraryByName("reflectable.capability");

    // For each pattern, the list of Reflectors that are associated with it via
    // a GlobalQuantifyCapability.
    Map<RegExp, List<ClassElement>> globalPatterns =
        new Map<RegExp, List<ClassElement>>();

    // For each Type, the list of Reflectors that are associated with it via
    // a GlobalQuantifyCapability.
    Map<ClassElement, List<ClassElement>> globalMetadata =
        new Map<ClassElement, List<ClassElement>>();

    // This call populates [globalPatterns] and [globalMetadata].
    _findGlobalQuantifyAnnotations(globalPatterns, globalMetadata);

    /// Get the [ReflectorDomain] associated with [reflector], or create it if
    /// none exists.
    _ReflectorDomain getReflectorDomain(ClassElement reflector) {
      return domains.putIfAbsent(reflector, () {
        _Capabilities capabilities =
            _capabilitiesOf(capabilityLibrary, reflector);
        world.importCollector._addLibrary(reflector.library);
        return new _ReflectorDomain(reflector, capabilities);
      });
    }

    /// Add [library] to the supported libraries of [reflector].
    void addLibrary(LibraryElement library, ClassElement reflector) {
      _ReflectorDomain domain = getReflectorDomain(reflector);
      if (domain._capabilities.supportsLibraries) {
        world.importCollector._addLibrary(library);
        domain._libraries.add(library);
      }
    }

    /// Add [ClassDomain] representing [type] to the supported classes of
    /// [reflector].
    void addClassDomain(ClassElement type, ClassElement reflector) {
      _ReflectorDomain domain = getReflectorDomain(reflector);
      if (domain._classMap.containsKey(type)) return;
      world.importCollector._addLibrary(type.library);
      domain._classMap[type] = _createClassDomain(type, domain);
      addLibrary(type.library, reflector);
    }

    /// Runs through a list of metadata, and finds any Reflectors, and
    /// objects that are associated with reflectors via
    /// GlobalQuantifyMetaCapability and GlobalQuantifyCabability.
    /// [qualifiedName] is the name of the library or class annotated by
    /// metadata.
    Iterable<ClassElement> getReflectors(
        String qualifiedName, List<ElementAnnotation> metadata) {
      List<ClassElement> result = new List<ClassElement>();

      for (ElementAnnotationImpl metadatum in metadata) {
        EvaluationResultImpl evaluation = metadatum.evaluationResult;
        DartObject value = evaluation.value;

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
            _getReflectableAnnotation(metadatum, focusClass);
        if (reflector != null) {
          result.add(reflector);
        }
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

    for (LibraryElement library in _resolver.libraries) {
      for (ClassElement reflector
          in getReflectors(library.name, library.metadata)) {
        addLibrary(library, reflector);
      }

      for (CompilationUnitElement unit in library.units) {
        for (ClassElement type in unit.types) {
          for (ClassElement reflector in getReflectors(
              "${type.library.name}.${type.name}", type.metadata)) {
            addClassDomain(type, reflector);
          }
        }
      }
    }

    world.reflectors.addAll(domains.values.toList());
    return world;
  }

  /// Returns the [ReflectCapability] denoted by the given [initializer].
  ec.ReflectCapability _capabilityOfExpression(LibraryElement capabilityLibrary,
      Expression expression, LibraryElement containingLibrary) {
    EvaluationResult evaluated =
        _resolver.evaluateConstant(containingLibrary, expression);

    if (!evaluated.isValid) {
      _logger.error("Invalid constant $expression in capability-list.");
    }

    DartObjectImpl constant = evaluated.value;

    ParameterizedType dartType = constant.type;
    // We insist that the type must be a class, and we insist that it must
    // be in the given `capabilityLibrary` (because we could never know
    // how to interpret the meaning of a user-written capability class, so
    // users cannot write their own capability classes).
    if (dartType.element is! ClassElement) {
      if (dartType.element.source != null) {
        _logger.error(
            errors.applyTemplate(errors.SUPER_ARGUMENT_NON_CLASS,
                {"type": dartType.displayName}),
            span: _resolver.getSourceSpan(dartType.element));
      } else {
        _logger.error(errors.applyTemplate(
            errors.SUPER_ARGUMENT_NON_CLASS, {"type": dartType.displayName}));
      }
    }
    ClassElement classElement = dartType.element;
    if (classElement.library != capabilityLibrary) {
      _logger.error(
          errors.applyTemplate(errors.SUPER_ARGUMENT_WRONG_LIBRARY,
              {"library": capabilityLibrary, "element": classElement}),
          span: _resolver.getSourceSpan(classElement));
    }

    /// Extracts the namePattern String from an instance of a subclass of
    /// NamePatternCapability.
    String extractNamePattern(DartObjectImpl constant) {
      if (constant.fields == null ||
          constant.fields["(super)"] == null ||
          constant.fields["(super)"].fields["namePattern"] == null ||
          constant.fields["(super)"].fields["namePattern"].stringValue ==
              null) {
        // TODO(sigurdm) diagnostic: Better error-message.
        _logger.warning("Could not extract namePattern.");
      }
      return constant.fields["(super)"].fields["namePattern"].stringValue;
    }

    /// Extracts the metadata property from an instance of a subclass of
    /// MetadataCapability.
    ClassElement extractMetaData(DartObjectImpl constant) {
      if (constant.fields == null ||
          constant.fields["(super)"] == null ||
          constant.fields["(super)"].fields["metadataType"] == null) {
        // TODO(sigurdm) diagnostic: Better error-message. We need a way
        // to get a source location from a constant.
        _logger.warning("Could not extract the metadata field.");
        return null;
      }
      Object metadataFieldValue =
          constant.fields["(super)"].fields["metadataType"].value;
      if (metadataFieldValue is! ClassElement) {
        _logger.warning("The metadataType field must be a Type object.");
        return null;
      }
      return constant.fields["(super)"].fields["metadataType"].value;
    }

    switch (classElement.name) {
      case "_NameCapability":
        return ec.nameCapability;
      case "_ClassifyCapability":
        return ec.classifyCapability;
      case "_MetadataCapability":
        return ec.metadataCapability;
      case "_TypeRelationsCapability":
        return ec.typeRelationsCapability;
      case "_LibraryCapability":
        return ec.libraryCapability;
      case "_DeclarationsCapability":
        return ec.declarationsCapability;
      case "_UriCapability":
        return ec.uriCapability;
      case "_LibraryDependenciesCapability":
        return ec.libraryDependenciesCapability;
      case "InstanceInvokeCapability":
        return new ec.InstanceInvokeCapability(extractNamePattern(constant));
      case "InstanceInvokeMetaCapability":
        return new ec.InstanceInvokeMetaCapability(extractMetaData(constant));
      case "StaticInvokeCapability":
        return new ec.StaticInvokeCapability(extractNamePattern(constant));
      case "StaticInvokeMetaCapability":
        return new ec.StaticInvokeMetaCapability(extractMetaData(constant));
      case "TopLevelInvokeCapability":
        return new ec.TopLevelInvokeCapability(extractNamePattern(constant));
      case "TopLevelInvokeMetaCapability":
        return new ec.TopLevelInvokeMetaCapability(extractMetaData(constant));
      case "NewInstanceCapability":
        return new ec.NewInstanceCapability(extractNamePattern(constant));
      case "NewInstanceMetaCapability":
        return new ec.NewInstanceMetaCapability(extractMetaData(constant));
      case "TypeCapability":
        return new ec.TypeCapability(constant.fields["upperBound"].value);
      case "InvokingCapability":
        return new ec.InvokingCapability(extractNamePattern(constant));
      case "InvokingMetaCapability":
        return new ec.NewInstanceMetaCapability(extractMetaData(constant));
      case "TypingCapability":
        return new ec.TypingCapability(constant.fields["upperBound"].value);
      case "SubtypeQuantifyCapability":
        // TODO(eernst) feature:
        throw new UnimplementedError("$classElement not yet supported!");
      case "AdmitSubtypeCapability":
        // TODO(eernst) feature:
        throw new UnimplementedError("$classElement not yet supported!");
      case "GlobalQuantifyCapability":
        // TODO(eernst) feature:
        throw new UnimplementedError("$classElement not yet supported!");
      case "GlobalQuantifyMetaCapability":
        // TODO(eernst) feature:
        throw new UnimplementedError("$classElement not yet supported!");
      default:
        throw new UnimplementedError("Unexpected capability $classElement");
    }
  }

  /// Returns the list of Capabilities given given as a superinitializer by the
  /// reflector.
  _Capabilities _capabilitiesOf(
      LibraryElement capabilityLibrary, ClassElement reflector) {
    List<ConstructorElement> constructors = reflector.constructors;
    // The superinitializer must be unique, so there must be 1 constructor.
    assert(constructors.length == 1);
    ConstructorElement constructorElement = constructors[0];
    // It can only be a const constructor, because this class has been
    // used for metadata; it is a bug in the transformer if not.
    // It must also be a default constructor.
    assert(constructorElement.isConst);
    // TODO(eernst) clarify: Ensure that some other location in this
    // transformer checks that the reflector class constructor is indeed a
    // default constructor, such that this can be a mere assertion rather than
    // a user-oriented error report.
    assert(constructorElement.isDefaultConstructor);

    ConstructorDeclaration constructorDeclarationNode =
        constructorElement.computeNode();
    NodeList<ConstructorInitializer> initializers =
        constructorDeclarationNode.initializers;

    if (initializers.length == 0) {
      // Degenerate case: Without initializers, we will obtain a reflector
      // without any capabilities, which is not useful in practice. We do
      // have this degenerate case in tests "just because we can", and
      // there is no technical reason to prohibit it, so we will handle
      // it here.
      return new _Capabilities(<ec.ReflectCapability>[]);
    }
    // TODO(eernst) clarify: Ensure again that this can be a mere assertion.
    assert(initializers.length == 1);

    // Main case: the initializer is exactly one element. We must
    // handle two cases: `super(..)` and `super.fromList(<_>[..])`.
    SuperConstructorInvocation superInvocation = initializers[0];

    ec.ReflectCapability capabilityOfExpression(Expression expression) {
      return _capabilityOfExpression(
          capabilityLibrary, expression, reflector.library);
    }

    if (superInvocation.constructorName == null) {
      // Subcase: `super(..)` where 0..k arguments are accepted for some
      // k that we need not worry about here.
      NodeList<Expression> arguments = superInvocation.argumentList.arguments;
      return new _Capabilities(arguments.map(capabilityOfExpression).toList());
    }
    assert(superInvocation.constructorName == "fromList");

    // Subcase: `super.fromList(const <..>[..])`.
    NodeList<Expression> arguments = superInvocation.argumentList.arguments;
    assert(arguments.length == 1);
    ListLiteral listLiteral = arguments[0];
    NodeList<Expression> expressions = listLiteral.elements;
    return new _Capabilities(expressions.map(capabilityOfExpression).toList());
  }

  /// Generates code for a new entry-point file that will initialize the
  /// reflection data according to [world], and invoke the main of
  /// [entrypointLibrary] located at [originalEntryPointFilename]. The code is
  /// generated to be located at [generatedId].
  String _generateNewEntryPoint(ReflectionWorld world, AssetId generatedId,
      String originalEntryPointFilename, LibraryElement entryPointLibrary) {
    // Notice it is important to generate the code before printing the
    // imports because generating the code can add further imports.
    String code = world.generateCode(_resolver, _logger, generatedId);

    List<String> imports = new List<String>();
    world.importCollector._libraries.forEach((LibraryElement library) {
      Uri uri = _resolver.getImportUri(library, from: generatedId);
      String prefix = world.importCollector._getPrefix(library);
      imports.add("import '$uri' as $prefix;");
    });
    imports.sort();

    String args =
        (entryPointLibrary.entryPoint.parameters.length == 0) ? "" : "args";
    return """
// This file has been generated by the reflectable package.
// https://github.com/dart-lang/reflectable.

library reflectable_generated_main_library;

import "dart:core";
import "$originalEntryPointFilename" as original show main;
${imports.join('\n')}

import "package:reflectable/src/mirrors_unimpl.dart" as r;
import "package:reflectable/reflectable.dart" show isTransformed;

export "$originalEntryPointFilename" hide main;

main($args) {
  _initializeReflectable();
  return original.main($args);
}

_initializeReflectable() {
  if (!isTransformed) {
    throw new UnsupportedError(
        "The transformed code is running with the untransformed "
        "reflectable package. Remember to set your package-root to "
        "'build/.../packages'.");
  }
  r.data = ${code};
}
""";
  }

  /// Performs the transformation which eliminates all imports of
  /// `package:reflectable/reflectable.dart` and instead provides a set of
  /// statically generated mirror classes.
  Future apply(
      AggregateTransform aggregateTransform, List<String> entryPoints) async {
    _logger = aggregateTransform.logger;
    // The type argument in the return type is omitted because the
    // documentation on barback and on transformers do not specify it.
    Resolvers resolvers = new Resolvers(dartSdkDirectory);

    List<Asset> assets = await aggregateTransform.primaryInputs.toList();

    if (assets.isEmpty) {
      // It is not an error to have nothing to transform.
      _logger.info("Nothing to transform");
      // Terminate with a non-failing status code to the OS.
      exit(0);
    }

    // TODO(eernst) algorithm: Build a mapping from entry points to assets by
    // iterating over `assets` and doing a binary search on a sorted
    // list of entry points: if A is the number of assets and E is the
    // number of entry points (note: E < A, and E == 1 could be quite
    // common), this would cost O(A*log(E)), whereas the current
    // approach costs O(A*E). OK, it's log(E)+epsilon, not 0 when E == 1.
    for (String entryPoint in entryPoints) {
      // Find the asset corresponding to [entryPoint]
      Asset entryPointAsset = assets.firstWhere(
          (Asset asset) => asset.id.path.endsWith(entryPoint),
          orElse: () => null);
      if (entryPointAsset == null) {
        aggregateTransform.logger.info("Missing entry point: $entryPoint");
        continue;
      }
      Transform wrappedTransform =
          new _AggregateTransformWrapper(aggregateTransform, entryPointAsset);

      _resolver = await resolvers.get(wrappedTransform);
      LibraryElement reflectableLibrary =
          _resolver.getLibraryByName("reflectable.reflectable");
      if (reflectableLibrary == null) {
        // Stop and do not consumePrimary, i.e., let the original source
        // pass through without changes.
        continue;
      }
      ReflectionWorld world = _computeWorld(reflectableLibrary);
      if (world == null) continue;

      String source = await entryPointAsset.readAsString();
      AssetId originalEntryPointId =
          entryPointAsset.id.changeExtension("_reflectable_original_main.dart");
      // Rename the original entry-point.
      aggregateTransform
          .addOutput(new Asset.fromString(originalEntryPointId, source));

      String originalEntryPointFilename =
          path.basename(originalEntryPointId.path);

      LibraryElement entryPointLibrary =
          _resolver.getLibrary(entryPointAsset.id);

      // Generate a new file with the name of the entry-point, whose main
      // initializes the reflection data, and calls the main from
      // [originalEntryPointId].
      aggregateTransform.addOutput(new Asset.fromString(
          entryPointAsset.id,
          _generateNewEntryPoint(world, entryPointAsset.id,
              originalEntryPointFilename, entryPointLibrary)));
      _resolver.release();
    }
  }
}

/// Wrapper of `AggregateTransform` of type `Transform`, allowing us to
/// get a `Resolver` for a given `AggregateTransform` with a given
/// selection of a primary entry point.
/// TODO(eernst) future: We will just use this temporarily; code_transformers
/// may be enhanced to support a variant of Resolvers.get that takes an
/// [AggregateTransform] and an [Asset] rather than a [Transform], in
/// which case we can drop this class and use that method.
class _AggregateTransformWrapper implements Transform {
  final AggregateTransform _aggregateTransform;
  final Asset primaryInput;
  _AggregateTransformWrapper(this._aggregateTransform, this.primaryInput);
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

bool _accessorIsntImplicitGetterOrSetter(PropertyAccessorElement accessor) {
  return !accessor.isSynthetic || (!accessor.isGetter && !accessor.isSetter);
}

bool _executableIsntImplicitGetterOrSetter(ExecutableElement executable) {
  return executable is! PropertyAccessorElement ||
      _accessorIsntImplicitGetterOrSetter(executable);
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
  if (element.parameterKind.isOptional) {
    result |= constants.optionalAttribute;
  }
  if (element.parameterKind == ParameterKind.NAMED) {
    result |= constants.namedAttribute;
  }
  if (element.type.isDynamic) {
    result |= constants.dynamicAttribute;
  }
  Element elementType = element.type.element;
  if (elementType is ClassElement) {
    result |= constants.classTypeAttribute;
  }
  return result;
}

/// Returns an integer encoding of the kind and attributes of the given
/// method/constructor/getter/setter.
int _declarationDescriptor(ExecutableElement element) {
  int result;
  if (element is PropertyAccessorElement) {
    result = element.isGetter ? constants.getter : constants.setter;
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
  } else {
    result = constants.method;
  }
  if (element.isPrivate) result |= constants.privateAttribute;
  if (element.isStatic) result |= constants.staticAttribute;
  if (element.isSynthetic) result |= constants.syntheticAttribute;
  if (element.isAbstract) result |= constants.abstractAttribute;
  return result;
}

String _nameOfDeclaration(ExecutableElement element) {
  if (element is ConstructorElement) {
    return element.name == ""
        ? element.enclosingElement.name
        : "${element.enclosingElement.name}.${element.name}";
  }
  return element.name;
}

String _formatAsList(Iterable parts) => "[${parts.join(", ")}]";

String _formatAsMap(Iterable parts) => "{${parts.join(", ")}}";

/// Returns code that will reproduce the given constant expression.
String _extractConstantCode(
    Expression expression,
    LibraryElement originatingLibrary,
    Resolver resolver,
    _ImportCollector importCollector) {
  if (expression is ListLiteral) {
    List<String> elements = expression.elements.map((Expression subExpression) {
      return _extractConstantCode(
          subExpression, originatingLibrary, resolver, importCollector);
    });
    // TODO(sigurdm) feature: Type arguments.
    return "const ${_formatAsList(elements)}";
  } else if (expression is MapLiteral) {
    List<String> elements = expression.entries.map((MapLiteralEntry entry) {
      String key = _extractConstantCode(
          entry.key, originatingLibrary, resolver, importCollector);
      String value = _extractConstantCode(
          entry.value, originatingLibrary, resolver, importCollector);
      return "$key: $value";
    });
    // TODO(sigurdm) feature: Type arguments.
    return "const ${_formatAsMap(elements)}";
  } else if (expression is InstanceCreationExpression) {
    String constructor = expression.constructorName.toSource();
    LibraryElement libraryOfConstructor = expression.staticElement.library;
    importCollector._addLibrary(libraryOfConstructor);
    String prefix =
        importCollector._getPrefix(expression.staticElement.library);
    // TODO(sigurdm) implement: Named arguments.
    String arguments =
        expression.argumentList.arguments.map((Expression argument) {
      return _extractConstantCode(
          argument, originatingLibrary, resolver, importCollector);
    }).join(", ");
    // TODO(sigurdm) feature: Type arguments.
    return "const $prefix.$constructor($arguments)";
  } else if (expression is Identifier) {
    Element element = expression.staticElement;
    importCollector._addLibrary(element.library);
    String prefix = importCollector._getPrefix(element.library);
    Element enclosingElement = element.enclosingElement;
    if (enclosingElement is ClassElement) {
      prefix += ".${enclosingElement.name}";
    }
    // TODO(sigurdm) diagnostic: Emit a warning/error if the element is not
    // in the global public scope of the library.
    return "$prefix.${element.name}";
  } else if (expression is BinaryExpression) {
    String a = _extractConstantCode(
        expression.leftOperand, originatingLibrary, resolver, importCollector);
    String op = expression.operator.lexeme;
    String b = _extractConstantCode(
        expression.rightOperand, originatingLibrary, resolver, importCollector);
    return "$a $op $b";
  } else if (expression is ConditionalExpression) {
    String condition = _extractConstantCode(
        expression.condition, originatingLibrary, resolver, importCollector);
    String a = _extractConstantCode(expression.thenExpression,
        originatingLibrary, resolver, importCollector);
    String b = _extractConstantCode(expression.elseExpression,
        originatingLibrary, resolver, importCollector);
    return "$condition ? $a : $b";
  } else if (expression is ParenthesizedExpression) {
    String nested = _extractConstantCode(
        expression.expression, originatingLibrary, resolver, importCollector);
    return "($nested)";
  } else if (expression is PropertyAccess) {
    String target = _extractConstantCode(
        expression.target, originatingLibrary, resolver, importCollector);
    String selector = expression.propertyName.token.lexeme;
    return "$target.$selector";
  } else if (expression is MethodInvocation) {
    // We only handle "identical(a, b)".
    assert(expression.target == null);
    assert(expression.methodName.token.lexeme == "identical");
    NodeList arguments = expression.argumentList.arguments;
    assert(arguments.length == 2);
    String a = _extractConstantCode(
        arguments[0], originatingLibrary, resolver, importCollector);
    String b = _extractConstantCode(
        arguments[1], originatingLibrary, resolver, importCollector);
    return "identical($a, $b)";
  } else {
    assert(expression is IntegerLiteral ||
        expression is BooleanLiteral ||
        expression is StringLiteral ||
        expression is NullLiteral ||
        expression is SymbolLiteral);
    return expression.toSource();
  }
}

/// The names of the libraries that can be accessed with a 'dart:x' import uri.
Set<String> sdkLibraryNames = new Set.from([
  "async",
  "collection",
  "convert",
  "core",
  "developer",
  "html",
  "indexed_db",
  "io",
  "isolate",
  "js",
  "math",
  "mirrors",
  "profiler",
  "svg",
  "typed_data",
  "web_audio",
  "web_gl",
  "web_sql"
]);

/// Returns a String with the code used to build the metadata of [element].
///
/// Also adds any neccessary imports to [importCollector].
String _extractMetadataCode(Element element, Resolver resolver,
    _ImportCollector importCollector, TransformLogger logger, AssetId dataId) {
  Iterable<ElementAnnotation> elementAnnotations = element.metadata;

  if (elementAnnotations == null) return "<Object>[]";

  // Synthetic accessors do not have metadata. Only their associated fields.
  if ((element is PropertyAccessorElement || element is ConstructorElement) &&
      element.isSynthetic) {
    return "<Object>[]";
  }

  List<String> metadataParts = new List<String>();

  AstNode node = element.computeNode();

  // The `element.node` of a field is the [VariableDeclaration] that is nested
  // in a [VariableDeclarationList] that is nested in a [FieldDeclaration]. The
  // metadata is stored on the [FieldDeclaration].
  if (element is FieldElement) {
    node = node.parent.parent;
  }

  AnnotatedNode annotatedNode = node;
  for (Annotation annotationNode in annotatedNode.metadata) {
    // TODO(sigurdm) diagnostic: Emit a warning/error if the element is not
    // in the global public scope of the library.
    if (annotationNode.element == null) {
      // Some internal constants (mainly in dart:html) cannot be resolved by
      // the analyzer. Ignore them.
      // TODO(sigurdm) clarify: Investigate this, and see if these constants can
      // somehow be included.
      logger.fine("Ignoring unresolved metadata $annotationNode",
          asset: resolver.getSourceAssetId(element),
          span: resolver.getSourceSpan(element));
      continue;
    }

    LibraryElement library = annotationNode.element.library;
    Uri importUri = resolver.getImportUri(library, from: dataId);
    if (annotationNode.element.isPrivate ||
        (importUri.scheme == "dart" &&
            !sdkLibraryNames.contains(importUri.path))) {
      // Private constants, and constants made of classes in internal libraries
      // cannot be represented.
      // Skip them.
      // TODO(sigurdm) clarify: Investigate this, and see if these constants can
      // somehow be included.
      logger.fine("Ignoring unrepresentable metadata $annotationNode",
          asset: resolver.getSourceAssetId(element),
          span: resolver.getSourceSpan(element));
      continue;
    }
    importCollector._addLibrary(library);
    String prefix = importCollector._getPrefix(library);
    if (annotationNode.arguments != null) {
      // A const constructor.
      String constructor = (annotationNode.constructorName == null)
          ? annotationNode.name
          : "${annotationNode.name}.${annotationNode.constructorName}";
      String arguments =
          annotationNode.arguments.arguments.map((Expression argument) {
        return _extractConstantCode(
            argument, element.library, resolver, importCollector);
      }).join(", ");
      metadataParts.add("const $prefix.$constructor($arguments)");
    } else {
      // A field reference.
      metadataParts.add("$prefix.${annotationNode.name}");
    }
  }

  return _formatAsList(metadataParts);
}

Iterable<FieldElement> _extractDeclaredFields(
    ClassElement classElement, _Capabilities capabilities) {
  return classElement.fields.where((FieldElement field) {
    if (field.isPrivate) return false;
    Function capabilityChecker = field.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    return !field.isSynthetic && capabilityChecker(field.name, field.metadata);
  });
}

Iterable<MethodElement> _extractDeclaredMethods(
    ClassElement classElement, _Capabilities capabilities) {
  return classElement.methods.where((MethodElement method) {
    if (method.isPrivate) return false;
    Function capabilityChecker = method.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    return capabilityChecker(method.name, method.metadata);
  });
}

Iterable<ParameterElement> _extractDeclaredParameters(
    Iterable<MethodElement> declaredMethods) {
  List<ParameterElement> result = <ParameterElement>[];
  for (MethodElement declaredMethod in declaredMethods) {
    result.addAll(declaredMethod.parameters);
  }
  return result;
}

/// Returns the [PropertyAccessorElement]s which are the accessors
/// of the given [classElement], including both the declared ones
/// and the implicitly generated ones corresponding to fields. This
/// is the set of accessors that corresponds to the behavioral interface
/// of the corresponding instances, as opposed to the source code oriented
/// interface, e.g., `declarations`. But the latter can be computed from
/// here, by filtering out the accessors whose `isSynthetic` is true
/// and adding the fields.
Iterable<PropertyAccessorElement> _declaredAndImplicitAccessors(
    ClassElement classElement, _Capabilities capabilities) {
  return classElement.accessors.where((PropertyAccessorElement accessor) {
    if (accessor.isPrivate) return false;
    Function capabilityChecker = accessor.isStatic
        ? capabilities.supportsStaticInvoke
        : capabilities.supportsInstanceInvoke;
    return capabilityChecker(accessor.name, accessor.metadata);
  });
}

Iterable<ConstructorElement> _declaredConstructors(
    ClassElement classElement, _Capabilities capabilities) {
  return classElement.constructors.where((ConstructorElement constructor) {
    if (constructor.isPrivate) return false;
    return capabilities.supportsNewInstance(
        constructor.name, constructor.metadata);
  });
}

_ClassDomain _createClassDomain(ClassElement type, _ReflectorDomain domain) {
  List<FieldElement> declaredFieldsOfClass =
      _extractDeclaredFields(type, domain._capabilities).toList();
  List<MethodElement> declaredMethodsOfClass =
      _extractDeclaredMethods(type, domain._capabilities).toList();
  List<ParameterElement> declaredParametersOfClass =
      _extractDeclaredParameters(declaredMethodsOfClass);
  List<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
      _declaredAndImplicitAccessors(type, domain._capabilities).toList();
  List<ConstructorElement> declaredConstructorsOfClass =
      _declaredConstructors(type, domain._capabilities).toList();
  return new _ClassDomain(
      type,
      declaredFieldsOfClass,
      declaredMethodsOfClass,
      declaredParametersOfClass,
      declaredAndImplicitAccessorsOfClass,
      declaredConstructorsOfClass,
      domain);
}
