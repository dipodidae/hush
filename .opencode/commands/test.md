---
description: Run make build then make test, show the pass/fail table
agent: build
---

Run `make build` then `make test` in the project root. Show the final pass/fail
table verbatim. Call out every SKIP and why (missing savestate
`tests/states/test_room.mss` is expected until the human makes it). On any FAIL
or TIMEOUT, read `build/test-results/<test>/stdout.txt` and summarise the cause.
Do not edit anything. Extra arguments: $ARGUMENTS
