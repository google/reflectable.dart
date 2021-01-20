/// A minimal serialization library, just intended to give an
/// example of how package:reflectable can be used
/// Doesn't check for cycles in the serialized data, and is not customizable
/// at all.
/// Only serializes public fields.
library test_reflectable.serialize;

import 'package:reflectable/reflectable.dart';

// ignore_for_file: omit_local_variable_types

class Serializable extends Reflectable {
  const Serializable()
      : super(instanceInvokeCapability, const NewInstanceCapability(r'^$'),
            declarationsCapability);
}

/// Serializes instances of classes marked with a `Serializable`
/// annotation to a map-based format.
/// All public fields are serialized together with the qualified name of the
/// class.
/// [int], [String] and [List] are supported as primitive types.
/// When de-serializing, the default constructor of the class is used to
/// construct a new empty instance, and all the fields are set.
class Serializer {
  var serializable = const Serializable();
  final Map<String, ClassMirror> classes = <String, ClassMirror>{};

  Serializer() {
    // `Serializable` inherits support for finding all classes carrying itself
    // as metadata from `Reflectable`, and they are exactly the classes that we
    // wish to provide serialization support for.
    for (var classMirror in serializable.annotatedClasses) {
      classes[classMirror.qualifiedName] = classMirror;
    }
  }

  /// Returns the names of all the public non-final fields in the class
  /// represented by [classMirror].
  List<String> _getPublicFieldNames(ClassMirror classMirror) {
    Map<String, MethodMirror> instanceMembers = classMirror.instanceMembers;
    return instanceMembers.values
        .where((MethodMirror method) {
          return method.isGetter &&
              method.isSynthetic &&
              // Check that the setter also exists.
              instanceMembers[method.simpleName + '='] != null &&
              !method.isPrivate;
        })
        .map((MethodMirror method) => method.simpleName)
        .toList();
  }

  Map<String, dynamic> serialize(Object? o) {
    if (o is num) {
      return {'type': 'num', 'val': o};
    }
    if (o is List) {
      return {'type': 'List', 'val': o.map(serialize).toList()};
    }
    if (o is String) {
      return {'type': 'String', 'val': o};
    }
    Map<String, dynamic> result = {};
    InstanceMirror im = serializable.reflect(o!);
    ClassMirror classMirror = im.type;
    result['type'] = classMirror.qualifiedName;
    result['fields'] = {};
    for (var fieldName in _getPublicFieldNames(classMirror)) {
      result['fields'][fieldName] = serialize(im.invokeGetter(fieldName));
    }
    return result;
  }

  Object deserialize(Map<String, dynamic> m) {
    if (m['type'] == 'num') {
      return m['val'];
    }
    if (m['type'] == 'String') {
      return m['val'];
    }
    if (m['type'] == 'List') {
      return m['val'].map(deserialize).toList();
    }

    ClassMirror classMirror = classes[m['type']!]!;
    Object instance = classMirror.newInstance('', []);
    InstanceMirror im = serializable.reflect(instance);
    m['fields']!.forEach((name, value) {
      im.invokeSetter(name, deserialize(value));
    });
    return instance;
  }
}
