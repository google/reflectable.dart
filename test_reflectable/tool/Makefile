# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGES=../.packages
OPTIONS=--packages=$(PACKAGES)
TEST_DIR=../test

all: get check build test

g: get

u: upgrade

c: check

m: measure_output

b: build

t: test

cb: clean build

get:
	( cd ..; pub get --no-packages-dir )

upgrade:
	( cd ..; pub upgrade --no-packages-dir )

check:
	dartanalyzer $(OPTIONS) ../{lib,test}/*.dart

measure_output: build
	@./measure_output --include-js --include-source-tree --include-unminified

build:
	( cd ..; tool/reflectable_builder test/*_test.dart)
	( cd ..; pub build --mode=debug test)

test:
	@echo "-------------------- test"
	@./run_tests

clean:
	( rm -rf ../.dart_tool ../build )
	( rm -f ../test/*.reflectable.dart )

.PHONY: all g u c b t ft get upgrade check measure_output build test clean
