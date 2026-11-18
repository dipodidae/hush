# HUSH - ROM hack of ALttP (US 1.0). See README.md and AGENTS.md.
PY := .venv/bin/python
SHELL := /usr/bin/env bash

.PHONY: help setup vendor build patch test chaos validate check freespace clean refdump leakcheck leakcheck-control gfx gfx-selftest

help:
	@echo "make setup     install/build local tools into .tools/ and .venv/ (needs apt for cmake, xvfb, libsdl2)"
	@echo "make vendor    clone reference disassemblies into vendor/ (gitignored)"
	@echo "make build     verify ROM, copy to build/hush.sfc, assemble src/main.asm with asar"
	@echo "make patch     build, then create dist/hush.bps with flips"
	@echo "make validate  check design/rooms/*.yaml against the schema"
	@echo "make test      run tests/smoke + tests/solutions headless in MesenCE"
	@echo "make chaos     run tests/chaos fuzz scripts"
	@echo "make check     build + validate + freespace + test (the gate before 'done')"
	@echo "make gfx       regenerate inventory + placeholders from gfx tools (art step; needs vendor/ + build/ref)"
	@echo "make leakcheck scan VRAM/CGRAM dumps of every HUSH scene for vanilla tiles/palettes (fails on a leak)"
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
	$(PY) tools/gfx_compress.py --selftest
	$(PY) tools/run_test.py --suite smoke --suite solutions $(if $(STRICT),--strict)
	$(MAKE) --no-print-directory leakcheck

# vanilla reference (build/ref/, gitignored) for the leak detector and the art tools' metadata
refdump:
	$(PY) tools/gfx_refdump.py

# A0 art step: inventory (needs vendor/) -> placeholders, guides, briefs, palettes, gallery.
# WARNING: this OVERWRITES gfx/src placeholders. Do not run it once you have painted over them.
gfx: refdump
	$(PY) tools/gfx_inventory.py
	$(PY) tools/gfx_placeholder.py
	$(PY) tools/gfx_convert.py check

gfx-selftest:
	$(PY) tools/gfx_compress.py --selftest --full

# scene tests (tests/gfx) dump VRAM/CGRAM of every HUSH scene; the detector fails on any vanilla tile/palette
leakcheck: build refdump
	$(PY) tools/run_test.py --suite gfx
	$(PY) tools/gfx_leakcheck.py

# control: the same scenes on a build WITH vanilla graphics must report leaks (proves the detector works)
leakcheck-control: refdump
	HUSH_GFX=off $(PY) tools/build.py build
	cp build/hush.sfc build/control.sfc
	$(PY) tools/build.py build
	HUSH_ROM=build/control.sfc HUSH_RESULTS=build/test-results-control $(PY) tools/run_test.py --suite gfx
	$(PY) tools/gfx_leakcheck.py --control --results-root build/test-results-control

chaos: build
	$(PY) tools/run_test.py --suite chaos

check: build validate test

clean:
	rm -rf build
