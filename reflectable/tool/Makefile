# Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst): Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
OPTIONS=--package-root=$(PACKAGE_ROOT)
TEST_DIR=../test
XFORM_DIR=../test/to_be_transformed

all: check build full_test

g: get

c: check

b: build

t: test

ft: full_test

get:
	( cd ..; pub get )

check:
	( cd ..; dartanalyzer {lib,test}/{,*/}*.dart )

build:
	( cd ..; pub build --mode=debug test )

test:
	@echo "-------------------- source_manager_test"
	@dart $(OPTIONS) $(TEST_DIR)/source_manager_test.dart
	@echo "-------------------- mock_tests"
	@./run_mock_tests

.PHONY: all c b t ft check build test

