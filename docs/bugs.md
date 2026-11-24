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
- Status: fixed by spec change (design/rooms/r15.yaml: intended_solution step 1 calls (1,6) a transit cell; must_not 5 names (2,6)-(5,6) as the hiding cells; must_not 6 says standing at (1,6) while b walks west MUST get you Suspicious when b passes col 3). QA 2026-11-20: the XFAIL(B-004) case "r15 hidden at (1,6)" in tests/smoke/mustnot2.lua is replaced by `H r15 seen at (1,6) by b when he passes col 3 (must_not 6, ex-B-004)` (b must be the first guard to notice, from cols 2-4, within 600 frames) plus HIDE cases (2,6) (all guards) and (5,6) (lane guards a, b) for must_not 5. No XFAIL left for B-004. The repro file now demonstrates the specified behaviour.

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

## B-007: the per-guard meter cooldown lets a same-size hit through at exactly +120 frames (spec blocks +1..+120)
- Severity: minor (one frame of the cooldown window; a re-notice exactly 120 frames after a hit costs 4 / 16 instead of 0)
- Spec line violated: design/pillars.md:65-66 ("cannot cause another hit of the same size for 120 gameplay frames") and :107-109 ("re-noticing within 120 frames lowers it by 0"; "more than 120 frames ... by 4 again")
- Build: commit 5fe9d78 + working tree of 2026-11-20 (`build/hush_dev.sfc`, `-- @rom dev`)
- Test: tests/smoke/meter_cooldown.lua (no savestate: debug jump into dev room ai4_dark). Frame H = `$1A` of the gameplay frame whose meter check applies the hit; "+k" = the transition is first seen by the meter check of frame H+k (poke at the end of H+k-1, `hush_aprev` asserted to change in H+k)
- Repro input: tests/smoke/meter_cooldown.lua (self-contained, deterministic RAM-poke script; the boundary cannot be hit with pad inputs to the frame). Run: `.venv/bin/python tools/run_test.py tests/smoke/meter_cooldown.lua`
- Expected: +1..+120 cost 0, +121 costs 4 (small) / 16 (big).
- Actual: small +40 = 0, **+120 = 4**, +121 = 4; big +4 = 0, **+120 = 16**, +121 = 16. Cause (critic): `Hush_MeterFrame` decrements `hush_cd_small` / `hush_cd_big` (src/hooks/meter.asm:73-76) before testing them (:86, :91) in the same frame, so a cooldown set to 120 in frame H reads 0 in frame H+120. Fix options for engine: test before decrementing, or store 121.
- Status: fixed (engine): src/hooks/meter.asm:89 / :94 store 121 in `hush_cd_big` / `hush_cd_small` (decremented before the test, so H+1..H+120 see 120..1 = blocked, H+121 sees 0). QA 2026-11-20, `.venv/bin/python tools/run_test.py tests/smoke/meter_cooldown.lua` on the dev ROM: PASS, all 7 checks: small +40 = 0, +120 = 0, +121 = 4; big after small = 16, +4 = 0, +120 = 0, +121 = 16. tests/lib/meter.lua `budget` (spec order) and the engine now agree.

## B-008: r15 middle corridor (3,6)-(5,6) is not hidden from the lane guards (spec: (2,6)-(5,6) are); only (2,6) is
- Severity: major (the spec tells the player to wait at (5,6) - intended_solution step 2 - and a player who waits there while a walks west is seen, alerted and caught; the recorded r15 replay is unaffected because it only waits there while a walks east)
- Spec line violated: design/rooms/r15.yaml:65-67 (intended_solution step 2: "Walk east to (5,6) and wait there (cols 2-5 of the corridor are hidden from both lane guards by the wall row 7)") and :78 (must_not 5: "The middle corridor cells (2,6) to (5,6) are hidden by the wall row 7 ... must NOT get you seen by the lane guards")
- Build: commit 5fe9d78 + working tree of 2026-11-20 (`build/hush.sfc`)
- Test: tests/smoke/mustnot2.lua HIDE cases for every cell the spec names, 900 frames each, Link teleported there at room entry: (2,6) PASS; (3,6) FAIL "seen after 291 frames (a=0 c=0 b=1)"; (4,6) FAIL "seen after 409 frames (a=1 ...)"; (5,6) FAIL "seen after 413 frames (a=1 ...)". (3,6)-(5,6) count only the lane guards a, b.
- Repro input: tests/chaos/repros/B-008_r15_seen_at_5_6.inputs (real inputs: 120 up, 42 right, wait; `.venv/bin/python tools/run_test.py tests/dev/b008_probe.lua` prints the transitions)
- Expected: no lane guard leaves Unaware while Link waits anywhere in (2,6)-(5,6) (c sees cols 6-10 only, so these cells are outside his range too).
- Actual (repro): f418: guard a (slot 0) at (8,4), walking west, turns Suspicious with Link at (5,6) (px 3279,9960); f478 Alert; Link is caught and the room restarts (f532 Link back at (1,12)). Geometry: (8,4) -> (5,6) is |dx| = 3, |dy| = 2 cells: inside his cone, within the dark range 5, and the line runs through the open lane-1 gap (6,5)/(7,5). (3,6) is the mirror image of B-004 for b: from the lane-2 gap side (cols 1-2 of row 8) the diagonal passes the open cell (2,7). The wall row 7 the spec cites shields only the part of the corridor that no gap diagonal reaches. Engine behaviour matches docs/engine_notes.md 11.3; the spec text is the mismatch.
- Decision needed: designer (e.g. make (2,6) the only waiting cell and say "pass (3,6)-(5,6) only while a is east of col 8 / walking east and b is not at cols 1-3", or close / move a gap in the grid). QA keeps the three cases failing (not XFAIL) until the spec or the game changes.
- Status: fixed by spec change (designer, 2026-11-20; grid unchanged, `make rooms` output byte-identical). design/rooms/r15.yaml:65-69 (step 2: wait at (2,6), the only hidden corridor cell; (3,6)-(5,6) are transit cells), :70-75 (step 3 starts from (2,6)), :86 (must_not 5: (2,6) only, all three guards count), :88 (new must_not 7: (3,6) seen within 900 frames, b first), :89 (new must_not 8: (4,6) / (5,6) seen within 900 frames, a first). QA 2026-11-20, tests/smoke/mustnot2.lua: HIDE cases (3,6)-(5,6) removed, (2,6) kept with all guards counting (PASS, 900 frames); new cases `H r15 seen at (3,6) ... b first` (PASS, b after 291 frames), `(4,6) ... a first` (PASS, a after 409), `(5,6) ... a first` (PASS, a after 413). The repro `tests/chaos/repros/B-008_r15_seen_at_5_6.inputs` now shows the specified behaviour (must_not 8): `tests/dev/b008_probe.lua` prints f418 a 0->1 with Link at (5,6), f478 Alert, f532 caught / room restart. tests/solutions/r15.lua replays (see the `make test` table of the same date).

## B-009: final room, top 4 px of (8,5): the spec's band (Link y 9936-9939, "e first") does not match the engine (d ties e at 9936-9937, nobody sees at 9939)
- Severity: minor (spec / engine mismatch at the pixel edge of the waiting cell; the intended solution waits at the centre, y 9944, which stays hidden; the recorded final replay is unaffected)
- Spec line violated: design/rooms/final.yaml:103 (must_not: "Standing in the top 4 px of (8,5) (Link y 9936-9939) without smoke must get you Suspicious, e first") and :102 (the same band: "with Link in the top 4 px of the cell (Link y 9936-9939 ...) e sees him")
- Build: commit 5fe9d78 + working tree of 2026-11-20 (`build/hush.sfc`)
- Test: tests/smoke/mustnot2.lua `H final seen at (8,5) top band y <Y> within 900 frames, e first (final.yaml:103)`, one case per Y in 9936-9939 (Link teleported to col 8 (x 6400) at room entry + 3 frames, no input, no smoke, Link's y asserted constant)
- Repro input: tests/dev/final_top_probe.lua (self-contained, deterministic: teleport, no pad input; same precedent as B-007). Run: `.venv/bin/python tools/run_test.py tests/dev/final_top_probe.lua`. It sweeps Link y 9928-9946 x AI phase 0-3 and prints the first-notice frame of each guard.
- Expected (spec): at every y in 9936-9939 some guard turns Suspicious within 900 frames, and e is the first.
- Actual: y <= 9937: d (slot 0, (1,4) facing east) AND e (slot 1, (14,4) facing west) both see Link; which one is first only depends on the frame parity of the teleport (the AI look phase): phase 0 / 2 d at frame 1, e at 2; phase 1 / 3 e at 1, d at 2; caught at frame 62-64. In mustnot2's set-up (phase 0) d is first -> y 9936 and 9937 FAIL. y 9938: e only (PASS). y 9939 (and 9940-9946): nobody notices (FAIL: 900 frames, no guard leaves Unaware). So the engine's real band is 9938 for "e only", <= 9937 for "d and e", and 9939 is hidden. The spec's "measured by qa 2026-11-20" number is off by 1 px at the bottom and does not account for d.
- Decision needed: designer (e.g. "Link y <= 9938: seen; <= 9937 by d and e, either first" and make the hidden part start at y 9939), or engine if d should not see (8,5) at all. QA keeps the failing cases failing (not XFAIL); the spec was not changed by QA.
- Status: fixed by spec change (designer, 2026-11-20; grid and engine unchanged). design/rooms/final.yaml:90 (step 5: d and e see the top 3 px of (8,5), Link y 9936-9938), :102 (must_not: (8,5) hidden at Link y 9939-9946, centre 9944, every guard Unaware for 900 frames at each y), :103 (must_not: y 9936-9938 without smoke must get you Suspicious from d or e, either may notice first). QA 2026-11-20, tests/smoke/mustnot2.lua (build/hush.sfc, commit 5fe9d78 + working tree): the old "e first, y 9936-9939" cases and the 500-frame HIDE case at the (8,5) centre are replaced by `H final seen at (8,5) top band y <Y> within 900 frames, d or e first (final.yaml:103)` for Y = 9936-9938 (PASS: d after 1 frame at 9936 / 9937, e after 2 frames at 9938) and `H final hidden at (8,5) y <Y> for 900 frames, every guard Unaware (final.yaml:102)` for Y = 9939-9946 (PASS, all 8; all six guards count, c awake; caught counts as seen; Link's y asserted constant; the y 9944 case also asserts that the cell centre is 9944). smoke_mustnot2: PASS, 122 cases, 0 unexpected failures.

## B-010: guard light falls hundreds of frames behind in rooms with 3+ guards (light_done stays 0 for up to 949 frames with Link standing still)
- Severity: major (readability pillar: "amber on the floor is exactly where a guard can see you" is false on screen for seconds at a time in r12-final; no lag frames, no wrong tile once caught up)
- Spec line violated: design/lighting.md 4.4 ("The light of a moving guard steps cell by cell ... and may trail the guard by a few frames (restored by revision 4)"), 4.5 item 5 ("a guard light whenever its committed map changes, as often as the frame budget allows"; glow "every few frames"); section 5 accuracy contract only holds on light_done frames, which are rare in r19 / final
- Build: commit c78866b + working tree of 2026-11-24 (light.asm L3 D1a, design/lighting.md rev 4), `build/hush.sfc`
- Test: tests/smoke/lighting.lua (no savestate: post-new-game + debug jump), liveness bound WAIT_MAX = 120 frames from "Link stops" to light_done ($7EE7F6) = 1
- Repro input: tests/dev/repros/b010_r19.inputs (r19: 10 frames left, then 1200 frames still), driven by tests/dev/b010_light_done.lua (`.venv/bin/python tools/run_test.py tests/dev/b010_light_done.lua`; room via HUSH_ROOM, default r19)
- Expected: with Link still, the light catches up (light_done = 1) within a few frames of a guard's cell change; test bound 120 frames.
- Actual (smoke_lighting, max wait per room, frames): r01 5, r02 17, r03 4, r04 17, r05 16, r06 85, r07 16, r08 88, r09 47, r10 9, r11 7, **r12 173, r13 77, r14 168, r15 90, r16 238, r17 153, r18 201, r19 949, r20 188, final 428**; 39 of 504 waits > 120 (23 of 24 legs in r19, 9 in final). Probe on the repro (r19, 1190 still frames): first light_done = 1 at frame 237, done on only 10 frames, longest done = 0 run 336 frames, 0 lag frames; only 15 guard jobs started yet a job was running on 1106 frames (~74 frames per job), region running 1035, amber dirty box 942, light_dirty 1031, glow d mismatch 5 (the glow is not the cause). So a single guard light job takes ~70+ frames in a lit 4-guard room and guards change cell faster than jobs finish.
- Accuracy is not affected: on every light_done frame all 451584 tile words matched the section 5 oracle (0 wrong) and every guard map matched section 3.
- Status: open (engine: guard job throughput, `Hush_LightStep` / `Hush_L3Lat`; L3_REPORT.md D1a lists "an amber latency metric" as open)
- **Update 2026-11-24 (spec changed first):** design/lighting.md section 5 "Catch-up (guard light liveness)" replaces the light_done bound: per room, stale episodes (live signature change -> committed signature equal, no job for the slot, amber lattice / tile rows and light_dirty rows 0-13 empty) median <= 15, p90 <= 40, max <= 90 frames; "all light idle" is not required. tests/smoke/lighting.lua now asserts that (every gameplay frame of its 24-leg walk per room) and keeps light_done == 1 only as the gate for tile checks (hard cap 1200, fails only if the light never settles; max seen 253, final). Same build as `make check` of 2026-11-24 (working tree on c78866b lineage, `build/hush.sfc`). Repro: tests/smoke/lighting.lua (deterministic: new game + debug jump, inline inputs; `.venv/bin/python tools/run_test.py tests/smoke/lighting.lua`).
- Actual under the new rule (median/p90/max, episodes): r02 8/13/14 (15), r04 4/13/14 (14), r06 9/14/24 (23), r08 7/27/38 (12), r09 8/21/26 (10), r10 4/9/12 (11), r13 12/16/23 (34), r15 12/31/60 (39), r18 15/33/35 (17); **FAIL: r12 24/135/135 (6), r14 12/53/55 (17), r16 13/155/156 (19), r17 10/39/100 (32), r19 19/106/124 (58), r20 12/130/130 (19), final 33/94/252 (32)** (r01, r05, r11: no episodes in the walk). Diagnosis: the time from the change to the slot's commit alone is over 90 (max to commit: r12 123, r16 147, r20 125, r19 117, final 229); commit -> VRAM is <= 64 everywhere. So guard job throughput is still the cause, not the global amber-pipeline condition. Tiles: 0 wrong of 451584. Status stays **open** (engine), severity major.


