// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'package:reflectable/src/source_manager.dart';
import 'package:unittest/unittest.dart';

main() {
  SourceManager sm = new SourceManager('testing');
  // Initial indices are preserved:     01234567

  test('replace - internal insertion', () {
    sm.replace(2,2,'___');
    expect(sm.source, 'te___sting');
    // Usable indices: 01   234567
  });

  test('replace - internal deletion', () {
    sm.replace(4,6,'');
    expect(sm.source, 'te___stg');
    // Usable indices: 01   2367
  });

  test('replace - deletion at the end', () {
    sm.replace(6,7,'');
    expect(sm.source, 'te___st');
    // Usable indices: 01   237
  });

  test('replace - enlargement next to prior insertion to the left', () {
    sm.replace(1,2,'**');
    expect(sm.source, 't**___st');
    // Usable indices: 0     237
  });

  test('replace - enlargement next to prior insertion to the right', () {
    sm.replace(2,3,'****');
    expect(sm.source, 't**___****t');
    // Usable indices: 0         37
  });

  test('replace - deletion at the beginning', () {
    sm.replace(0,1,''); 
    expect(sm.source, '**___****t');
    // Usable indices:          37
  });

  test('replace - deletion between insertion and end', () {
    sm.replace(3,4,''); 
    expect(sm.source, '**___****');
    // Usable indices:          7
  });

  test('replace - using the very last available index', () {
    sm.replace(7,7,'ting');
    expect(sm.source, '**___****ting');
    // Usable indices:              7
    sm.replace(7,7,'tes');
    expect(sm.source, '**___****testing');
    // Usable indices:              7
  });

  test('replace - detect overlap', () {
    try {
      sm.replace(3,5,'nope');
      fail('replace - did not detect overlapping replacements');
    } on ArgumentError catch (ok) {}
  });

  test('replace - detect empty overlap', () {
    try {
      sm.replace(5,5,'Insert a lot of extra stuff on top of existing edit');
      fail('replace - did not detect overlapping no-op replacement');
    } on ArgumentError catch (ok) {}
  });
}

