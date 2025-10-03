// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests the new runtime type access feature through callWithReflectedType.

library test_reflectable.test.runtime_type_access_test;

import 'package:test/test.dart';
import 'package:reflectable/reflectable.dart' as r;
import 'package:reflectable/capability.dart';
import 'runtime_type_access_test.reflectable.dart';

// ignore_for_file: omit_local_variable_types

class RuntimeTypeReflectable extends r.Reflectable {
  const RuntimeTypeReflectable()
    : super(typeRelationsCapability, typeCapability, reflectedTypeCapability);
}

const runtimeTypeReflectable = RuntimeTypeReflectable();

@runtimeTypeReflectable
class TestClass {
  String getValue() => 'TestClass';
}

@runtimeTypeReflectable
class GenericClass<T> {
  T? value;

  GenericClass([this.value]);

  String getTypeName() => T.toString();

  T? getValue() => value;

  void setValue(T newValue) {
    value = newValue;
  }
}

@runtimeTypeReflectable
class StringClass extends GenericClass<String> {
  StringClass([super.value]);
}

@runtimeTypeReflectable
class IntClass extends GenericClass<int> {
  IntClass([super.value]);
}

// Helper function to test type access
R testTypeAccess<R>(R Function<T>() callback) {
  return callback<R>();
}

void main() {
  setUp(() {
    initializeReflectable();
  });

  group('Runtime Type Access Tests', () {
    test('callWithReflectedType on simple class', () {
      TestClass instance = TestClass();
      r.InstanceMirror instanceMirror = runtimeTypeReflectable.reflect(
        instance,
      );
      r.ClassMirror classMirror = instanceMirror.type;

      String result = classMirror.callWithReflectedType(<T>() {
        expect(T, equals(TestClass));
        return 'ok';
      });

      expect(result, equals('ok'));
    });

    test('callWithReflectedType on generic class with String', () {
      StringClass instance = StringClass('test');
      r.InstanceMirror instanceMirror = runtimeTypeReflectable.reflect(
        instance,
      );
      r.ClassMirror classMirror = instanceMirror.type;

      bool isString = classMirror.callWithReflectedType<bool>(<T>() {
        return T == StringClass;
      });

      expect(isString, isTrue);
    });

    test('callWithReflectedType on generic class with int', () {
      IntClass instance = IntClass(42);
      r.InstanceMirror instanceMirror = runtimeTypeReflectable.reflect(
        instance,
      );
      r.ClassMirror classMirror = instanceMirror.type;

      String typeName = classMirror.callWithReflectedType<String>(<T>() {
        return T.toString();
      });

      expect(typeName, equals('IntClass'));
    });

    test('callWithReflectedType with Type comparison', () {
      TestClass instance = TestClass();
      r.InstanceMirror instanceMirror = runtimeTypeReflectable.reflect(
        instance,
      );
      r.ClassMirror classMirror = instanceMirror.type;

      Type actualType = classMirror.callWithReflectedType<Type>(<T>() {
        return T;
      });

      expect(actualType, same(TestClass));
      expect(instance.runtimeType, same(actualType));
    });

    test('callWithReflectedType on TypeMirror from reflectType', () {
      r.TypeMirror typeMirror = runtimeTypeReflectable.reflectType(TestClass);

      bool isCorrectType = typeMirror.callWithReflectedType<bool>(<T>() {
        return T == TestClass;
      });

      expect(isCorrectType, isTrue);
    });

    test('callWithReflectedType with generic function behavior', () {
      StringClass stringInstance = StringClass('hello');
      IntClass intInstance = IntClass(123);

      r.InstanceMirror stringMirror = runtimeTypeReflectable.reflect(
        stringInstance,
      );
      r.InstanceMirror intMirror = runtimeTypeReflectable.reflect(intInstance);

      String stringResult = stringMirror.type.callWithReflectedType<String>(
        <T>() {
          return T == StringClass ? 'String specialization' : 'Unexpected';
        },
      );

      String intResult = intMirror.type.callWithReflectedType<String>(<T>() {
        return T == IntClass ? 'Int specialization' : 'Unexpected';
      });

      expect(stringResult, equals('String specialization'));
      expect(intResult, equals('Int specialization'));
    });

    test('callWithReflectedType preserves generic type information', () {
      GenericClass<String> genericString = GenericClass<String>('test');
      r.InstanceMirror instanceMirror = runtimeTypeReflectable.reflect(
        genericString,
      );
      r.ClassMirror classMirror = instanceMirror.type;

      Type genericType = classMirror.callWithReflectedType<Type>(<T>() {
        return T;
      });

      expect(genericType.toString(), contains('GenericClass'));
    });
  });
}
