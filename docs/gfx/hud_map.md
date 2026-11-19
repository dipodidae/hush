# HUD map: what each BG3 cell of the in-room HUD is, and which HUSH art it carries

Owner: art helper. **Measured, not guessed**: positions/palettes come from real VRAM dumps of the running HUSH ROM
(`tools/art/hud_snap.lua`: rooms r01 none, r03 knife, r07 darts, r10 ink, plus ink/dart selected, hearts full/half/empty),
the meaning of each tile id from the usdasm HUD code (cited `bank_0D.asm:line`). HUD pixels are **original** (drawn in
`tools/art/hud_art.py` from ASCII art / geometry; no vanilla pixel was read, traced or recoloured).
Tile numbers and tilemap positions are vanilla (ROM tilemap) and unchanged; only pixels and the palette groups changed.

## 1. Facts

* BG3, 2bpp, VRAM `$E000` chr: tile id 0-127 = `GFX_DD` idx, 128-255 = `GFX_DE` idx (`tile = 128*sheet + idx`, DE idx = id - 128).
* The HUD buffer is `$7EC700` (template `HUDTemplate`, `bank_0D.asm:17752`, 32 words/row), uploaded to tilemap rows 2-7 (`$0219 = $6040`,
  docs/engine_notes.md line 100). Buffer row r = tilemap row r+2. Blank cell = word `$207F` (tile `$7F` = `GFX_DD` idx 127, **kept blank**).
* Tilemap palette bits p (0-7) select CGRAM `p*4..p*4+3` = group `pal_hud_0p` of `gfx/src/palettes/hud.yaml` (index 0 transparent).
  Groups `08-0F` are overwritten by the room palettes; `04-06` are not used by the in-room HUD (menu/text only).
* The room controller refills health every frame (`room_ctrl.asm:39`), so the hearts row always shows the full max; half/empty heart tiles
  can only be seen by writing the buffer (that is how `hud_hearts_states.png` was made).

## 2. Layout (tilemap column, row; `H`/`V` = flip used)

```
col:   2      3      4      5      6      7     8   9   10     12   13    15   16    18     20 21 22      22 23 24 25 26 27
row 2  $50    $56V   $52    $5B    $5B    $5C        $A8         $88  $89   $A7  $A9   (key)             $8B $8F $AB $AC $8F(H) $8B(H)
row 3  $54    $F5    $58    icon   icon   $5D    $90 $90 $90     $90  $90   $90  $90   (key digit)  $A0 $A0 $A0   <- hearts
row 4  $54    $F5    $58    icon   icon   $5D
row 5  $54    $F5    $59    $5B(V) $5B(V) $5C(V)
row 6  $54    $F5    $54H
row 7  $50(V) $56    $50(VH)
```

* **Meter box** = cols 2-4 x rows 2-7 (vanilla magic meter; the interior is col 3 rows 3-6 = tile `$F5` pal 7). HUSH has no magic, so the meter is
  always empty: it is drawn as a tidy dark inset gauge.
* **Item box** = cols 4-7 x rows 2-5; **the wall in col 4 is shared** with the meter (`$52` top junction, `$58` wall, `$59` bottom junction).
  The 16x16 item icon is cols 5-6 x rows 3-4; with no item selected those four cells are `$7F` (blank), so the box is empty.
* Counters: row 2 = icon, row 3 = digits (`HexToDec` `bank_0D.asm:16469`; digit tile = `$90 | digit`, `:16510`): rupees (cols 8-10), bombs (12-13),
  arrows (15-16), key (col 18: blank `$247F` when no key, `:17525`). Digits of all counters share palette group 1 (the tilemap code writes `$2400`).
* Hearts row 3 from col 20 (`$7EC768`, up to 10 per row, then next row +`$40`): `$A0` full, `$A1` half, `$A2` empty container (`HeartTiles` `:17000`;
  max hearts drawn with `FullHeartTiles` `:16995`); `$A3`, `$A4` = refill animation frames (`HeartFlipTiles` `:17005`, used `:16606`).
* `LIFE` label: `$AB $AC` (16x8, cols 24-25) with decorations `$8B $8F` either side (H-flipped on the right).

## 3. Cell table

`sheet idx` = cell index in the sheet PNG (`idx = row*16 + col`, PNG pixel `x=8*col, y=8*row`). pal = tilemap palette bits (= `pal_hud_0p`).

| tile id | sheet idx (col,row) | role in vanilla and HUSH | pal | HUSH art | positions (col,row) |
|---|---|---|---|---|---|
| `$50` | DD 80 (0,5) | meter box corner, top-left; V/H flips = other corners | 2 | 2 px teal line, rounded outer corner | (2,2); (2,7) V; (4,7) VH |
| `$52` | DD 82 (2,5) | junction top (meter right wall = item box left wall) | 2 | top line + shared wall (mid teal 2 px) | (4,2) |
| `$54` | DD 84 (4,5) | vertical wall of the meter | 2 | wall at px 6-7 (H flip: px 0-1) | (2,3)-(2,6); (4,6) H |
| `$56` | DD 86 (6,5) | meter horizontal edge (stored as bottom; V flip = top) | 2 | line + dark interior fill | (3,7); (3,2) V |
| `$58` | DD 88 (8,5) | shared wall meter / item box | 2 | 2 px mid-teal wall | (4,3) (4,4) |
| `$59` | DD 89 (9,5) | junction bottom of the item box | 2 | wall continues down + bottom line to the right | (4,5) |
| `$5B` | DD 91 (11,5) | item box horizontal edge (top; V flip = bottom) | 2 | 2 px line | (5,2) (6,2); (5,5) (6,5) V |
| `$5C` | DD 92 (12,5) | item box corner top-right (V flip = bottom-right) | 2 | 2 px line, rounded | (7,2); (7,5) V |
| `$5D` | DD 93 (13,5) | item box right wall | 2 | 2 px wall | (7,3) (7,4) |
| `$F5` | DE 117 (5,7) | meter interior (also "no item" icon in the vanilla item slot) | 7 | flat dark fill (`081828`) | (3,3)-(3,6) |
| `$BA` `$4A` `$49` `$CB` | DE 58 (10,3); DD 74 (10,4); DD 73 (9,4); DE 75 (11,4) | item icon "bow and arrows" 16x16: TL, TR, BL, BR (`ItemIcons.bows` `bank_0D.asm:16780`) -> **Hush Dart** | 2 | teal dart pointing right (2 colours + tip) | (5,3) (6,3) (5,4) (6,4) |
| `$B2` `$B3` `$C2` `$C2`(H) | DE 50 (2,3); DE 51 (3,3); DE 66 (2,4) | item icon "bombs" 16x16 (`ItemIcons.bombs` `:16796`) -> **Ink Pot** | 3 | violet ink pot (bottom half symmetric: C2 is H-flipped) | (5,3) (6,3) (5,4) (6,4) when the ink pots are selected (`hud_r10_ink.png`) |
| `$A8` | DE 40 (8,2) | rupee icon -> loot gem | 7 | white/teal gem | (9,2) |
| `$88` `$89` | DE 8 (8,0), DE 9 (9,0) | bomb counter icon 16x8 -> mini Ink Pot | 3 | violet pot | (12,2) (13,2) |
| `$A7` `$A9` | DE 39 (7,2), DE 41 (9,2) | arrow counter icon 16x8 -> mini Hush Dart | 0 | teal dart | (15,2) (16,2) |
| `$90`-`$99` | DE 16-25 (0..9,1) | digits 0-9 (5x7 glyph + 1 px shadow) | 1 | white digits, dark-violet shadow | (8..10,3) (12,13,3) (15,16,3) (18,3 key digit) |
| `$A0` | DE 32 (0,2) | heart full | 1 | violet heart, white glint, dark-violet outline | (20..22,3) |
| `$A1` | DE 33 (1,2) | heart half | 1 | left half filled, right half empty outline | (20..,3) |
| `$A2` | DE 34 (2,2) | heart empty (container) | 1 | outline only | (20..,3) |
| `$A3` `$A4` | DE 35 (3,2), DE 36 (4,2) | heart refill animation frames (turning, edge-on) | 1 | narrow hearts | row 3 during a refill |
| `$AB` `$AC` | DE 43 (11,2), DE 44 (12,2) | "LIFE" label (16x8) | 1 | 3x5 letters, violet + dark shadow | (24,2) (25,2) |
| `$8B` `$8F` | DE 11 (11,0), DE 15 (15,0) | decoration either side of LIFE (H flip on the right) | 2 | teal diamond + line | (22,2) (23,2); (26,2) (27,2) H |
| `$7F` | DD 127 | blank (everything else) | any | untouched (blank) | all other cells |

Reserved (not drawn in HUSH rooms, but drawn so a magic pickup cannot show a hex label): meter gauge fills `$4C $4D $4E $5E $5F` (DD 76 77 78 94 95;
`MagicGaugeTiles` `bank_0D.asm:17731`; pal 7 `3CF5/3C5F/...`). Not drawn at all: half-magic label (`$F7 $51 $FA`), silver bow / boomerang / hookshot icons,
key icon `$71` (hidden: `$247F`), everything the START menu and text box use (still hex-labelled placeholders).

## 4. Palette groups (gfx/src/palettes/hud.yaml; low 3 bits are dropped in game)

| group | used by | 1 | 2 | 3 |
|---|---|---|---|---|
| `pal_hud_00` (p0) | mini Hush Dart (`$A7 $A9`) | `98E8E0` light teal | `40B8B0` teal | `081828` |
| `pal_hud_01` (p1) | hearts, digits, LIFE | `E8E8F8` white (digits, glint) | `A878F0` **violet = you** (hearts fill, LIFE) | `5030A0` dark violet (outline, shadow) |
| `pal_hud_02` (p2) | frame, Hush Dart icon | `80D8D0` pale teal (outer line, dart) | `308088` mid teal (inner line, dart shading) | `081828` dark (unused by tiles drawn; the meter fill uses p7) |
| `pal_hud_03` (p3) | Ink Pot icons | `D8C8F8` light violet (rim, label) | `A878F0` violet (pot) | `081828` (ink drop on the label) |
| `pal_hud_07` (p7) | gem, meter fill | `E8E8F8` white | `80D8D0` teal | `081828` dark gauge fill |
| `pal_hud_04-06`, `08-0F` | not used in rooms | untouched placeholder (`ECE8FF 6C66C8 14123A`) | | |

Rules kept: amber is not used anywhere (amber = danger); violet = player stuff (hearts, ink pot, LIFE); teal = secondary (frame, dart, gem);
no pale gold. Colour 0 is transparent in every group. The `ui` role has no colour rule (`gfx_convert.py check` passes, 227 files).
Digits cannot be teal for the dart/ink counters: all counters share tile `$90-$99` with palette group 1 (set by the vanilla HUD code), so the
**icons** carry the colour (teal dart, violet ink pot) and the digits are white.

## 5. What the player sees per tool stage (real game, `docs/gfx/screenshots/hud_*.png`)

| stage | screenshot | HUD |
|---|---|---|
| no tools (r01) | `hud_r01_none.png` | empty teal item box + empty gauge, gem `000`, ink pot `00`, dart `00`, "LIFE" + 3 violet hearts |
| Shade Knife (r03) | `hud_r03_knife.png` | identical to r01: the knife is the B-button sword, vanilla has no HUD cell for it |
| + Hush Darts (r07) | `hud_r07_darts.png` | teal dart in the item box, dart counter (`08`) |
| + Ink Pots (r10) | `hud_r10_ink.png` | violet Ink Pot in the box (selected), ink counter (`03` in the shot); selecting the darts shows the dart again |
| counters / health | `hud_full_ink.png`, `hud_hearts_states.png` | multi-digit counters; full + half + empty hearts |
| zoom / composite | `hud_stages_zoom.png`, `hud_preview_compose.png` | 4x crops; the compose preview is rendered offline (`tools/art/hud_preview.py`) |

Observations for the engine owner (no src change made): the gem counter and the ink/dart counters are always on screen, even in rooms where
the tool does not exist yet (vanilla draws them unconditionally); hiding them means blanking buffer words `$7EC750..$7EC760` / the icons at row 0.
The START menu (vanilla item menu) shares these sheets and still shows hex-labelled placeholder tiles (`build/art_research/hud/hud_snap/hud_menu.png`).

## 6. Re-run

```
.venv/bin/python tools/art/hud_art.py                  # redraw every HUD cell into gfx/src/hud/GFX_DD.png, GFX_DE.png (+ validation)
.venv/bin/python tools/art/hud_preview.py --zoom 4     # offline compose preview: build/art_preview/hud_preview.png
.venv/bin/python tools/gfx_convert.py check            # whole-tree check
make build
HUSH_RESULTS=build/art_research/hud .venv/bin/python tools/run_test.py tools/art/hud_snap.lua   # real-game shots + VRAM/CGRAM dumps
.venv/bin/python tools/art/hud_zoom.py out.png build/art_research/hud/hud_snap/hud_r07_darts.png --zoom 4
```

`make gfx` regenerates all placeholders and would overwrite this art (re-run `hud_art.py` afterwards).
