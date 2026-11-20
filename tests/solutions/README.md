# Solutions

One recorded input script per room (`r01.inputs` .. `r20.inputs`, `final.inputs`) that clears the room on the real ROM, plus the tests
that replay them.

| File | What |
|---|---|
| `<id>.inputs` | the replay (`frames buttons  # comment`, see `tests/README.md`); generated, do not edit by hand |
| `all_rooms.lua` | `make test`: boots once, saves the post-new-game state, then for every room: restore that state, debug-jump to the room, replay the inputs. Asserts: the exit was touched (`hush_room` = next room; after `final` the game is back at the title) and Link was **never caught** (no `hush_caught`/`hush_flash`, i.e. no fast restart). Prints one `SOLUTION:` line per room (frames, awareness reached, lagged frames). `HUSH_ONLY=r05,r06` restricts it. `EXPECTED_FAIL` (top of the file) is the list of rooms that are known to be unsolvable: they show as `XFAIL` with the bug id, never silently skipped |
| `must_not.lua` | the `must_not` lines of the specs as tests (walk in front of the guard -> `?`, stand in the open -> `!`, no ink -> caught, knife on a suspicious guard does nothing ...): `MUST_NOT:` lines |

Every room is entered from the same post-new-game state (`hush.snapshot()` / `hush.restore()`), so a replay does not depend on what the
previous room left in RAM (the selected Y item, the frame counter, Link's sub-pixels: all of them changed the outcome before this).

## Regenerating

The inputs are produced by a planner + recorder; they are invalidated by any change to `design/rooms/*.yaml`, to the AI constants
(speeds, ranges, timers), or to Link's movement.

```
make build                                          # build/hush.sfc + build/rooms_gen.lua
.venv/bin/python tools/solve_rooms.py traces        # 1. unperturbed guard patrols of every room (Link ignored) -> build/traces/ghost_<n>.csv
.venv/bin/python tools/solve_rooms.py solve all     # 2. plan (search WHEN to go), 3. record on the real ROM, 4. write tests/solutions/<id>.inputs
.venv/bin/python tools/solve_rooms.py solve r06     # one room
.venv/bin/python tools/solve_rooms.py record all    # re-record the saved plans (build/plans/*.plan) without planning again
.venv/bin/python tools/solve_rooms.py plan r06      # only print the schedule the model found
```

* `tools/room_plans.py` has the route of each room (where to go and which tools to use: derived from `intended_solution`).
  `tools/solve_rooms.py` searches the waiting times with a port of the engine's vision rules (`src/hooks/guard_vision.asm`) over the
  recorded patrols. A room whose route changes needs its skeleton changed there.
* `tests/dev/record_room.lua` is the recorder: it executes the plan closed-loop on the real ROM (pixel-exact walking, the real START
  item menu, dart / pot / knife) and writes the button presses; the recorder fails on the first catch. `tests/dev/trace_room.lua`
  records per-frame traces (the same CSV is what `tools/why_rec.py <room>` reads to explain a failed recording).
* Game time = ticks of `$1A`. The item menu pauses the game; with five or six guards and a sleeping one the game loop overruns the
  frame (see docs/bugs.md B-001), so emulator frames and game frames differ in those rooms. The planner works in game frames.
  E4 (custom guard drawing) removed that lag; `r20.inputs` and `final.inputs`, which had been recorded under lag, were re-recorded (the other 19 are unchanged).
* `final.inputs` (2026-11-20) is hand-timed by QA, not by the planner: `tests/dev/plans/final_qa.plan` (each wait cites a step of
  design/rooms/final.yaml:80-91), recorded with `tests/dev/record_final.lua` (record_room.lua with fixed paths: run_test.py passes no env)
  and checked with `tests/dev/final_probe.lua` (every awareness transition with slot -> spec letter, Link / guard cells, the ink cloud).
  The planner's version walked into row 4 two frames before the cloud was up, so guard e (slot 1) went "?" (meter 28). The recorder's
  last `goto` reports "stuck" in the final room (the ending fade keeps hush_room = 20); the inputs were trimmed at the exit frame.
