/// A minimal serialization library, just intended to give an
/// example of how package:reflectable can be used
/// Doesn't check for cycles in the serialized data, and is not customizable
/// at all.
library test_reflectable.serialize;

import "package:reflectable/reflectable.dart";

class Serializable extends Reflectable {
  const Serializable() : super(const [
        invokeInstanceMembersCapability,
        const InvokeConstructorCapability("")
      ]);
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
  final Map<String, ClassMirror> classes = new Map<String, ClassMirror>();

  Serializer() {
    // `Serializable` inherits support for finding all classes carrying itself
    // as metadata from `Reflectable`, and they are exactly the classes that we
    // wish to provide serialization support for.
    for (ClassMirror classMirror in serializable.annotatedClasses) {
      classes[classMirror.qualifiedName] = classMirror;
    }
  }

  List<VariableMirror> _getPublicFields(ClassMirror classMirror) {
    // TODO(sigurdm): Handle fields in superclasses.
    return new List<VariableMirror>.from(classMirror.declarations.values.where(
        (DeclarationMirror declaration) {
      return declaration is VariableMirror && !declaration.isPrivate;
    }));
  }

  Map<String, dynamic> serialize(Object o) {
    if (o is num) {
      return {"type": "num", "val": o};
    }
    if (o is List) {
      return {"type": "List", "val": o.map(serialize).toList()};
    }
    if (o is String) {
      return {"type": "String", "val": o};
    }
    Map result = {};
    InstanceMirror im = serializable.reflect(o);
    ClassMirror classMirror = im.type;
    result["type"] = classMirror.qualifiedName;
    result["fields"] = {};
    for (VariableMirror field in _getPublicFields(classMirror)) {
      result["fields"][field.simpleName] =
          serialize(im.invokeGetter(field.simpleName));
    }
    return result;
  }

  Object deserialize(Map<String, dynamic> m) {
    if (m["type"] == "num") {
      return m["val"];
    }
    if (m["type"] == "String") {
      return m["val"];
    }
    if (m["type"] == "List") {
      return m["val"].map(deserialize).toList();
    }

    ClassMirror classMirror = classes[m["type"]];
    Object instance = classMirror.newInstance("", []);
    InstanceMirror im = serializable.reflect(instance);
    m["fields"].forEach((name, value) {
      im.invokeSetter(name, deserialize(value));
    });
    return instance;
  }
}
