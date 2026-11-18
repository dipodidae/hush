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

- Palette: deep indigo + warm amber.
- The player and their tools are **faint violet**.
- **Amber = danger** (lanterns, alert guards, alert icon).
- **Violet = you** (player, knife, darts, ink pots).
- Violet never appears on guards or hazards; amber never appears on the player.
  `tools/gfx_convert.py` enforces this by file-name role prefix.

## Scope (MVP)

In: awareness states, conditional damage, instant restart, ~20 rooms, final
heist room, the three tools, lit-room detection range, BPS release.

Out (do not build, do not design for): overworld, new bosses, new items beyond
the three tools, dialogue/story scenes, multiple save files, any new engine
subsystem not named in AGENTS.md.

## Difficulty curve (to be filled by the designer)

| Floor | Rooms | New idea per room | Par time |
|---|---|---|---|
| 1 | ~6 | one rule at a time (see/not see, knife, darkness) | 10-25 s |
| 2 | ~8 | combine two rules; first lit rooms; darts and ink | 20-45 s |
| 3 | ~6 | combinations and timing; no new rules | 30-60 s |
| Final | 1 | everything, in one screen | 60-90 s |

_(Room-by-room plan lives in `design/rooms/*.yaml` once drafted; the
designer keeps this table in sync.)_
