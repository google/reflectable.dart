# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
OPTIONS=--checked --package-root=$(PACKAGE_ROOT)
TEST_DIR=../test
XFORM_DIR=../test/to_be_transformed

all: get check build test

g: get

u: upgrade

c: check

b: build

t: test

get:
	( cd ..; pub get )

upgrade:
	( cd ..; pub upgrade )

check:
	( cd ..; dartanalyzer `find test lib -name \*.dart` )

build:
	( cd ..; pub build --mode=debug test )

test:
	@echo "-------------------- mock_tests"
	@./run_mock_tests

.PHONY: all g u c b t ft get upgrade check build test

