# HUSH backlog

Owned by the `director`. One row per task. Status: todo / doing / blocked / done.
Acceptance is a command that must pass or a named human check.

## M0: Harness  (current)

| ID | Task | Owner | Acceptance | Status |
|---|---|---|---|---|
| M0-1 | Toolchain: asar, flips, MesenCE, xvfb, venv | engine/human | `make setup` clean; versions print | done |
| M0-2 | Repo scaffold, .gitignore, legal rules in AGENTS.md | director | `git check-ignore` covers rom/, build/, *.sfc, .env.local | done |
| M0-3 | Build pipeline + freespace ledger check | engine | `make build` ok; negative cases fail loudly | done |
| M0-4 | Headless test harness + 3 smoke tests | qa | `make test`: boot PASS; read_link/determinism PASS with a state | done (state-dependent tests SKIP until M0-6) |
| M0-5 | Room spec schema + `make validate` | designer | `make validate` ok | done |
| M0-6 | Human makes `tests/states/test_room.mss` | **human** | `make test STRICT=1` all PASS | **todo** |
| M0-7 | Human confirms ROM verifies and tools run | **human** | `make build`, `make test` | **todo** |
| M0-GATE | Human approves M0 | **human** | `/gate` | **todo** |

## A0: Placeholder overhaul  (ready for gate)

| ID | Task | Owner | Acceptance | Status |
|---|---|---|---|---|
| A0-1 | Format research + inventory (`docs/gfx/formats.md`, `INVENTORY.md`) | engine/art | `python tools/gfx_inventory.py` | done |
| A0-2 | Placeholder generator, guides, briefs, gallery | art | `make gfx`; `build/gfx_gallery.html` | done |
| A0-3 | Insertion pipeline + compressor + ledger rows | engine | `make build`; `gfx_compress.py --selftest` | done |
| A0-4 | Vanilla leak detector + scene tests | qa | `make leakcheck` clean; `make leakcheck-control` finds leaks | done |
| A0-5 | Boot straight to a readable title (intro skip hook, HUSH logo placeholder) | engine/art | `tests/gfx/scenes_boot.lua` | done |
| A0-6 | A0 report | director | `docs/gfx/A0_report.md` | done |
| A0-7 | Critic review of the A0 diff | critic | no blocking findings | **todo** |
| A0-GATE | Human reviews gallery, report, leak output | **human** | `/gate` | **todo** |
| A0-CUT | Engine: remove overworld / map / attract / mirror warp (see report) | engine | after the gate | todo |

## M1: One test room (blocked on M0 gate)

| ID | Task | Owner | Acceptance | Status |
|---|---|---|---|---|
| M1-1 | Pick the test room (vanilla dungeon room) and write `design/rooms/test_room.yaml` | designer | `make validate` | todo |
| M1-2 | Failing tests: unaware takedown works; alert guard takes no damage | qa | tests fail for the right reason | todo |
| M1-3 | 3-state awareness hook (Unaware/Suspicious/Alert) + de-alert timer | engine | M1-2 awareness tests pass | todo |
| M1-4 | Conditional damage on sword hit by awareness | engine | M1-2 damage tests pass | todo |
| M1-5 | Critic review of M1 diff | critic | no blocking findings | todo |
| M1-GATE | Human fun check: one guard + knife for 10 minutes | **human** | `/gate` | todo |

## Build pass (gates waived by the human)

| ID | Task | Status |
|---|---|---|
| E1-E7 | Foundation, guard AI, damage, fast transitions, audio, ending, bug fixes | done |
| D1 | 21 room specs (r01-r20, final) | done |
| Q1 | 21 solution replays, 108 must-not cases, chaos suite (6 scripts) | done |
| A1 | Colour/art pass: floors, decor, HUD, menu, guards, Link, tools, title | done |
| B-006 | Lag with 5-6 guards + pot/dart spam | open (needs ~190 free bytes in bank $07) |
| M5 | `dist/hush.bps` | built; human approval pending |
