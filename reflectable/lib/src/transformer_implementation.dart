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
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'element_capability.dart' as ec;
import 'encoding_constants.dart' as constants;
import "reflectable_class_constants.dart" as reflectable_class_constants;
import 'source_manager.dart';
import 'transformer_errors.dart' as errors;

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

  String generateCode() {
    String result = reflectors.map((ReflectorDomain reflector) {
      return "const ${reflector.reflector.name}(): ${reflector.generateCode()}";
    }).join(",  ");
    return "{$result}";
  }
}

/// Similar to a `Set<T>` but also keeps track of the index of the first
/// insertion of each item.
class Enumerator<T> {
  final Map<T, int> _map = new Map<T, int>();
  int _count = 0;

  get length => _count;

  /// Tries to insert [t]. If it was already there return false, else insert it
  /// and return true.
  bool add(T t) {
    if (_map.containsKey(t)) return false;
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
class ReflectorDomain {
  final ClassElement reflector;

  Iterable<ClassDomain> get annotatedClasses => classMap.values;

  final Map<ClassElement, ClassDomain> classMap =
      new Map<ClassElement, ClassDomain>();

  final Capabilities capabilities;

  /// Libraries that must be imported to `reflector.library`.
  final Set<LibraryElement> missingImports = new Set<LibraryElement>();

  ReflectorDomain(this.reflector, this.capabilities) {}

  // TODO(eernst, sigurdm): Perhaps reconsider what the best strategy for
  // caching is.
  Map<ClassElement, Map<String, ExecutableElement>> _instanceMemberCache =
      new Map<ClassElement, Map<String, ExecutableElement>>();

  /// Returns a string that evaluates to a closure invoking [constructor] with
  /// the given arguments.
  /// For example for a constructor Foo(x, {y: 3}):
  /// returns "(x, {y: 3}) => new Foo(x, y)".
  /// This is to provide something that can be called with [Function.apply].
  String constructorCode(ConstructorElement constructor) {
    FunctionType type = constructor.type;

    int requiredPositionalCount = type.normalParameterTypes.length;
    int optionalPositionalCount = type.optionalParameterTypes.length;

    List<String> parameterNames = type.parameters
        .map((ParameterElement parameter) => parameter.name)
        .toList();

    List<String> NamedParameterNames = type.namedParameterTypes.keys.toList();

    String positionals = new Iterable.generate(
        requiredPositionalCount, (int i) => parameterNames[i]).join(", ");

    String optionalsWithDefaults = new Iterable.generate(
        optionalPositionalCount, (int i) {
      String defaultValueCode =
          constructor.parameters[requiredPositionalCount + i].defaultValueCode;
      String defaultValueString =
          defaultValueCode == null ? "" : " = $defaultValueCode";
      return "${parameterNames[i + requiredPositionalCount]}"
          "$defaultValueString";
    }).join(", ");

    String namedWithDefaults = new Iterable.generate(NamedParameterNames.length,
        (int i) {
      // TODO(eernst, sigurdm, #8): Recreate the default values faithfully.
      // TODO(eernst, sigurdm, #8): Until that is done, recognize unhandled
      // cases, and emit error/warning.
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

    return ('(${parameterParts.join(', ')}) => '
        'new ${_nameOfDeclaration(constructor)}'
        '(${argumentParts.join(", ")})');
  }

  String generateCode() {
    Enumerator<ClassElement> classes = new Enumerator<ClassElement>();
    Enumerator<ExecutableElement> members = new Enumerator<ExecutableElement>();
    Enumerator<FieldElement> fields = new Enumerator<FieldElement>();
    Set<String> instanceGetterNames = new Set<String>();
    Set<String> instanceSetterNames = new Set<String>();

    for (ClassDomain classDomain in annotatedClasses) {
      // For each annotated class we need a class domain.
      classes.add(classDomain.classElement);

      // Gather the behavioral interface into [members]. Note that
      // this includes implicitly generated getters and setters, but
      // omits fields. Also note that this does not match the
      // semantics of the `declarations` method in a [ClassMirror].
      classDomain.declarations.forEach(members.add);

      // Add the behavioral interface from this class (redundantly) and
      // all superclasses (which matters) to [members], such that it
      // contains both the behavioral parts for the target class and its
      // superclasses, and the program structure oriented parts for the
      // target class (omitting those from its superclasses).
      classDomain.instanceMembers.forEach(members.add);

      // Gather the fields declared in the target class (not inherited
      // ones) in [fields], i.e., the elements missing from [members]
      // at this point, in order to support `declarations` in a
      // [ClassMirror].
      classDomain.declaredFields.forEach(fields.add);

      // Gather all getters and setters based on [instanceMembers], including
      // both explicitly declared ones, implicitly generated ones for fields,
      // and the implicitly generated ones that correspond to method tear-offs.
      classDomain.instanceMembers.forEach((ExecutableElement instanceMember) {
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
      return '"${getterName}": $closure';
    }

    String staticGettingClosure(ClassElement classElement, String getterName) {
      String className = classElement.name;
      // Operators cannot be static.
      return '"${getterName}": () => $className.$getterName';
    }

    String settingClosure(String name) {
      return '"$name": (dynamic instance, value) => instance.$name value';
    }
    String staticSettingClosure(ClassElement classElement, String name) {
      String className = classElement.name;
      return '"$name": (value) => $className.$name value';
    }

    int classIndex = 0;
    String classMirrors = formatAsList(annotatedClasses
        .map((ClassDomain classDomain) {

      // Fields go first in [memberMirrors], so they will get the
      // same index as in [fields].
      List<int> fieldsIndices = classDomain.declaredFields
          .map((FieldElement element) {
        return fields.indexOf(element);
      });

      int fieldsLength = fields.length;

      // All the elements in the behavioral interface go after the
      // fields in [memberMirrors], so they must get an offset of
      // `fields.length` on the index.
      List<int> methodsIndices = classDomain.declarations
          .where(_executableIsntImplicitGetterOrSetter)
          .map((ExecutableElement element) {
        return members.indexOf(element) + fieldsLength;
      });

      List<int> declarationsIndices = <int>[]
        ..addAll(fieldsIndices)
        ..addAll(methodsIndices);
      String declarationsCode = formatAsList(declarationsIndices);

      // All instance members belong to the behavioral interface, so they
      // also get an offset of `fields.length`.
      String instanceMembersCode = formatAsList(classDomain.instanceMembers
          .map((ExecutableElement element) {
        return members.indexOf(element) + fieldsLength;
      }));

      ClassElement superclass = classDomain.classElement.supertype.element;
      String superclassIndex;
      if (superclass == null) {
        superclassIndex = null;
      } else {
        int index = classes.indexOf(superclass);
        if (index == null) {
          // There is a superclass, but we have no capability for it.
          index = -1;
        }
        superclassIndex = "$index";
      }

      String constructorsCode;

      if (classDomain.classElement.isAbstract) {
        constructorsCode = '{}';
      } else {
        constructorsCode = formatAsMap(classDomain.constructors
            .map((ConstructorElement constructor) {
          return '"${constructor.name}": ${constructorCode(constructor)}';
        }));
      }

      String classMetadataCode;
      if (capabilities.supportsMetadata) {
        classMetadataCode = extractMetadataCode(classDomain.classElement);
      } else {
        classMetadataCode = "null";
      }

      String staticGettersCode = formatAsMap([
        classDomain.declaredMethods
            .where((ExecutableElement element) => element.isStatic),
        classDomain.declaredAndImplicitAccessors.where(
            (PropertyAccessorElement element) =>
                element.isStatic && element.isGetter)
      ].expand((x) => x).map((ExecutableElement element) =>
          staticGettingClosure(classDomain.classElement, element.name)));
      String staticSettersCode = formatAsMap(
          classDomain.declaredAndImplicitAccessors
              .where((PropertyAccessorElement element) =>
                  element.isStatic && element.isSetter)
              .map((PropertyAccessorElement element) => staticSettingClosure(
                  classDomain.classElement, element.name)));
      String result = 'new r.ClassMirrorImpl("${classDomain.simpleName}", '
          '"${classDomain.qualifiedName}", $classIndex, '
          'const ${reflector.name}(), '
          '$declarationsCode, $instanceMembersCode, $superclassIndex, '
          '$staticGettersCode, $staticSettersCode, $constructorsCode, '
          '$classMetadataCode)';
      classIndex++;
      return result;
    }));

    String gettersCode = formatAsMap(instanceGetterNames.map(gettingClosure));
    String settersCode = formatAsMap(instanceSetterNames.map(settingClosure));

    List<String> methodsList = members.items.map((ExecutableElement element) {
      int descriptor = _declarationDescriptor(element);
      int ownerIndex = classes.indexOf(element.enclosingElement);
      String metadataCode;
      if (capabilities.supportsMetadata) {
        metadataCode = extractMetadataCode(element);
      } else {
        metadataCode = null;
      }
      return 'new r.MethodMirrorImpl("${element.name}", $descriptor, '
          '$ownerIndex, const ${reflector.name}(), $metadataCode)';
    });

    List<String> fieldsList = fields.items.map((FieldElement element) {
      int descriptor = _fieldDescriptor(element);
      int ownerIndex = classes.indexOf(element.enclosingElement);
      String metadataCode;
      if (capabilities.supportsMetadata) {
        metadataCode = extractMetadataCode(element);
      } else {
        metadataCode = null;
      }
      return 'new r.VariableMirrorImpl("${element.name}", $descriptor, '
          '$ownerIndex, const ${reflector.name}(), $metadataCode)';
    });

    List<String> membersList = <String>[]
      ..addAll(fieldsList)
      ..addAll(methodsList);
    String membersCode = formatAsList(membersList);

    String typesCode = formatAsList(
        classes.items.map((ClassElement classElement) => classElement.name));

    return "new r.ReflectorData($classMirrors, $membersCode, $typesCode, "
        "$gettersCode, $settersCode)";
  }
}

/// Information about reflectability for a given class.
class ClassDomain {
  /// Element describing the target class.
  final ClassElement classElement;

  /// Fields declared by [classElement] and included for reflection support,
  /// according to the reflector described by the [reflectorDomain];
  /// obtained by filtering `classElement.fields`.
  final Iterable<FieldElement> declaredFields;

  /// Methods which are declared by [classElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `classElement.methods`.
  final Iterable<MethodElement> declaredMethods;

  /// Getters and setters possessed by [classElement] and included for
  /// reflection support, according to the reflector described by
  /// [reflectorDomain]; obtained by filtering `classElement.accessors`.
  /// Note that it includes declared as well as synthetic accessors,
  /// implicitly created as getters/setters for fields.
  final Iterable<PropertyAccessorElement> declaredAndImplicitAccessors;

  /// Constructors declared by [classElement] and included for reflection
  /// support, according to the reflector described by [reflectorDomain];
  /// obtained by filtering `classElement.constructors`.
  final Iterable<ConstructorElement> constructors;

  /// The reflector domain that holds [this] object as one of its
  /// class domains.
  final ReflectorDomain reflectorDomain;

  ClassDomain(this.classElement, this.declaredFields, this.declaredMethods,
      this.declaredAndImplicitAccessors, this.constructors,
      this.reflectorDomain);

  Iterable<MethodElement> get invokableMethods => instanceMembers
      .where((ExecutableElement element) => element is MethodElement);

  String get simpleName => classElement.name;
  String get qualifiedName {
    return "${classElement.library.name}.${classElement.name}";
  }

  /// Returns the declared methods, accessors and constructors in
  /// [classElement]. Note that this includes synthetic getters and
  /// setters, and omits fields; in other words, it provides the
  /// behavioral point of view on the class. Also note that this is not
  /// the same semantics as that of `declarations` in [ClassMirror].
  Iterable<ExecutableElement> get declarations {
    // TODO(sigurdm): Include type variables (if we decide to keep them).
    return [
      declaredMethods,
      declaredAndImplicitAccessors,
      constructors
    ].expand((x) => x);
  }

  /// Finds all instance members by going through the class hierarchy.
  Iterable<ExecutableElement> get instanceMembers {
    Map<String, ExecutableElement> helper(ClassElement classElement) {
      if (reflectorDomain._instanceMemberCache[classElement] != null) {
        return reflectorDomain._instanceMemberCache[classElement];
      }
      Map<String, ExecutableElement> result =
          new Map<String, ExecutableElement>();

      void addIfCapable(ExecutableElement member) {
        if (reflectorDomain.capabilities.supportsInstanceInvoke(
            member.name, member.metadata)) {
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
    return helper(classElement).values;
  }

  String nameOfDeclaration(ExecutableElement element) {
    if (element is ConstructorElement) {
      return element.name == ""
          ? classElement.name
          : "${classElement.name}.${element.name}";
    }
    return element.name;
  }

  String toString() {
    return "ClassDomain(classElement)";
  }
}

/// A wrapper around a list of Capabilities.
/// Supports queries about the methods supported by the set of capabilities.
class Capabilities {
  List<ec.ReflectCapability> capabilities;
  Capabilities(this.capabilities);

  instanceMethodsFilterRegexpString() {
    if (capabilities.contains(ec.instanceInvokeCapability)) return ".*";
    if (capabilities.contains(ec.invokingCapability)) return ".*";
    return capabilities.where((ec.ReflectCapability capability) {
      return capability is ec.InstanceInvokeCapability;
    }).map((ec.InstanceInvokeCapability capability) {
      return "(${capability.namePattern})";
    }).join('|');
  }

  bool _supportsName(ec.NamePatternCapability capability, String methodName) {
    RegExp regexp = new RegExp(capability.namePattern);
    return regexp.hasMatch(methodName);
  }

  bool _supportsMeta(
      ec.MetadataQuantifiedCapability capability, List<DartObject> metadata) {
    if (metadata == null) return false;
    return metadata.contains(capability.metadata);
  }

  bool _supportsInstanceInvoke(List<ec.ReflectCapability> capabilities,
      String methodName, List<DartObjectImpl> metadata) {
    bool supportsTarget(ec.ReflecteeQuantifyCapability capability) {
      // TODO(eernst): implement this correctly; will need something
      // like this, which will cover the case where we have applied
      // the trivial subtype:
      return _supportsInstanceInvoke(
          capability.capabilities, methodName, metadata);
    }

    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if ((capability is ec.InvokingCapability ||
              capability is ec.InstanceInvokeCapability) &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if ((capability is ec.InvokingMetaCapability ||
              capability is ec.InstanceInvokeMetaCapability) &&
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
      // TODO(eernst): We probably need to refactor a lot of stuff
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

  bool _supportsNewInstance(List<ec.ReflectCapability> capabilities,
      String constructorName, List<DartObjectImpl> metadata) {
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
      // TODO(eernst, sigurdm): implement.
    }

    // All options exhausted, give up.
    return false;
  }

  List<DartObjectImpl> getEvaluatedMetadata(
      List<ElementAnnotationImpl> metadata) {
    return metadata.map((ElementAnnotationImpl elementAnnotation) {
      EvaluationResultImpl evaluation = elementAnnotation.evaluationResult;
      assert(evaluation != null);
      return evaluation.value;
    });
  }

  // TODO(sigurdm): Find a way to cache these. Perhaps take an element instead
  // of name+metadata.
  bool supportsInstanceInvoke(
      String methodName, List<ElementAnnotation> metadata) {
    var v = _supportsInstanceInvoke(
        capabilities, methodName, getEvaluatedMetadata(metadata));
    return v;
  }

  bool supportsNewInstance(
      String constructorName, List<ElementAnnotation> metadata) {
    var result = _supportsNewInstance(
        capabilities, constructorName, getEvaluatedMetadata(metadata));
    return result;
  }

  bool _supportsStaticInvoke(List<ec.ReflectCapability> capabilities,
      String methodName, List<DartObject> metadata) {
    bool supportsTarget(ec.ReflecteeQuantifyCapability capability) {
      // TODO(eernst): implement this correctly; will need something
      // like this, which will cover the case where we have applied
      // the trivial subtype:
      return _supportsStaticInvoke(
          capability.capabilities, methodName, metadata);
    }

    for (ec.ReflectCapability capability in capabilities) {
      // Handle API based capabilities.
      if ((capability is ec.InvokingCapability ||
              capability is ec.StaticInvokeCapability) &&
          _supportsName(capability, methodName)) {
        return true;
      }
      if ((capability is ec.InvokingMetaCapability ||
              capability is ec.StaticInvokeMetaCapability) &&
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
      // TODO(eernst): We probably need to refactor a lot of stuff
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

  bool supportsStaticInvoke(
      String methodName, List<ElementAnnotation> metadata) {
    return _supportsStaticInvoke(
        capabilities, methodName, getEvaluatedMetadata(metadata));
  }

  bool get supportsMetadata {
    return capabilities.any((ec.ReflectCapability capability) =>
        capability == ec.metadataCapability);
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

  Iterable<FieldElement> declaredFields(
      ClassElement classElement, Capabilities capabilities) {
    return classElement.fields.where((FieldElement field) {
      Function capabilityChecker = field.isStatic
          ? capabilities.supportsStaticInvoke
          : capabilities.supportsInstanceInvoke;
      return !field.isSynthetic &&
          capabilityChecker(field.name, field.metadata);
    });
  }

  Iterable<MethodElement> declaredMethods(
      ClassElement classElement, Capabilities capabilities) {
    return classElement.methods.where((MethodElement method) {
      Function capabilityChecker = method.isStatic
          ? capabilities.supportsStaticInvoke
          : capabilities.supportsInstanceInvoke;
      return capabilityChecker(method.name, method.metadata);
    });
  }

  /// Returns the [PropertyAccessorElement]s which are the accessors
  /// of the given [classElement], including both the declared ones
  /// and the implicitly generated ones corresponding to fields. This
  /// is the set of accessors that corresponds to the behavioral interface
  /// of the corresponding instances, as opposed to the source code oriented
  /// interface, e.g., `declarations`. But the latter can be computed from
  /// here, by filtering out the accessors whose `isSynthetic` is true
  /// and adding the fields.
  Iterable<PropertyAccessorElement> declaredAndImplicitAccessors(
      ClassElement classElement, Capabilities capabilities) {
    return classElement.accessors.where((PropertyAccessorElement accessor) {
      Function capabilityChecker = accessor.isStatic
          ? capabilities.supportsStaticInvoke
          : capabilities.supportsInstanceInvoke;
      return capabilityChecker(accessor.name, accessor.metadata);
    });
  }

  Iterable<ConstructorElement> declaredConstructors(
      ClassElement classElement, Capabilities capabilities) {
    return classElement.constructors.where((ConstructorElement constructor) {
      return capabilities.supportsNewInstance(
          constructor.name, constructor.metadata);
    });
  }

  warn(String message, Element element) {
    logger.warning(message,
        asset: resolver.getSourceAssetId(element),
        span: resolver.getSourceSpan(element));
  }

  /// Finds all GlobalQuantifyCapability and GlobalQuantifyMetaCapability
  /// annotations on imports of [reflectableLibrary], and record the arguments
  /// of these annotations by modifying [globalPatterns] and [globalMetadata].
  void findGlobalQuantifyAnnotations(
      Map<RegExp, List<ClassElement>> globalPatterns,
      Map<ClassElement, List<ClassElement>> globalMetadata) {
    LibraryElement reflectableLibrary =
        resolver.getLibraryByName("reflectable.reflectable");
    LibraryElement capabilityLibrary =
        resolver.getLibraryByName("reflectable.capability");
    ClassElement reflectableClass = reflectableLibrary.getType("Reflectable");
    ClassElement typeClass =
        resolver.getLibraryByUri(Uri.parse("dart:core")).getType("Type");

    ConstructorElement globalQuantifyCapabilityConstructor = capabilityLibrary
        .getType("GlobalQuantifyCapability")
        .getNamedConstructor("");
    ConstructorElement globalQuantifyMetaCapabilityConstructor =
        capabilityLibrary
            .getType("GlobalQuantifyMetaCapability")
            .getNamedConstructor("");

    for (LibraryElement library in resolver.libraries) {
      for (ImportElement import in library.imports) {
        for (ElementAnnotationImpl metadatum in import.metadata) {
          if (metadatum.element == globalQuantifyCapabilityConstructor) {
            EvaluationResultImpl evaluation = metadatum.evaluationResult;
            if (evaluation != null && evaluation.value != null) {
              DartObjectImpl value = evaluation.value;
              String pattern = value.fields["classNamePattern"].stringValue;
              if (pattern == null) {
                // TODO(sigurdm): Create a span for the annotation rather than
                // the import.
                warn("The classNamePattern must be a string", import);
                continue;
              }
              ClassElement reflector =
                  value.fields["(super)"].fields["reflector"].type.element;
              if (reflector == null ||
                  reflector.type.element.supertype.element !=
                      reflectableClass) {
                String found =
                    reflector == null ? "" : " Found ${reflector.name}";
                warn("The reflector must be a direct subclass of Reflectable." +
                    found, import);
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
              Object metadataFieldValue = value.fields["metadata"].value;
              if (metadataFieldValue == null ||
                  value.fields["metadata"].type.element != typeClass) {
                // TODO(sigurdm): Create a span for the annotation.
                warn("The metadata must be a Type. "
                    "Found ${value.fields["metadata"].type.element.name}",
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
                warn("The reflector must be a direct subclass of Reflectable." +
                    found, import);
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

    // For each pattern, the list of Reflectors that are associated with it via
    // a GlobalQuantifyCapability.
    Map<RegExp, List<ClassElement>> globalPatterns =
        new Map<RegExp, List<ClassElement>>();

    // For each Type, the list of Reflectors that are associated with it via
    // a GlobalQuantifyCapability.
    Map<ClassElement, List<ClassElement>> globalMetadata =
        new Map<ClassElement, List<ClassElement>>();

    // This call populates [globalPatterns] and [globalMetadata].
    findGlobalQuantifyAnnotations(globalPatterns, globalMetadata);

    void addClass(ClassElement type, ClassElement reflector) {
      ReflectorDomain domain = domains.putIfAbsent(reflector, () {
        Capabilities capabilities =
            _capabilitiesOf(capabilityLibrary, reflector);
        return new ReflectorDomain(reflector, capabilities);
      });
      if (domain.classMap.containsKey(type)) return;

      List<FieldElement> declaredFieldsOfClass =
          declaredFields(type, domain.capabilities).toList();
      List<MethodElement> declaredMethodsOfClass =
          declaredMethods(type, domain.capabilities).toList();
      List<PropertyAccessorElement> declaredAndImplicitAccessorsOfClass =
          declaredAndImplicitAccessors(type, domain.capabilities).toList();
      List<ConstructorElement> declaredConstructorsOfClass =
          declaredConstructors(type, domain.capabilities).toList();
      domain.classMap[type] = new ClassDomain(type, declaredFieldsOfClass,
          declaredMethodsOfClass, declaredAndImplicitAccessorsOfClass,
          declaredConstructorsOfClass, domain);
    }

    for (LibraryElement library in resolver.libraries) {
      for (CompilationUnitElement unit in library.units) {
        for (ClassElement type in unit.types) {
          for (ElementAnnotationImpl metadatum in type.metadata) {
            EvaluationResultImpl evaluation = metadatum.evaluationResult;
            DartObject value = evaluation.value;
            // Add the class to the domain of all reflectors associated with
            // the type of this metadata via GlobalQuantifyMetaCapability
            // (if any).
            if (value != null) {
              List<ClassElement> reflectors =
                  globalMetadata[value.type.element];
              if (reflectors != null) {
                for (ClassElement reflector in reflectors) {
                  addClass(type, reflector);
                }
              }
            }

            // Add the class if it is annotated by a reflector.
            ClassElement reflector =
                _getReflectableAnnotation(metadatum, focusClass);
            if (reflector != null) {
              addClass(type, reflector);
            }
          }
          // Add the class to the domain of all reflectors associated with a
          // pattern, via GlobalQuantifyCapability, that matches the qualified
          // name of the class.
          globalPatterns
              .forEach((RegExp pattern, List<ClassElement> reflectors) {
            String qualifiedName = "${type.library.name}.${type.name}";
            if (pattern.hasMatch(qualifiedName)) {
              for (ClassElement reflector in reflectors) {
                addClass(type, reflector);
              }
            }
          });
        }
      }
    }
    domains.values.forEach(_collectMissingImports);

    world.reflectors.addAll(domains.values.toList());
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

  /// Returns the [ReflectCapability] denoted by the given [initializer].
  ec.ReflectCapability _capabilityOfExpression(LibraryElement capabilityLibrary,
      Expression expression, LibraryElement containingLibrary) {
    EvaluationResult evaluated =
        resolver.evaluateConstant(containingLibrary, expression);

    if (!evaluated.isValid) {
      logger.error("Invalid constant $expression in capability-list.");
    }

    DartObjectImpl constant = evaluated.value;

    ParameterizedType dartType = constant.type;
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

    /// Extracts the namePattern String from an instance of a subclass of
    /// NamePatternCapability.
    String extractNamePattern(DartObjectImpl constant) {
      if (constant.fields == null ||
          constant.fields["(super)"] == null ||
          constant.fields["(super)"].fields["namePattern"] == null ||
          constant.fields["(super)"].fields["namePattern"].stringValue ==
              null) {
        // TODO(sigurdm): Better error-message.
        logger.warning("Could not extract namePattern.");
      }
      return constant.fields["(super)"].fields["namePattern"].stringValue;
    }

    /// Extracts the metadata property from an instance of a subclass of
    /// MetadataCapability.
    DartObject extractMetaData(DartObjectImpl constant) {
      if (constant.fields == null ||
          constant.fields["(super)"] == null ||
          constant.fields["(super)"].fields["metadata"] == null) {
        // TODO(sigurdm): Better error-message.
        logger.warning("Could not extract metadata.");
      }
      return constant.fields["(super)"].fields["metadata"];
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
      case "_OwnerCapability":
        return ec.ownerCapability;
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
      return new Capabilities(<ec.ReflectCapability>[]);
    }
    // TODO(eernst): Ensure again that this can be a mere assertion.
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

  /// Returns the source of the file containing the reflection data for [world].
  /// [id] is used to create relative import uris.
  String reflectionWorldSource(ReflectionWorld world, AssetId id) {
    Set<String> imports = new Set<String>();
    imports.addAll(world.reflectors.map((ReflectorDomain reflector) {
      Uri uri = resolver.getImportUri(reflector.reflector.library, from: id);
      return "import '$uri';";
    }));
    imports.addAll(world.reflectors
        .expand((ReflectorDomain reflector) => reflector.annotatedClasses)
        .map((ClassDomain classDomain) {
      Uri uri =
          resolver.getImportUri(classDomain.classElement.library, from: id);
      return "import '$uri';";
    }));
    List<String> importsList = new List<String>.from(imports);
    importsList.sort();
    return """
library ${id.path.replaceAll("/", ".")};
import "package:reflectable/src/mirrors_unimpl.dart" as r;
import "package:reflectable/reflectable.dart" show isTransformed;
${importsList.join('\n')}

initializeReflectable() {
  if (!isTransformed) {
    throw new UnsupportedError(
        "The transformed code is running with the untransformed "
        "reflectable package. Remember to set your package-root to "
        "'build/.../packages'.");
  }
  r.data = ${world.generateCode()};
}
""";
  }

  resetUsedNames() {}

  String transformMain(
      Asset entryPoint, String source, String reflectWorldUri) {
    // Used to manage replacements of code snippets by other code snippets
    // in [source].
    SourceManager sourceManager = new SourceManager(source);
    sourceManager.insert(
        0, "// This file has been transformed by reflectable.\n");
    LibraryElement mainLibrary = resolver.getLibrary(entryPoint.id);
    sourceManager.insert(_newImportIndex(mainLibrary),
        '\nimport "$reflectWorldUri" show initializeReflectable;');

    // TODO(eernst, sigurdm): This won't work if main is not declared in
    // `mainLibrary`.
    if (mainLibrary.entryPoint == null) {
      logger.warning("Could not find a main method in $entryPoint. Skipping.");
      return source;
    }
    sourceManager.insert(mainLibrary.entryPoint.nameOffset, "_");
    String args = (mainLibrary.entryPoint.parameters.length == 0) ? "" : "args";
    sourceManager.insert(source.length, """
void main($args) {
  initializeReflectable();
  _main($args);
}""");
    return sourceManager.source;
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

      String source = await entryPointAsset.readAsString();
      AssetId dataId =
          entryPointAsset.id.changeExtension("_reflection_data.dart");
      aggregateTransform.addOutput(
          new Asset.fromString(dataId, reflectionWorldSource(world, dataId)));

      String dataFileName = dataId.path.split('/').last;
      aggregateTransform.addOutput(new Asset.fromString(entryPointAsset.id,
          transformMain(entryPointAsset, source, dataFileName)));
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
  if (element.isConst) result |= constants.constAttribute;
  if (element.isFinal) result |= constants.finalAttribute;
  if (element.isStatic) result |= constants.staticAttribute;
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

String formatAsList(Iterable parts) => "[${parts.join(", ")}]";

String formatAsMap(Iterable parts) => "{${parts.join(", ")}}";

/// Returns a String with the code used to build the metadata of [element].
// TODO(sigurdm, 17307): Make this less fragile when the analyzer's
// element-model exposes the metadata in a more friendly way.
String extractMetadataCode(Element element) {
  Iterable<ElementAnnotation> elementAnnotations = element.metadata;
  if (elementAnnotations == null) return "[]";

  List<String> metadataParts = new List<String>();
  // Run through the two iterators in parallel.
  Iterator<Annotation> nodeIterator =
      (element.node as AnnotatedNode).metadata.iterator;
  Iterator<ElementAnnotation> elementIterator = elementAnnotations.iterator;
  while (nodeIterator.moveNext()) {
    bool r = elementIterator.moveNext();
    assert(r);
    Annotation annotationNode = nodeIterator.current;
    ElementAnnotation elementAnnotation = elementIterator.current;
    // Remove the @-sign.
    String source = annotationNode.toSource().substring(1);
    if (elementAnnotation.element is ConstructorElement) {
      // If this is a constructor call, add the otherwise implicit 'const'.
      metadataParts.add("const $source");
    } else {
      metadataParts.add(source);
    }
  }
  return formatAsList(metadataParts);
}
