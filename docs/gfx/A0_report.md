# Milestone A0 report: placeholder overhaul

Status: **ready for the A0 gate.** Everything below was run; commands and numbers are real.
Review: `build/gfx_gallery.html` (run `make gfx` to regenerate; open it from the checkout),
this report, `docs/gfx/leak_report.md`, `docs/gfx/screenshots/`.

## What the build does now

- **Boot goes straight to a readable title screen**: black for about 3.5 s (the game's own WRAM
  clearing), then "HUSH" and "PRESS START" at frame ~360. No triforce animation, no sword stab, no
  subtitle pop, and no attract-mode timeout. START goes to file select as in vanilla.
  Hook: `src/hooks/intro_skip.asm` (ledger rows in `src/FREESPACE.md`). Test: `tests/gfx/scenes_boot.lua`
  asserts the title appears within 600 frames and stays up for 600 more.
- **Every scene we test shows zero vanilla tiles or palettes.** `make leakcheck`: 27 scenes, 0 tile
  leaks, 0 palette leaks. The control build (same scenes, vanilla graphics) reports thousands, so the
  detector works (`make leakcheck-control`). `make leakcheck` is part of `make test`.
- `make build` replaces **207 graphics sheets + 503 palette rows + the title tilemap** in place. The
  byte-diff check passes (287,507 changed bytes, all inside ledger rows). No pointer was changed, no
  free space used for graphics, ROM size unchanged.

## Verified format facts (docs/gfx/formats.md, with vendor file:line)

Your understanding was mostly right. Corrections:

| Claim | Verdict |
|---|---|
| Most sheets compressed 3bpp | Yes: `GFX_00..D9`, 64 tiles x 24 bytes each after decompression. |
| Link uncompressed 4bpp | Yes: `$108000`, 896 tiles. |
| (new) `GFX_73..7E` | uncompressed 3bpp, and the game *also* feeds some of them to the decompressor (see gotcha). |
| (new) HUD sheets `GFX_DA..DE` | compressed **2bpp**. |
| (new) Font | uncompressed **2bpp**, `$0E8000`, 256 tiles. |
| (new) World map | uncompressed **8bpp** Mode 7, `$18C000`. |
| 3bpp in VRAM | expanded to 4bpp on upload: 7 opaque colours + transparent. |

Compression format implemented and round-trip tested (`tools/gfx_compress.py --selftest`,
`--full` = all 209 sheets). Compressed sheets are packed with no slack, so every replacement must
compress to <= its vanilla slot: **all 207 fit** (largest placeholder 998 of its slot; tightest slots
`GFX_DB` 46 B, `GFX_C7` 415 B). No relocation was needed, so no approval request.

**Gotcha found (worth knowing before you paint):** an uncompressed 3bpp sheet must start with byte
`$FF` (tile 0, row 0 = colour 1 across the row), because the intro runs the decompressor over
`GFX_7B`; any other first byte can run away and wipe the intro palettes. `gfx_insert.py` enforces it.

## Asset counts (docs/gfx/INVENTORY.md)

224 graphics assets, 158 palette groups.

| kind | redraw | reuse-as | cut | unused |
|---|---|---|---|---|
| bg_tileset | 78 | 0 | 13 | 19 |
| sprite | 63 | 0 | 19 | 14 |
| item (sword/bow/bomb/pickups) | 0 | 7 | 0 | 0 |
| hud | 5 | 0 | 0 | 0 |
| font | 1 | 0 | 0 | 0 |
| player (Link) | 1 | 0 | 0 | 0 |
| title (new in this change) | 3 | 0 | 0 | 0 |
| special screen (world map) | 0 | 0 | 1 | 0 |
| palettes (158 groups) | 101 | 5 | 48 | 4 |

**Tiles you have to draw** (non-blank vanilla tiles in `redraw` + `reuse-as` sheets):
**P0: 3,142** (Link 879, font 240, HUD 5 sheets, the dungeon tileset sheets used by >= 10 rooms,
common guard sprite sheets, title 162 cells) and **P1: 7,686**. P2 is only `cut`/`unused`.
Realistically the M1 test room needs a small subset of P0; the briefs tell you which sheets each
scene uses. Plus three new assets that have no vanilla slot yet: guard, awareness icons, tools
(`gfx/src/new/`, inserted at M1, 48 tiles each).

## `cut` tasks for engine (nothing is cut yet; the sheets are magenta CUT until then)

1. Remove or skip the overworld and the world map screen (module `$09` / map screens) so they are
   unreachable. Sheets: 13 BG + 19 sprite sheets, `WORLDMAP`, 48 overworld palette groups.
2. Intro-adjacent scenes: attract/ending/credits (`Attract*`, `Credits*` routines). The title no longer
   enters attract mode (A0 hook); the scenes themselves still exist.
3. Followers, mirror warp.
Full list with sheet ids: `docs/gfx/INVENTORY.md` -> "cut tasks for engine". These are written up, not
implemented, as agreed.

## Scenes covered by tests (tests/gfx, all scripted, no hand-made savestates)

title, title (idle 10 s), file select, name entry (+typed), text box, house gameplay, HUD at 4 health
values, sword swing, bow selected, arrow in flight, bomb selected/placed/exploding, pause menu,
death/game over, three dungeon rooms with soldiers (vanilla Hyrule Castle rooms as stand-ins), a
soldier reacting, a sword swing in a guard room.
Dev savestate is made by the test itself from this build (`build/dev_states/gfx_house.mss`), so it
never carries vanilla VRAM.

**Scenes I could not reach automatically (you may need savestates; make them on the placeholder
build, not a vanilla build):**
- A real alert/suspicious guard with awareness icons (does not exist until M1).
- Shade Knife / Hush Dart / Ink Pot as HUSH versions (stand-ins used: sword, bow, bomb).
- The caught/instant-restart screen (M5).
- Magic items, boss rooms, shops, the dungeon map screen, save menu "Continue/Save and quit" text.
- Lit vs dark room palettes (later milestone).
Any of these that show vanilla pixels will be caught by `make leakcheck` once a scene test exists.

## Known gaps

- The placeholder is **not final art** and some scenes are ugly on purpose: labelled hex tiles,
  magenta for cut/unused. Vanilla tilemaps are untouched except the title, so layouts keep their
  vanilla shape (e.g. dungeon walls follow tile *types* from the game's own tables; decorative tiles
  stay labelled grid).
- Sprites and Link draw as tile-index labels or simple shapes; animation frames are tile blocks, not
  poses (Link frames are listed in `gfx/src/player/LINK.yaml`).
- Text uses a new 5x7 pixel font mapped by the game's text codes; lowercase shows as capitals.
- The intro still spends ~3.5 s black while the game clears WRAM (vanilla init); not touched.
- 30 "weak" leak matches (single simple tiles like a line, identical in both games by geometry) are
  listed in the leak report but are not failures; detector rule is in `tools/gfx_leakcheck.py`.
- Palette colours loaded as immediates in code are not tables; they are only found by the scene dumps.
- Savestates are tied to MesenCE 2.2.1.

## Process notes (honest)

- I (the director session) edited tools, tests and `src/` directly instead of delegating to separate
  subagents, to move fast. The `AGENTS.md` and `.opencode/agents/*.md` permission changes you approved
  are applied. A `critic` review of this diff was **not** run; run it at the gate if you want one.
- `make check` needs the MesenCE harness; `make test` takes about 2 minutes.

## How to draw (for you)

1. Open `gfx/src/<kind>/<id>.png` in Aseprite (or similar) in **indexed colour mode**. Do not convert
   to RGB; keep the image size and the palette order. The brief `<id>.yaml` next to it lists what every
   palette index means; `gfx/guides/<id>_guide.png` shows the same sheet at 4x with a tile grid.
2. Index 0 is transparent. 3bpp sheets: indices 1-7 only; 2bpp: 1-3; Link (4bpp): 1-15.
3. Keep the tile grid (8x8 tiles, 16 per row, row-major = ROM order). Don't move tiles: tilemaps and
   sprite frames point at tile numbers.
4. Colours: amber = danger, violet = you. `tools/gfx_convert.py` enforces this by the `role` in the
   brief. Change a palette by editing `gfx/src/palettes/*.yaml` (RGB hex).
5. Save, then `make build`, then check in game. If a sheet is too detailed to compress into its slot,
   the build tells you the byte counts and stops (then simplify, or ask for a relocation plan).
6. Uncompressed sheets `GFX_73..7E`: keep tile 0 row 0 as colour 1.
7. The title: sheets `GFX_40/41/39`. The layout (which tile is which cell) is generated by
   `tools/gfx_title.py`; paint over the existing cells, keep the 18x7 + 18x2 cell blocks.
8. After editing, `make gfx` regenerates placeholders **over** your art if you re-run it. Do not run
   `make gfx` after you start painting; use `make build`.

## Commands

| | |
|---|---|
| `make build` | verify ROM, assemble, insert all gfx, byte-diff against the ledger |
| `make test` | build + compressor self-test + smoke + gfx scene tests + `make leakcheck` |
| `make leakcheck` | scene dumps vs vanilla hash set; fails on any leak |
| `make leakcheck-control` | same on a vanilla-graphics build; must find leaks |
| `make gfx` | regenerate inventory + placeholders + gallery (**overwrites placeholders**) |
| `make gfx-selftest` | compressor round trip on all 209 sheets (~2 min) |

## Screenshots (docs/gfx/screenshots/)

`boot_title.png`, `boot_file_select.png`, `boot_name_entry.png`, `boot_text_box.png`,
`boot_house_gameplay.png`, `play_hud_20_full.png`, `play_hud_low.png`, `play_sword_swing_a.png`,
`play_arrow_in_flight.png`, `play_bomb_exploding.png`, `play_pause_menu.png`, `play_death_menu.png`,
`dungeon_guard_room_62.png`, `dungeon_guard_room_62_guards_react.png`.
