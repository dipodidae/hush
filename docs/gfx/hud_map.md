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
| `$A0` | DE 32 (0,2) | heart full | 1 | violet heart, white glint, dark outline (idx 3) | (20..22,3) |
| `$A1` | DE 33 (1,2) | heart half | 1 | left half filled (dark outline), right half = violet (idx 2) outline only | (20..,3) |
| `$A2` | DE 34 (2,2) | heart empty (container) | 1 | violet (idx 2) outline only, so it shows on dark floors | (20..,3) |
| `$A3` `$A4` | DE 35 (3,2), DE 36 (4,2) | heart refill animation frames (turning, edge-on) | 1 | narrow hearts | row 3 during a refill |
| `$AB` `$AC` | DE 43 (11,2), DE 44 (12,2) | "LIFE" label (16x8) | 1 | 3x5 letters, violet + dark shadow | (24,2) (25,2) |
| `$8B` `$8F` | DE 11 (11,0), DE 15 (15,0) | decoration either side of LIFE (H flip on the right) | 2 | teal diamond + line | (22,2) (23,2); (26,2) (27,2) H |
| `$7F` | DD 127 | blank (everything else) | any | untouched (blank) | all other cells |

Since the menu pass (section 7) the item icons (`$BA $4A $49 $CB`, `$B2 $B3 $C2`) are **opaque**: transparent pixels are idx 3 = the group's dark colour, because the START menu draws them over the room, not over a slot tile. In the HUD the item box therefore shows a dark fill behind an item and stays see-through (`$7F`) while empty.

Reserved (not drawn in HUSH rooms, but drawn so a magic pickup cannot show a hex label): meter gauge fills `$4C $4D $4E $5E $5F` (DD 76 77 78 94 95;
`MagicGaugeTiles` `bank_0D.asm:17731`; pal 7 `3CF5/3C5F/...`). Not drawn at all: half-magic label (`$F7 $51 $FA`), silver bow / boomerang / hookshot icons,
key icon `$71` (hidden: `$247F`). The START menu and text box cells are drawn too: sections 7 and 8.

## 4. Palette groups (gfx/src/palettes/hud.yaml; low 3 bits are dropped in game)

Two shared dark colours since the menu pass: **PANEL `1A2456`** (group 1 idx 3: panel fill of the menu, heart outline, digit shadow, LIFE shadow) and **DARK `0A1028`** (idx 3 of every other group: meter interior, item slots, icon backgrounds, window bezels).

| group | used by | 1 | 2 | 3 |
|---|---|---|---|---|
| `pal_hud_00` (p0) | mini Hush Dart (`$A7 $A9`); START menu: empty item slots (`$F5`), inactive window frames | `98E8E0` light teal | `40B8B0` teal | `0A1028` DARK |
| `pal_hud_01` (p1) | hearts, digits, LIFE; menu: panel fill (`$F5`), labels, item names, ability window frame | `E8E8F8` white (digits, glint, text) | `A878F0` **violet = you** (hearts fill, LIFE, labels) | `1A2456` PANEL |
| `pal_hud_02` (p2) | frame, Hush Dart icon; menu: pendant/equipment window frames, text box frame, rule | `80D8D0` pale teal (outer line, dart) | `308088` mid teal (inner line, dart shading) | `0A1028` DARK |
| `pal_hud_03` (p3) | Ink Pot icons; menu: Shade Knife blade | `D8C8FF` light violet (rim, blade edge) | `A878F0` violet (pot) | `0A1028` |
| `pal_hud_04` (p4) | menu: the three empty floor sockets | `5CB8B8` bright ring | `24505E` dim ring | `0A1028` hollow |
| `pal_hud_05` (p5) | not used (spare) | `E8E8F8` | `A878F0` | `1A2456` |
| `pal_hud_06` (p6) | text box / dialogue text (font idx 1), text box tile fill if the engine makes it opaque (section 8) | `F4F0FF` white | `A878F0` | `0A1028` |
| `pal_hud_07` (p7) | gem, meter fill; menu: **active window frame, cursor ring**, cloak icon | `B898F8` **violet** (was white: the gem outline is violet now) | `80D8D0` teal | `0A1028` dark gauge fill |
| `pal_hud_08-0F` | not used in rooms | untouched placeholder (`ECE8FF 6C66C8 14123A`) | | |

Rules kept: amber is not used anywhere (amber = danger); violet = player stuff (hearts, ink pot, LIFE, knife, cursor); teal = secondary (frame, dart, gem, sockets);
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
The START menu (vanilla item menu) shares these sheets: section 7.

## 6. Re-run

```
.venv/bin/python tools/art/hud_art.py                  # redraw every HUD cell into gfx/src/hud/GFX_DD.png, GFX_DE.png (+ validation)
.venv/bin/python tools/art/hud_preview.py --zoom 4     # offline compose preview: build/art_preview/hud_preview.png
.venv/bin/python tools/gfx_convert.py check            # whole-tree check
make build
HUSH_RESULTS=build/art_research/hud .venv/bin/python tools/run_test.py tools/art/hud_snap.lua   # real-game shots + VRAM/CGRAM dumps
# START menu / text box / font: sections 7 and 8
.venv/bin/python tools/art/menu_art.py                 # menu + text box cells of GFX_DC / DD / DE
.venv/bin/python tools/art/font_art.py                 # FONT.png glyph patches (+ --preview docs/gfx/screenshots/font_preview.png)
HUSH_RESULTS=build/art_research/menu .venv/bin/python tools/run_test.py tools/art/menu_snap.lua tools/art/death_snap.lua   # real-game menu shots + dumps
.venv/bin/python tools/art/menu_preview.py build/art_research/menu/menu_snap/menu_open out.png   # recompose the menu with the CURRENT art, no rebuild
.venv/bin/python tools/art/menu_map.py [--grid] build/art_research/menu/menu_snap/menu_open ...   # which tile / palette sits where, which sheet cell it is
.venv/bin/python tools/art/menu_bg3.py build/art_research/menu/menu_snap/menu_open out.png        # the whole 64x64 BG3 map as a picture
.venv/bin/python tools/art/hud_zoom.py out.png build/art_research/hud/hud_snap/hud_r07_darts.png --zoom 4
```

`make gfx` regenerates all placeholders and would overwrite this art (re-run `hud_art.py` afterwards).

## 7. START item menu (module `$0E`; measured with `tools/art/menu_snap.lua`, decoded with `menu_map.py`, drawn by `tools/art/menu_art.py`)

Screenshots (real game, room 10 with Shade Knife + Hush Darts + Ink Pots): `docs/gfx/screenshots/menu_items.png` (cursor hidden half of the time: it flickers),
`menu_cursor_darts.png`, `menu_cursor_ink.png`, `menu_save_continue.png` (SELECT message), `menu_game_over.png`; `play_pause_menu.png` is a copy of `menu_items.png`.

### 7.1 Facts

* The menu is the vanilla BG3 tilemap: a 64x64 map at VRAM `$C000` (screens `$800` bytes apart), drawn by `ItemMenu_Initialize` (`bank_0D.asm:13115`) into `$7E1000+`, shown with BG3 vscroll 280 (map row 35 at the top).
  Windows (map screen 2, columns/rows below; px = `(col*8, (row-3)*8)`): **items** cols 1-19 rows 5-19 (`DrawYItems` `:14302`, 5x4 slots of 16x16, first slot at col 4 row 7, pitch 3 tiles), **equipped item** cols 21-30 rows 5-10
  (`DrawEquippedItemBox` `:14706`, `DrawEquippedYItem` `:15403`), **progress** cols 21-30 rows 11-19 (`DrawProgressWindow` `:15161`, pendants window while `$7EF3C5` < 3), **abilities** cols 1-19 rows 21-29
  (`DrawAbilityText` `:14786`), **equipment** cols 21-30 rows 21-29 (`DrawEquipmentWindow` `:15752`).
* Tile ids: `0x00-0x7F` = `GFX_DD` idx, `0x80-0xFF` = `GFX_DE` idx-`0x80`, `0x100-0x17F` = `GFX_DC` idx-`0x100`, `0x180+` = text box dynamic tiles (composed from `FONT`).
* Palette bits: `$3C..` = group 7, `$28..` = 2, `$24..`/`$25..` = 1, `$2C..` = 3, `$31..` = 4. `GetPaletteMask` (`:14282`) ANDs `$E3FF` into the window frames of the windows that are not active (-> group 0), `$FFFF` for the active ones.
* The menu tiles REPLACE the panel cells, so **every menu tile is opaque** (nothing may be idx 0 except the three rounded corner pixels of a window): the room shows through every cell that is not drawn (`$007F`), e.g. the gap between windows.
* The ROM tile ids and their positions are vanilla and unchanged; only the pixels, the palette groups (section 4) and the meaning of a few windows changed (below).

### 7.2 Cell table

`idx` = sheet cell (`row*16+col`), pal = group the vanilla tilemap word selects.

| tile id | sheet idx | pal | vanilla role | HUSH art |
|---|---|---|---|---|
| `$F9` `$FC` `$FB` | DE 121 124 123 | 7 (active), 2, 1 | window frame: top/bottom edge (V flip), left/right edge (H flip), corner (all 4 flips) | 2 px line (idx 1 outside, idx 2 inside) + 6 px dark bezel; rounded corner (3 transparent pixels) |
| `$F5` | DE 117 | 1 / 0 / 7 | panel fill / empty item slot / meter fill | flat idx 3: PANEL `1A2456` / DARK `0A1028` / DARK (an empty slot = a dark 16x16 square on the lighter panel) |
| `$60` `$61` `$70` | DD 96 97 112 | 7 | cursor ring around the selected 2x2 slot: corner, top/bottom edge (V flip), left/right edge (H flip); flickers (`$0207` bit 4, `DrawEquippedYItem` `:15426`) | **violet cursor**: 2 px violet frame (idx 1 `B898F8`) + 1 px teal inner line on the outer edge of the 8 px gap, dark mat next to the slot |
| `$6E` `$6F` | DD 110 111 | 1 | label tab on the items window's top edge | frame lines + `ITEM` (3x5 letters, violet) |
| `$82` `$83` | DE 2 3 | 1 | label tab of the abilities window | frame lines + `HUSH` (empty window: HUSH has no abilities) |
| `$F0` `$F1` `$F2` | DE 112 113 114 | 7 / 1 | 8x16 accent beside the top-left corner of the items / abilities window (`$F0` V-flipped in the abilities window) | dark cell with a 2 px accent bar (teal in group 7, violet in group 1) |
| `$BA $4A $49 $CB` | DE 58, DD 74 73, DE 75 | 2 | bow and arrows icon (`ItemIcons.bows`) | **Hush Dart** (same as the HUD), opaque |
| `$B2 $B3 $C2 $C2`(H) | DE 50 51 66 | 3 | bombs icon | **Ink Pot** (same as the HUD), opaque |
| `$16B $16C $16E $16F $17C $17D $17E $17F` | DC 107 108 110 111 124-127 | 1 | name row of "bow and arrows" (8 tiles, `ItemMenuNameText_Bow` `:16766`); the first 2 alone = name of "bow" (no arrows) | mini dart emblem in the first two tiles (alone when the quiver is empty) + `DARTS` (proportional 5x7, white) |
| `$151 $15E $15C $151` | DC 81 94 92 81 | 1 | name row of the bombs: 4 tiles `B O M B` (`ItemMenuNameText_YItems` `:16655`, the 1st and 4th tile are the same) | ink drop, `INK`, ink drop (text 15 px across tiles 2+3) |
| `$79 $7A $7B $7C $8C` | DD 121-124, DE 12 | 1 | `EQUIPMENT` label (`EQUIPMENT` `bank_0D.asm:15740`) | `EQUIPMENT` (3x5 letters, violet, 35 px) |
| `$64 $CE $75 $125` | DD 100, DE 78, DD 117, DC 37 | 3 3 3 7 | fighter sword icon (`ItemIcons.sword` `:16896`, `$7EF359`=1) | **Shade Knife**: vertical dagger, tip up, light/violet blade, violet guard, grip violet/teal |
| `$68 $68`(H) `$78 $78`(H) | DD 104, DD 120 | 7 | green mail icon (always drawn) | hooded cloak (violet, teal scarf), symmetric: left half drawn, right half H flipped |
| `$D7` | DE 87 | 2 | horizontal rule under the equipment row | 2 px teal rule on a dark cell |
| `$84 $85` (and H flips) | DE 4 5 | 1 | "0 heart pieces" icon (`ItemIcons.heart_pieces`) | blank (all idx 3): HUSH has no heart pieces |
| `$121 $122 $123 $124 $13F` | DC 33-36, 63 | 1 | label of the progress window ("PENDANTS", `PendantsWindow.row1` `:15087`) | **`FLOORS`** (3x5 letters): the window now reads as the three floors |
| `$13B-$13E` | DC 59-62 | 4 | empty pendant socket 2x2 (drawn 3 times) | dark ring socket, empty |
| `$12B-$12E` | DC 43-46 | 1 / 3 / 7 | pendant owned: red / blue / green (`ItemIcons.pendant_*` `:16927`) | **lit socket** (same ring with a glowing core), 3 colourways (white+violet / lavender+violet / violet+teal). Not shown yet: nothing sets `$7EF374` |
| `$7F` | DD 127 | 0 | blank | untouched (transparent: the room shows through) |

Not drawn (HUSH never shows them): the other 18 item icons and name rows, abilities text, dungeon item row, bottle submenu. Their cells are still hex-labelled placeholders (`DC`/`DD`/`DE` cells not listed above and in section 3).

### 7.3 What the player sees

Dark indigo panels, teal frames (the active window has a violet outer line), dark slot squares, the dart and the ink pot icons, a violet cursor ring, the item name under the equipped icon (`[dart] DARTS` / `INK`),
`EQUIPMENT` with the knife and the cloak, `FLOORS` with three empty sockets, an empty `HUSH` window. Verified in the real game (screenshots above): no hex label is visible; `make leakcheck` stays clean.

## 8. Text box, dialogue font, SELECT / game-over screens

* **Text box** (`RenderText_BorderTiles`, `bank_0E.asm:10273`): corner `$F3` (DE 115), top/bottom edge `$F4` (DE 116, V flip), left/right edge `$C8` (DE 72, H flip), all group 2; drawn exactly like the window frames (2 px teal line + 6 px dark bezel, rounded corner).
  The interior is `$387F` (tile `$7F` = blank, group 6): **transparent**, the room shows through. Fine on the dark floors; for a solid box see section 9.1.
  `$180-$1FD` are the dynamic text tiles the VWF composes from `FONT` (`RenderText_PerformVWFing` `$0ECB5E`).
* **Font** (`gfx/src/font/FONT.png`, `tools/art/font_art.py`): 128 glyphs of 8x16 (two stacked tiles: glyph code `g` at tile `(g>>4)*32 + (g&15)`, +16 for the bottom half), index 1 only, white (`pal_hud_06` idx 1 `F4F0FF`).
  The A0 sheet already held clean 5x7 caps with doubled rows (no labelled glyphs). Fixes: `l` (was a lone bottom bar), `I i !` 2 px stems that keep their 1 px gap, `M T V W X Y` (width 7 in the ROM table) redrawn 6 px wide, `?` 6 px wide.
  **Glyph codes for engine code** (advance width in `.width`, `bank_0E.asm:$0ECADF`): `A-Z` `$00-$19`, `a-z` `$1A-$33` (drawn like caps), `0-9` `$34-$3D`, `!` `$3E`, `?` `$3F`, `-` `$40`, `.` `$41`, `,` `$42`, `...` `$43`, `>` `$44`, `(` `$45`, `)` `$46`,
  **`:` `$47`** (NEW, was the ankh), **`/` `$48`** (NEW, was waves), **`+` `$49`** (NEW), `"` `$4C`, arrows `$4D-$50`, `'` `$51`, space `$59` (width 4). Widths: digits 6 (`1` = 4), `:` 6, `/` 6, `+` 6, `I` 3, `!` 3, `.` 4, `'` 4.
  Preview of every character plus the ending lines: `docs/gfx/screenshots/font_preview.png` (composed with the real advance widths).
* **SELECT message / game-over menu**: vanilla text-box text with the frame above; `menu_save_continue.png` is legible (white caps on the dark room). The game-over menu (`menu_game_over.png`) is only reachable by forcing module `$12`
  (Link cannot die in HUSH): its text is the same font; the red backdrop is the vanilla death flash and the dim `UNUSE D SE` lines at the top are sprites of an unpainted placeholder sheet (never seen in play).

## 9. Requests for the engine owner (no `src/` change made by art)

1. **Solid text box**: patch the two words `$387F` -> `$38F5` at `$0ED387` (`RenderText_BorderTiles` middle row interior) and `$0ED397` (`RenderText_ClearTileFill`): tile `$F5` in group 6 is the flat DARK `0A1028` fill, so the box interior becomes opaque (today the room shows through).
2. **Menu backdrop**: the menu leaves `$007F` cells (gap rows/columns between windows) transparent, so a strip of the room is visible between the windows (`menu_items.png`, the brown wall strip). Hide BG2/OBJ (or dim) while module `$0E` is open if that bothers the playtest.
3. **FLOORS window**: three empty sockets are drawn; to light one set bit 0/1/2 of `$7EF374` (red / blue / green colourway, `DrawPendantsWindow` `bank_0D.asm:15170`): the lit-socket art exists (section 7.2). Window title and abilities window (`HUSH`, empty) can stay as they are.
4. **Optional, bolder font**: the ROM advance table is 6 px for most glyphs, so the 5 px stems stay 1 px thick. Widening the table (`$0ECADF`, 98 bytes) to 7 px would allow 2 px stems; `font_art.py` would then need a second glyph set (not done).
5. Death screen (module `$12`): sprite placeholder labels (`UNUSED`) come from a sprite sheet that is not part of any HUSH room; unreachable while the room controller refills health.
