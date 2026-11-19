# Art map: which pixel of which `gfx/src` PNG ends up where in the real game

Owner: engine/art helper (research for the director). **Measured, not guessed**: every row below was read out of MesenCE
(headless, `build/hush.sfc` built 2026-11-19 13:25 from the working tree, all 21 rooms of `design/rooms`) and cross-checked
against the usdasm loaders (cited as `bank_XX.asm:line`). Method and how to re-run it: section 13.

Conventions used in every table:

* **cell** = one 8x8 tile of a sheet. `idx = row*16 + col` (all sheets are 16 cells wide; `LINK` is 16 x 56). Pixel position of a
  cell = `(col*8, row*8)`. A "16x16 block at (c,r)" covers cells `(c,r) (c+1,r) (c,r+1) (c+1,r+1)`, i.e. PNG pixels `x=8c..8c+15, y=8r..8r+15`.
  Cell numbers are written `(col,row)`; tile/idx numbers are decimal unless prefixed `$`/`0x`.
* **expansion**: a 3bpp sheet is expanded to 4bpp when it is uploaded (`docs/gfx/formats.md`). **left** = sheet index `i` becomes CGRAM
  colour `i` of the palette row (1-7); **right** = it becomes colour `8+i` (9-15). Which one is a property of the sheet's VRAM slot, below.
* **row** = the 16-colour palette row the tile/sprite selects (BG tilemap bits 10-12, OAM attribute bits 1-3). OBJ row `n` = CGRAM `$80+16n`.
* Flips: the art is drawn once; the game mirrors it with the tilemap/OAM flip bits (H/V). Where a flip is used the table says so, so draw the unflipped version.
* "As the game shows it" colours are the CGRAM values (BGR555 expanded to 8 bit). They differ slightly from the yaml hex (low 3 bits dropped).

---

## 1. The top 15 (read this first)

| # | What | Sheet (file) | Cells (col,row) -> PNG px | Row + expansion | Notes |
|---|---|---|---|---|---|
| 1 | **Floor** (every floor cell `.`, `S`, guard letters: 2090 cells over the 21 rooms, all the same 16x16) | `bg_tileset/GFX_06.png` | block (12,2) = px (96,16) 16x16 | BG row 3, right | one 16x16 block repeated; no checker/variation possible except inside it |
| 2a | **Wall top surface** (`#` whose cell below is wall/pillar/outside the grid; the ceiling) | `bg_tileset/GFX_00.png` | **one** cell (5,1) = px (40,8) 8x8, fills all 4 quarters of the cell | BG row 7, right, **priority 1** | hides sprites that overlap it |
| 2b | **Wall face** (`#` whose cell below is floor: the vertical front side of the wall) | `bg_tileset/GFX_00.png` | top half of the 16x16 cell = the wall-top cell (5,1) twice; **bottom half = face A (4,2) px (32,16) + face B (5,2) px (40,16)** (A on the even tile column, B on the odd one: a 16x8 strip) | face strip BG row **6**, right, priority 1 | solid; added in E3 |
| 2c | **Pillar `p`** (own art, solid) | `bg_tileset/GFX_00.png` | block (12,2) = px (96,16) 16x16 = cells (12,2) (13,2) / (12,3) (13,3) = px (96,16) (104,16) / (96,24) (104,24) | BG row **5**, right, **priority 0** (Link and guards draw IN FRONT of it) | solid; added in E3 |
| 3 | **Exit marker `X`** (walkable, never solid) | `bg_tileset/GFX_06.png` | block (0,0) = px (0,0) 16x16 = cells (0,0) (1,0) / (0,1) (1,1) = px (0,0) (8,0) / (0,8) (8,8) | BG row **4**, right, priority 0 | floor type `$00`; added in E3 |
| 4 | **Guard** (head + body + lantern, all 4 facings, all steps, all states) | `sprite/GFX_BC.png` | **14 blocks** (12 of 16x16, 2 of 8x8), see section 5 (E4 contract) | OBJ row 4 (calm), **OBJ row 6 (alert)**, left | alert only swaps the row, not the pixels |
| 5 | **Awareness icons** `?` `!` `Z` | `sprite/GFX_C5.png` | (12,3) `?`, (13,3) `!`, (14,3) `Z`, (15,3) spare = px (96..127, 24) | OBJ row 4, right | 8x8, drawn 22 px above the guard |
| 6 | **Link** (head + body blocks, 8-step walk cycles, sword poses, bow poses) | `player/LINK.png` | blocks listed in section 8 | OBJ row 7, 4bpp (1-15) | side view is drawn facing **right**; left = H flip |
| 7 | **Shade Knife blade** | `item/GFX_D1.png` | cells (0..11,0) and (0..11,1) | OBJ row 5, right, **idx 1-3 only** | in-game idx 4-7 are the unused magenta shield colours (section 11) |
| 8 | **Shadow** under guards/Link | `sprite/GFX_7D.png` | block (12,2) = px (96,16) | OBJ row 4, right | **GFX_7D is labelled "unused/debug" in the inventory but is drawn** |
| 9 | **Ink cloud** (the bomb explosion held 300 frames) | `sprite/GFX_79.png` | block (6,0) = px (48,0) 16x16, drawn 6x with H/V flips | OBJ row 1 (HUSH ink colours), left | same "labelled unused" problem |
| 10 | Ink Pot (the thrown bomb) | `sprite/GFX_7D.png` | block (14,2) = px (112,16) | OBJ row 2 (flashes rows 0-7), right | |
| 11 | Guard death poof | `sprite/GFX_79.png` | blocks (6,0) then (10,0) | OBJ row 2, left | |
| 12 | Hush Dart (arrow) in flight | `sprite/GFX_73.png` | (10,2) (11,2) (12,2) (13,2) (10,3) (11,3) (12,3) (13,3), 8x8 each | OBJ row 2, left | also "labelled unused" |
| 13 | **HUD** (BG3, rows 2-7 of the screen = px y 16..63) | `hud/GFX_DD.png` (tile ids 0-127) + `hud/GFX_DE.png` (ids 128-255) | 26 distinct cells, section 4 | BG3 sub-palettes 0-3, 7 -> `pal_hud_0x` | 2bpp |
| 14 | Sword hit sparkles / charge stars | `sprite/GFX_79.png`, `GFX_7A.png` | 79: (0,0) (3,0) (7,3), 7A: (6,1) (7,1) | OBJ rows 1/2, left | only while B is held/after a hit |
| 15 | Everything else loaded but **never drawn** in HUSH rooms | `GFX_01 10 0E 1F 18 0F 5C 5D` (BG), `GFX_B9 GFX_86` (sprites), `GFX_C7 D2 D3 D8` | -- | -- | leave as placeholders; nothing on screen shows them |

**Total BG art for all 21 rooms: 15 cells** = floor 4 (GFX_06) + wall top 1 + wall face 2 + pillar 4 (GFX_00) + exit marker 4 (GFX_06). Floors 1/2/3 x lit/dark use **six palette groups** (`pal_dungeon_00..05`, section 3.3):
floor/wall colours differ per variant, the tiles are shared.

---

## 2. What is in VRAM during a room (identical in all 21 rooms: 1 distinct layout, 0 CGRAM differences)

PPU (read from MesenCE): Mode 1, main screen = **BG2 + BG3 + OBJ** (`mainScreenLayers=0x16`; BG1 is hidden and holds a copy of the floor only).
BG2 tilemap at VRAM byte `$0000` (64x64 entries), BG1 `$2000`, BG3 (HUD) `$C000` (32x32), BG1/BG2 characters at `$4000` (4bpp), BG3 characters at `$E000` (2bpp).
The room window is tilemap x 16..47, y 18..45 (32x28 tiles = the 256x224 screen), scroll fixed at (128,144) px of the 512x512 room.

### 2.1 Background sheets (VRAM `$4000 + slot*$800`, 64 cells per slot; tile id = `slot*64 + idx`)

Blockset 0 (`$0AA2=0`), `$0AA1=4`: `SheetsTable_AA1` row 4 = `00 01 10 07 0E 21 18 0F` with slot 3-6 overridden by `SheetsTable_AA2` row 0 = `06 00 1F 18`
-> `$7EC2F8-FB = 06 0E 1F 18` (`bank_00.asm:11564-11570, 11720-11760`). Verified by decoding every VRAM cell (sheet id + cell index are recoverable, section 13).

| slot | tile ids | sheet | expansion | drawn by the rooms? |
|---|---|---|---|---|
| 0 | `$000-$03F` | `GFX_00` | right | **yes**: cell 21 (ceiling) |
| 1 | `$040-$07F` | `GFX_01` | right | no |
| 2 | `$080-$0BF` | `GFX_10` | right | no |
| 3 | `$0C0-$0FF` | `GFX_06` | right | **yes**: cells 44 45 60 61 (floor) |
| 4 | `$100-$13F` | `GFX_0E` | left | no |
| 5 | `$140-$17F` | `GFX_1F` | left | no |
| 6 | `$180-$1BF` | `GFX_18` cells 0-47 + `GFX_5D` cells 48-63 | left | no |
| 7 | `$1C0-$1FF` | `GFX_5C` cells 0-15 + `GFX_0F` cells 16-63 | left | no |

### 2.2 Sprite sheets (OAM: name table 0 = VRAM `$8000`, name table 1 = `$A000`; 8x8 and 16x16 sprites)

| name table / tile ids | sheet | expansion | what draws from it |
|---|---|---|---|
| 0: `$00-$3F` (dynamic, rewritten every frame by `DoNMIUpdates`, `bank_00.asm:1742-1900`) | `LINK` (blocks via DMA), `GFX_D1` (sword), `GFX_73` (arrow/bow pieces), `GFX_D8` (not drawn) | LINK 4bpp, others right/left per tile | Link, blade, arrows |
| 0: `$40-$7F` | `GFX_7D` (`$0AA4=$0A`, `LoadCommonSprites` `bank_00.asm:12651`) | right | shadow, ink pot |
| 0: `$80-$BF` | `GFX_79` | left | explosion, poof, sparkles |
| 0: `$C0-$FF` | `GFX_7A` | left | sparkles (cells 22,23) |
| 1: `$00-$3F` | `GFX_B9` | left | nothing drawn |
| 1: `$40-$7F` | **`GFX_BC`** | left | **guard** |
| 1: `$80-$BF` | `GFX_86` | left | nothing drawn |
| 1: `$C0-$FF` | **`GFX_C5`** | **right** (`LoadSpriteGraphics` forces right for sheet `$52`, `bank_00.asm:12414`) | **icons** (cells 60-63 = tiles `$FC-$FF`) |

Sprite set `$44` (`SheetsTable_AA3` `bank_00.asm:11079`: `46 49 13 52` + `$73` = `B9 BC 86 C5`).

---

## 3. Room background (BG2)

### 3.1 The tilemap entries that exist (E3: 15 distinct words; counted over the 21 rooms: 2090 floor, 1913 wall-top, 667 wall-face, 2 pillar, 32 exit cells)

Tile word = `v h o ppp cccccccccc` (o = BG priority, ppp = palette row). A grid cell (16x16 px) = 2x2 tiles, order TL TR / BL BR. All rows below use the **right** expansion (sheet index `i` -> colour `8+i` of the BG row).
Cell kinds are chosen by `tools/roomgen.py` (`cell_kinds`), collision is **identical** to the plain-wall build (`$01` on `#` and `p`, `$00` everywhere else incl. `X`; test `tests/smoke/visual_tiles.lua`).

| kind | tile words TL TR / BL BR | sheet cells -> PNG px | row | priority | collision | where |
|---|---|---|---|---|---|---|
| floor | `0CEC 0CED / 0CFC 0CFD` | `GFX_06` block (12,2) = idx 44 45 / 60 61 -> px (96,16) (104,16) / (96,24) (104,24) | 3 | 0 | `$00` | `.` `S` guard letters (vanilla floor fill, unchanged) |
| wall top | `3C15 3C15 / 3C15 3C15` | `GFX_00` cell (5,1) idx 21 -> px (40,8), all four quarters | 7 | **1** | `$01` | `#` with wall/pillar below or at the grid bottom |
| wall face | `3C15 3C15 / 3824 3825` | top: `GFX_00` (5,1) twice (row 7); bottom: A `GFX_00` (4,2) idx 36 -> px (32,16), B (5,2) idx 37 -> px (40,16) | top 7, bottom **6** | **1** | `$01` | `#` whose cell below is floor (`.` `S` `X` guard) |
| pillar | `142C 142D / 143C 143D` | `GFX_00` block (12,2) = idx 44 45 / 60 61 -> px (96,16) (104,16) / (96,24) (104,24) | **5** | **0** | `$01` | `p` |
| exit marker | `10C0 10C1 / 10D0 10D1` | `GFX_06` block (0,0) = idx 0 1 / 16 17 -> px (0,0) (8,0) / (0,8) (8,8) | **4** | **0** | `$00` | `X` |

The four sheet areas are disjoint (GFX_00: (5,1), (4,2), (5,2), (12..13, 2..3); GFX_06: (12..13, 2..3), (0..1, 0..1)). Painting rules that follow from the tile wiring:
* **Wall face A/B are a 16x8 strip that repeats every cell**: A is the left 8 px, B the right 8 px of a cell, so a long wall repeats a 16-px pattern. The 8 px above the strip are the wall-top tile (5,1); paint the face so that it meets a top-surface edge at the strip's top row.
* The pillar is a standalone 16x16, draw its own top/front. Priority 0: Link/guards overlapping it draw on top of it (they stand in front); a pillar never hides them, a wall (priority 1) does.
* The exit marker is a floor-level decal on a 16x16 floor cell, nothing hides it; there is no floor tile under it (the 16x16 replaces the floor block), so paint its background too.
* Why these cells: the vanilla tile *types* (collision) of the ids are what the cell needs (`UnderworldTileTypes`, `bank_0E.asm:274`): ids `$024 $025 $02C $02D $03C $03D` = solid, `$0C0 $0C1 $0D0 $0D1` = floor. Other cells of the sheets have other types
  (e.g. `$02` standard, `$27`, ...): **do not move the art to other cells without checking the type table**, a type other than `$00`/`$01` changes how Link and the guards collide.
* How they get on screen: vanilla room objects `$07` (face), `$B8`/`$92` (pillar), `$B9`/`$93` (exit marker) whose 4 tile words are rewritten (`src/hooks/room_visuals.asm`); the wall top is still object `$00`/`$60`.

There is no door, no torch, no separate border tile (the outer border is wall top / wall face like every other `#`).

### 3.2 Priority (important for painting walls)

Wall top, wall face and the ceiling tile have the BG priority bit set. In Mode 1 BG2 priority-1 tiles draw **above** sprites with OAM priority <= 2; guards (`attr $29`) and Link (`$2E`) are priority 2. So a guard or Link whose
sprite overlaps a wall cell is **covered by the wall tile** (Link's head sticks up 8 px above his box). The placeholder shows it: with Link on the top free row his head is cut flat at the wall edge (`tools/art/probe_priority.lua`). Draw wall art so that this looks right (e.g. a dark top face).
The wall-face strip is priority 1 as well (it is the bottom 8 px of the cell, i.e. what Link's head overlaps when he stands directly under a wall). **Pillars and the exit marker are priority 0** (sprites in front).

### 3.3 Palettes of the room tiles (six variants)

The header byte 1 of each room selects an `UnderworldPaletteSets` row (`src/hooks/room_visuals.asm`: rows 0-5 all have the same sprite bytes `00 03 01`, only the BG palette id differs, so **every OBJ palette is identical in all variants**: `tests/smoke/visual_tiles.lua` compares CGRAM `$100-$1FF` of all 21 rooms).
`tools/roomgen.py`: **dark: floor 1/2/3 -> row 0/1/2 -> `pal_dungeon_00/01/02`; lit: floor 1/2/3 -> row 3/4/5 -> `pal_dungeon_03/04/05`** (all in `gfx/src/palettes/bg_dungeon.yaml`; rooms that use floors/lighting outside 1-3 fail the roomgen check).
Each group has 12 elements = BG rows 2-7 as `colours[2(k-2)]` (7 entries, left half) + `colours[2(k-2)+1]` (8 entries, right half; element 0 never drawn). Rows used by the room tiles (all **right half**, so the elements below are `colours[2(k-2)+1]`):

| element (sheet index) | floor (BG 3, `colours[3]`) | exit marker (BG 4, `colours[5]`) | pillar (BG 5, `colours[7]`) | wall face strip (BG 6, `colours[9]`) | wall top (BG 7, `colours[11]`) |
|---|---|---|---|---|---|
| idx 1..7 in every group | pit, floor, floor 2, wall, wall edge, amber, gray | same | same | same | same |

The placeholders of E3 hold the **same colours in all five rows** of a group, tinted per variant (the director will tune them; edit all of the rows 3-7 of a group, or just the ones the new art uses). `colours[0]` (BG row 2 left) must stay equal in all six groups
(it is also OBJ row 0 colours 9-15, used by the bomb flash frames). Authored hex per variant (idx 2 floor / 3 floor 2 / 4 wall / 5 wall edge; the same four colours in every row 3-7; idx 1 pit `07061A`, 6 amber `F2A93B`, 7 gray `8A88A0` are shared):

| variant | header row | group | idx 2 | idx 3 | idx 4 | idx 5 | in game (BGR555 floor idx 2) |
|---|---|---|---|---|---|---|---|
| dark, floor 1 | 0 | `pal_dungeon_00` | `2A2660` | `322D70` | `171436` | `5A54A8` | `3085` |
| dark, floor 2 | 1 | `pal_dungeon_01` | `1F3566` | `274076` | `101C3A` | `4F6AA8` | `30C3` |
| dark, floor 3 | 2 | `pal_dungeon_02` | `1F1F3A` | `282848` | `0E0E22` | `46468A` | `1C63` |
| lit, floor 1 | 3 | `pal_dungeon_03` | `564358` | `5C4864` | `292036` | `665B9F` | `2D0A` |
| lit, floor 2 | 4 | `pal_dungeon_04` | `4D4F5D` | `545769` | `22273A` | `5C6F9F` | `2D29` |
| lit, floor 3 | 5 | `pal_dungeon_05` | `4D3D3A` | `544445` | `201A24` | `544E84` | `1CE9` |

(Lit = the floor-N colours blended 22% (floor) / 8% (wall) toward amber `F2A93B`.) In game, BG row `k` = CGRAM bytes `32k .. 32k+31` (floor BG 3 = `$60-$7F`); `tests/smoke/visual_tiles.lua` logs the floor colour of every room.

### 3.4 What is still the same everywhere

* One floor block for every floor/lighting (only the palette differs). All 64-cell slots above not mentioned are never referenced by the tilemap, so painting them changes nothing visible.
* The wall face repeats every 16 px, the pillar/exit marker are single 16x16 blocks used for every `p` / `X`.

---

## 4. HUD (BG3, 2bpp, no flips except where noted)

BG3 chr at VRAM `$E000`: tile ids `0-127` = **`GFX_DD`**, `128-255` = **`GFX_DE`**, `256-383` = `GFX_DC` (not used by the HUD in rooms) (`LoadDefaultGraphics` loads `$6A,$6B,$69` = DD, DE, DC there, `bank_00.asm:11837-11866`).
Tilemap entry palette bits `p` select CGRAM `p*4..p*4+3` = group `pal_hud_0p` in `gfx/src/palettes/hud.yaml` (colour 0 transparent, 1 `ECE8FF`, 2 `6C66C8`, 3 `14123A` as authored; in game `EFEFFF 6B63CE 101039`).
Blank fill is tile `$7F` (all other cells). The HUD occupies tilemap rows 2-7, columns 2-27 (px y 16-63). Cells used (this is the full set over the 21 rooms; 3 full hearts, whatever each room's tools show):

| sheet | cells idx -> (col,row) | tilemap positions (col,row) / flips / palette bits |
|---|---|---|
| `GFX_DD` | 80 (0,5); 82 (2,5); 84 (4,5); 86 (6,5); 88 (8,5); 89 (9,5); 91 (11,5); 92 (12,5); 93 (13,5); also 73 (9,4) and 74 (10,4) in some rooms | frame/meter tiles at cols 2-7, rows 2-7, pal 2, priority 1; V/H flips are used to make the 4 corners and bottom edge |
| `GFX_DE` | 8 (8,0) 9 (9,0) | (12,2) (13,2), pal 3 |
| `GFX_DE` | 11 (11,0); 15 (15,0) | (22,2),(23,2),(26,2),(27,2) pal 2 (H flips on the right side) |
| `GFX_DE` | 16 (0,1) | row 3 at cols 8,9,10,12,13,15,16, pal 1 |
| `GFX_DE` | 32 (0,2) | (20..22,3), pal 1 |
| `GFX_DE` | 39 (7,2); 40 (8,2); 41 (9,2); 43 (11,2); 44 (12,2) | (15,2) pal 0; (9,2) pal 7; (16,2) pal 0; (24,2) pal 1; (25,2) pal 1 |
| `GFX_DE` | 117 (5,7) | (3,3)-(3,6), pal 7 |
| `GFX_DE` | 24 (8,1); 58 (10,3); 75 (11,4): drawn in some rooms only (item/counter states) | positions not captured in the room dump; palette 0-3 |

---

## 5. Guards (`sprite/GFX_BC.png`, name table 1 tiles `$40-$7F`, OBJ row 4 left; row 6 when ALERT) - E4 SHEET CONTRACT

Since E4 the guard is **not** drawn by the vanilla soldier code any more (60 cells, 9 OAM entries, a dozen flips). `src/hooks/guard_draw.asm` (`Hush_DrawGuard`) draws every guard from
**14 clean blocks, 4 OAM entries + the shadow** (`SpriteData_OAMHarm` = 5 entries). Paint one pose per block; the engine only picks blocks and mirrors them. The sheet is 128 x 32 px = 16 x 4 cells.
Guard direction codes: 0 right, 1 left, 2 down (front), 3 up (back).

**OAM tile = `$40` + cell index**, cell index = `(py/8)*16 + px/8` of the block's top-left cell. A 16x16 block covers its cell, the next one, and the two below (`+0 +1 +16 +17`). The same positions as `px = (bx,by)` in the PNG:

| block (PNG px, size) | cell idx | OAM tile | used for | flip by the engine |
|---|---|---|---|---|
| `head_down` (0,0) 16x16 | 0 | `$40` | head facing the viewer (down) | -- |
| `head_up` (16,0) 16x16 | 2 | `$42` | head from behind (up) | -- |
| `head_side` (32,0) 16x16 | 4 | `$44` | head in profile, **drawn facing LEFT**; facing right = the same block H flipped | right: H |
| `head_sleep` (48,0) 16x16 | 6 | `$46` | head facing down, eyes closed (ASLEEP) | -- |
| `body_down_A` (64,0) 16x16 | 8 | `$48` | body facing down, standing / phases 0 and 2 | -- |
| `body_down_B` (80,0) 16x16 | 10 | `$4A` | body facing down, step (phase 1), and H flipped for phase 3 (the other foot) | phase 3: H |
| `body_up_A` (96,0) 16x16 | 12 | `$4C` | body facing up, standing | -- |
| `body_up_B` (112,0) 16x16 | 14 | `$4E` | body facing up, step (phase 1; H flipped for phase 3) | phase 3: H |
| `body_side_A` (0,16) 16x16 | 32 | `$60` | body in profile **facing LEFT**, standing | right: H |
| `body_side_B` (16,16) 16x16 | 34 | `$62` | profile, step 1 | right: H |
| `body_side_C` (32,16) 16x16 | 36 | `$64` | profile, step 2 | right: H |
| `body_sleep` (48,16) 16x16 | 38 | `$66` | slumped body (ASLEEP), drawn at the same place as the standing body | -- |
| `lantern_0` (64,16) **8x8** | 40 | `$68` | lantern, frame 0 | -- |
| `lantern_1` (72,16) **8x8** | 41 | `$69` | lantern, frame 1 (flicker; also the lantern on the ground while asleep) | -- |
| free | -- | -- | px x 80..127 / y 16..31 and x 64..79 / y 24..31 (cells 42-47, 56-63 and the two cells under the lanterns) | -- |

Composition (sprite origin `(X, Y)` = top-left of the guard's 16x16 hitbox box; the figure is **16 wide x 24 tall, feet at the bottom of the box**). Lower OAM entry = in front:

| OAM entry | part | size | position | notes |
|---|---|---|---|---|
| 0 | head | 16x16 | `(X, Y-8)` | covers screen y `Y-8 .. Y+7`; its lower half covers the upper half of the body (transparent pixels show the body) |
| 1 | lantern | 8x8 | right `(X+13, Y+6)`, left `(X-5, Y+6)`, down `(X+10, Y+6)`, up `(X-3, Y+6)`; asleep `(X+10, Y+10)` | frame 0 / 1 alternates every 12 frames (a slot-dependent phase, so a group does not flicker in sync); asleep = frame 1, no flicker |
| 2 | body | 16x16 | `(X, Y)` | covers `Y .. Y+15` |
| 3 | awareness icon | 8x8 | `(X+4, Y-22)` | GFX_C5 tiles `$FC $FD $FE`, section 6; hidden while UNAWARE |
| 4 | shadow | 16x16 | `(X, Y+10)` (down / up) or `(X, Y+12)` (side) | vanilla shadow tile `$6C` of `GFX_7D` (section 7), unchanged |

Pose by state (facing = `$0DE0`):

* **UNAWARE / SUSPICIOUS / ALERT** (same pixels; only the palette row differs): facing **down** = `head_down` + `body_down_*`; **up** = `head_up` + `body_up_*`; **left** = `head_side` + `body_side_*`; **right** = the same two blocks, **both H flipped**. The lantern sits on the side given above.
* **Walk phase** = 4-phase counter, advanced every 8 frames **only while the guard really moves** (patrol or chase); standing, paused at a wall, suspicious or sleeping = phase 0. Phases: down / up = `A, B, A, B (H flipped)`; side = `A, B, A, C`.
* **ASLEEP**: `head_sleep` + `body_sleep` + `lantern_1` on the ground; facing is ignored. Dead / dying guards use no sprite (the poof comes from the common sheet, section 7).

Palette: calm and asleep = OBJ row 4 (CGRAM `$A0`), alert = **OBJ row 6** (`$C0`): every block of the guard (head, body, lantern) takes the same row, so the alert guard turns amber as a whole. The icon keeps row 4 (attr `$29`).
Index meaning in game:

| idx | OBJ row 4 (calm) | OBJ row 6 (alert) |
|---|---|---|
| 1 | `080818` ink | `080818` |
| 2 | `39317B` | `CE7318` dark amber |
| 3 | `21184A` | `7B4210` brown |
| 4 | `9C94DE` | `F7C663` light amber |
| 5 | `F7AD39` amber | `FFD65A` bright amber |
| 6 | `EFEFFF` | `FFF7D6` |
| 7 | `AD7BF7` **violet** | `AD7BF7` **violet** |

Painting rule that follows: use the same index for "the lantern/the face" and the game recolours the whole guard amber when alert: put the body in indices 2-3, lantern/accents in 5, face in 6.
Row 6 colours 1-7 are **assembler constants** (`Hush_PalAlert`, `src/hooks/guard_runtime.asm:118`), not yaml, until the art agent moves them into `sprites.yaml`.

What the engine does NOT do any more (the old vanilla soldier pieces are gone): no weapon column, no 24-px-wide body strips, no duplicate/mirrored body halves, no head bobbing, no separate legs. A pose = one head block + one body block + the lantern, so each block can be painted on its own as a plain 16x16 picture.
Culling: all five entries are drawn only while the guard origin is inside screen x 8..231, y 24..199 (always true in HUSH rooms: rows 0-1 / 13 and columns 0 / 15 are walls); outside that window the guard is hidden.
Placeholder state: the current `GFX_BC.png` carries labelled placeholder blocks in exactly these 14 positions (`HD HU HS HZ`, `D1 D2 U1 U2`, `S1 S2 S3 BZ`, lanterns `0 1`); `make gfx` would regenerate the old labelled grid (it does not know this layout) - do not run it after painting.
Test: `tests/smoke/guard_draw.lua` checks every guard draw call (tiles, flips, positions, palette, entry count, flicker period) against this section.

---

## 6. Awareness icons (`sprite/GFX_C5.png`)

| icon | when | OAM tile (name table 1) | cell | PNG px | notes |
|---|---|---|---|---|---|
| `?` | SUSPICIOUS | `$FC` | idx 60 = (12,3) | (96,24) | 8x8 |
| `!` | ALERT | `$FD` | idx 61 = (13,3) | (104,24) | 8x8 |
| `Z` | ASLEEP | `$FE` | idx 62 = (14,3) | (112,24) | 8x8 |
| spare | -- | `$FF` | idx 63 = (15,3) | (120,24) | not drawn |

Drawn at guard origin `(+4, -22)` (x 4..11, y -22..-15), attr `$29` (OBJ row 4, priority 2, name table 1), **right expansion**: sheet idx `i` -> OBJ row 4 colour `8+i`
(same colours as the left half: 5 `F7AD39` amber, 6 `EFEFFF`). Source of truth for the tile numbers: `src/hooks/guard_draw.asm` (icon tile = `$FB` + awareness state, attribute `$29`, offset (+4, -22)). The 8x8 placeholders already there are hand painted; `make gfx` would erase them.

---

## 7. Shadows, Ink Pot, poof, sparkles, arrow (the "common sprite" sheets)

**These four sheets (`GFX_73`, `GFX_79`, `GFX_7A`, `GFX_7D`) are listed as `role: debug`, `decision: unused`, magenta palette in their yaml/PNG, but the game draws them** (loaded by `LoadCommonSprites`
for every room). Everything in this section needs the yaml role and PNG palette fixed before painting (section 12, item 2).

| element | sheet | cells -> px | OAM | row / expansion |
|---|---|---|---|---|
| shadow, guard | `GFX_7D` | block (12,2) -> (96,16) 16x16 | tile `$6C` 16x16 | OBJ 4, right |
| shadow, Link | `GFX_7D` | cell (12,2) twice, 2nd H flipped | tile `$6C` 8x8 | OBJ 4, right |
| Ink Pot (thrown bomb) | `GFX_7D` | block (14,2) -> (112,16) | tile `$6E` 16x16 | OBJ 2 normally; flashes rows 0..7 for a few frames before exploding |
| **Ink cloud / explosion** (in order) | `GFX_79` | (12,0) x4 corners; block (4,0); block (8,0); **held 300 frames: block (6,0) x6, H/V flips**; then block (8,0) again, block (10,0), cell (11,1) | tiles `$8C $84 $88 $86 $8A $9B` | OBJ **row 1** (`Hush_PalInk`), left |
| guard-death poof | `GFX_79` | blocks (6,0) then (10,0) | `$86`, `$8A` | OBJ row 2, left |
| sparkles | `GFX_79` (0,0) (3,0) (7,3) (12,0) (2,1) (3,1); `GFX_7A` (6,1) (7,1) | 8x8 | `$80 $83 $B7 $8C $92 $93 $D6 $D7` | OBJ rows 1 and 2, left |
| Hush Dart (arrow) | `GFX_73` | (10,2) (11,2) (12,2) (13,2) (10,3) (11,3) (12,3) (13,3), 8x8 each, H/V flips | `$2A $2B $2C $2D $3A $3B $3C $3D` | OBJ row 2, left |
| bow limbs (Link aiming) | `GFX_73` | cell (10,0) twice mirrored (up/down aim) / blocks in (8..10, 0..1) (left/right aim) | `$09` 8x8 / 16x16 | OBJ row 1, left |

Exact `GFX_79` cells seen: (0,0) (3,0) (4,0) (5,0) (6,0) (7,0) (8,0) (9,0) (10,0) (11,0) (12,0) (2,1) (3,1) (4,1) (5,1) (6,1) (7,1) (8,1) (9,1) (10,1) (11,1) (7,3).
`GFX_7A`: (6,1) (7,1). `GFX_7D`: (12,2) (13,2) (14,2) (15,2) (12,3) (13,3) (14,3) (15,3).
Mark-up of which cells are drawn: `tools/art_preview.py <sheet> --used`.

Palette the explosion is drawn with (OBJ row 1 colours 1-7 are overwritten at room load by `Hush_PalInk`, `src/hooks/guard_runtime.asm:120`): `080818 181042 100831 292963 4A399C 8C84E7 AD7BF7`
(idx 7 of this row is the violet `AD7BF7`; the ink cloud is a player tool, so violet is legitimate here); poof/sparkles/arrow use row 2: `080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7`.

---

## 8. Link (`player/LINK.png`, 4bpp, OBJ row 7 = CGRAM `$F0`)

Link is **two 16x16 OAM blocks**: the head block at (x, y) and the body block at (x, y+8) (the head's lower half overlaps the body's upper half; transparent head pixels show the body). The game DMA-copies the chosen blocks into
VRAM tiles 0-4 / 16-20 every frame (`DoNMIUpdates` reads `$0ACC..$0AD6` as offsets into LinkGraphics, `bank_00.asm:1742-1900`), so the exact LINK.png cells per frame are measured from those words (not guessed).
**Side view is drawn facing RIGHT; left = H flip of head and body.** Down-walking alternates an H-flipped body every second step. Blocks are `(col,row)` -> PNG px:

### 8.1 Heads

| head | block | px |
|---|---|---|
| facing down | (2,0) | (16,0) |
| facing up | (4,0) | (32,0) |
| facing left/right | (0,0) | (0,0) |
| side walk, head bob a / b | (6,20) / (8,20) | (48,160) / (64,160) |
| sword wind-up/hold, down / up | (0,10) / (2,10) | (0,80) / (16,80) |
| sword slash heads (down) | (6,0), (8,0) | (48,0), (64,0) |
| push against wall: down / side / up | (0,40) / (2,40) / (4,40) | (0,320) / (16,320) / (32,320) |

### 8.2 Bodies

| pose | facing | blocks (px) |
|---|---|---|
| stand | down / up / side | (6,2) (48,16) / (2,4) (16,32) / (0,2) (0,16) |
| walk, 8 steps | down | (8,2) (64,16), (8,2) H, (10,2) (80,16) H, (10,2), (10,36) (80,288), (12,36) (96,288), (10,36) H, (12,36) H |
| walk, 8 steps | up | (12,2) (96,16), (0,4) (0,32), (14,36) (112,288), (6,38) (48,304), (14,38) (112,304), (8,38) (64,304), (10,38) (80,304), (12,38) (96,304) |
| walk, 8 steps | side | (0,2) (0,16), (2,2) (16,16), (4,2) (32,16) +head (6,20), (14,32) (112,256) +head (8,20), (8,36) (64,288), (12,34) (96,272), (14,34) (112,272) +head (6,20), (6,36) (48,288) +head (8,20) |
| push | down / up / side | (10,46) (12,46) (14,46) / (6,24) (8,24) (10,24) / (4,46) (6,46) (8,46) |
| sword hold/wind-up | down / up | (0,11) (0,88) / (2,11) (16,88) |
| sword slash (in order) | down | (12,4) (96,32); (0,6) (0,48); (0,54) (0,432); (6,22) (48,176); (0,24) (0,192) |
| sword slash (in order) | up | (2,6) (16,48); (4,6) (32,48); (2,54) (16,432); (8,22) (64,176); (6,24) (48,192) |
| sword slash (in order) | side | (4,4) (32,32); (6,4) (48,32); (8,4) (64,32) [+ 8x8 cell (12,51) (96,408)]; (14,52) (112,416) [+ same 8x8]; (10,4) (80,32); (12,24) (96,192) |
| bow draw | down | (6,2); (8,2); (8,30) (64,240) |
| bow draw | up | (2,4); (8,24) (64,192); (10,30) (80,240) |
| bow draw | side | (12,24) (96,192); (8,4) (64,32); (12,30) (96,240); (0,2) |
| throw / place Ink Pot | down | (6,2) (stand pose) |

About 226 of the 896 cells are referenced (`tools/art_preview.py LINK --used` marks them); the rest of the sheet is never drawn in the scenes captured. `gfx/src/player/LINK.yaml` `frames:` lists the same blocks with the vanilla `LinkOAM_*` animation indices (`bank_00.asm:3462-4106`). The sword blade and sparkles
are separate sprites (section 9), not part of LINK.png.

Index colours (all rows as the game shows them, OBJ row 7): `1 080818, 2 4A298C, 3 734ACE, 4 AD7BF7, 5 CEADFF, 6 EFEFFF, 7 21184A, 8 E7D6FF, 9 6B63B5, 10 5A39AD, 11 8C63DE, 12 B58CFF, 13 392173, 14 DEC6FF, 15 F7EFFF`;
yaml `gfx/src/palettes/link.yaml` group `pal_Palettes_GreenMail` (colours[0] = idx 1-7, colours[1] = idx 8-15; its element 0 is CGRAM colour 8 = idx 8).

---

## 9. Tools

### 9.1 Shade Knife blade (`item/GFX_D1.png`, name table 0 tiles `$05 $06 $15`, OBJ row 5 = CGRAM `$B0`, **right** expansion)

The blade is assembled from the WRAM copy of `GFX_D1` (`DecompressSwordGraphics`, `bank_00.asm:9214`: 12 cells of rows 0 and 1) and drawn as 8x8 pairs and 16x16 blocks with flips
(H, V, HV) as the swing turns. Cells used: **(0..11, 0) and (0..11, 1)**, i.e. PNG px x 0..95, y 0..15 (24 cells; rows 2-3 of the sheet are never drawn).
Per swing step (`$3C` = 1..9, down-facing; the other facings reuse the same cells with other flips):

| step | cells (col,row) |
|---|---|
| 1 | (3,1) (4,1) side by side |
| 2 | (3,0) (4,0) |
| 3 | block (1,0) |
| 4 | block (10,0) |
| 5-6 | 8x16 columns: (5,0)+(5,1) and (0,0)+(0,1), drawn V flipped (lower cell on top) |
| 7 | the (5,0)+(5,1) column flipped H+V |
| 8-9 | block (6,0); block (8,0); then (5,1)/(5,0) is held while B is down |

In game, idx 1-3 are the sword colours `AD7BF7 CEADFF 4A298C` (`sword.yaml`, 3 colours at CGRAM 9-11). **Idx 4-7 of this sheet are the magenta shield placeholders (`FF00FF 101010 FF63FF B500B5`) in game** (section 11).

### 9.2 Other tools: see section 7 (arrow, Ink Pot, ink cloud, poof, sparkles)

---

## 10. Palettes: CGRAM rows as the game shows them and which yaml defines each (measured with a ROM whose yaml colours carried unique codes)

| CGRAM row | colour positions | defined by (`gfx/src/palettes/...`) | loader (usdasm) | notes |
|---|---|---|---|---|
| BG 0 / BG 1 (BG3 HUD, 4 colours per sub-palette) | 0-3, 4-7, 8-11, 12-15 | `hud.yaml` `pal_hud_00..03` (row 0) / `pal_hud_04..07` (row 1) | `PaletteLoad_HUD` `bank_1B.asm:6386` | colour 0 = transparent. `EFEFFF 6B63CE 101039` |
| BG 2..7 (rooms) | 1-7 / 8-15 | `bg_dungeon.yaml` **`pal_dungeon_00..05`**, BG row `k` = `colours[2(k-2)]` (7 entries) + `colours[2(k-2)+1]` (8 entries) | `PaletteLoad_UnderworldSet` `bank_1B.asm:6409` | room header palette set -> `UnderworldPaletteSets` row 0-5 -> group 00-05 (section 3.3: dark floor 1/2/3 = 00/01/02, lit = 03/04/05); groups 06-19 unused. Floor = BG 3, exit marker BG 4, pillar BG 5, wall face BG 6, wall top BG 7 |
| OBJ 0 | 1-7 / 9-15 | `sprites.yaml` `pal_spritepal0_00` / `bg_dungeon.yaml` `pal_dungeon_00` row 0 | `PaletteLoad_SpritePal0Left` `bank_1B.asm:6039`, `PaletteLoad_UnderworldSet` | used by nothing visible except bomb flash frames |
| OBJ 1 | 1-7 / 9-15 | **colours 1-7: asm `Hush_PalInk`** (runtime, `guard_runtime.asm`) / `sprites.yaml` `pal_sprite_00_right` | `PaletteLoad_SpriteMain` `bank_1B.asm:6067` | ink smoke, explosion, bow, sparkles |
| OBJ 2 | 1-7 / 8-15 | `sprites.yaml` `pal_sprite_01` / `pal_sprite_01_right` | `PaletteLoad_SpriteMain` | poof, arrow, sparkles, Ink Pot |
| OBJ 3 | 1-7 / 8-15 | `sprites.yaml` `pal_sprite_02` rows 0/1 | `PaletteLoad_SpriteMain` | not used by anything drawn |
| **OBJ 4** | 1-7 / 8-15 | `sprites.yaml` **`pal_sprite_03`** rows 0/1 | `PaletteLoad_SpriteMain` | **guards (calm), icons, shadows** |
| OBJ 5 | 1-7 / 9-11 / 12-15 | `pal_spriteaux_03` (sprites.yaml) / **`sword.yaml` `pal_sword_00`** (3 colours) / `cut_unused.yaml` `pal_shield_00` (4 colours, magenta) | `PaletteLoad_SpriteAux1`, `PaletteLoad_Sword` `:6141`, `PaletteLoad_Shield` `:6167` | Shade Knife = right half, colours 9-11 only |
| **OBJ 6** | 1-7 / 9-15 | **colours 1-7: asm `Hush_PalAlert`** (runtime) / `sprites.yaml` `pal_environment_0A` | `PaletteLoad_SpriteEnvironment` `:6215` | alert guard (amber) |
| **OBJ 7** | 1-7 / 8-15 | `link.yaml` `pal_Palettes_GreenMail` rows 0/1 | `PaletteLoad_LinkArmorAndGloves` `:6322` | Link |

Full CGRAM dump, room 6 (identical in all rooms; `RT` = runtime asm constants):

```
BG2..BG7  000000 | 000018 292163 312973 101031 5A52AD F7AD39 8C8CA5 | 8C8CA5 000018 292163 312973 101031 5A52AD F7AD39 8C8CA5
OBJ0      000000 | 080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7 | 000000 000018 292163 312973 101031 5A52AD F7AD39 8C8CA5
OBJ1 RT   000000 | 080818 181042 100831 292963 4A399C 8C84E7 AD7BF7 | EFEFFF 080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7
OBJ2,3,4  000000 | 080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7 | EFEFFF 080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7
OBJ5      000000 | 080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7 | 000000 AD7BF7 CEADFF 4A298C FF00FF 101010 FF63FF B500B5
OBJ6 RT   000000 | 080818 CE7318 7B4210 F7C663 FFD65A FFF7D6 AD7BF7 | 000000 080818 39317B 21184A 9C94DE F7AD39 EFEFFF AD7BF7
OBJ7      000000 | 080818 4A298C 734ACE AD7BF7 CEADFF EFEFFF 21184A | E7D6FF 6B63B5 5A39AD 8C63DE B58CFF 392173 DEC6FF F7EFFF
```

Editing rule: a room only loads one group of a family (the ones named above for HUSH). Edit **exactly those groups**; for the room BG family that means `pal_dungeon_00..05`. The CGRAM dump above is room 6 (`pal_dungeon_00`); the other variants differ only in BG rows 2-7.

---

## 11. Where the colour rules (`tools/gfx_convert.py`) bite

The check looks only at **palette entries of the PNG that the image actually uses**. Hue bands (HSV): amber = hue 25-55 / sat >= .40 / val >= .35; violet = hue 255-300 / sat >= .20 / val >= .30.
Roles come from each sheet's yaml. Which PNG indices are amber/violet in the authored palettes: sprite family (GFX_BC, C5, D1..): amber idx 5, violet idx 7; bg family (GFX_00, 06..): amber idx 6, no violet; LINK: violet idx 2 3 4 5 10 11 12 13 14, no amber.

| sheet | role in yaml | rule | where it bites |
|---|---|---|---|
| `GFX_00`, `GFX_06` (floor, wall) | env | no violet | harmless: the bg palette has no violet. Amber idx 6 (torch/lamp light) is allowed |
| `GFX_BC` (guard) | **env** (not danger!) | no violet; nothing requires amber | **never use idx 7** (violet, and in game = violet in both rows). If the art agent re-roles it to `danger` it must contain amber (idx 5) and no idx 7. In game the alert row recolours idx 2-6 amber automatically; E4: head, body and lantern all use the row |
| `GFX_C5` (icons) | env | no violet | `?` `!` amber idx 5, `Z` idx 6: fine; idx 7 forbidden |
| `LINK` | player | must contain violet, no amber | violet = idx 2,3,4,5,10-14; idx 6,7,8,9,15 do not count. Painting only with 1/6/7/8/9/15 fails the rule. No amber idx exists, so amber cannot be used |
| `GFX_D1` (blade) | player | must contain violet, no amber | **trap**: the PNG palette says idx 7 = violet `A878F0`, idx 5 = amber (forbidden). The game's blade colours are idx 1-3 = violet shades; idx 7 renders `B500B5` magenta. To *pass the check* the PNG must use idx 7 at least once, which puts magenta on screen. **Fix needed (art agent):** change D1's PNG palette and yaml `palette.indices` so idx 1-3 are `A878F0 C9ABFF 4B2E8C` (as `sword.yaml`) and idx 4-7 unused; same for D2/D3/C7 if used |
| `GFX_73/79/7A/7D` | **debug** | exempt from role rules, magenta palette | painting with the magenta palette = in-game colours come from the CGRAM row anyway (section 10), but a debug role means **no rule protects it**: the ink cloud (violet idx 7 in row 1) and the dart (row 2) are player colours; the poof is neutral. Needs `role:` + PNG palette of the `spr` family before painting |
| `GFX_DD/DE/DC`, `FONT` | ui | none | free |
| any sheet | -- | SNES limits | 3bpp: indices 1-7 only; two distinct colours may not collapse to the same BGR555; sizes multiple of 8 |

`make gfx` regenerates **all** placeholders and would overwrite painted art (and the hand-painted C5 icons): never run it after painting. `gfx_convert.py check` itself validates everything in `gfx/src`; `tools/art_apply.py` runs the same code for just the file it wrote.

---

## 12. Problems found while mapping (need a decision/owner)

1. ~~No exit marker, no pillar look, no floor-per-floor look~~ done in E3 (sections 3.1, 3.3): exit marker, pillar, wall face and six palette variants exist as separate tiles/palette groups; the art in them is still the A0 placeholder.
2. **Four sheets in use are labelled unused/debug** (`GFX_73 GFX_79 GFX_7A GFX_7D`, magenta yaml): shadow, ink cloud, poof, sparkles, dart, bow, Ink Pot. Owner: art agent (`gfx/src/sprite/*.yaml`, role + palette).
3. **`GFX_D1` palette mismatch**: the colour rule forces idx 7 (violet) while the game renders idx 4-7 magenta (section 11). Owner: art agent.
4. **`GFX_BC` has role env**, but it is the danger sprite; and the alert/ink rows are asm constants, not yaml (`Hush_PalAlert`, `Hush_PalInk`).
5. Walls hide sprites (priority 1, section 3.2); wall art must be designed with that.
6. Dart "arrow" and bow limbs share palette row 2 / row 1 with the poof/ink; row 1 is the ink-smoke palette, so the bow limbs are ink-coloured.
7. Placeholder tile art of different sheets is identical (same label text per cell), so a pixel comparison of VRAM against `gfx/src` **cannot** tell sheets apart; do not rely on it. The trace ROM (section 13) can.

---

## 13. Tools and how this was measured (re-runnable)

```
# artists   (E4: the `--used` marks of GFX_BC come from the vanilla-layout research (tools/art/game_map.json) and are stale: use the section 5 block table instead)
.venv/bin/python tools/art_preview.py GFX_BC --game --used          # build/art_preview/GFX_BC.png: PNG palette + in-game palette(s), used cells marked
.venv/bin/python tools/art_apply.py --export /tmp/bc.png gfx/src/sprite/GFX_BC.png --zoom 1   # RGBA to paint over
.venv/bin/python tools/art_apply.py /tmp/bc.png gfx/src/sprite/GFX_BC.png                    # whole sheet
.venv/bin/python tools/art_apply.py floor16.png gfx/src/bg_tileset/GFX_06.png --at 96 16       # a 16x16 patch: the floor block
.venv/bin/python tools/gfx_convert.py check                                                  # the whole-tree check
```

Research chain (all under `tools/art/`, output under `build/art_research/`, nothing in the repo changes):

1. `make_trace_rom.py`: private copy of the repo whose placeholder sheets carry `(sheet id, cell idx)` in the last pixel rows -> every VRAM cell is traceable (10 sheets that would not fit their slot carry the sheet id only).
   `make_trace_pal_rom.py`: same for palette yaml colours -> each CGRAM entry traceable to group/row/colour.
2. `dump_rooms.lua` (VRAM/CGRAM/OAM/PPU of all 21 rooms) and `dump_sprites.lua` (per-frame OAM, name-table-0 VRAM, Link DMA words, guard slots, ancillae: patrol/unaware, forced suspicious/alert/asleep, Link walking/sword/bow/Ink Pot, a sword kill) via
   `HUSH_ROM=<trace rom> HUSH_RESULTS=build/art_research/tr .venv/bin/python tools/run_test.py tools/art/dump_*.lua`.
3. `sprlog.py`, `tilelib.py`, `catalog.py`, `linkposes.py`, `build_game_map.py` (-> `tools/art/game_map.json`, read by `art_preview.py`).
