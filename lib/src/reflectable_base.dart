// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.reflectable_base;

import '../capability.dart';

/// This class enables sharing of the basic machinery associated with the
/// "varargs" style construction supported by [Reflectable] in both
/// `reflectable.dart` and `static_reflectable.dart`, i.e., the ability to
/// give arguments directly as in `super(myCap0, myCap1)` rather than
/// using one list argument: `const <ReflectCapability>[myCap0, myCap1]`. The
/// approach only works up to a fixed number of arguments (in this case: 10)
/// so the ability to give even longer argument lists has been preserved using
/// a named constructor:
/// `super.fromList(const <ReflectCapability>[myCap0, myCap1])`
class ReflectableBase {
  // Fields holding capabilities; we use discrete fields rather than a list
  // of fields because this allows us to use a syntax similar to a varargs
  // invocation as the superinitializer (omitting `<ReflectCapability>[]` and
  // directly giving the elements of that list as constructor arguments).
  // This will only work up to a fixed number of arguments (we have chosen
  // to support at most 10 arguments), and with a larger number of arguments
  // the fromList constructor must be used.

  final bool _capabilitiesGivenAsList;

  final ReflectCapability _cap0, _cap1, _cap2, _cap3, _cap4;
  final ReflectCapability _cap5, _cap6, _cap7, _cap8, _cap9;
  final List<ReflectCapability> _capabilities;

  /// Specifies limits on the support for reflective operations on instances
  /// of classes having an instance of this ReflectableBase as metadata.
  List<ReflectCapability> get capabilities {
    if (_capabilitiesGivenAsList) return _capabilities;
    var result = <ReflectCapability>[];
    void add(ReflectCapability cap) {
      if (cap != null) result.add(cap);
    }

    add(_cap0);
    add(_cap1);
    add(_cap2);
    add(_cap3);
    add(_cap4);
    add(_cap5);
    add(_cap6);
    add(_cap7);
    add(_cap8);
    add(_cap9);
    return result;
  }

  /// Const constructor, to enable usage as metadata, allowing for varargs
  /// style invocation with up to ten arguments.
  const ReflectableBase(
      [this._cap0,
      this._cap1,
      this._cap2,
      this._cap3,
      this._cap4,
      this._cap5,
      this._cap6,
      this._cap7,
      this._cap8,
      this._cap9])
      : _capabilitiesGivenAsList = false,
        _capabilities = null;

  const ReflectableBase.fromList(this._capabilities)
      : _capabilitiesGivenAsList = true,
        _cap0 = null,
        _cap1 = null,
        _cap2 = null,
        _cap3 = null,
        _cap4 = null,
        _cap5 = null,
        _cap6 = null,
        _cap7 = null,
        _cap8 = null,
        _cap9 = null;
}
