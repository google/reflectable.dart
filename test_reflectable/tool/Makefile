# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

PACKAGES=../.packages
OPTIONS=

all: clean get build check test

g: get

u: upgrade

c: check

m: measure_output

b: build

t: test

cb: clean get build

get:
	( cd ..; dart pub get )

upgrade:
	( cd ..; dart pub upgrade )

check:
	( cd ..; dart analyze $(OPTIONS) {lib,test}/*.dart )

measure_output: build
	@./measure_output --include-js --include-source-tree --include-unminified

build:
	( cd ..; dart run build_runner build )

test:
	( cd ..; dart test )

clean:
	( rm -rf ../.dart_tool )
	( rm -f ../test/*.reflectable.dart )

.PHONY: all g u c b t ft get upgrade check measure_output build test clean
