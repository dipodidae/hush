# HUSH tile spec (T0): autotiled background

Status: **revision 3, BUILT (T0). Human approved the look and said to pick the open questions' defaults (see "Decisions").** Spec comes before tests, art and code (AGENTS.md rule 2).
Supersedes the 5-kind cell model in `docs/gfx/art_map.md` section 3.1 and `tools/roomgen.py` `cell_kinds` once built.
Scope extension: doorway, pit and water tiles and a grid-driven tile placement are outside the original MVP list in `design/pillars.md`.
The human approved them for this task (director question, "Everything incl. new tile types" + "Direct tilemap blit"); `design/pillars.md` Scope
carries the matching line. **No shipped room (`design/rooms/*.yaml`) uses `O` or `W` until question 1 is answered.** They exist in the tileset,
the validator and the gallery dev room only, so no guard-sight or arrow behaviour changes in this task.

Goal (human requirement): a seamless, autotile-compatible tileset with dedicated edge, corner and centre tiles. Adjacent tiles
connect; borders and surface transitions continue across tile boundaries. No more "floating island in a ragged dark mass".

## 1. Model

* Grid: 14 rows x 16 columns of cells (16x16 px; the visible window is 256x224). One cell = 4 **quarters** (8x8 SNES tiles): NW NE / SW SE.
* Autotiling is done **per quarter** (the RPG-Maker "2x2 sub-tile" blob method). A quarter looks at 3 neighbours: the vertical one
  `v` (N for NW/NE, S for SW/SE), the horizontal one `h` (W for NW/SW, E for NE/SE) and the diagonal `d`. This gives the full
  47-case blob result from only 5 tile shapes per quarter position (fill, v-edge, h-edge, outer corner, inner corner).
* Out-of-grid neighbours count as **wall**.
* Neighbour classes used by the rules:

| symbol(s) | class | solid |
|---|---|---|
| `#` | WALL | yes |
| `.` `S` `X` `a-h` | FLOOR | no |
| `p` | PILLAR (floor-like for autotiling; own art) | yes |
| `D` | DOOR (floor-like) | no |
| `O` | PIT | yes |
| `W` | WATER | yes |

* "open(x)" = x is not WALL. Pillar, door, pit and water all count as open for the wall rules (the wall draws a rim toward them).
* The tile choice is a **pure function of the grid and a seed** (`sha256(room id, cell, salt)`, same hash as today).

## 2. Tile vocabulary

Collision comes from the grid (engine builds `$7F2000` from the grid, not from tile ids). Priority: 1 = hides sprites, 0 = sprites in front.

| surface | role | collision | priority | BG palette row (existing numbering) |
|---|---|---|---|---|
| floor | walkable ground, brick skeleton (mortar rows y=0,8; joints x=0,8) | walk | 0 | 3 |
| wall roof | top surface of a wall mass | solid | 1 | 7 |
| wall face | front of a wall seen from below (floor south of it) | solid | 1 | 6 |
| pillar | free-standing cover, own 16x16 art incl. base shadow | solid | 0 | 5 |
| exit | glow marker on floor (`X`) | walk | 0 | 4 |
| door | open archway threshold in a one-cell wall gap (`D`) | walk | 0 (whole cell: a lintel must never hide a sprite) | 6 (frame), 3 (threshold) |
| pit | dark void with rim | solid (sight rule: open question 1) | 0 | see question 2 |
| water | still water with shore line | solid (sight rule: open question 1) | 0 | see question 2 |

Pit and water are obstacles Link and guards never enter. They do not use vanilla pit (`$20`) or water tile types.
**Gameplay side effect (must be decided, question 1):** today every non-zero `$7F2000` value blocks guard line of sight (`guard_vision.asm:143`),
guard boxes (`guard_box.asm:39-40`), the knife check and arrows. A solid pit would therefore also block sight, which looks wrong
(you see across it). Until the human decides, no shipped room may contain `O` or `W`.

## 3. Autotile rules

### 3.1 Quarter classes

For a quarter with neighbours `v`, `h`, `d` and a "joins" predicate `J(x)` that is surface specific (below), the class is:

| J(v) | J(h) | J(d) | class | meaning |
|---|---|---|---|---|
| 1 | 1 | 1 | FILL | interior |
| 0 | 1 | - | V_EDGE | border toward `v` |
| 1 | 0 | - | H_EDGE | border toward `h` |
| 0 | 0 | - | OUTER | convex corner |
| 1 | 1 | 0 | INNER | concave corner (diagonal is the odd one out) |

Total reachable cases per cell = 47 (blob), produced by 4 quarters x 5 classes.

### 3.2 Surface rules

| surface | J(x) | notes |
|---|---|---|
| wall roof | x is WALL | N quarters use the table. S quarters use the face rules when S (cell below) is open. |
| wall face | cell is WALL and the cell below is open | bottom half of the cell. Top half is the roof's N quarters. |
| floor | x is not WALL (floor, door, pit, water, pillar all join) | edges are shade only: N edge = contact shadow, W/E edge = thin shade strip, S edge = lip. Never high contrast. |
| pit, water | x is the same basin **or** WALL | a wall hides the basin interior, so no rim is drawn against walls. |
| pillar | none | fixed 2x2 art. |
| door | none | fixed art, see 3.4. |

Floor next to a pillar, pit, water or door: treated as joined (FILL). The obstacle draws its own edge.

### 3.3 Wall face and ends

For a WALL cell whose south cell is open, the bottom quarters (SW, SE) are face quarters. `h` = W cell (for SW) or E cell (for SE);
`d` = the cell below `h` (SW or SE diagonal of the cell). The table is total over (h, d):

| h | d | face tile | what it is |
|---|---|---|---|
| WALL | open | BRICK (A on even tile column, B on odd tile column, absolute grid tile x) | the face continues sideways (the neighbour is a face cell too) |
| WALL | WALL | FACE_INNER | the face meets a wall mass that continues south (concave corner) |
| open | open | END_CAP | the face stops at open floor |
| open | WALL | END_CAP (reused; the wall roof below it draws its own N rim) | step: floor beside us, wall below that floor |

At the left/right grid edge the `h` and `d` lookups clamp to the in-grid column (the face continues off-screen as BRICK, never FACE_INNER).
Reference implementation: `tools/art/autotile_art.py` `autotile()`; QA golden tables must match it.

The N quarters of a face cell are ordinary roof quarters (so the roof lip sits on top of the brick strip and the roof rim continues
along the wall).

### 3.4 Special cells

* **Outer outline.** The grid edge counts as wall, so the outline is simply more wall mass. There is no separate frame tile.
  Wall mass that is 2 or more cells away from any open cell (all 8 neighbours WALL) is **deep**: it uses the calm FILL tile, with
  speckle variants on at most ~15% of cells, and crack/seam blocks only on at most 2 cells per room. The rim zone (a wall cell with an
  open 8-neighbour) never uses speckle variants.
* **Door** (`D`): one 16x16 archway art for a **horizontal** wall: W and E cells are WALL, N and S cells are not solid, the wall is one
  cell thick, and no two `D` are 4-adjacent. Vertical walls get no door (that would need a second art). Art: threshold stone plus jamb
  posts and a lintel drawn inside the cell. **Whole cell priority 0**: a guard or Link standing in the doorway is fully visible.
* **Pillar**: 2x2 fixed art with its own base shadow. Floor around it uses plain FILL so seams stay clean. Because `p` is open for the
  wall rules, walls beside a pillar (r05, r14) get rim tiles toward it; **r05 and r14 look different even though their collision is unchanged.**
* **Exit**: 2x2 fixed art with a floor background (the art includes the brick skeleton so it seams with floor FILL).

### 3.5 Decoration (kept from E5, rate-limited)

Decorations replace a cell's FILL/edge result only when allowed below. All E5 placement rules in `roomgen.variant_plan` carry over except
the ones below; **where this table and `variant_plan` disagree, this table wins** (in particular wall-top variants drop from ~55% of ceil cells
to at most ~15% of deep cells, and crack/seam blocks to at most 2 per room):

| survives | rule |
|---|---|
| floor cracks, worn, moss, rune | only on floor cells whose class is FILL in all 4 quarters; `f_shadow` is removed (the floor N edge is now the autotile contact shadow). **Lit-room floor glow pools (`f_glow`, `f_glow2`) are dropped**: amber boxes on the floor hurt guard readability |
| wall faces: torch, sconce, banner, sigil, crack, warm | only on face cells whose two bottom quarters are BRICK (not caps/inner) |
| wall roof variants | only on deep wall cells (section 3.4) |

## 4. Placement algorithm (what roomgen must compute)

1. Classify every cell (section 1 table).
2. For every cell and every quarter compute `(class, surface)` by sections 3.1 to 3.3.
3. Map `(surface, quarter position, class)` to a logical tile name (table `TILE_NAMES`, owned by `tools/art/` and listed in the art
   brief) and then to a tile word `vhoppp cccccccccc`: character index, palette row, priority and flip bits.
4. Apply decoration (3.5) deterministically.
5. Emit the per-room data defined by the engine contract (section 4b).

Symmetry: the NW and NE quarters of an edge/corner class are mirror images and may share one character with the H flip bit, **except
for floor** (its brick joints break under a mirror). V flips are never used (light comes from the top).

### 4b. Engine contract (what the engine agent must deliver; owner: engine)

The old model (vanilla objects + tile-id collision through `UnderworldTileTypes`) is replaced for HUSH rooms. Superseded by this change:
`docs/gfx/art_map.md` section 3.1 and 3.5, `docs/engine_notes.md` sections 12-13, `tests/smoke/visual_tiles.lua` (the per-kind tile-word table),
`src/hooks/room_visuals.asm`, and the object-stream path of `roomgen.py`. The engine must:

1. **Choose and justify the per-room data form** and report its ROM size before any art is inserted. Naive 32 x 28 words = 1792 B x 21 rooms is
   about 37 KB and does not fit the current budget (object streams use ~9.4 KB of 12.3 KB). Candidates: (a) 4-bit cell kind per cell
   (112 B/room), autotile on the console in 65816; (b) one tile byte per quarter + a 256-entry attribute table, RLE-compressed.
2. **Hook point:** write the words into the `$7E2000` BG2 buffer after `LoadAndBuildRoom` (`src/hooks/roomload.asm:40`), then DMA as today.
3. **Collision:** replace the tile-type lookup in `Hush_AttrSet` (`roomload.asm:79-101`) by a grid-derived map. Values stay `$00` walk / `$01`
   solid so every other consumer (guard vision, guard box, knife, arrows) is unchanged. All 21 rooms must produce a byte-identical `$7F2000`.
4. **Ledger:** every new region and hook goes in `src/FREESPACE.md` and gets a hook header (`src/hooks/README.md`).
5. Other consumers of the grid symbols that must learn `D O W` (owners in brackets): `tools/roomgen.py:217,309,497` [engine],
   `tools/solve_rooms.py:115` [qa], `tests/lib/bot.lua:117`, `tests/smoke/mustnot2.lua:57` [qa].

### Seam rule

Every logical tile declares an **edge profile** for each of its four 8-px sides (a short code from a closed list, for example
`wall_fill`, `wall_rim_n`, `floor_fill`, `floor_shade_n`, `face_brick_a`). Two tiles may be neighbours in a placement only if the
touching sides carry the same code, and tiles with the same code must have **identical palette indices** along that side. When the two tiles
use different BG palette rows, the colours of those rows for the indices used on the seam must also be identical (checked from
`bg_dungeon.yaml`). The art brief lists the profiles. A QA check compares the pixel columns for every pair that can occur.

## 5. New grid symbols

Existing symbols are unchanged. Additions to `GRID_SYMBOLS`:

| symbol | meaning | validate_specs.py rules |
|---|---|---|
| `D` | doorway | W and E cells are `#`, N and S cells are not solid (`#`, `p`, `O`, `W`), not 4-adjacent to another `D`, never in rows 0, 1, 13 or cols 0, 15. Walkable for reachability. |
| `O` | pit | solid for reachability. Never 4-adjacent to `S`, `X` or a guard letter. Not 4-adjacent to `W`. |
| `W` | water | same as `O`. |

`S` to every `X` must stay reachable with `#`, `p`, `O`, `W` as solid (the existing reachability check, with the extended solid set).
Guard letters must keep a walkable cell. The 21 existing rooms use none of `D`, `O`, `W`, so they remain valid unchanged.

## 6. Tile budget (unique 8x8 cells)

| group | minimum | stretch |
|---|---|---|
| wall roof: FILL + 3 speckle (4); N quarters 5 classes mirrored NW=NE (5); S quarters (south is wall) FILL/H_EDGE/INNER mirrored (3) | 12 | 20 (crack, seam blocks) |
| wall face: BRICK A/B, END_CAP, FACE_INNER (mirrored for the E side) | 4 | 6 |
| floor: 4 quarter positions x 5 classes | 20 | 20 |
| floor decoration (4 blocks) | 16 | 28 |
| face decoration (torch, sconce, banner, sigil, crack, warm) | 10 | 14 |
| pit (10) + water (10) | 20 | 24 |
| door | 4 | 8 |
| pillar + exit | 8 | 8 |
| **total** | **94** | **128** |

The current build uses about 160 cells of art over 3 sheets (many are E5 variants), so this is a net reduction. The pit and water sets use H mirroring, so 10 each. The engine owns the sheet
and compressed-slot plan.

## 7. Acceptance criteria (QA turns these into tests)

1. **Golden table:** a hand-written table in `tests/` (grid snippet -> expected (surface, quarter, class, tile name)) covers all 47 blob cases for
   wall roof, floor, pit and water, and all four (h, d) face cases. `autotile(grid)` reproduces it exactly, and is total (never fails) over random
   valid grids.
2. **Coverage:** over the gallery room, the set of (surface, quarter position, class) equals the full expected set; plus BRICK, END_CAP,
   FACE_INNER and the door appear.
3. **Collision:** the engine-built `$7F2000` equals the collision implied by the grid (`# p O W` solid, all else walk). For all 21 existing
   rooms it is byte-identical to the current map.
4. **Seams:** the seam rule check (section 4, including the palette-colour clause) passes for every adjacent tile pair in all 21 rooms and the gallery.
5. **Determinism:** two runs of roomgen produce identical output.
6. **Budget:** unique 8x8 characters used by all rooms is at most the stretch number in section 6; the per-room data size is reported (4b.1).
7. **Readability:** floor autotile edge tiles (every class except decor `f_glow`, `f_glow2`, which are lit-room light pools and keep amber) contain
   no amber index, and their lightness step from the base floor stays within the limit the art brief states before painting (art owns the number).
8. All 21 rooms load, walk-exit tests still pass, and `make leakcheck` has no vanilla tile or palette hits.
9. Visual: before/after screenshots of r01, r05, r09, r14, r18 and final, plus the gallery with a guard standing in the doorway, are reviewed by
   the human before the engine change merges.

## 8. Gallery dev room (QA owns the file, `tests/dev/rooms/`)

One room that exercises everything in a single screen:

* a wall mass with an irregular outline: a straight run, an L, a U (both inner corner kinds), a 1-cell pillar of wall, a diagonal
  staircase edge, and a 1-cell gap, arranged so all four (h, d) face cases occur;
* a floor region with all four edge shades, all four outer corners and all four inner corners;
* a 3x3 pit, a plus-shaped pit and a lone 1-cell pit; the same three shapes in water (split over two gallery screens if one does not fit);
* one doorway in a horizontal wall, with a guard standing in it in one variant of the room;
* a pillar, an exit, `S`, and one guard on floor.

## Open questions for the human

1. **Pit and water vs guard sight and arrows.** Solid pits block guard sight, darts and the ink line like walls. Options:
   (A) accept that (simplest, odd looking: you cannot see across a pit); (B) add a second collision value that sight/arrows ignore (engine work in
   `guard_vision.asm`, `guard_box.asm`, arrows, knife; AI-adjacent); (C) keep `O`/`W` gallery-only for now (**recommended, the default in this spec**).
2. **Palette for pit and water.** BG rows 0 and 1 hold the HUD, row 2's left half is shared with OBJ row 0. Proposal: pit and water use the **left
   expansion** (slots 4-7 of VRAM, colours 1-7 of rows 3-7, currently unused by room tiles). The engine must confirm slot 4-7 can be loaded with our sheets.
3. **Doorway meaning.** `D` is an open archway in a one-cell horizontal wall only. Locked or closed doors would be gameplay and need their own spec.
4. **Edge contrast on the floor.** Floor edge shading is deliberately subtle for guard readability. Say if you want it stronger.
5. **Engine data form.** (4b.1) The engine will propose on-console autotile (112 B/room) or a precomputed table. This is reported before art is inserted.

## Decisions (director, delegated by the human: "pick goated decisions")

1. Pit / water: **gallery-only** (option C). They exist in the tileset, `validate_specs.py` and `tests/dev/rooms/gallery.yaml`; no shipped room uses them, so guard sight and arrows are unchanged.
2. Pit / water palette: **no new rows**. Pit uses BG row 7 (wall palette), water uses row 5 (pillar palette), right expansion, like every other tile.
3. Door: open archway only, horizontal one-cell walls only. Pit / water: visual obstacles only.
4. Floor edge contrast stays subtle.
5. Engine data form: **cell-level** data. Per room a RLE of 224 cell ids + a global dictionary of 4 tile words per distinct cell (81 cells for the 21 rooms), decoded by `Hush_Blit`.

## As built (T0)

| Part | Where |
|---|---|
| tile art, autotiler, decoration, char / cell / tile-id registry | `tools/autotile.py` (`autotile`, `autotile_px`, `place`, `char_words`, `tile_types`) |
| sheet painter + previews | `tools/art/autotile_art.py apply | preview` (clears and repaints GFX_00 ids 0-63 and GFX_10 ids 128-191; GFX_06 is empty) |
| ROM data | `tools/roomgen.py` -> `build/rooms_gen.asm`: ROOM TABLE (+24..26 = RLE pointer), `Hush_CellWords`, per-room RLE, `UnderworldTileTypes` rewrite at `$0E9659` |
| decoder | `src/hooks/roomload.asm` `Hush_Blit` at `$1FB680` (called after `LoadAndBuildRoom`); `Hush_AttrSet` is unchanged apart from dropping the unused "types $10-$1B" rule |
| removed | vanilla object hacks (`$009EDA`, `$00BAA4`, `$018212`, `$018014`, `$009F72`, `Hush_DrawVariant`) |
| tests | `tests/unit/test_autotile.py` (oracle, totality, collision, gallery coverage, RLE round trip, seams, budgets), `tests/smoke/visual_tiles.lua`, `tests/smoke/visual_gallery.lua` |
| numbers | 131 chars, 113 unique 8x8 cells (budget 192), 81 distinct cells, ROM data 5.7 KB of 12 KB |

Role deviation, recorded for the director: the `designer`, `qa` and `critic` sub-agents returned empty results and wrote nothing, so the spec, tests and engine work of T0 were written directly by the main agent.
