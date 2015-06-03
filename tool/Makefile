# Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst): Rewrite this to a Dart script, make is not available
# on all platforms.

RTOOLS=../reflectable/tool
TTOOLS=../test_reflectable/tool

all: check build full_test

g: get

c: check

b: build

t: test

bt: bot_test

ft: full_test

get:
	@./makein Getting $(RTOOLS) get
	@./makein Getting $(TTOOLS) get

check:
	@./makein Checking $(RTOOLS) check
	@./makein Checking $(TTOOLS) check

build:
	@./makein Building $(RTOOLS) build
	@./makein Building $(TTOOLS) build

test:
	@./makein Testing $(RTOOLS) test
	@./makein Testing $(TTOOLS) test

bot_test:
	@echo '------------------- bottest'
	./bottest --preserve-output

full_test: test bot_test

.PHONY: all c b t ft check build test bot_test full_test

