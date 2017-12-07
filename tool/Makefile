# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

RTOOLS=../reflectable/tool
TTOOLS=../test_reflectable/tool

all: get clean build check test

g: get

u: upgrade

c: check

m: measure_output

b: build

t: test

cb: clean build

get:
	@./makein Getting $(RTOOLS) get
	@./makein Getting $(TTOOLS) get

upgrade:
	@./makein Getting $(RTOOLS) upgrade
	@./makein Getting $(TTOOLS) upgrade

check:
	@./makein Checking $(RTOOLS) check
	@./makein Checking $(TTOOLS) check
	@./grep_debug
	@./grep_todos --check-consistency
	@./grep_todos --find-unknown-category

measure_output:
	@./makein Measuring $(TTOOLS) measure_output

build:
	@./makein Building $(RTOOLS) build
	@./makein Building $(TTOOLS) build

test:
	@./makein Testing $(RTOOLS) test
	@./makein Testing $(TTOOLS) test

clean:
	@./makein Cleaning $(RTOOLS) clean
	@./makein Cleaning $(TTOOLS) clean

.PHONY: all g u c b t get upgrade clean build check test measure_output
