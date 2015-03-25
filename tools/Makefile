# Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst): Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
ANALYZER_OPTIONS="--package-root=$(PACKAGE_ROOT)"

all: check build test

c: check

b: build

t: test

check:
	dartanalyzer $(ANALYZER_OPTIONS) ../{lib,test}/**/*.dart

build:
	( cd ..; pub build --mode=debug test )

test:
	../test/checktransforms_test.dart
	dart --package-root=../packages ../test/source_manager_test.dart
	@echo '------------------------------------------------------------'
	./bottest --preserve-output

.PHONY: all c b t check build test

