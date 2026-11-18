# HUSH - ROM hack of ALttP (US 1.0). See README.md and AGENTS.md.
PY := .venv/bin/python
SHELL := /usr/bin/env bash

.PHONY: help setup vendor build patch test chaos validate check freespace clean

help:
	@echo "make setup     install/build local tools into .tools/ and .venv/ (needs apt for cmake, xvfb, libsdl2)"
	@echo "make vendor    clone reference disassemblies into vendor/ (gitignored)"
	@echo "make build     verify ROM, copy to build/hush.sfc, assemble src/main.asm with asar"
	@echo "make patch     build, then create dist/hush.bps with flips"
	@echo "make validate  check design/rooms/*.yaml against the schema"
	@echo "make test      run tests/smoke + tests/solutions headless in MesenCE"
	@echo "make chaos     run tests/chaos fuzz scripts"
	@echo "make check     build + validate + freespace + test (the gate before 'done')"
	@echo "make clean     remove build/ (keeps dist/ and rom/)"

setup:
	tools/setup.sh

vendor:
	tools/fetch_vendor.sh

build:
	$(PY) tools/build.py build

patch:
	$(PY) tools/build.py patch

freespace:
	$(PY) tools/check_freespace.py

validate:
	$(PY) tools/validate_specs.py

test: build
	$(PY) tools/run_test.py --suite smoke --suite solutions $(if $(STRICT),--strict)

chaos: build
	$(PY) tools/run_test.py --suite chaos

check: build validate test

clean:
	rm -rf build
