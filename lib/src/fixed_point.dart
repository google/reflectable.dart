// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'dart:async';

abstract class FixedPoint<T> {
  Future<Iterable<T>> successors(final T element);

  /// Expands the given `initialSet` until a fixed point is reached.
  /// Uses [successors] on each element to find the expansion at each
  /// step, and terminates when the set has the closure property that
  /// every successor of an included element is itself included.
  /// Finally it also returns the expanded `initialSet`.
  Future<Set<T>> expand(final Set<T> initialSet) async {
    // Invariant: Every element that may have successors is in `workingSet`.
    var workingSet = initialSet;
    bool isNew(T element) => !initialSet.contains(element);
    while (workingSet.isNotEmpty) {
      var newSet = <T>{};
      Future<void> addSuccessors(T element) async =>
          (await successors(element)).where(isNew).forEach(newSet.add);
      for (var t in workingSet) {
        await addSuccessors(t);
      }
      initialSet.addAll(newSet);
      workingSet = newSet;
    }
    return initialSet;
  }

  /// Expands the given `initialSet` a single time, adding the immediate
  /// [successors] to it. Then it returns the expanded `initialSet`.
  Future<Set<T>> singleExpand(final Set<T> initialSet) async {
    var newSet = <T>{};
    Future<void> addSuccessors(T t) async =>
        (await successors(t)).forEach(newSet.add);
    for (var t in initialSet) {
      await addSuccessors(t);
    }
    initialSet.addAll(newSet);
    return initialSet;
  }
}
