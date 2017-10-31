# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
OPTIONS=--checked --package-root=$(PACKAGE_ROOT)
TEST_DIR=../test
XFORM_DIR=../test/to_be_transformed

all: get clean build check test

g: get

u: upgrade

c: check

b: build

t: test

cb: clean build

get:
	( cd ..; pub get --no-packages-dir )

upgrade:
	( cd ..; pub upgrade --no-packages-dir )

check:
	( cd ..; dartanalyzer `find lib bin test -name \*.dart` )

build:
	( cd ..; pub build --mode=debug test )

test:
	@echo "-------------------- mock_tests"
	@./run_mock_tests

clean:
	@echo "[No actions for clean in reflectable]"

.PHONY: all g u c b t cb get upgrade clean build check test
