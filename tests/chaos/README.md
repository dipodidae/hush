# Chaos tests (fuzz)

`make chaos` runs every `tests/chaos/*.lua` through `tools/run_test.py --suite chaos` (about 4.5 minutes in total).
Everything is **seeded and deterministic**: a seed means the same inputs on every run, the game itself is deterministic
(`chaos_determinism.lua` proves it), so every failure comes with a repro.

| Script | Scenario | Runs |
|---|---|---|
| `chaos_mash.lua` | **(a) random button mashing**: all 12 buttons with independent random hold lengths, ~2000 frames from a fresh entry of the room (cold boot -> new game -> in-memory snapshot -> synced debug jump). Rooms r01 r02 r03 r04 r05 r06 r07 r08 r10 r11 r12 r14 r17 r19 r20 final (1 to 6 guards, dark and lit, the knife / darts / pots rooms, a pre-selected tool in some) | 22 seeds |
| `chaos_menu.lua` | **(b) item-menu mashing**: START / SELECT / Y / X (+ d-pad taps) at random. Afterwards every button is released and a human recovery (B, A, START taps) must give control back within 600 frames, the d-pad must move Link again, START must open and close the menu | 6 seeds |
| `chaos_churn.lua` | **(c) churn**: 50 rapid room jumps (`$7EC901` written idle, in the menu, during a restart, mid-load, twice in a row) and 50 caught-restarts in the 5-guard room (poke of `hush_caught`, real contact, with a pot / an arrow in flight, with the cloud up, mid-mash). After every settle the room must look like the first time (sprite count, no ancilla, no cloud, same OAM count, Link at the start, full brightness); frame counts are bounded (restart <= 40, full load <= 700) | 2 runs |
| `chaos_spam.lua` | **(d) pot / dart spam**: Y every few frames, tool flipped between bow and pots (while no item is in use, and through the real item menu every ~150 frames), ammo refilled whenever it runs out, Link walking at random. Ancilla ids, cloud timer / position, "a guard inside the cloud is not suspicious / alert", and after the spam stops all ancilla slots and the cloud must clear within 900 frames. Reports `lagged=` per seed | 6 seeds |
| `chaos_determinism.lua` | **(e) determinism**: the same seed + inputs twice: hash of the HUSH state every 100 frames + the whole 128 KiB WRAM at the end must be identical (3 mash runs + 1 spam run) | 4 x 2 runs |
| `chaos_edge.lua` | **(f) frame-offset edges**: knife / dart on every frame offset around the moment a guard first sees Link (k = -6 .. +8); two guards alerting in the same frame (r14 corridor) -> exactly one restart; exit versus caught poke at offsets -4 .. +4 -> never a half state | 41 runs |

Total: 22 + 6 + 2 + 6 + 4 + 41 runs; 20+ mash / spam seeds over the 5-6 guard rooms (r20, final) and the rooms with each tool.

## Invariants (`tests/chaos/lib/chaos.lua`, checked after every frame)

* **Module**: only 5 / 6 (load), 7 (play), `$0E` (item menu). In the last room anything is tolerated for a bounded time after the exit
  (the ending), as long as the game returns to the title and a new game starts (`resume_after_ending`). Module `$17` (SELECT "Save and
  Quit") is the known issue B-002 (fixed by E6 on the current build): tolerated, counted as `quits=`, `HUSH_CHAOS_STRICT=1` makes it fail.
  `hush_room` only changes by +1 (an exit), to a room the run itself asked for (`run:jump`), or on a new game after the ending.
* **Play** (module 7, submodule 0): camera `$E2/$E8` = room base + window; Link inside the 256 x 224 window and the four corners of his
  collision box never in a solid cell of `$7F2000`; health full; Link's layer constant.
* **Sprites**: only the room's guards (type `$41`, state 9, or 0 once killed; spawning state 8 right after a load / restart), nothing in
  a slot >= #guards, `spr_aware` 0..3, guards not outside the window, awareness transitions only along the spec (0->1, 0->2, 0->3, 1->0,
  1->2, 2->0, 3->0), a Suspicious / Alert guard never dies, no guard comes back to life without a restart. A guard whose centre is in a
  wall tile is the known issue B-005 (counted as `known=B-005xN`).
* **Ancillae**: no slot keeps one thing for > 700 frames (a pot's held explosion does not count while the cloud is up), `hush_ink_t` <= 300.
* **RAM**: `$7EC900-$7EE7FF` holds only bytes documented in `docs/ram_map.md` (an undocumented byte inside HUSH's block `$7EC900-$7EC9FF`
  is a `CHAOS: WARN`, anything beyond `$7ECA00` fails); the stack pointer stays in `$0100-$01FF`; the game loop keeps ticking (`$1A`).
* Statistics only (printed per run): `restarts exits jumps kills quits endings max_aware cells menu_frames lagged rooms`.

## Repros

A failing seed writes `tests/chaos/repros/<scenario>_<seed>.inputs` (and a copy in `build/test-results/<test>/`): the `hush.play` input
format (`frames buttons`), with header comments `# @room <id>` (how the run was entered) and `#@poke <frame> <hex address> <value>` (the
WRAM pokes the scenario made: item selection, ammo, teleports, jump requests). `hush.play` ignores them, the replay tool applies them:

```
HUSH_REPLAY=tests/chaos/repros/mash_7.inputs .venv/bin/python tools/run_test.py tests/dev/chaos_replay.lua     # same invariants, prints the end state
HUSH_REPLAY_FRAMES=n ...                                                                                         # stop after n frames (bisect)
```

`tests/chaos/repros/B-00x_*.inputs` are the hand-kept repros of the open bugs of `docs/bugs.md` (committed); generated
`<scenario>_<seed>.inputs` files are only there while a seed fails.

## Knobs

* `HUSH_CHAOS_SEED=k` shifts every seed by 1000 k (explore new inputs; the default run is the committed seed set).
* `HUSH_CHAOS_SCALE=f` multiplies the frame counts (0.25 = a quick 1-minute pass; the floor is 120 frames).
* `HUSH_CHAOS_STRICT=1` makes the known issues (B-002 quit, B-005 guard in wall) failures.
* `HUSH_ROM=/path/to/hush.sfc` runs against another build (e.g. a clean worktree of `HEAD`) - `tools/run_test.py` honours it.
* Each test also writes `build/test-results/<test>/chaos.log` (flushed per run: stdout only reaches the runner at exit, a timeout would hide it).

## Planned fuzz targets of M4 that are not possible / not done

* *Sleeping guard woken by another's alarm*: there is no alarm / noise mechanic (docs/engine_notes.md 11.11), nothing to fuzz.
* *Dying sprites* (kill / sleep a guard while it is spawning / falling): HUSH guards never fall or stun; spawning is covered by the
  restart loops of `chaos_churn.lua` and the `state 8` allowance of the invariants.
* *Room-transition edges*: `chaos_churn.lua` (jumps at random moments), `chaos_edge.lua` section 3 (exit vs catch). A walk through the exit
  on every frame offset of a guard's cycle is not done.

## Writing one

```lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush"); local C = require("chaos")
hush.test("my chaos", function()
  C.boot()                                                  -- once per script
  local seed = C.seed(900)
  local run = C.enter("myscenario", seed, "r05")            -- restore snapshot, debug jump, return a run
  local rng = C.rng(seed)
  C.guard(run, function()                                   -- prints the CHAOS: line, writes the repro on failure, never throws
    C.mash(run, rng, C.frames(2000), C.RATES_ALL)           -- or: run:step({"left", "b"}) / run:poke(addr, v) / run:jump(idx) / run:settle()
  end)
  C.finish()
end)
```

Put pokes and teleports through `run:poke` / `run:teleport` / `run:jump` (never `bot.poke`) so they land in the repro; keep every
random choice a function of the seed; wait on state (`run:settle`, module / `hush_room` / `spr_aware`), not on fixed frame counts.
A script that dies while loading (`require` error) times out silently: put `tests/chaos/lib` **and** `tests/lib` on `package.path`.
