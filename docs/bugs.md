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

## B-002: SELECT opens the vanilla "Continue Game / Save and Quit" dialog; Save and Quit writes SRAM and drops to the title
- Severity: minor (no soft-lock: the title and a new game work afterwards; but an unspecified escape hatch that loses the run, and it writes SRAM)
- Spec line violated: AGENTS.md / docs/engine_notes.md 6 ("Slot 0 SRAM is never read or written"); docs/engine_notes.md 10 ("SELECT in a room opens the vanilla save/continue message ... not suppressed")
- Build: commit 6fec04b (clean HEAD build in a separate worktree) and the working tree until 2026-11-19 17:09
- Test: found by tests/chaos/chaos_mash.lua (game module `$17` after SELECT, A); tests/chaos/lib/chaos.lua tolerates it (counted as `quits`) unless `HUSH_CHAOS_STRICT=1`; regression case `T r01 SELECT does nothing` in tests/smoke/mustnot2.lua
- Repro input: tests/chaos/repros/B-002_select_save_quit.inputs (`@room r01`; on the HEAD build: SELECT, down, A -> module `$17` -> title in ~250 frames, SRAM sum 0 -> 436)
- Expected: SELECT does nothing (or nothing that ends the run / touches SRAM).
- Actual: the message box "Continue Game / Save and Quit" appears (module `$0E`/`$0B`; START does not close it, A / B do); Save and Quit runs Module `$17`, writes the save mirror to SRAM, and soft-resets to the title.
- Status: fixed by E6 (src/hooks/ending.asm hook 2: the SELECT test `AND #$20` -> `AND #$00`). Verified on the 2026-11-19 17:17 build: the replay stays in module 7 and the SRAM is untouched.

## B-003: the Shade Knife kills a guard through a one-cell wall (reach 32 px ignores walls)
- Severity: major (breaks the designed puzzles: a still guard behind a 1-cell wall dies to the knife from the next corridor without a dart or smoke, unseen; r11, r14, r20 and the final room are bypassed this way, and every patrol lane in r06, r08, r13, r15, r17, r19)
- Spec line violated: design/pillars.md tools table (knife = melee, permanent takedown of an unaware guard; darts are the ranged tool) and the `intended_solution` of r11 / r14 / r20 / final; r08 spec ("the wall must stop darts elsewhere") shows walls are meant to stop weapons
- Build: working tree of 2026-11-19 17:17 (design/rooms: 21 specs) and commit 6fec04b
- Test: tests/smoke/mustnot2.lua family `K` (22 cases computed from the grids: guard cell, one wall cell, a floor cell Link can reach; 10 fail, listed as XFAIL(B-003) until fixed; the other 12 do not kill: Link above / left of the guard (the reach is not symmetric) or a patrol guard a pixel off the limit - not investigated further)
- Repro input: tests/chaos/repros/B-003_knife_through_wall_r11.inputs (real inputs only: r11, up col 1 to (1,7), flush under the wall row 6, swing: the unaware guard a at (1,5) dies; replay end line `a=0/dead`)
- Expected: a wall between Link and the guard stops the knife (the guard stays alive and unaware), like the dart does (the same geometry with a dart: all 8 `D` cases pass).
- Actual: `Hush_SwordCheck` (docs/engine_notes.md 11.5) overlaps the vanilla sword box with the guard box and never looks at the tile map. Link flush against a 16-px wall is exactly 32 px (centre to centre) from a guard on the far side, the documented reach limit, so the hit counts. The vanilla spin attack was not separately measured.
- Status: fixed by E7 (docs/engine_notes.md 15.1): `Hush_SwordCheck` accepts a kill only with a clear tile line of sight guard centre -> Link centre (`Hush_Vision` mode 3). All 22 `K` cases of tests/smoke/mustnot2.lua pass (the 10 XFAIL(B-003) expectations were flipped to normal PASS by the engine agent: `KNOWN` entry removed, nothing else in the test touched), the repro `tests/chaos/repros/B-003_knife_through_wall_r11.inputs` ends with guard a alive, all 21 solutions replay unchanged (knife kills in r03 r06 r07 r10 r17 r19 still kill).

## B-004: r15 must_not "waiting at (1,6) must NOT get you seen by the lane guards" is violated by guard b
- Severity: minor (spec / engine mismatch; the recorded solution never waits there)
- Spec line violated: design/rooms/r15.yaml must_not 4 ("The south hall and the middle corridor west of col 6 are hidden by walls: waiting at (1,12) and (1,6) must NOT get you seen by the lane guards")
- Build: working tree of 2026-11-19 17:17
- Test: tests/smoke/mustnot2.lua `H r15 hidden at (1,6) ...` (XFAIL(B-004)); (1,12) passes
- Repro input: tests/chaos/repros/B-004_r15_glimpse_at_1_6.inputs (real inputs: from the start straight up col 1 to (1,6), then wait)
- Expected: guard b (lane 2, row 8) never sees Link at (1,6).
- Actual: when b walks west and reaches col 3 he is on the diagonal of Link (|dx| = |dy| = 32 px); the cone test is inclusive on its edges (docs/engine_notes.md 11.3) and the line passes the open cell (2,7), so he turns Suspicious (then Alert after 1 s, then catches Link). The hiding spot only works for the 1 s window of the recorded solution. Decision needed: designer (change the spec text / grid so that (1,6) is a transit cell, or close (2,7)) or engine (exclusive cone edge).
- Status: fixed by spec change (design/rooms/r15.yaml now treats (1,6) as a transit cell; the XFAIL case in mustnot2.lua stays until QA flips it)

## B-005: an alert guard chasing Link slides into the corner of a doorway (up to ~10 px inside a wall cell)
- Severity: minor (cosmetic: the sprite overlaps the wall; also the guard centre sits in a wall tile, so his line of sight starts blocked for a few frames)
- Spec line violated: docs/engine_notes.md 11.4 ("it stops 14 px before a wall tile, i.e. the 16-px sprite overlaps the wall by 2 px")
- Build: working tree of 2026-11-19 17:17 (also commit 6fec04b: r20 seed 304 on the pinned HEAD build, r19 seed 306 on the current one)
- Test: tests/chaos/chaos_spam.lua (invariant "guard centre not in a solid tile"; known issue, counted as `known=B-005xN` in the CHAOS line, fails with `HUSH_CHAOS_STRICT=1`)
- Repro input: tests/chaos/repros/B-005_guard_in_wall_r19.inputs (pot / dart spam in r19, seed 306; with `HUSH_CHAOS_STRICT=1` the replay fails at frame 1701: guard 2 at (5414,10022), local (166,150): x is 10 px left of the 2-cell doorway (cols 11-12), so 10 of his 16 px are inside the wall column)
- Expected: a chasing guard never overlaps a wall by more than 2 px.
- Actual: `Hush_Chase` steps along the larger axis and, when blocked, slides along the other; the vanilla soldier tile box only tests a few points, so at a doorway corner the guard keeps moving down while 8-10 px of him are over the wall column (r19 here, r20: local (119,151), 9 px).
- Status: fixed by E7 (docs/engine_notes.md 15.2): `Hush_Step` runs `Hush_BoxProbe` (leading-edge feet-box probe, 3 tiles) for alert steps, speed / timing unchanged. The repro `B-005_guard_in_wall_r19.inputs` replays clean with `HUSH_CHAOS_STRICT=1` and `HUSH_CHAOS_STRICT=1 make chaos` passes (6 of 6 chaos scripts, no `known=B-005`); all 21 solutions replay unchanged.

## B-006: the game loop overruns the frame (30 fps) with 5-6 live ancillae in a room with 5-6 guards
- Severity: minor (performance, like B-001: Link, guards and timers run at half speed while it lasts; no catch or soft-lock)
- Spec line violated: docs/engine_notes.md 11.8 / 11.12 (frame budget: 6 guards must fit in 60 fps)
- Build: working tree of 2026-11-19 17:17
- Test: tests/chaos/chaos_spam.lua prints `lagged=N` per seed (frames in play where `$1A` did not tick; fails above 30 %): r10 (1 guard) 0 of 1680, r12 (3 guards) 1 of 1899, r14 (4) 96 of 1733, r20 (5) 181 of 1798, final (6) 236 of 1825 (13 %), r19 (4, alert guards) 92 of 1721
- Repro input: tests/chaos/repros/B-006_lag_pots_arrows_final.inputs (final room, pot / dart spam; the replay's end line prints `lagged frames 236`)
- Expected: 60 fps whatever the player does with the tools.
- Actual: all the lagged frames of the replay have 4-6 live ancilla slots (2 pots in flight / held explosions + 2-3 stuck arrows `$0A`, e.g. `anc=07,07,0A,0A,0A`), even with no awake guard and no cloud (lag 33 of 82 frames in that state); in the 5-6 guard rooms only. Scripted probes with at most 4 live ancillae (3 arrows + 2 pots, 12 frames apart, r20 / final / r10) show 0 lagged frames, so the trigger is a longer burst, not a single pot. Cause not isolated (candidates: `Hush_AncillaHit` runs once per ancilla x guard; each held explosion frame draws 6 OAM objects; stuck arrows live long under spam).
- Status: open, mitigated by E7 (docs/engine_notes.md 15.3-15.4): cause isolated (not a HUSH routine: the vanilla ancilla code costs ~2000-2500 CPU cycles per pot / flying arrow per frame: draw of the held explosion, 6 guards x hitbox set-up for an arrow in flight), two hooks cut it (`Hush_BombEntry`, `Hush_AncPre`; flying arrow 2270 -> 1219 cycles, held pot 2449 -> 2022): the repro now lags 115 of 1825 frames (was 280 on the same build without them; the chaos spam seeds: r14 96 -> 4, r20 181 -> 104, final 236 -> 195, r19 92 -> 71 lagged frames). Residual: 2 held ink clouds + 3-4 arrows in a 5-6 guard lit room still reach the NMI line (logic ends at scanline 205-224 of 225); needs a hand-written draw of the held cloud (~190 bytes of free ROM in bank $07, not available) - see 15.4 item 3.
