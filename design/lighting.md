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

## 4. Look (revision 2, human-approved 2026-11-23: "the light effect which is now blocky should be smooth and not so blocky / tily"; revision 3, human-approved 2026-11-23: motion, section 4.5; revision 4, human decision 2026-11-24: "Hybrid: smooth glow only", section 4.5)

Sections 1-3 (the logic, per-cell steps 0..6) are unchanged. Only the drawing changes: the cell steps are **samples at the cell
centres**, and the screen shows a smooth interpolation between them. The old per-cell blocks and 50% checker half-steps are gone.
Revision 3 (4.5) adds motion only; 4.1-4.3 are unchanged. Revision 4: only the violet player glow is shifted pixel by pixel; guard
(amber) light is drawn undisplaced, exactly as in revision 2.

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
  With motion (4.5) the displaced violet glow can also slide up to one cell (normally <= half a cell) onto a wall top or past a corner;
  this is the expected cost of smooth motion, not a bug.

### 4.3 Player glow (violet)

* Same lattice and interpolation (4.1, 4.2) on the violet glow cells of section 3 (player cell 2, its 4 orthogonal neighbours 1),
  with its own levels (at least 3: 0, 1, 2), its own small tile set and its own faint violet ramp (at least 2 colours plus none):
  a soft, round look.
* **Amber wins per tile:** a tile with any amber corner level > 0 shows the amber tile (no violet). Else, a tile with any violet corner
  level > 0 shows the violet tile. Else, the empty tile.

### 4.4 Unchanged rules

* Sprites (guards, the player, icons) and the HUD are never tinted: they stay readable on top of the light.
* The light **logic** is per cell (16 x 16 px): a carrier's committed per-cell map is rebuilt only when it changes cell, facing or
  state, or when an ink cloud appears or ends. The light of a moving guard steps cell by cell (smoothly drawn) and may trail the
  guard (restored by revision 4), bounded by the **catch-up rule** in section 5. For the **player glow only** this stays superseded
  by 4.5: the glow moves with the player pixel by pixel.
* No lag frames (section 5).

### 4.5 Motion (revision 3, narrowed by revision 4): the glow is glued to the player

Human request (2026-11-23): "as smooth as butter with the actor xy coordinates, not just when they hit a new tile ... 0 frame drop."
**Revision 4 (human decision 2026-11-24, "Hybrid: smooth glow only"):** measured on the SNES, pixel-glued guard lights cost far more
than the spare frame time once a room has 3+ guards (`src/dev/L3_REPORT.md` "C5 all rooms": a 450-640-point region costs up to
~239k cycles, ~25+ frames of r14's 50 spare lines; guard light re-renders take a median 90-300 frames in r14-final, and 30-69 % of
lit-guard frames in r14 / r18-final show no or stale guard light). So 4.5 now applies **only to the violet glow carrier**; every
guard (amber) light has d = (0, 0) always and is drawn as in revision 2 (4.1/4.2, steps cell by cell, may trail per the section 5 catch-up rule).
All math is integer; `floor` rounds toward minus infinity, `X >> 3` = floor(X / 8), `X & 7` = X - 8 * floor(X / 8) (0..7).

1. **Carriers.** Every guard with light (section 3) is an amber carrier (never displaced, revision 4); the player glow is the violet
   carrier (the only displaced carrier).
   * Guard g: `l_g(i, j)` = the 4.1 lattice levels (N = 7, integers 0..6) of g's **committed** per-cell map **alone** (all other
     guards' cells = 0). 33 x 29 points, i = 0..32, j = 0..28.
   * Player: `l_v(i, j)` = the 4.1/4.3 lattice levels (NV = 3, integers 0..2) of the section 3 glow cells of the player's committed
     glow cell.
2. **Displacement** (violet glow carrier only; amber: dx = dy = 0 always). `(cx, cy)` = the cell the carrier's committed light was computed from; `(px, py)` = the carrier's current
   centre pixel (room-relative, the same point the engine uses to pick the carrier's cell, so d = 0 when the carrier stands on its
   cell centre).
   * `dx = clamp(px - (16 * cx + 8), -16, +16)`, `dy = clamp(py - (16 * cy + 8), -16, +16)`.
   * The engine may quantize to a step `D` in {1, 2} px, rounding toward zero: `dx' = sign(dx) * D * floor(|dx| / D)` (same for dy).
     The engine reports D. Below, (dx, dy) means the quantized values.
   * Effect: when the map is up to date the light moves with the carrier pixel by pixel; while a job is still catching up (stale
     map) the light still follows the carrier for up to one cell, so there is no gap and no trail. If the map is more than one cell
     stale, the light waits at the clamp and moves on at the next commit.
3. **Displaced lattice** (separable, rounded; per carrier, l = l_g or l_v):
   * Horizontal: `X = 8 * i - dx`, `i0 = X >> 3`, `t = X & 7`;
     `H(i, j) = floor(((8 - t) * l(i0, j) + t * l(i0 + 1, j) + 4) / 8)`.
   * Vertical: `Y = 8 * j - dy`, `j0 = Y >> 3`, `s = Y & 7`;
     `V(i, j) = floor(((8 - s) * H(i, j0) + s * H(i, j0 + 1) + 4) / 8)`.
   * Any l or H index outside i = 0..32 / j = 0..28 counts as 0. V stays in 0..N-1 (0..NV-1 for violet); with d = 0, V = l.
   * A lone level-1 point never vanishes: it survives at t <= 4 on one side or t >= 4 on the other (same for s).
4. **Composite.** Amber `A(i, j)` = the 4.1 lattice of the composite per-cell map (each cell = the brightest guard step,
   section 3), undisplaced: exactly revision 2. (This equals `max over guards g of l_g(i, j)` everywhere except at edge/corner
   points where two guards' lights meet, where the composite lattice can be brighter; the composite lattice is the rule.) Violet =
   `V_v(i, j)` with the glow's displacement. The tile at 8x8 position
   (i, j) uses corners (i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1) and is chosen exactly as in 4.2/4.3 (amber wins per tile,
   else violet, else empty). Same tiles, same corner LUT, same ramp: no new tiles.
   * **Substitute tiles** (director decision, option A: displaced lattices produce tuples no stored tile shows, e.g. (5,2,5,2),
     and full coverage, ~636 amber tiles, does not fit the 192 VRAM slots): a corner tuple t that no stored tile shows (in any
     H/V flip) is drawn with the stored tile orientation s that minimizes `E(t, s)` = sum over the 64 tile pixels of
     `(L_t(x, y) - L_s(x, y))^2`, L = the 4.2 bilinear value; ties go to the larger corner sum, then the lexicographically smaller
     tuple. A tuple with any corner >= 1 is never drawn empty. The generator (`tools/autotile.py` `light_shown` / `light_lut`)
     applies this offline, so there is zero per-frame cost. Since revision 4 amber is never displaced, so amber substitutes do not
     occur in practice (the amber LUT stays the reference); violet substitutes still can.
   * Visible effect: at the glow's edge while the player moves a tile may be off by about one level. Expected, not a bug.
5. **Update rate.** The glow is re-rendered whenever its quantized displacement or committed map changes, and a guard light
   whenever its committed map changes, as often as the frame budget allows.
   * Target: the glow **every few frames** for a moving player (the engine reports the measured rate). Guard lights step cell by
     cell and may trail the guard, bounded by the section 5 catch-up rule.
   * Between glow updates the glow jumps by a few px (target <= 4 px per update), **never by a whole cell** (except the stale-map
     case of item 2).
   * It must **never cause a lag frame**. The engine reports the measured update rates (frames between renders of a moving
     carrier, glow and guards separately, median / p90 / max per room, incl. r13, r19, final) and how often the glow sits at the
     16 px clamp.
6. **Logic unchanged.** Section 3 and the guard AI do not change: "amber is seen" stays true at cell level for the committed map.
   The drawn glow may lead or trail the logic by < 1 cell (normally <= half a cell); the per-cell map, not the pixels, is the truth.

## 5. Accuracy contract (for qa)

* For every guard in every room, in every state: a floor cell is lit by that guard **iff** the rules of section 3 say so.
  The AI tests the exact pixel line every 8 px; light is a cell-level approximation, so a test compares the light map with the
  rules of section 3, not with pixel-level AI sight. (Unchanged by the smooth look.)
* **Smooth look (section 4), offline (unchanged):** every stored light tile matches the 4.2 pixel formula for its corner levels;
  every tile with a corner level >= 1 has a non-r0 pixel; the lattice of each committed map follows 4.1.
* **Smooth look, in-emulator (revision 4):** on a frame where the engine reports no pending render or upload, for every 8x8 BG1
  position the tile matches (up to H/V flip) the corner levels looked up in the exported corner LUTs (incl. 4.5 item 4 substitutes):
  `light.lut_amber` / `light.lut_violet` in `build/rooms_gen.lua`, index `((a*n + b)*n + c)*n + d` (n = N = 7 amber, NV = 3
  violet), value = BG1 tile word. These LUTs are the oracle's reference.
  * **Amber (revision 2 rule):** corners = the undisplaced 4.1 lattice of the committed composite per-cell map (4.5 item 4); at every
    cell-centre point (i odd, j odd) the level is exactly `Q(step)` of that cell.
  * **Violet (4.5 rule):** corners = the displaced lattice of 4.5 items 1-3 from the committed glow map and the displacement (dx, dy)
    the engine last rendered the glow with, which it exposes in RAM as carrier 8 (row in `docs/ram_map.md`, read by qa from there).
    qa also checks that displacement follows 4.5 item 2 (clamp, quantization by the reported D) for the player position it was
    rendered from.
  * Per tile, amber wins over violet (4.3).
* **Catch-up (guard light liveness; director decision 2026-11-24, from measured L2 / L3 builds):** a stale episode runs from the
  frame a guard's light signature (class, facing, cell) changes to S to the first frame the light drawn in VRAM for that guard is S
  **or any later signature of that guard** (a guard that changes cell faster than its light job, e.g. a charging Alert guard, closes
  each episode when a newer light is shown; otherwise the episode would never close while it runs). Over a solution replay / walk of every room, per room: median <= 15, p90 <= 40, max <= 90 frames. "All light idle"
  (nothing pending at all) is **not** a liveness requirement: with constantly moving guards the light is legitimately always busy.
* The light never shows on the HUD, in the item menu or on the ending screen.
* Light work must not add lag frames (hard requirement, including the per-frame motion of 4.5): the engine spends only the time
  left in each frame.

## 6. Out of scope

Torches as light sources (they would be amber but harmless: confusing), light that tints sprites, light on the overworld.
