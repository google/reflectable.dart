# Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
# source code is governed by a BSD-style license that can be found in
# the LICENSE file.

PACKAGE_ROOT=../packages
OPTIONS=--checked --package-root=$(PACKAGE_ROOT)

all: get check

g: get

u: upgrade

c: check

get:
	( cd ..; dart pub get )

upgrade:
	( cd ..; dart pub upgrade )

check:
	( cd ..; dart analyze lib )

.PHONY: all g u c b cb get upgrade clean build check
