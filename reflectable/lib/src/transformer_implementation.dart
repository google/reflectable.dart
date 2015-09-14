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

  /// A mapping giving the connection between a [ClassElement] and the
  /// [_ClassDomain] that describes the members that are available under
  /// reflection with [_reflector].
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

    List<String> namedParameterNames = type.namedParameterTypes.keys.toList();

    String positionals = new Iterable.generate(
        requiredPositionalCount, (int i) => parameterNames[i]).join(", ");

    String optionalsWithDefaults =
        new Iterable.generate(optionalPositionalCount, (int i) {
      ParameterElement parameterElement =
          constructor.parameters[requiredPositionalCount + i];
      FormalParameter parameterNode = parameterElement.computeNode();
      String defaultValueCode = "";
      if (parameterNode is DefaultFormalParameter &&
          parameterNode.defaultValue != null) {
        defaultValueCode = " = ${_extractConstantCode(
            parameterNode.defaultValue,
            parameterElement.library,
            importCollector)}";
      }
      return "${parameterNames[requiredPositionalCount + i]}"
          "$defaultValueCode";
    }).join(", ");

    String namedWithDefaults =
        new Iterable.generate(namedParameterNames.length, (int i) {
      // Note that the use of `requiredPositionalCount + i` below relies
      // on a language design where no parameter list can include
      // both optional positional and named parameters, so if there are
      // any named parameters then all optional parameters are named.
      ParameterElement parameterElement =
          constructor.parameters[requiredPositionalCount + i];
      FormalParameter parameterNode = parameterElement.computeNode();
      String defaultValueCode = "";
      if (parameterNode is DefaultFormalParameter &&
          parameterNode.defaultValue != null) {
        defaultValueCode = ": ${_extractConstantCode(
            parameterNode.defaultValue,
            parameterElement.library,
            importCollector)}";
      }
      return "${namedParameterNames[i]}$defaultValueCode";
    }).join(", ");

    String optionalArguments = new Iterable.generate(optionalPositionalCount,
        (int i) => parameterNames[i + requiredPositionalCount]).join(", ");
    String namedArguments =
        namedParameterNames.map((String name) => "$name: $name").join(", ");

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
    if (namedParameterNames.isNotEmpty) {
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

    _annotatedClasses
        .forEach((_ClassDomain domain) => classes.add(domain._classElement));

    // Because the analyzer doesn't model MixinApplications as classes we
    // do our own modelling, and keep record of the superclass hierarchy.
    // The superclass of a class with a mixin is the
    // mixin-application. The superclass of any other class is the same as the
    // `ClassElement.supertype.element`.
    Map<ClassElement, ClassElement> superclasses =
        new Map<ClassElement, ClassElement>();

    // Perform the downward closure if requested. Note that we will add
    // subtypes of classes which are already included because they carry
    // `_reflector` as metadata or they match a global quantifier for
    // `_reflector`, but we will not add subtypes of types included otherwise,
    // e.g., classes added because of a superclass quantifier.
    if (_capabilities._capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.subtypeQuantifyCapability)) {
      Set<ClassElement> subtypes = new Set<ClassElement>();
      for (LibraryElement library in resolver.libraries) {
        for (CompilationUnitElement unit in library.units) {
          // TODO(eernst) algorithm: Create a data structure representing
          // the inverse of the subtype relation (linking any class C to every
          // class that extends C, implements C, or applies C as a mixins),
          // and then use a working set iteration in order to find all
          // transitively reachable classes from `classes.items`.
          for (ClassElement type in unit.types) {
            if (classes._contains(type)) continue;
            for (ClassElement potentialSuperType in classes.items) {
              if (type.type.isSubtypeOf(potentialSuperType.type)) {
                subtypes.add(type);
                break;
              }
            }
          }
        }
      }
      subtypes
          .forEach((ClassElement classElement) => classes.add(classElement));
    }

    // Compute `classes`, i.e., the transitive closure of _annotated_classes
    // with classes implied by different capabilities.
    Set<ClassElement> workingSetOfClasses =
        new Set<ClassElement>.from(classes.items);

    while (workingSetOfClasses.isNotEmpty) {
      // Compute additional classes that are included due to different
      // capabilities, and the synthetic mixin-applications.
      Set<ClassElement> additionalClasses = new Set<ClassElement>();

      void addClass(ClassElement classElement) {
        if (_isImportable(classElement, dataId, resolver) &&
            !classes._contains(classElement)) {
          additionalClasses.add(classElement);
        }
      }

      for (ClassElement classElement in workingSetOfClasses) {
        _ClassDomain classDomain = _createClassDomain(classElement, this);
        _classMap[classElement] = classDomain;
        // Because a mixin-application does not add further methods and fields
        // we skip them here.
        if (classElement is MixinApplication) continue;

        if (_capabilities._impliesTypes) {
          classDomain._declaredFields.forEach((FieldElement fieldElement) {
            Element fieldType = fieldElement.type.element;
            if (fieldType is ClassElement) {
              addClass(fieldType);
            }
          });
          void addParameter(ParameterElement parameterElement) {
            Element parameterType = parameterElement.type.element;
            if (parameterType is ClassElement) {
              addClass(parameterType);
            }
          }
          classDomain._declaredParameters.forEach(addParameter);
          classDomain._instanceParameters.forEach(addParameter);
          void addReturnType(ExecutableElement executableElement) {
            Element returnType = executableElement.returnType.element;
            if (returnType is ClassElement) {
              addClass(returnType);
            }
          }
          classDomain._declaredMethods.forEach(addReturnType);
          classDomain._instanceMembers.forEach(addReturnType);
        }
      }

      if (_capabilities._impliesUpwardsClosure) {
        List<Element> upperBounds = _capabilities._upwardsClosureBounds;

        bool isSubclassOfBounds(ClassElement classElement) {
          bool isSuperclassOfClassElement(ClassElement bound) {
            if (classElement == bound) return true;
            if (classElement.supertype == null) return false;
            return isSubclassOfBounds(classElement.supertype.element);
          }
          return upperBounds.isEmpty ||
              upperBounds.any(isSuperclassOfClassElement);
        }

        workingSetOfClasses.forEach((ClassElement classElement) {
          // Mixin applications are handled by their subclasses.
          if (classElement is MixinApplication) return;

          InterfaceType workingSuperType = classElement.supertype;
          if (workingSuperType == null) return;
          ClassElement workingSuperclass = workingSuperType.element;

          if (!isSubclassOfBounds(classElement)) return;
          if (!classes._contains(workingSuperclass)) {
            addClass(workingSuperclass);
          }

          // Create the chain of mixin applications between the class and the
          // class it extends.
          ClassElement superclass = workingSuperclass;
          classElement.mixins.forEach((InterfaceType mixin) {
            ClassElement mixinClass = mixin.element;
            if (isSubclassOfBounds(mixinClass)) addClass(mixinClass);
            ClassElement mixinApplication = new MixinApplication(
                superclass, mixinClass, classElement.library,
                "${_qualifiedName(superclass)} with "
                    "${_qualifiedName(mixinClass)}");
            // We have already ensured that `workingSuperclass` is a
            // subclass of a bound (if any); the value of `superclass` is
            // either `workingSuperclass` or one of its superclasses created
            // by mixin application. Since there is no way to denote these
            // mixin applications directly, they must also be subclasses
            // of a bound, so these mixin applications must be added
            // unconditionally.
            addClass(mixinApplication);
            superclasses[mixinApplication] = superclass;
            superclass = mixinApplication;
          });
          superclasses[classElement] = superclass;
        });
      } else {
        // No upwards-closure. For each class set its superclass, and create
        // mixin applications for each mixin available.
        workingSetOfClasses.forEach((ClassElement classElement) {
          // Mixin-applications are handled when they are created, so we
          // skip them here.
          if (classElement is MixinApplication) return;
          InterfaceType supertype = classElement.supertype;
          // Object is the only class with no supertype, it has no mixins, so
          // we skip it here.
          if (supertype == null) return;
          ClassElement superclass = supertype.element;
          String superclassName  = _qualifiedName(superclass);
          classElement.mixins.forEach((InterfaceType mixin) {
            ClassElement mixinClass = mixin.element;
            if (classes._contains(mixinClass)) {
              ClassElement mixinApplication = new MixinApplication(
                  superclass, mixinClass, classElement.library,
                  "${superclassName} with "
              "${_qualifiedName(mixinClass)}");
              addClass(mixinApplication);
              superclasses[mixinApplication] = superclass;
              superclass = mixinApplication;
            } else {
              superclass = null;
            }
            superclassName = _qualifiedName(mixinClass);
          });
          superclasses[classElement] = superclass;
        });
      }

      additionalClasses.forEach(classes.add);
      workingSetOfClasses = additionalClasses;
    }

    // Fill in [libraries], [classes], [members], [fields], [parameters],
    // [instanceGetterNames], and [instanceSetterNames].

    // We run through _classMap.values rather than `annotatedClasses` because
    // we need to include the classes added by taking closures related to
    // different capabilities in the work-list loop above.
    for (_ClassDomain classDomain in _classMap.values) {
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

    for (LibraryElement library in _libraries) {
      libraries.add(library);
    }

    String gettingClosure(String getterName) {
      String closure;
      if (new RegExp(r"^[A-Za-z$_][A-Za-z$_0-9]*$").hasMatch(getterName)) {
        // Starts with letter, not an operator.
        closure = "(dynamic instance) => instance.${getterName}";
      } else if (getterName == "[]=") {
        closure = "(dynamic instance) => (x, v) => instance[x] = v";
      } else if (getterName == "[]") {
        closure = "(dynamic instance) => (x) => instance[x]";
      } else if (getterName == "unary-") {
        closure = "(dynamic instance) => () => -instance";
      } else if (getterName == "~") {
        closure = "(dynamic instance) => () => ~instance";
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

    String staticSettingClosure(ClassElement classElement, String setterName) {
      assert(setterName.substring(setterName.length - 1) == "=");
      // The [setterName] includes the "=", remove it.
      String name = setterName.substring(0, setterName.length - 1);
      String className = classElement.name;
      String prefix = importCollector._getPrefix(classElement.library);
      return 'r"$setterName": (value) => $prefix.$className.$name = value';
    }

    int computeTypeIndexBase(
        Element typeElement, bool isVoid, bool isDynamic, bool isClassType) {
      if (_capabilities._impliesTypes) {
        if (isDynamic || isVoid) {
          // The mirror will report 'dynamic' or 'void' as its `returnType`
          // and it will never use the index.
          return null;
        }
        if (isClassType) {
          // Normal encoding of a class type. That class has been added
          // to `classes`, so the `indexOf` cannot return `null`.
          assert(classes._contains(typeElement));
          return classes.indexOf(typeElement);
        }
      }
      return constants.NO_CAPABILITY_INDEX;
    }

    int computeFieldTypeIndex(FieldElement element, int descriptor) {
      return computeTypeIndexBase(
          element.type.element,
          false, // No field has type `void`.
          descriptor & constants.dynamicAttribute != 0,
          descriptor & constants.classTypeAttribute != 0);
    }

    int computeReturnTypeIndex(ExecutableElement element, int descriptor) {
      int result = computeTypeIndexBase(
          element.returnType.element,
          descriptor & constants.voidReturnTypeAttribute != 0,
          descriptor & constants.dynamicReturnTypeAttribute != 0,
          descriptor & constants.classReturnTypeAttribute != 0);
      return result;
    }

    // Generate the class mirrors.
    String classMirrorsCode = _formatAsList("m.ClassMirror",
        classes.items.map((ClassElement classElement) {
      _ClassDomain classDomain = _classMap[classElement];

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
        declarationsCode = _formatAsList("int", declarationsIndices);
      }

      // All instance members belong to the behavioral interface, so they
      // also get an offset of `fields.length`.
      String instanceMembersCode = _formatAsList("int",
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
      String staticMembersCode = _formatAsList("int",
          classDomain._staticMembers.map((ExecutableElement element) {
        int index = members.indexOf(element);
        return index == null
            ? constants.NO_CAPABILITY_INDEX
            : index + fields.length;
      }));

      ClassElement superclass = superclasses[classElement];
      // [Object]'s superclass is reported as `null`.
      String superclassIndex = (classElement ==
              resolver.getType('dart.core.Object'))
          ? "null"
          : (classes._contains(superclass))
              ? "${classes.indexOf(superclass)}"
              : "${constants.NO_CAPABILITY_INDEX}";

      String constructorsCode;
      if (classElement is MixinApplication ||
          classDomain._classElement.isAbstract) {
        constructorsCode = '{}';
      } else {
        constructorsCode = _formatAsMap(
            classDomain._constructors.map((ConstructorElement constructor) {
          String code = _constructorCode(constructor, importCollector);
          return 'r"${constructor.name}": $code';
        }));
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
              staticSettingClosure(classDomain._classElement, element.name)));

      int mixinIndex = (classElement is MixinApplication)
          ? classes.indexOf(classElement.mixin) ?? constants.NO_CAPABILITY_INDEX
          : classes.indexOf(classElement);

      int ownerIndex = _capabilities.supportsLibraries
          ? libraries.indexOf(classElement.library)
          : constants.NO_CAPABILITY_INDEX;

      String superinterfaceIndices = _formatAsList(
          'int',
          classElement.interfaces
              .map((InterfaceType type) => type.element)
              .where(classes._contains)
              .map(classes.indexOf));

      String classMetadataCode;
      if (_capabilities._supportsMetadata) {
        classMetadataCode = _extractMetadataCode(classDomain._classElement,
            resolver, importCollector, logger, dataId);
      } else {
        classMetadataCode = "null";
      }

      int classIndex = classes.indexOf(classElement);

      String result = 'new r.ClassMirrorImpl(r"${classDomain._simpleName}", '
          'r"${_qualifiedName(classElement)}", $classIndex, '
          '${_constConstructionCode(importCollector)}, '
          '$declarationsCode, $instanceMembersCode, $staticMembersCode, '
          '$superclassIndex, $staticGettersCode, $staticSettersCode, '
          '$constructorsCode, $ownerIndex, $mixinIndex, '
          '$superinterfaceIndices, $classMetadataCode)';
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
        int returnTypeIndex = computeReturnTypeIndex(element, descriptor);
        int ownerIndex = classes.indexOf(element.enclosingElement);
        String parameterIndicesCode = _formatAsList("int",
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
      int classMirrorIndex = computeFieldTypeIndex(element, descriptor);
      String metadataCode;
      if (_capabilities._supportsMetadata) {
        metadataCode = _extractMetadataCode(
            element, resolver, importCollector, logger, dataId);
      } else {
        // We encode 'without capability' as `null` for metadata, because
        // it is a `List<Object>`, which has no other natural encoding.
        metadataCode = null;
      }
      return 'new r.VariableMirrorImpl(r"${element.name}", $descriptor, '
          '$ownerIndex, ${_constConstructionCode(importCollector)}, '
          '$classMirrorIndex, $metadataCode)';
    });

    List<String> membersList = <String>[]
      ..addAll(fieldsList)
      ..addAll(methodsList);
    String membersCode = _formatAsList("m.DeclarationMirror", membersList);

    String typesCode =
        _formatAsList("Type", classes.items.map((ClassElement classElement) {
      if (classElement is MixinApplication) {
        return 'new r.FakeType(r"${classElement.name}")';
      }
      String prefix = importCollector._getPrefix(classElement.library);
      return "$prefix.${classElement.name}";
    }));

    String librariesCode;
    if (!_capabilities.supportsLibraries) {
      librariesCode = "null";
    } else {
      librariesCode = _formatAsList("m.LibraryMirror",
          libraries.items.map((LibraryElement library) {
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
      int ownerIndex =
          members.indexOf(element.enclosingElement) + fields.length;
      int classMirrorIndex;
      if (_capabilities._impliesTypes) {
        if (descriptor & constants.dynamicAttribute != 0) {
          // This parameter will report its type as `dynamic`, and it
          // will never use `classMirrorIndex`.
          classMirrorIndex = null;
        } else if (descriptor & constants.classTypeAttribute != 0) {
          // Normal encoding of a class type. That class has been added
          // to `classes`, so the `indexOf` cannot return `null`.
          assert(classes._contains(element.type.element));
          classMirrorIndex = classes.indexOf(element.type.element);
        }
      } else {
        classMirrorIndex = constants.NO_CAPABILITY_INDEX;
      }
      String metadataCode = "null";
      if (_capabilities._supportsMetadata) {
        FormalParameter node = element.computeNode();
        if (node == null) {
          metadataCode = "<Object>[]";
        } else {
          NodeList<Annotation> annotations = node.metadata;
          metadataCode =
              _formatAsList("Object", annotations.map((Annotation annotation) {
            return _extractAnnotationValue(
                annotation, element.library, importCollector);
          }));
        }
      }
      FormalParameter parameterNode = element.computeNode();
      String defaultValueCode = "null";
      if (parameterNode is DefaultFormalParameter &&
          parameterNode.defaultValue != null) {
        defaultValueCode = _extractConstantCode(
            parameterNode.defaultValue, element.library, importCollector);
      }
      return 'new r.ParameterMirrorImpl(r"${element.name}", $descriptor, '
          '$ownerIndex, ${_constConstructionCode(importCollector)}, '
          '$classMirrorIndex, $metadataCode, $defaultValueCode)';
    });
    String parameterMirrorsCode =
        _formatAsList("m.ParameterMirror", parametersList);

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

      if (classElement is MixinApplication) {
        if (classElement.superclass != null) {
          helper(classElement.superclass)
              .forEach((String name, ExecutableElement member) {
            addIfCapable(member);
          });
        }
        helper(classElement.mixin)
            .forEach((String name, ExecutableElement member) {
          addIfCapable(member);
        });
        return result;
      }
      ClassElement superclass = (classElement.supertype != null)
          ? classElement.supertype.element
          : null;
      if (superclass != null) {
        helper(superclass).forEach((String name, ExecutableElement member) {
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
    Map<String, ExecutableElement> helper(ClassElement classElement) {
      if (_reflectorDomain._staticMemberCache[classElement] != null) {
        return _reflectorDomain._staticMemberCache[classElement];
      }
      if (classElement is MixinApplication) {
        return new Map<String, ExecutableElement>();
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
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
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
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
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
      // Quantifying capabilities do not influence the availability
      // of reflection support for top level invocation.
    }

    // All options exhausted, give up.
    return false;
  }

  bool _supportsStaticInvoke(List<ec.ReflectCapability> capabilities,
      String methodName, Iterable<DartObject> metadata) {
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
      // Quantifying capabilities have no effect on the availability of
      // specific mirror features, their semantics has already been unfolded
      // fully when the set of supported classes was computed.
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
        capability is ec.SuperclassQuantifyCapability);
  }

  List<Element> get _upwardsClosureBounds {
     List<Element> result = <Element>[];
    _capabilities.forEach((ec.ReflectCapability capability) {
      if (capability is ec.SuperclassQuantifyCapability) {
        // Note that `null` represents the [ClassElement] for `Object`,
        // which does not need to be included because it represents the
        // constraint which is always satisfied.
        if (capability.upperBound != null) {
          result.add(capability.upperBound);
        }
      }
    });
    return result;
  }

  bool get _impliesDeclarations {
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability == ec.declarationsCapability;
    });
  }

  bool get _impliesTypes {
    if (!_impliesDeclarations) return false;
    return _capabilities.any((ec.ReflectCapability capability) {
      return capability is ec.TypeCapability;
    });
  }

  bool get supportsLibraries {
    return _capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.libraryCapability);
  }
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
      // This behavior is based on the assumption that a `null` element means
      // "there is no annotation here".
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
  ReflectionWorld _computeWorld(
      LibraryElement reflectableLibrary, AssetId dataId) {
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
      if (!_isImportable(type, dataId, _resolver)) {
        _logger.fine("Ignoring unrepresentable class ${type.name}",
            asset: _resolver.getSourceAssetId(type),
            span: _resolver.getSourceSpan(type));
      } else {
        _ReflectorDomain domain = getReflectorDomain(reflector);
        if (domain._classMap.containsKey(type)) return;
        world.importCollector._addLibrary(type.library);
        domain._classMap[type] = _createClassDomain(type, domain);
        addLibrary(type.library, reflector);
      }
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
      case "_SubtypeQuantifyCapability":
        return ec.subtypeQuantifyCapability;
      case "SuperclassQuantifyCapability":
        return new ec.SuperclassQuantifyCapability(
            constant.fields["upperBound"].value);
      case "AdmitSubtypeCapability":
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

import "package:reflectable/mirrors.dart" as m;
import "package:reflectable/src/reflectable_transformer_based.dart" as r;
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
      ReflectionWorld world =
          _computeWorld(reflectableLibrary, entryPointAsset.id);
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

      if (entryPointLibrary.entryPoint == null) {
        aggregateTransform.logger.info(
            "Entry point: $entryPoint has no member called `main`. Skipping.");
        continue;
      }

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
  } else {
    assert(element is MethodElement);
    result = constants.method;
    handleReturnType(element);
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

String _formatAsList(String typeName, Iterable parts) =>
    "<$typeName>[${parts.join(", ")}]";

String _formatAsDynamicList(Iterable parts) => "[${parts.join(", ")}]";

String _formatAsMap(Iterable parts) => "{${parts.join(", ")}}";

/// Returns a [String] containing code that will evaluate to the same
/// value when evaluated in the generated file as the given [expression]
/// would evaluate to in [originatingLibrary].
String _extractConstantCode(Expression expression,
    LibraryElement originatingLibrary, _ImportCollector importCollector) {
  if (expression is ListLiteral) {
    List<String> elements = expression.elements.map((Expression subExpression) {
      return _extractConstantCode(
          subExpression, originatingLibrary, importCollector);
    });
    // TODO(sigurdm) feature: Type arguments.
    return "const ${_formatAsDynamicList(elements)}";
  } else if (expression is MapLiteral) {
    List<String> elements = expression.entries.map((MapLiteralEntry entry) {
      String key =
          _extractConstantCode(entry.key, originatingLibrary, importCollector);
      String value = _extractConstantCode(
          entry.value, originatingLibrary, importCollector);
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
          argument, originatingLibrary, importCollector);
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
    return "$prefix.${element.name}";
  } else if (expression is BinaryExpression) {
    String a = _extractConstantCode(
        expression.leftOperand, originatingLibrary, importCollector);
    String op = expression.operator.lexeme;
    String b = _extractConstantCode(
        expression.rightOperand, originatingLibrary, importCollector);
    return "$a $op $b";
  } else if (expression is ConditionalExpression) {
    String condition = _extractConstantCode(
        expression.condition, originatingLibrary, importCollector);
    String a = _extractConstantCode(
        expression.thenExpression, originatingLibrary, importCollector);
    String b = _extractConstantCode(
        expression.elseExpression, originatingLibrary, importCollector);
    return "$condition ? $a : $b";
  } else if (expression is ParenthesizedExpression) {
    String nested = _extractConstantCode(
        expression.expression, originatingLibrary, importCollector);
    return "($nested)";
  } else if (expression is PropertyAccess) {
    String target = _extractConstantCode(
        expression.target, originatingLibrary, importCollector);
    String selector = expression.propertyName.token.lexeme;
    return "$target.$selector";
  } else if (expression is MethodInvocation) {
    // We only handle "identical(a, b)".
    assert(expression.target == null);
    assert(expression.methodName.token.lexeme == "identical");
    NodeList arguments = expression.argumentList.arguments;
    assert(arguments.length == 2);
    String a =
        _extractConstantCode(arguments[0], originatingLibrary, importCollector);
    String b =
        _extractConstantCode(arguments[1], originatingLibrary, importCollector);
    return "identical($a, $b)";
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

/// Returns a [String] containing code that will evaluate to the same
/// value when evaluated as an expression in the generated file as the
/// given [annotation] when attached as metadata to a declaration in
/// the given [library].
String _extractAnnotationValue(Annotation annotation, LibraryElement library,
    _ImportCollector importCollector) {
  String keywordCode = annotation.arguments != null ? "const " : "";
  Identifier name = annotation.name;
  String _nullIsEmpty(Object object) => object == null ? "" : "$object";
  if (name is SimpleIdentifier) {
    return "$keywordCode"
        "${importCollector._getPrefix(library)}.$name"
        "${_nullIsEmpty(annotation.period)}"
        "${_nullIsEmpty(annotation.constructorName)}"
        "${_nullIsEmpty(annotation.arguments)}";
  }
  throw new UnimplementedError(
      "Cannot move this annotation: $annotation, from library $library");
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
  if ((element is PropertyAccessorElement ||
          element is ConstructorElement ||
          element is MixinApplication) &&
      element.isSynthetic) {
    return "<Object>[]";
  }

  List<String> metadataParts = new List<String>();

  AstNode node = element.computeNode();

  // The `element.node` of a field is the [VariableDeclaration] that is nested
  // in a [VariableDeclarationList] that is nested in a [FieldDeclaration]. The
  // metadata is stored on the [FieldDeclaration].
  //
  // Similarly the `element.node` of a libraryElement is the identifier that
  // forms its name. The parent's parent is the actual Library declaration that
  // contains the metadata.
  if (element is FieldElement || element is LibraryElement) {
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
    if (!_isImportable(annotationNode.element, dataId, resolver)) {
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
        return _extractConstantCode(argument, element.library, importCollector);
      }).join(", ");
      metadataParts.add("const $prefix.$constructor($arguments)");
    } else {
      // A field reference.
      metadataParts.add("$prefix.${annotationNode.name}");
    }
  }

  return _formatAsList("Object", metadataParts);
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
  if (type is MixinApplication) {
    List<FieldElement> declaredFieldsOfClass =
        _extractDeclaredFields(type.mixin, domain._capabilities)
            .where((FieldElement e) => !e.isStatic)
            .toList();
    List<MethodElement> declaredMethodsOfClass =
        _extractDeclaredMethods(type.mixin, domain._capabilities)
            .where((MethodElement e) => !e.isStatic)
            .toList();
    List<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
        _declaredAndImplicitAccessors(type.mixin, domain._capabilities)
            .toList();
    List<ConstructorElement> declaredConstructorsOfClass =
        new List<ConstructorElement>();
    List<ParameterElement> declaredParametersOfClass =
        _extractDeclaredParameters(declaredMethodsOfClass,
            declaredConstructorsOfClass, declaredAndImplicitAccessorsOfClass);

    return new _ClassDomain(
        type,
        declaredFieldsOfClass,
        declaredMethodsOfClass,
        declaredParametersOfClass,
        declaredAndImplicitAccessorsOfClass,
        declaredConstructorsOfClass,
        domain);
  }

  List<FieldElement> declaredFieldsOfClass =
      _extractDeclaredFields(type, domain._capabilities).toList();
  List<MethodElement> declaredMethodsOfClass =
      _extractDeclaredMethods(type, domain._capabilities).toList();
  List<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
      _declaredAndImplicitAccessors(type, domain._capabilities).toList();
  List<ConstructorElement> declaredConstructorsOfClass =
      _declaredConstructors(type, domain._capabilities).toList();
  List<ParameterElement> declaredParametersOfClass = _extractDeclaredParameters(
      declaredMethodsOfClass,
      declaredConstructorsOfClass,
      declaredAndImplicitAccessorsOfClass);
  return new _ClassDomain(
      type,
      declaredFieldsOfClass,
      declaredMethodsOfClass,
      declaredParametersOfClass,
      declaredAndImplicitAccessorsOfClass,
      declaredConstructorsOfClass,
      domain);
}

/// Answers true iff this [element] can be imported into [dataId].
// TODO(sigurdm) implement: Make a test that tries to reflect on native/private
// classes.
bool _isImportable(Element element, AssetId dataId, Resolver resolver) {
  Uri importUri = resolver.getImportUri(element.library, from: dataId);
  return !(element.isPrivate ||
      (importUri.scheme == "dart" &&
          !sdkLibraryNames.contains(importUri.path)));
}

/// Modelling a MixinApplication as a ClassElement.
///
/// This class is only used to mark the synthetic mixin application classes.
/// So most of the class is left unimplemented.
class MixinApplication implements ClassElement {
  final ClassElement superclass;

  final ClassElement mixin;

  final LibraryElement library;
  final String name;

  MixinApplication(this.superclass, this.mixin, this.library, this.name);


  @override
  List<InterfaceType> get interfaces => <InterfaceType>[];

  @override
  List<ElementAnnotation> get metadata => <ElementAnnotation>[];

  @override
  bool get isSynthetic => true;

  @override
  InterfaceType get supertype => superclass.type;

  @override
  InterfaceType get type => mixin.type;

  @override
  bool operator ==(Object object) {
    return object is MixinApplication &&
        superclass == object.superclass &&
        mixin == object.mixin &&
        library == object.library;
  }

  @override
  int get hashCode =>
      superclass.hashCode ^ mixin.hashCode ^ library.hashCode;

  toString() => "MixinApplication($superclass, $mixin)";

  _unImplemented() => throw new UnimplementedError();

  @override
  List<PropertyAccessorElement> get accessors => _unImplemented();

  @override
  List<InterfaceType> get allSupertypes => _unImplemented();

  @override
  List<ConstructorElement> get constructors => _unImplemented();

  @override
  List<FieldElement> get fields => _unImplemented();

  @override
  bool get hasNonFinalField => _unImplemented();

  @override
  bool get hasReferenceToSuper => _unImplemented();

  @override
  bool get hasStaticMember => _unImplemented();

  @override
  bool get isAbstract => _unImplemented();

  @override
  bool get isEnum => _unImplemented();

  @override
  bool get isMixinApplication => _unImplemented();

  @override
  bool get isOrInheritsProxy => _unImplemented();

  @override
  bool get isProxy => _unImplemented();

  @override
  bool get isTypedef => _unImplemented();

  @override
  bool get isValidMixin => _unImplemented();

  @override
  List<MethodElement> get methods => _unImplemented();

  @override
  List<InterfaceType> get mixins => _unImplemented();

  @override
  List<TypeParameterElement> get typeParameters => _unImplemented();

  @override
  ConstructorElement get unnamedConstructor => _unImplemented();

  @override
  NamedCompilationUnitMember computeNode() => _unImplemented();

  @override
  FieldElement getField(String name) => _unImplemented();

  @override
  PropertyAccessorElement getGetter(String name) => _unImplemented();

  @override
  MethodElement getMethod(String name) => _unImplemented();

  @override
  ConstructorElement getNamedConstructor(String name) => _unImplemented();

  @override
  PropertyAccessorElement getSetter(String name) => _unImplemented();

  @override
  bool isSuperConstructorAccessible(ConstructorElement constructor) {
    return _unImplemented();
  }

  @override
  MethodElement lookUpConcreteMethod(
      String methodName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  PropertyAccessorElement lookUpGetter(
      String getterName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  PropertyAccessorElement lookUpInheritedConcreteGetter(
      String getterName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  MethodElement lookUpInheritedConcreteMethod(
      String methodName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  PropertyAccessorElement lookUpInheritedConcreteSetter(
      String setterName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  MethodElement lookUpInheritedMethod(
      String methodName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  MethodElement lookUpMethod(String methodName, LibraryElement library) {
    return _unImplemented();
  }

  @override
  PropertyAccessorElement lookUpSetter(
      String setterName, LibraryElement library) {
    return _unImplemented();
  }

  // This seems to be the defined behaviour according to dart:mirrors.
  @override
  bool get isPrivate => false;

  @override
  get context => _unImplemented();

  @override
  String get displayName => _unImplemented();

  @override
  Element get enclosingElement => _unImplemented();

  @override
  int get id => _unImplemented();

  @override
  bool get isDeprecated => _unImplemented();

  @override
  bool get isOverride => _unImplemented();

  @override
  bool get isPublic => _unImplemented();

  @override
  ElementKind get kind => _unImplemented();

  @override
  ElementLocation get location => _unImplemented();

  @override
  int get nameOffset => _unImplemented();

  @override
  AstNode get node => _unImplemented();

  @override
  get source => _unImplemented();

  @override
  CompilationUnit get unit => _unImplemented();

  @override
  accept(ElementVisitor visitor) => _unImplemented();

  @override
  String computeDocumentationComment() => _unImplemented();

  @override
  Element getAncestor(predicate) => _unImplemented();

  @override
  String getExtendedDisplayName(String shortName) => _unImplemented();

  @override
  bool isAccessibleIn(LibraryElement library) => _unImplemented();

  @override
  void visitChildren(ElementVisitor visitor) => _unImplemented();
}

String _qualifiedName(ClassElement classElement) {
  return "${classElement.library.name}.${classElement.name}";
}
