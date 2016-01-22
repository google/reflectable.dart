# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGE_ROOT=../packages
OPTIONS=--package-root=$(PACKAGE_ROOT)
TEST_DIR=../test

all: get check build test

g: get

u: upgrade

c: check

m: measure_output

b: build

t: test

get:
	( cd ..; pub get )

upgrade:
	( cd ..; pub upgrade )

check:
	dartanalyzer $(OPTIONS) ../{lib,test}/*.dart

measure_output: build
	@./measure_output --include-js --include-source-tree --include-unminified

build:
	( cd ..; pub build --mode=debug test )

test:
	@echo "-------------------- test"
	@./run_tests

.PHONY: all g u c b t ft get upgrade check measure_output build test

