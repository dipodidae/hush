# Chaos tests (fuzz)

Empty at M0. `make chaos` runs every `tests/chaos/*.lua` through
`tools/run_test.py --suite chaos` and passes trivially while the directory
has no scripts.

Chaos tests start from a savestate, apply randomised but **seeded** input and
timing, and assert invariants. Every failure must be reproducible: the seed and
the input log are written to `build/test-results/<test>/` and, for a real bug,
copied to `docs/bugs.md` with a repro input file under `tests/solutions/` or
`tests/chaos/repros/`.

## Planned fuzz targets (M4)

1. **Attack on the frame a guard turns.** Swing the knife / throw a dart on
   every frame offset around the Unaware -> Suspicious and Suspicious -> Alert
   transitions. Invariant: damage is applied only if the awareness state read at
   the moment of the hit was Unaware; an Alert guard never loses HP.
2. **Two guards alerting at once.** Trigger two guards in the same frame (and
   one frame apart). Invariant: both end Alert, no slot is skipped, no state
   array corruption, caught -> room restart still fires exactly once.
3. **Sleeping guard woken by another's alarm.** Dart-sleep guard A, alert guard
   B. Invariant: sleep timer and awareness state stay coherent (A wakes into
   Suspicious/Alert per spec, never into a stale state), no stuck sleeping
   sprite.
4. **Room-transition edges.** Walk into and out of the room on every frame
   offset, with guards mid-state. Invariant: no guard state leaks into the next
   room, restart-on-caught still restores the room, no softlock.
5. **Dying sprites.** Kill / put to sleep guards while they are spawning,
   falling, stunned, or on the transition frame. Invariant: dead sprites
   (`spr_state == 0`) never keep an awareness state; slots are reusable.

## Writing one

Use `tests/lib/hush.lua`. Pass a seed through the script header or an env var
and log it with `hush.log`. A chaos test must be deterministic for a given
seed (the harness's `smoke/determinism` guards this).
