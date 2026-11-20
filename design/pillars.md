# HUSH design pillars

HUSH is a ROM hack of The Legend of Zelda: A Link to the Past (SNES, US 1.0).
You are a shadow thief infiltrating a vault tower guarded by lantern-carrying
guards. There is no overworld: about 20 single-screen stealth-puzzle rooms
across 3 floors, plus a final heist room.

**Only the designer edits this file, and only with the human's approval of the
change.** Every other agent treats it as read-only law.

## Pillars

1. **Light is the enemy.** Your weapons are made of shadow and melt in lantern
   light. Lantern light is not just a hazard; it is the rule that makes every
   room a puzzle.
2. **Unaware guards fall. Alert guards cannot be hurt at all.** The whole game
   is the window between "hasn't noticed you" and "has". Alerted guards are
   immune; the answer to an alert is to hide, not to fight harder.
3. **One screen, one idea.** Every room fits on a single screen and teaches or
   tests one thing. If a room needs a paragraph to explain, it is two rooms.
4. **Fail fast, retry instantly.** Caught means an instant room restart, and so
   does an empty stealth meter. No death screen, no lost progress, no hearts.
   Rooms must be short enough that restarting is fun.
5. **Readable at a glance.** Amber = danger. Violet = you. Awareness is shown
   by icon and colour, never only by behaviour. A player must be able to tell
   what a guard knows from one frame.

## Rules (the game's physics)

- **Guard awareness has three states:**
  Unaware (no icon) -> Suspicious ("?", turns and investigates) ->
  Alert ("!", sprite turns amber, charges).
- **Caught** (an Alert guard reaches you) = instant room restart.
- Alerted guards **return to patrol** after losing sight of you for the
  de-alert time.
- **Lit rooms increase guard detection range** (planned for late milestones).
- **Damage rule:** a hit from a player tool damages a guard only if the guard
  was Unaware (or asleep) at the moment of the hit. Alert guards take no damage.
- **Stealth meter** replaces hearts (section below). Being noticed drains it;
  empty = instant room restart.

## Stealth meter (human-approved; replaces hearts and health)

Numbers are exact; the engine names the RAM byte `hush_meter` and documents its
address in `docs/ram_map.md`.

- **Capacity: 32 units.** `hush_meter` holds 0..32. Every hit below is a
  multiple of 4, so the value is always a multiple of 4 (0, 4, ..., 32).
- **Refill:** set to 32 on every room entry: new game, room advance, and every
  room restart (caught or meter empty). Nothing else refills it; nothing in a
  room raises it (no pickups).
- **Hits** fire once per guard **state transition**, never per frame:

  | Transition of one guard | Hit | Units |
  |---|---|---|
  | Unaware -> Suspicious ("?") | small | 4 |
  | Suspicious -> Alert ("!") | big | 16 |
  | Unaware -> Alert directly (Link touched him) | big only | 16 |
  | anything -> Unaware (de-alert, ink), -> Asleep, Asleep -> Unaware, kill | none | 0 |

  So a full notice chain (? then !) costs 20; one is survivable, a second in
  the same room is not (20 + 20 > 32). Eight separate "?" (8 x 4) also empty it.
- **Re-notice hits again:** a guard that went back to Unaware (de-alert timer
  or ink) and then notices Link again takes the hit again.
- **Per-guard cooldown: 120 frames (2 s).** After guard G causes a hit, G
  cannot cause another hit *of the same size* for 120 gameplay frames. A big
  hit is never blocked by a recent small hit (? then ! after 60 frames costs
  4 + 16). The cooldown is per guard slot; different guards always hit
  independently (two guards noticing in one frame = 8 units). Cooldowns clear
  on room entry.
- **Empty meter:** when a hit brings `hush_meter` to 0 (clamped, never
  negative), the room restarts exactly as if caught: same path (`hush_caught`),
  same flash and sound, same timing, `hush_retries` +1.
- **Caught still wins:** an Alert guard touching Link restarts the room at once,
  whatever the meter shows (pillar 4).
- **Tools and light do not change hit sizes.** Lit rooms only make notices more
  likely (sight 8). Ink makes guards Unaware (no hit, no refund). A dart that
  hits a Suspicious / Alert guard does nothing to guard or meter.
- **Vanilla damage is ignored, not converted.** Link never loses health; the
  vanilla health value stays at its max at the end of every gameplay frame and
  the vanilla death / game-over module never runs. Why ignored: HUSH guards
  never deal vanilla damage (E2) and no shipped room has a vanilla hazard, so
  any vanilla damage left would be a bug with no on-screen cause; turning it
  into a meter hit would drain the bar with no "?" or "!" to explain it
  (pillar 5).
- **HUD:** a horizontal bar in place of the heart row (BG3 tilemap row 3,
  columns 20-27: 8 cells x 8 px; 1 cell = 4 units, so a cell is only ever full
  or empty). No other HUD cell moves; the label above may be relabelled by art.
  - Filled cells: **violet** (you).
  - Drained cells: empty container (violet outline, dark interior), like the
    old empty heart.
  - Hit flash: the cells just lost show **amber** for 16 frames, then drained.
  - Low meter (8 units or less = 2 cells or fewer): the filled cells alternate
    violet / amber every 16 frames until the room restarts or ends.
  - Amber in the bar is a danger cue only; the bar is never amber at full or
    healthy meter. No new sound (the existing notice / alert sounds cover hits).

Acceptance criteria (headless, RAM-observable; `spr_aware` = `$7E0D80`):

1. On room load, advance and every restart, `hush_meter` = 32 on the first
   gameplay frame.
2. Forcing one guard Unaware -> Suspicious lowers `hush_meter` by exactly 4;
   holding him Suspicious for 60 more frames (no Alert yet) lowers it by 0 more.
3. Suspicious -> Alert lowers it by exactly 16 (total 20 from full).
4. Contact with an Unaware guard lowers it by exactly 16 (not 20) before the
   catch restart.
5. A guard made Unaware by ink and re-noticing more than 120 frames after his
   last small hit lowers it by 4 again; re-noticing within 120 frames lowers it
   by 0.
6. Two guards turning Suspicious in the same frame lower it by 8.
7. With `hush_meter` = 4, one small hit sets it to 0, `hush_caught` is set that
   frame, the room restarts next frame, `hush_retries` +1, `hush_meter` = 32.
8. With `hush_meter` = 32, an Alert guard touching Link restarts the room
   (meter value irrelevant).
9. Over every solution replay and the chaos suite: vanilla health `$7EF36D`
   equals `$7EF36C` at the end of every gameplay frame, and the game-over module
   never runs.
10. HUD (BG3 tilemap row 3, cols 20-27): at 32 all 8 cells show the filled tile;
    at 20 exactly 5 filled + 3 drained; at 8 or less the filled cells change
    palette every 16 frames.
11. Asleep / killed / ink-calmed transitions and dart hits on aware guards
    leave `hush_meter` unchanged.

## Player tools (one per vanilla item slot)

| Tool | Slot | Effect |
|---|---|---|
| Shade Knife | sword | Melee. Permanent takedown of an **unaware** guard. |
| Hush Darts | bow | Ranged. Puts an **unaware** guard to sleep for ~8 s. |
| Ink Pots | bomb | Darkness cloud. **Alerted** guards inside it lose you and return to patrol. |

Tools are given room by room (`tools_given` in the room spec); a room never
assumes a tool it did not give.

## Art direction

- Palette: colourful yet dark. A deep indigo base with a distinct hue per floor:
  floor 1 indigo + jade / brown / teal accents, floor 2 teal + rust / ice / slate,
  floor 3 wine + gold / charcoal. Lit rooms are brighter and warmer, with wall torches.
- Guards: steel-blue uniform with an amber lantern (alert = the whole guard turns amber).
- Player: violet hooded thief with cyan eyes and a teal scarf. Exit cells: green glow marker.
- The player and their tools are **faint violet**.
- **Amber = danger and light sources** (lanterns, torches, alert guards, alert icon).
- **Violet = you** (player, knife, darts, ink pots).
- Violet never appears on guards or hazards; amber never appears on the player.
  `tools/gfx_convert.py` enforces this by file-name role prefix.

## Scope (MVP)

In: awareness states, conditional damage, instant restart, stealth meter
(replaces hearts; human-approved), ~20 rooms, final heist room, the three
tools, lit-room detection range, BPS release.

In (human-approved extension, see `design/tiles.md`): autotiled background
(walls, floor, edges, corners), grid-driven tile placement, and visual-only
doorway / pit / water tiles. No guard-AI or sight change; no shipped room uses
pit or water until `design/tiles.md` question 1 is decided.

Out (do not build, do not design for): overworld, new bosses, new items beyond
the three tools, dialogue/story scenes, multiple save files, any new engine
subsystem not named in AGENTS.md.

## Difficulty curve

| Floor | Rooms | New idea per room | Par time |
|---|---|---|---|
| 1 | r01-r06 (6) | one rule at a time: see/not see, patrol timing, knife, ambush, hide from a "?", exam | 10-25 s |
| 2 | r07-r14 (8) | combine two rules; darts, then the first lit rooms, then ink, then exams | 20-45 s |
| 3 | r15-r20 (6) | combinations and timing, 3-5 guards, lit and dark; no new rules | 30-60 s |
| Final | final (1) | everything, in one screen, 6 guards | 60-90 s |

Room-by-room plan (specs in `design/rooms/<id>.yaml`; `L` = lit, `D` = dark; tools are cumulative):

| Seq | Id | Light | Tools given | Guards | Idea | Par |
|---|---|---|---|---|---|---|
| 1 | r01 | D | - | 1 still | guards only see in front; walk behind him | 12 s |
| 2 | r02 | D | - | 1 patrol | cross a patrol lane in a timing window | 15 s |
| 3 | r03 | D | Shade Knife | 1 still | stab an unaware guard in the back | 12 s |
| 4 | r04 | D | - | 1 patrol | hide in a deep pocket, ambush the patrol | 15 s |
| 5 | r05 | D | - | 1 still | a "?" can be survived by breaking line of sight behind a pillar; alert guards are immune | 15 s |
| 6 | r06 | D | - | 3 (2 patrol, 1 still) | floor 1 exam: ambush, stab, crossing | 25 s |
| 7 | r07 | D | Hush Darts | 1 still | sleep a guard from beyond his range, then knife him | 20 s |
| 8 | r08 | D | - | 2 (1 patrol, 1 still) | dart through a door; time the shot around a patrol | 30 s |
| 9 | r09 | L | - | 1 patrol | first lit room (sight 8): cover and timing | 25 s |
| 10 | r10 | D | Ink Pots | 1 patrol | smoke as an ambush bubble (the pot takes about 2.6 s to go off) | 20 s |
| 11 | r11 | L | - | 2 still | smoke over a gap to cross a corridor watched from both ends | 25 s |
| 12 | r12 | L | - | 3 still | lit + darts: shoot through three doors from beyond 8 cells | 35 s |
| 13 | r13 | D | - | 2 patrol | two crossing patrol lanes, safe corner rooms | 30 s |
| 14 | r14 | L | - | 4 (2 still at corridor ends, 1 still, 1 patrol) | floor 2 exam: dart, patrol, smoke | 45 s |
| 15 | r15 | D | - | 3 (2 patrol, 1 still) | lane, dart along a corridor, lane | 30 s |
| 16 | r16 | L | - | 3 (2 still, 1 patrol) | two darts (row and column), lit lane | 40 s |
| 17 | r17 | D | - | 3 (2 patrol, 1 still) | lane, dart, ink ambush | 45 s |
| 18 | r18 | L | - | 3 (2 still, 1 patrol) | choose a door, dart, lit lane | 40 s |
| 19 | r19 | D | - | 4 (3 patrol, 1 still) | two-patrol lane, stab, ink ambush | 60 s |
| 20 | r20 | L | - | 5 (4 still, 1 patrol) | two darts, lit lane, smoke corridor | 50 s |
| 21 | final | L | - | 6 (4 still, 2 patrol) | the heist: darts, lane, darts, smoke | 75 s |

Design constants the rooms rely on (engine, `docs/engine_notes.md` section 11): sight 5 cells dark / 8 cells lit, 90-degree cone,
blind behind and (in practice) beside the guard; a Suspicious guard turns Alert after 60 frames of seeing you; Link walks about 1-1.5 px/frame,
patrols 0.75 px/frame, alert guards 1.125 px/frame; the dart sleeps an Unaware guard for about 8 s; an ink pot explodes about 2.6 s
after you place it and its 3x3-cell cloud lasts 5 s (only one cloud at a time). Rooms are timed for the slower Link speed (1 px/frame); par times include
reading the room and switching items.

Meter budget: an intended solution may cost at most 2 small hits (8 of 32 units) and no big hit. r05 is the only spec whose intended solution plans a "?" (1 small hit, 28 left); qa confirms the recorded replays stay within budget.
