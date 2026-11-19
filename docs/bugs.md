# Bugs

Owned by `qa`. A bug needs a repro input file; no repro, no bug.

Template:

```
## B-001: <title>
- Severity: blocker | major | minor
- Spec line violated: design/... or AGENTS.md rule
- Build: <git commit or build date>
- Test: tests/<suite>/<name>.lua  (state: tests/states/<file>.mss)
- Repro input: tests/solutions/<file>.inputs  (or tests/chaos/repros/<file>)
- Expected:
- Actual:
- Status: open | fixed | wontfix
```

## B-001: game loop overruns the frame (30 fps) in r20 and final once a guard is asleep
- Severity: minor (performance; no catch or soft-lock, but Link, guards and timers run at half speed while it lasts)
- Spec line violated: docs/engine_notes.md 11.8 ("at most 6 guards per room ... for 60 fps"; measured there with idle / chasing guards, not with sleepers)
- Build: working tree of 2026-11-19 (design/rooms: 21 specs), `build/hush.sfc`
- Test: tests/solutions/all_rooms.lua prints `lagged frames N` per room (frames in the playing state where `$1A` did not tick)
- Repro input: tests/solutions/r20.inputs (5 guards, lit: 130 of 946 frames lagged), tests/solutions/final.inputs (6 guards, lit: 463 of 1536 frames lagged)
- Expected: 60 fps (no lagged frame) with up to 6 guards, whatever their state.
- Actual: with 5-6 guards in the room the same rooms run clean while all guards are unaware (the unperturbed patrols of all 21 rooms were traced for 2400 frames: 0 lagged frames) but as soon as one or two guards are ASLEEP (dart) the loop overruns on 30-70 % of the frames (r20: 73 of 255 frames with 1 sleeper, 36 of 406 with 2). (Frames with no sleeper in r20: 0 of 97 lagged; the ink cloud on top of a sleeper was not separated out.) Every other room (at most 4 guards, e.g. r14, r16) has 0 lagged frames. Effect: game time (ticks of `$1A`) and emulator frames differ, 1-frame button taps can be swallowed (the recorder lengthens its taps when that happens), and patrol timing relative to wall-clock changes for the player.
- Status: fixed by E4 (custom guard drawing, docs/engine_notes.md 11.12): the draw went from 1745 to 500 CPU cycles per guard, 6 sleeping guards end the logic at scanline 157 instead of 212 (`tests/dev/cpu_load.lua`). Verified on the real rooms: `r20` and `final` replay with 0 lagged frames (were 130 and 463). The two replays were re-recorded (they had been recorded under lag, so the old inputs no longer reproduce the bug or the solution).


