# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
OPTIONS=--checked --package-root=$(PACKAGE_ROOT)
TEST_DIR=../test
XFORM_DIR=../test/to_be_transformed

all: get check pub_test

g: get

u: upgrade

c: check

t: test

pt: pub_test

get:
	( cd ..; pub get )

upgrade:
	( cd ..; pub upgrade )

check:
	( cd ..; dartanalyzer `find lib test -name \*.dart` )

build:
	@echo "[No actions for build in reflectable]"

test:
	@echo "-------------------- mock_tests"
	@./run_tests

pub_test:
	( cd ..; pub run test )

clean:
	@echo "[No actions for clean in reflectable]"

.PHONY: all g u c b t cb get upgrade clean build check test
