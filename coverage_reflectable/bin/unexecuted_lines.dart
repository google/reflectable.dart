// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

import 'dart:async';
import 'package:observatory/service_io.dart';
import 'package:observe/observe.dart';

Future<Isolate> isStoppedAtBreakpoint(Isolate isolate) {
  Completer completer = new Completer();
  isolate.vm.getEventStream(VM.kDebugStream).then((stream) {
    var subscription;
    subscription = stream.listen((ServiceEvent event) {
      if (event.kind == ServiceEvent.kPauseBreakpoint) {
        subscription.cancel();
        if (completer != null) {
          // Reload to update isolate.pauseEvent.
          completer.complete(isolate.reload());
          completer = null;
        }
      }
    });
    isolate.reload().then((_) {
      if ((isolate.pauseEvent != null) &&
          (isolate.pauseEvent.kind == ServiceEvent.kPauseBreakpoint)) {
        // Already waiting at a breakpoint.
        subscription.cancel();
        if (completer != null) {
          completer.complete(isolate);
          completer = null;
        }
      }
    });
  });
  return completer.future; // Will complete when the breakpoint is reached.
}

Future<ObservableList> getCoverage(Isolate isolate) async {
  // Wait for the `pub build ..` process to near-finish.
  await isStoppedAtBreakpoint(isolate);

  // Check that we are at the expected location in the program.
  ServiceMap stack = await isolate.getStack();
  assert(stack.type == 'Stack');
  assert(stack['frames'].length >= 2);
  assert(stack['frames'][0].function.name == '<apply_async_body>');
  assert(stack['frames'][0].function.dartOwner.name == 'apply');
  assert(stack['frames'][0].function.dartOwner.dartOwner.name ==
      'TransformerImplementation');

  // Check that we can get a coverage result that looks credible.
  ObservableMap<String, dynamic> coverage =
      await isolate.invokeRpcNoUpgrade('_getCoverage', {});
  assert(coverage['type'] == 'CodeCoverage');
  assert(coverage['coverage'].length > 100);
  return new Future<ObservableList<ObservableMap>>.value(coverage['coverage']);
}

Future main(List<String> args) async {
  int port = int.parse(args[0]);
  String addr = 'ws://localhost:$port/ws';
  WebSocketVM webSocketVM = await new WebSocketVM(new WebSocketVMTarget(addr));
  VM vm = await webSocketVM.load();
  Iterable<Isolate> isolates = await vm.isolates;
  Isolate isolate = isolates.firstWhere((Isolate isolate) =>
      "$isolate".contains("runInIsolate"));
  ObservableList<ObservableMap> coverage = await getCoverage(isolate);
  isolate.resume();
  String oldSource = null, source = null;
  Set<int> unexecutedLines = new Set<int>();
  for (var elm in coverage) {
    source = elm['source'];
    if (source.startsWith("package:reflectable")) {
      if (source != oldSource) {
        if (unexecutedLines.isNotEmpty) {
          print("$oldSource: ${unexecutedLines.toList()..sort()}");
          unexecutedLines.clear();
        }
        oldSource = source;
      }
      List<int> hits = elm['hits'];
      int index = 0;
      for (index = 0; 2 * index < hits.length - 1; index++) {
        if (hits[2 * index + 1] == 0) {
          unexecutedLines.add(hits[2 * index]);
        }
      }
    }
  }
  if (source != null && unexecutedLines.isNotEmpty) {
    print("$source: ${unexecutedLines.toList()..sort()}");
    unexecutedLines.clear();
  }
}
