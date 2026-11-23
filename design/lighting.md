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
| one brightness | soft falloff in 6 steps from the lantern outwards, drawn as a smooth dithered gradient (section 4) |
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

* **Fringe (d = R + 1, step 1, the faintest light):** the light is per cell, the AI is per pixel. A guard walking between two cells can
  see half a cell further than its cell says, so the ring just past the range is drawn as a faint fringe: "maybe". Full shadow is
  always safe; amber is always seen; the fringe is seen only while the guard is between cells.

* **Player glow (violet = you):** the player's cell (step 2) and its 4 orthogonal neighbours (step 1) get a faint violet light, on
  floor cells only (also inside the ink cloud) and only where no amber light is. It does
  not affect guards; it only keeps the player readable in deep shadow.

## 4. Look (revision 2, human-approved 2026-11-23: "the light effect which is now blocky should be smooth and not so blocky / tily")

Sections 1-3 (the logic, per-cell steps 0..6) are unchanged. Only the drawing changes: the cell steps are **samples at the cell
centres**, and the screen shows a smooth interpolation between them. The old per-cell blocks and 50% checker half-steps are gone.

### 4.1 Lattice (corner values)

* A lattice of points every 8 px (the 8x8 tile corners): **33 x 29 points** over the 16 x 14 cell grid. Point (i, j), i = 0..32,
  j = 0..28, sits at pixel (8i, 8j) of the room area.
* Intensity of a cell: `I(cell) = step` (0..6; 0 = no light). Cells outside the grid count as 0.
* **Cell centre** (i odd, j odd): the cell's own `I`.
* **Edge midpoint** (exactly one of i, j odd): the average of the 2 cells sharing that edge.
* **Cell corner** (i even, j even): the average of the 4 cells touching it (always divided by 4; outside cells are 0).
* **Quantization:** a point value v (0..6, may be fractional) is stored as a level `Q(v) = floor(v * (N - 1) / 6 + 0.5)`, 0..N-1.
  N >= 5; the engine chooses N to fit VRAM/ROM and reports it (more is better; **N = 7 gives `Q(step) = step` exactly**). Q is
  monotone, `Q(0) = 0`, `Q(1) >= 1`, `Q(6) = N - 1`.

### 4.2 Tiles (bilinear gradient, ordered dither)

* Each 8x8 BG1 tile shows a bilinear gradient between its 4 corner levels a (top-left), b (top-right), c (bottom-left),
  d (bottom-right). For tile pixel (x, y), x, y = 0..7: `u = (x + 0.5) / 8`, `w = (y + 0.5) / 8`,
  `L = a(1-u)(1-w) + b·u(1-w) + c(1-u)w + d·u·w`.
* **Ramp:** K colours `r0..r(K-1)`, r0 = none (adds nothing), then at least 4 amber colours from faint deep amber (edge) to a bright
  warm core, monotone in brightness and warmth (art owns the colour values, engine the palette slot).
* **Dither (4x4 Bayer):** `p = L * (K - 1) / (N - 1)`, `lo = floor(p)`, `f = p - lo`; the pixel is `r(lo + 1)` if
  `f > (B[y mod 4][x mod 4] + 0.5) / 16`, else `r(lo)`, with `B = [[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]`.
* Adjacent tiles share their corner points, so the gradient is continuous across tile seams: **no visible 8 px or 16 px block edges
  and no checkerboard cells.**
* The tiles are **precomputed** (one per distinct corner-level 4-tuple that the engine supports); H/V flips may be used to share
  tiles (a flipped tile has a mirrored dither pattern; that is allowed). The engine reports N, K and the tile count.
* The light is still **added** (colour math on the sub screen): it brightens and warms; it never darkens.
* **Step 1 (far end, fringe) stays faintly visible:** any tile with a corner level >= 1 has at least one non-r0 pixel.
* **Boundary fade:** the light fades over about half a cell on each side of a lit/unlit boundary; for example a dark wall top next
  to a lit lane may catch a faint 8 px fade at its edge. This is expected, not a bug: the logic (section 3) still says that wall is unlit.

### 4.3 Player glow (violet)

* Same lattice and interpolation (4.1, 4.2) on the violet glow cells of section 3 (player cell 2, its 4 orthogonal neighbours 1),
  with its own levels (at least 3: 0, 1, 2), its own small tile set and its own faint violet ramp (at least 2 colours plus none):
  a soft, round look.
* **Amber wins per tile:** a tile with any amber corner level > 0 shows the amber tile (no violet). Else, a tile with any violet corner
  level > 0 shows the violet tile. Else, the empty tile.

### 4.4 Unchanged rules

* Sprites (guards, the player, icons) and the HUD are never tinted: they stay readable on top of the light.
* The light **logic** is per cell (16 x 16 px). The light of a moving guard steps cell by cell (smoothly drawn) and may trail the
  guard by a few frames; it is rebuilt only when a guard changes cell, facing or state, or when an ink cloud appears or ends.
* No lag frames (section 5).

## 5. Accuracy contract (for qa)

* For every guard in every room, in every state: a floor cell is lit by that guard **iff** the rules of section 3 say so.
  The AI tests the exact pixel line every 8 px; light is a cell-level approximation, so a test compares the light map with the
  rules of section 3, not with pixel-level AI sight. (Unchanged by the smooth look.)
* **Smooth look (section 4):** at every cell-centre lattice point (i odd, j odd) the shown level is exactly `Q(step)` of that cell
  (lit cell centre = its step, unlit cell centre = 0 / dark); edge-midpoint and corner points equal `Q` of the 4.1 averages. Offline:
  every stored light tile matches the 4.2 pixel formula for its corner levels; every tile with a corner level >= 1 has a non-r0 pixel.
  In-emulator: the BG1 tile chosen for each 8x8 position matches the corner levels computed from the per-cell map (up to H/V flip).
* The light never shows on the HUD, in the item menu or on the ending screen.
* Light work must not add lag frames: the engine spends only the time left in each frame.

## 6. Out of scope

Torches as light sources (they would be amber but harmless: confusing), light that tints sprites, light on the overworld.
