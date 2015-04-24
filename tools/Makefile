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

c: check

b: build

t: test

ft: full_test

check:
	dartanalyzer $(OPTIONS) ../{lib,test}/**/*.dart

build:
	( cd ..; pub build --mode=debug test )

test:
	@echo "-------------------- checktransforms_test"
	@$(TEST_DIR)/checktransforms_test.dart
	@echo "-------------------- source_manager_test"
	@dart $(OPTIONS) $(TEST_DIR)/source_manager_test.dart
	@echo "-------------------- path_helper_test"
	@dart $(OPTIONS) $(TEST_DIR)/path_helper_test.dart
	@./run_transformation_tests

full_test: test
	@echo '------------------- bottest'
	./bottest --preserve-output

.PHONY: all c b t ft check build test full_test

