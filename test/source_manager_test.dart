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

    // Usable indices:                           01  234567
    sourceManager.replace(2,2,'__');         // 'te__sting'
    // Usable indices:                           01   234567
    sourceManager.replace(2,2,'-');          // 'te-__sting'
    chk('te-__sting', 'internal insertion, repeated');

    // Usable indices:                           01   2367
    sourceManager.replace(4,6,'');           // 'te-__stg'
    chk('te-__stg', 'internal deletion');

    // Usable indices:                           01   237
    sourceManager.replace(6,7,'');           // 'te-__st'
    chk('te-__st', 'deletion at the end');

    // Usable indices:                           0     237
    sourceManager.replace(1,2,'**');         // 't**-__st'
    chk('t**-__st', 'enlargement next to prior insertion to the left');

    // Usable indices:                           0         37
    sourceManager.replace(2,3,'****');       // 't**-__****t'
    chk('t**-__****t', 'enlargement next to prior insertion to the right');

    // Usable indices:                                    37
    sourceManager.replace(0,1,'');           // '**-__****t'
    chk('**-__****t', 'deletion at the beginning');

    // Usable indices:                                    7
    sourceManager.replace(3,4,'');           // '**-__****'
    chk('**-__****', 'deletion between insertion and end');

    // Usable indices:                                    7
    sourceManager.replace(7,7,'ting');       // '**-__****ting'
    chk('**-__****ting', 'using the very last available index');

    // Usable indices:                                    7
    sourceManager.replace(7,7,'tes');        // '**-__****testing'
    chk('**-__****testing', 'using the very last available index');

    expect(() { sourceManager.replace(3,5,'nope'); }, 
           throwsArgumentError,
           reason: 'detect overlap');

    expect(() { sourceManager.replace(5, 5, 'Insert into existing edit'); },
           throwsArgumentError,
           reason: 'detect empty overlap');
  });
}
