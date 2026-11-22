# HUSH lighting: lantern light is the guard's sight

Human-approved extension (2026-11-22): "use the colour illumination of the first castle area of vanilla ALttP, expanded and
redesigned for our mechanics, to make navigating more intuitive; guards illuminate their path with their lights and the shadow is
softly illuminated." Owner: designer. Engine notes: `docs/engine_notes.md` section 16.

## 1. The idea in one sentence

**Amber light on the floor is exactly where a guard can see you.** If you stand in amber, you are seen; if you stand in shadow, you
are not. The light is drawn from the same rules the guard AI uses (cone, range, walls, ink), so the player never has to guess.

## 2. Where it comes from

The vanilla castle-escape rooms light Link's lamp cone with a second background layer (BG1, a pre-drawn cone) that colour math
*adds* onto the dark room (`OrientLampLightCone`, `bank_00.asm:15413`; `RoomDraw_LampCones`, `bank_01.asm:5679`). HUSH keeps the
technique (BG1 on the sub screen, additive colour math onto BG2 and the backdrop) and changes what is drawn:

| vanilla castle | HUSH |
|---|---|
| one fixed cone, Link's lamp | one light shape per guard, rebuilt live, any number of guards |
| cone ignores walls | light stops at walls (walls in the beam catch it) and in the ink cloud |
| one brightness | soft falloff in 6 steps from the lantern outwards, dithered half-steps |
| the rest is pitch black | the rest is soft, readable shadow (the room palette); a faint violet glow follows the player |

## 3. Rules (must match the guard AI exactly at cell level)

The room grid is 16 x 14 cells. A guard's light is computed from the cell that holds the guard's centre.

| guard state | light shape | brightness |
|---|---|---|
| Unaware | 90-degree cone in the facing direction (`|lateral| <= forward`), range = sight range | falloff (table below); the two cone diagonals are one step dimmer (soft edge) |
| Suspicious "?" | all around (the square of side 2 x range + 1), as the AI senses all around | falloff capped at step 4 (a raised, searching lantern) |
| Alert "!" | all around | falloff + 1 step (unhooded lantern), capped at 6 |
| Asleep, dead, gone | none | - |

* **Range** = the sight range: 5 cells in dark rooms, 8 cells in lit rooms (`hush_range` 80 / 128 px). Lit rooms therefore show
  bigger light. Distance is Chebyshev (`max(|dx|, |dy|)`), as in `Hush_Vision`.
* **Walls (line of sight):** light travels outwards ring by ring. Take the guard's facing as "forward": a cell at forward distance
  d >= 1 and lateral offset b (|b| <= d) is *reached* iff its parent, the cell at (d - 1, round(b * (d - 1) / d)) (round half toward
  zero), is reached and open (not solid, not ink). The guard's own cell (d = 0) is always reached. A reached open cell is lit; a reached
  solid cell is lit only if it is a **face** (a solid cell whose cell below is open: wall fronts, pillar fronts), so wall tops and the
  void around the room stay dark; nothing behind a solid cell is reached. All-around light is the union of the 4 facings.
* **Ink cloud:** the 3 x 3 cells of the cloud are dark and block light, as they block sight.
* **Several guards:** each cell shows the brightest light that reaches it.
* **Falloff** (step by Chebyshev distance d from the guard's cell; R = range):

| R | d = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| 5 (dark) | 6 | 6 | 5 | 4 | 3 | 2 | **1** | | | |
| 8 (lit) | 6 | 6 | 6 | 5 | 5 | 4 | 3 | 3 | 2 | **1** |

Every step >= 1 is visible on screen, so the far end of a cone is dim but never invisible.

* **Fringe (d = R + 1, step 1, the faint checker):** the light is per cell, the AI is per pixel. A guard walking between two cells can
  see half a cell further than its cell says, so the ring just past the range is drawn as a faint fringe: "maybe". Full shadow is
  always safe; amber is always seen; the fringe is seen only while the guard is between cells.

* **Player glow (violet = you):** the player's cell (step 2) and its 4 orthogonal neighbours (step 1) get a faint violet light, on
  floor cells only (also inside the ink cloud) and only where no amber light is. It does
  not affect guards; it only keeps the player readable in deep shadow.

## 4. Look

* Steps 1-6 = edge / mid / core amber with 50% checker half-steps: 1 = checker(edge, none), 2 = edge, 3 = checker(mid, edge),
  4 = mid, 5 = checker(core, mid), 6 = core. The light is added (it brightens and warms the floor; never darkens it).
* Violet glow: 2 steps (checker, solid), both faint.
* Sprites (guards, the player, icons) and the HUD are never tinted: they stay readable on top of the light.
* Light is per cell (16 x 16 px). The light of a moving guard steps cell by cell and may trail the guard by a few frames; it is
  rebuilt only when a guard changes cell, facing or state, or when an ink cloud appears or ends.

## 5. Accuracy contract (for qa)

* For every guard in every room, in every state: a floor cell is lit by that guard **iff** the rules of section 3 say so.
  The AI tests the exact pixel line every 8 px; light is a cell-level approximation, so a test compares the light map with the
  rules of section 3, not with pixel-level AI sight.
* The light never shows on the HUD, in the item menu or on the ending screen.
* Light work must not add lag frames: the engine spends only the time left in each frame.

## 6. Out of scope

Torches as light sources (they would be amber but harmless: confusing), light that tints sprites, light on the overworld.
