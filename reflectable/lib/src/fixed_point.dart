// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

abstract class FixedPoint<T> {
  Iterable<T> successors(final T element);

  /// Expands the given `initialSet` until a fixed point is reached.
  /// Uses [successors] on each element to find the expansion at each
  /// step, and terminates when the set has the closure property that
  /// every successor of an included element is itself included.
  /// Finally it also returns the expanded `initialSet`.
  Set<T> expand(final Set<T> initialSet) {
    // Invariant: Every element that may have successors is in `workingSet`.
    Set<T> workingSet = initialSet;
    bool isNew(T element) => !initialSet.contains(element);
    while (workingSet.isNotEmpty) {
      Set<T> newSet = new Set<T>();
      void addSuccessors(T element) =>
          successors(element).where(isNew).forEach(newSet.add);
      workingSet.forEach(addSuccessors);
      initialSet.addAll(newSet);
      workingSet = newSet;
    }
    return initialSet;
  }

  /// Expands the given `initialSet` a single time, adding the immediate
  /// [successors] to it. Then it returns the expanded `initialSet`.
  Set<T> singleExpand(final Set<T> initialSet) {
    Set<T> newSet = new Set<T>();
    void addSuccessors(T t) => successors(t).forEach(newSet.add);
    initialSet.forEach(addSuccessors);
    initialSet.addAll(newSet);
    return initialSet;
  }
}
