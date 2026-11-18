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

## M1: One test room (blocked on M0 gate)

| ID | Task | Owner | Acceptance | Status |
|---|---|---|---|---|
| M1-1 | Pick the test room (vanilla dungeon room) and write `design/rooms/test_room.yaml` | designer | `make validate` | todo |
| M1-2 | Failing tests: unaware takedown works; alert guard takes no damage | qa | tests fail for the right reason | todo |
| M1-3 | 3-state awareness hook (Unaware/Suspicious/Alert) + de-alert timer | engine | M1-2 awareness tests pass | todo |
| M1-4 | Conditional damage on sword hit by awareness | engine | M1-2 damage tests pass | todo |
| M1-5 | Critic review of M1 diff | critic | no blocking findings | todo |
| M1-GATE | Human fun check: one guard + knife for 10 minutes | **human** | `/gate` | todo |
