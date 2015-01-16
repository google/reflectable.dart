
DARTLIBS=lib/mirror.dart lib/reflectable.dart lib/capability.dart \
	test/common_dynamic.dart test/common_static.dart \
	test/reflector_dynamic.dart test/reflector_static.dart \
	test/my_reflectable.dart test/my_reflectable_s.dart \
	test/a.dart test/b.dart test/c.dart \
	test/a_s.dart test/b_s.dart test/c_s.dart \
	test/reflectee1.dart test/reflectee2.dart

PACKAGEROOT=$(HOME)/lang/dart/polymer/projects/test001/packages

analyze:
	dartanalyzer --no-hints --package-root=$(PACKAGEROOT) $(DARTLIBS)

run: run_dynamic run_static

run_common: run_common_dynamic run_common_static

run_reflector: run_reflector_dynamic run_reflector_static

run_dynamic: run_common_dynamic run_reflector_dynamic

run_static: run_common_static run_reflector_static

run_common_dynamic:
	dart --package-root=$(PACKAGEROOT) test/common_dynamic.dart

run_common_static:
	dart --package-root=$(PACKAGEROOT) test/common_static.dart

run_reflector_dynamic:
	dart --package-root=$(PACKAGEROOT) test/reflector_dynamic.dart

run_reflector_static:
	dart --package-root=$(PACKAGEROOT) test/reflector_static.dart

%.png: %.dot
	dot -Tpng $< >$@
	xdg-open $@

