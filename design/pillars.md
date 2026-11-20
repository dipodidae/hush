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
4. **Fail fast, retry instantly.** Caught means an instant room restart. No
   death screen, no lost progress. Rooms must be short enough that restarting
   is fun.
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

In: awareness states, conditional damage, instant restart, ~20 rooms, final
heist room, the three tools, lit-room detection range, BPS release.

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
