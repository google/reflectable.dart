// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// A [SourceManager] is created with a given [String] of text,
/// [source], typically a piece of source code.  Initially, [source]
/// contains elements which are addressable in terms of known indices,
/// based on an external source of information such as a [Resolver] and
/// a number of instances of [LibraryElement], [ClassElement], etc.  We
/// may then update the [source] using the [replace] method, and the
/// [SourceManager] will perform the replacement after having
/// "translated" the indices for the update according to earlier
/// invocations of [replace].  If the first [replace] operation replaces
/// the substring of [source] at indices `k..m` (that is, the characters
/// at `source[k]` up to `source[m-1]`) by a string of length `m - k +
/// n` (so the net change in length is that we added `n` characters),
/// then subsequent [replace] operations will translate indices lower
/// than `m - 1 + n` to themselves, and indices from `m + n` and up by
/// adding `n` to them.  This means that the "old" indices known by the
/// external source of information will remain pointing to the same text
/// after translation.
class SourceManager {
  String _source;
  final int _initialLength;
  List<_SourceEdit> _edits;

  SourceManager(String source):
      _source = source,
      _initialLength = source.length,
      _edits = new List<_SourceEdit>();

  /// Provides public read-only access to [_source].
  String get source => _source;

  /// Replaces the contents of [source] in the range from and including
  /// [oldLowIndex] to but excluding [oldHighIndex] by the given
  /// [newSubstring].  The indices are interpreted relative to the
  /// initial [source], i.e., if it is growing or shrinking over time
  /// due to replacements of a range 'k..k+n' by a [String] of a length
  /// different from 'n'.  Note that an [ArgumentError] exception is
  /// thrown if we do not have `0 <= oldLowIndex <= oldHighIndex <= N`
  /// where `N` is the length of the initial value of [source], and also
  /// if a [replace] operation is attempted where the range
  /// 'oldLowIndex..oldHighIndex' overlaps the range of a previous
  /// [replace] operation on this [SourceManager].
  void replace(int oldLowIndex, int oldHighIndex, String newSubstring) {
    // Ensure that the area to replace is within range.
    if (oldLowIndex < 0 ||
        oldLowIndex > oldHighIndex ||
        oldHighIndex > _initialLength) {
      String msg = "oldLowIndex == $oldLowIndex or "
          "oldHighIndex == $oldHighIndex is out of "
          "range [0..$_initialLength].";
      throw new ArgumentError(msg);
    }
    // Check for overlaps and compute the total offset.
    int offset = 0;
    for (_SourceEdit edit in _edits) {
      if (edit.oldLowIndex == edit.oldHighIndex &&
          edit.oldHighIndex == oldLowIndex) {
        // Insertions at the same index will end up in insertion order.
        offset += edit.newLength;
      } else if (oldHighIndex <= edit.oldLowIndex) {
        // The entire target area is to the left of [edit],
        // which is OK and causes no offset adjustment.
      } else if (oldLowIndex < edit.oldHighIndex) {
        // Overlaps, since `oldHighIndex >= edit.oldLowIndex`.
        String msg = "[oldLowIndex..oldHighIndex] == "
            "[$oldLowIndex..$oldHighIndex] overlaps previous replacement "
            "range [${edit.oldLowIndex}..${edit.oldHighIndex}].";
        throw new ArgumentError(msg);
      } else {
        // The entire target range is to the right of [edit],
        // since `oldLowIndex >= edit.oldHighIndex`; but in
        // this case we must adjust the offset.
        offset += edit.newLength - (edit.oldHighIndex - edit.oldLowIndex);
      }
    }
    // Since the new edit does not overlap any of the previous
    // [_edits], the same [offset] applies to every character in
    // the target area, so we simply add the offset to the
    // area being removed
    String prefix = _source.substring(0, oldLowIndex + offset);
    String suffix = _source.substring(oldHighIndex + offset);
    _source = "$prefix$newSubstring$suffix";
    // Register this [replace] operation.
    _edits.add(new _SourceEdit(oldLowIndex,
                               oldHighIndex,
                               newSubstring.length));
  }

  insert(int index, String newSubstring) {
    replace(index, index, newSubstring);
  }
}

/// Auxiliary class, used to keep track of the [replace] operations
/// performed by a SourceManager.
class _SourceEdit {
  int oldLowIndex;
  int oldHighIndex;
  int newLength;
  _SourceEdit(this.oldLowIndex, this.oldHighIndex, this.newLength);
}

