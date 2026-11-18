---
description: Run make chaos (fuzz tests in tests/chaos)
agent: build
---

Run `make chaos` in the project root and show the real output. If a chaos test
fails, report its seed and the repro files under `build/test-results/`, and say
that qa should file it in `docs/bugs.md`. Do not edit anything.
Extra arguments: $ARGUMENTS
