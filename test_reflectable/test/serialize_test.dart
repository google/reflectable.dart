library test_reflectable.serialize_test;

import "package:unittest/unittest.dart";
import "package:test_reflectable/serialize.dart";

// By annotating with [Serializable] we indicate that [A] can be serialized
// and reconstructed.
@Serializable()
class A {
  var a;
  var b;
  // The default constructor will be used for creating new instances when
  // deserializing.
  A();

  // This is just a convenience constructor for making the test data.
  A.fromValues(this.a, this.b);

  toString() => "A(a = $a, b = $b)";

  // The == operator is defined for testing if the reconstructed object is the
  // same as the original.
  bool operator ==(other) {
    /// Special case lists.
    equalsHandlingLists(dynamic x, dynamic y) {
      if (x is List) {
        if (y is! List) return false;
        for (int i = 0; i < x.length; i++) {
          if (!equalsHandlingLists(x[i], y[i])) return false;
        }
        return true;
      }
      return x == y;
    }
    return equalsHandlingLists(a, other.a) && equalsHandlingLists(b, other.b);
  }
}

main() {
  test("Round trip test", () {
    Serializer serializer = new Serializer();
    var input = new A.fromValues(
        "one", new A.fromValues(2, [3, new A.fromValues(4, 5)]));
    var out = serializer.serialize(input);
    // Assert that the output of the serialization is equals to
    // the expected map:
    expect(out, {
      "type": "test_reflectable.serialize_test.A",
      "fields": {
        "a": {"type": "String", "val": "one"},
        "b": {
          "type": "test_reflectable.serialize_test.A",
          "fields": {
            "a": {"type": "num", "val": 2},
            "b": {
              "type": "List",
              "val": [
                {"type": "num", "val": 3},
                {
                  "type": "test_reflectable.serialize_test.A",
                  "fields": {
                    "a": {"type": "num", "val": 4},
                    "b": {"type": "num", "val": 5}
                  }
                }
              ]
            }
          }
        }
      }
    });
    // Assert that deserializing the output gives a result that is equal to the
    // original input.
    expect(serializer.deserialize(out), input);
  });
}
