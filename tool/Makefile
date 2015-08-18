# Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

# TODO(eernst) implement: Rewrite this to a Dart script, make is not available
# on all platforms.

RTOOLS=../reflectable/tool
TTOOLS=../test_reflectable/tool

all_except_bottest: get check build test

all: get check build full_test

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
	@./grep_todos --check-consistency
	@./grep_todos --find-unknown-category

build:
	@./makein Building $(RTOOLS) build
	@./makein Building $(TTOOLS) build

test:
	@./makein Testing $(RTOOLS) test
	@./makein Testing $(TTOOLS) test

bot_test:
	@echo '------------------- bottest'
	./bottest

full_test: test bot_test

.PHONY: all_except_bottest all c b t ft check build test bot_test full_test
.PHONY: 
