# Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst): Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
OPTIONS=--package-root=$(PACKAGE_ROOT)
TEST_DIR=../test

all: get check build full_test

g: get

c: check

b: build

t: test

ft: full_test

get:
	( cd ..; pub get )

check:
	dartanalyzer $(OPTIONS) ../{lib,test}/*.dart

build:
	( cd ..; pub build --mode=debug test )

test:
	@echo "-------------------- test"
	@./run_tests

.PHONY: all c b t ft check build test

