// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'package:reflectable/src/source_manager.dart';
import 'package:unittest/unittest.dart';

main() {
  test('source_manager', () {
    // Initial indices are preserved:                01234567
    SourceManager sourceManager = new SourceManager('testing');

    void chk(String expectedSource, String reason) {
      expect(sourceManager.source, expectedSource, reason: reason);
    }

    sourceManager.replace(2,2,'__');
    // Usable indices:
    //   01  234567
    chk('te__sting', 'internal insertion');
    
    sourceManager.replace(2,2,'-');
    //   01   234567
    chk('te__-sting', 'internal insertion, same location');

    sourceManager.replace(4,6,'');
    //   01   2367
    chk('te__-stg', 'internal deletion');

    sourceManager.replace(6,7,'');
    //   01   237
    chk('te__-st', 'deletion at the end');

    sourceManager.replace(1,2,'**');
    //   0     237
    chk('t**__-st', 'enlargement next to prior insertion to the left');

    sourceManager.replace(2,3,'****');
    //   0         37
    chk('t**__-****t', 'enlargement next to prior insertion to the right');

    sourceManager.replace(0,1,'');
    //            37
    chk('**__-****t', 'deletion at the beginning');

    sourceManager.replace(3,4,'');
    //            7
    chk('**__-****', 'deletion between insertion and end');

    sourceManager.replace(7,7,'tes');
    //               7
    chk('**__-****tes', 'using the very last available index');

    sourceManager.replace(7,7,'ting');
    //                   7
    chk('**__-****testing', 'using the very last available index');

    expect(() { sourceManager.replace(3,5,'nope'); },
           throwsArgumentError,
           reason: 'detect overlap');

    expect(() { sourceManager.replace(5, 5, 'Insert into existing edit'); },
           throwsArgumentError,
           reason: 'detect empty overlap');
  });
}
