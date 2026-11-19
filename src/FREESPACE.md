# ROM space ledger

**Every byte HUSH writes to the ROM must be inside a region listed here.**
This covers both free space (new code/data) and hook sites (vanilla bytes we
overwrite). `tools/check_freespace.py` fails the build if:

- an `org` in `src/**/*.asm` is not inside a listed region,
- any byte that differs between `rom/vanilla.sfc` and `build/hush.sfc` is not
  inside a listed region,
- two listed regions overlap,
- `freecode` / `freedata` / `freespace` is used (automatic allocation is banned).

Only the `engine` agent edits this file. Add the row in the same change that
adds the `org`.

## Format

The parser reads the table below. Keep the column order and use `$BBAAAA`
LoROM SNES addresses (inclusive range). Type is `free` or `hook`.

| Start | End | Type | Owner file | Purpose |
|---|---|---|---|---|
| $00E852 | $00E87F | free | src/hooks/intro_skip.asm | A0: FinishTitle. NULL_00E852 "FREE ROM: 0x2E" (bank_00.asm:13064); all $FF in vanilla ROM, no references in vendor/usdasm |
| $0CC10C | $0CC11F | free | src/hooks/intro_skip.asm | A0: HideSprites. NULL_0CC10C "FREE ROM: 0x14" (bank_0C.asm:6-9); all $FF in vanilla ROM, no references in vendor/usdasm. E1: now `JML Hush_HideSprites` + `Hush_TitleStart` (JSL Hush_NewGame : RTL), 9 of 20 bytes |
| $0CC120 | $0CC123 | hook | src/hooks/intro_skip.asm | A0: Module00_Intro entry `LDA.b $11 : CMP.b #$08` (bank_0C.asm:15-17) -> `JSL IntroSkip` |
| $0CC151 | $0CC153 | hook | src/hooks/intro_skip.asm | A0: intro jump-table entry 8 `dl Intro_TrianglesBeforeAttract` (bank_0C.asm:33) -> `dl TitleHold` |
| $0CFFB1 | $0CFFFF | free | src/hooks/intro_skip.asm | A0: IntroSkip. NULL_0CFFB1 "FREE ROM: 0x4F" (bank_0C.asm:9340-9342); all $FF in vanilla ROM, no references in vendor/usdasm |
| $02885E | $028860 | hook | src/hooks/camera_lock.asm | E1: Underworld_TryScreenEdgeTransition entry `REP #$20 : LDA.b $30` (bank_02.asm:1513-1516) -> `SEP #$20 : RTS`; no screen-edge room transitions |
| $02BA31 | $02BA33 | hook | src/hooks/camera_lock.asm | E1: HandleUnderworldCamera entry `REP #$20 : LDA.w #$0001` (bank_02.asm:10800-10803) -> `SEP #$20 : RTS`; the camera never scrolls |
| $0287BA | $0287BD | hook | src/hooks/room_ctrl.asm | E1: Module07_Underworld `JSL LoadChrHalfSlot` (bank_02.asm:1396) -> `JSL Hush_FrameHook` (per-frame game controller) |
| $0CC130 | $0CC132 | hook | src/hooks/new_game.asm | E1: Module00_Intro START branch `JMP.w FadeMusicAndResetSRAMMirror` (bank_0C.asm:19-24) -> `JMP.w Hush_TitleStart` (new game) |
| $07F89D | $07F9FF | free | src/hooks/room_ctrl.asm | E1: Hush_FrameHook, Hush_LoadRoom, Hush_RestartRoom, Hush_CheckExit, Hush_GrantTools, Hush_Ending. NULL_07F89D "FREE ROM: 0x763" (bank_07.asm:23958-23960); all $FF in vanilla ROM, no references in vendor/usdasm |
| $07FA00 | $07FAFF | free | src/hooks/new_game.asm | E1: Hush_NewGame, Hush_HideSprites (same NULL_07F89D block, 0x8C bytes used; $07FB00-$07FFFF stays unclaimed for later hooks) |
| $05C155 | $05C15C | hook | src/hooks/guard_ai.asm | E2: Sprite_41/42/43 entry `LDA.w $0DB0,X : BNE Probe : JMP.w Guard_Main` (bank_05.asm:11942-11946) -> `JML Hush_GuardEntry` + 4 NOPs (the stealth AI replaces Guard_Main) |
| $0EEE22 | $0EF3FF | free | src/hooks/guard_ai.asm | E2: Hush_GuardEntry + the AI (states, patrol, chase, icons, tables). NULL_0EEE21 "FREE ROM: 0x05DF" (bank_0E.asm:11950) minus its first byte: $0EEE21 MUST stay $FF, it is the end marker of the dialogue text that the text loader scans for (found by boot hang when it was overwritten); all $FF in vanilla ROM, no references in vendor/usdasm |
| $0EFB64 | $0EFFFF | free | src/hooks/guard_vision.asm | E2: Hush_Geom, Hush_Vision (cone/range/LOS/ink), Hush_AncillaHit, Hush_BombHook. NULL_0EFB64 "FREE ROM: 0x049C" (bank_0E.asm:13307); all $FF in vanilla ROM, no references in vendor/usdasm |
| $06ECB7 | $06ECBB | hook | src/hooks/guard_hooks.asm | E2: CheckAncillaDamageToSprite entry `LDY.w $0EF0,X : BPL _aggressive` (bank_06.asm:21177-21180) -> `JML Hush_AncillaHit` + NOP (arrow = sleep, no other damage to guards) |
| $089815 | $089819 | hook | src/hooks/guard_hooks.asm | E2: Bomb_CheckSpriteAndPlayerDamage entry `LDA.w $0C5E,X : BEQ .no_damage` (bank_08.asm:5069-5072) -> `JML Hush_BombHook` + NOP (bombs do no damage; the explosion is the ink cloud) |
| $0DB0C1 | $0DB0C3 | hook | src/hooks/guard_ai.asm | E4: SpriteData_OAMHarm rows $41/$42/$43 (blue/green/red soldier; `08 08 08` = 9 OAM entries, bank_0D.asm:5871-5873) -> `04 04 04` = 5 entries (head, lantern, body, icon, shadow); the table is read only by LoadSpriteProperties ($0DB823) |
| $07FB00 | $07FCFF | free | src/hooks/guard_runtime.asm | E2: Hush_Tick, Hush_ResetRuntime, Hush_FastRestart, Hush_SetPalettes + palette data. The unclaimed tail of NULL_07F89D "FREE ROM: 0x763" (bank_07.asm:23958); all $FF in vanilla ROM, no references in vendor/usdasm |
| $07FD00 | $07FFFF | free | src/hooks/guard_draw.asm | E4: Hush_DrawGuard (head, lantern, body, icon, shadow = 5 OAM entries) + its tables. The unclaimed tail of NULL_07F89D "FREE ROM: 0x763" (bank_07.asm:23958); all $FF in vanilla ROM, no references in vendor/usdasm |
| $009EDA | $009EE1 | hook | src/hooks/room_visuals.asm | E3: RoomDrawObjectData obj0388 (object $07, bank_00.asm:4864) `dw $1C6A,$1C7A,$1C6A,$1C7A` -> wall-face tiles (ceiling top row, face bottom row); vanilla object never used by HUSH |
| $00BAA4 | $00BAB3 | hook | src/hooks/room_visuals.asm | E3: RoomDrawObjectData obj1F52 + obj1F5A (objects $B8/$92 and $B9/$93, bank_00.asm:6952-6958) -> pillar and exit-marker tile words; vanilla objects never used by HUSH |
| $0ED464 | $0ED477 | hook | src/hooks/room_visuals.asm | E3: UnderworldPaletteSets rows 1-5 (bank_0E.asm:10412-10418): BG palette id 2,4,6,8,10 + the sprite bytes `00 03 01` of row 0, so the 6 dark/lit x floor variants share the OBJ palettes |
| $01B53C | $01B54E | free | src/hooks/room_visuals.asm | E5: Hush_DrawVariant (19 bytes: object routine that draws one decoration cell, size field = variant index). NULL_01B53C "FREE ROM: 0x24" (bank_01.asm:9965-9968); all $FF in vanilla ROM, no references in vendor/usdasm |
| $018212 | $018215 | hook | src/hooks/room_visuals.asm | E5: DrawObjects.type1_routine[$09],[$0A] (bank_01.asm:278-279) `dw RoomDraw_DiagonalAcute_1to16, RoomDraw_DiagonalGrave_1to16` -> `dw Hush_DrawVariant` x2; vanilla diagonal objects never used by HUSH |
| $018014 | $018015 | hook | src/hooks/room_visuals.asm | E5: DrawObjects.type1_data_offset[$0A] (bank_01.asm:19) `dw obj042A` -> `dw $04A0` (second 16-variant bank) |
| $009F72 | $00A071 | hook | build/rooms_gen.asm | E5: RoomDrawObjectData obj0420..obj0510 (bank_00.asm, the data blocks of the unused diagonal objects $09-$20; only ids $09/$0A read them in HUSH) -> variant tile words, 8 bytes per variant (28 used today, window = 32 variants), generated by tools/roomgen.py |
| $1F8378 | $1F83BF | hook | build/rooms_gen.asm | E1: RoomData_ObjectDataPointers entries of rooms $128-$13F (3 bytes each, bank $1F table at $1F8000); the tail rooms are unused in vanilla (all point at the shared stub) |
| $1F8738 | $1F877F | hook | build/rooms_gen.asm | E1: RoomData_DoorDataPointers entries of rooms $128-$13F ($1F83C0 + 3*room) |
| $04F752 | $04F781 | hook | build/rooms_gen.asm | E1: RoomHeaderPointers entries of rooms $128-$13F (2 bytes each, table at $04F502, bank 04 hard-coded) |
| $09D87E | $09D8AD | hook | build/rooms_gen.asm | E1: RoomData_SpritePointers entries of rooms $128-$13F (2 bytes each, table at $09D62E, bank 09 hard-coded) |
| $1F8780 | $1FB77F | hook | build/rooms_gen.asm | E1: ROOM TABLE (engine runtime data) + object streams + door lists of the HUSH rooms, replacing the in-place vanilla room object data of rooms that are unreachable in HUSH (12 KiB budget, roomgen fails if exceeded) |
| $04F782 | $04F8D1 | hook | build/rooms_gen.asm | E1: room headers of the HUSH rooms (14 bytes each, up to 24), replacing vanilla headers of unreachable rooms (vanilla header region $04F782-$04FFEE) |
| $09D92E | $09DBCD | hook | build/rooms_gen.asm | E1: sprite lists of the HUSH rooms (up to 28 bytes each, 24 rooms), replacing vanilla sprite lists of unreachable rooms (vanilla region $09D92E-$09EC9F) |
| $02C813 | $02C842 | hook | build/rooms_gen.asm | E1: EntranceData.room_id rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02C91D | $02C9DC | hook | build/rooms_gen.asm | E1: EntranceData.camera_scroll_boundaries rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02CD45 | $02CD74 | hook | build/rooms_gen.asm | E1: EntranceData.horizontal_scroll rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02CE4F | $02CE7E | hook | build/rooms_gen.asm | E1: EntranceData.vertical_scroll rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02CF59 | $02CF88 | hook | build/rooms_gen.asm | E1: EntranceData.y_coordinate rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D063 | $02D092 | hook | build/rooms_gen.asm | E1: EntranceData.x_coordinate rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D16D | $02D19C | hook | build/rooms_gen.asm | E1: EntranceData.camera_trigger_y rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D277 | $02D2A6 | hook | build/rooms_gen.asm | E1: EntranceData.camera_trigger_x rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D381 | $02D398 | hook | build/rooms_gen.asm | E1: EntranceData.main_GFX rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D406 | $02D41D | hook | build/rooms_gen.asm | E1: EntranceData.floor rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D48B | $02D4A2 | hook | build/rooms_gen.asm | E1: EntranceData.dungeon_id rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D510 | $02D527 | hook | build/rooms_gen.asm | E1: EntranceData.in_door rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D595 | $02D5AC | hook | build/rooms_gen.asm | E1: EntranceData.layer rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D61A | $02D631 | hook | build/rooms_gen.asm | E1: EntranceData.camera_scroll_controller rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D69F | $02D6B6 | hook | build/rooms_gen.asm | E1: EntranceData.quadrant rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D724 | $02D753 | hook | build/rooms_gen.asm | E1: EntranceData.overworld_door_tilemap rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $02D82E | $02D845 | hook | build/rooms_gen.asm | E1: EntranceData.song rows 0-23 (bank_02.asm:13125-15440); entrance k loads HUSH room k |
| $0ADB27 | $0ADD26 | hook | tools/gfx_insert.py | A0: map-screen palettes Palettes_LWMAP/DWMAP (bank_0A.asm:3620-3670) replaced by magenta (screen is cut) |
| $0CC425 | $0CC434 | hook | tools/gfx_insert.py | A0: Palettes_Triforce (bank_0C.asm:538) replaced by magenta (scene is cut) |
| $0CDD6D | $0CDEE1 | hook | tools/gfx_insert.py | A0: IntroLogoTilemap stripe stream (bank_0C.asm:5351) replaced by the HUSH title layout generated by tools/gfx_title.py (373 bytes, starts at the vanilla stream start; the rest of the vanilla stream is unread) |
| $0E8000 | $0E8FFF | hook | tools/gfx_insert.py | A0: TheFont 2bpp (bank_0E.asm:5-6, 256 tiles) replaced by the HUSH placeholder font |
| $0EF4EB | $0EF580 | hook | tools/gfx_insert.py | A0: Palettes_BlueThunder1-5 + Palettes_GanonTowerFlash (bank_0E.asm:12290-12320) replaced |
| $108000 | $14FF8B | hook | tools/gfx_insert.py | A0: LinkGraphics (graphics.asm:5), uncompressed 3bpp GFX_73-7E and compressed sheets GFX_00-GFX_60+blank slots up to $14FF8B (graphics.asm:6-257), replaced in place; compressed data never exceeds its slot |
| $14FFFC | $16A26D | hook | tools/gfx_insert.py | A0: sprite sheets GFX_7F-GFX_9D (graphics.asm:~176-215) replaced in place (<= vanilla slot size each, padded $FF) |
| $16A275 | $18BFB4 | hook | tools/gfx_insert.py | A0: sprite sheets GFX_9F-GFX_D9, followers, HUD GFX_DA-DE (graphics.asm:~216-262) replaced in place |
| $18C000 | $18FFFF | hook | tools/gfx_insert.py | A0: WorldMap_Mode7TileGFX 8bpp (graphics.asm:281) replaced by magenta CUT placeholder |
| $1BD218 | $1BEBB3 | hook | tools/gfx_insert.py | A0: PaletteData colour words (bank_1B.asm:4646-5879) replaced in place; no pointer changes |

## Notes

- Vanilla US 1.0 is a 1 MiB LoROM. Before claiming "free" space, prove it is
  unused: check the region is `$FF`/`$00` fill in `rom/vanilla.sfc` and that
  nothing in `vendor/usdasm/` references it. Record that evidence in the
  Purpose column or a note below.
- Hook rows: put the original bytes/instructions in the hook file's header
  comment (see `src/hooks/README.md`).
- The header checksum is not fixed up (`--fix-checksum=off`). If a release
  needs it, add `$00FFDC-$00FFDF` as a `hook` row at M5.

## E1 notes (room data regions)

The `hook` rows owned by `build/rooms_gen.asm` (generated by `tools/roomgen.py`, checked by `tools/check_freespace.py`, which now scans `build/*_gen.asm` as well as `src/**`)
overwrite vanilla data in place. Why that is safe:

- **Rooms `$128-$13F`** (pointer-table tail, 24 rooms): no vanilla room-id-keyed table has real data for them. Checked in `rom/vanilla.sfc`: pot items -> shared `$E6B0`, headers -> shared `$FFEF`, sprites -> shared `$EC9D`,
  objects -> shared stubs `$1F8780/$1F878A`. Room flags `$7EF000+2*room` end at `$7EF27F` and sprite death flags at `$7FE1FF`, both the vanilla ranges for 320 rooms.
- **Data regions** `$1F8780-$1FB77F` (object streams + door lists + ROOM TABLE), `$04F782-$04F8D1` (headers), `$09D92E-$09DBCD` (sprite lists) are the first bytes of the vanilla per-room data areas
  (`rooms.asm`: `RoomDataTiles_*`; `bank_04.asm`: `RoomHeader_*`; `bank_09.asm`: `RoomData_Sprites_*`) of vanilla rooms. HUSH never loads a vanilla room: no overworld, no file select, `EntranceData` rows 0..N-1
  are rewritten, `$010E` is only ever written by `Hush_LoadRoom` with an index `< N`, and HUSH room headers carry zero stairs/warp targets and no doors/holes/pits.
- Budgets (24 rooms): streams+table 12 288 B (3 dev rooms use 420), headers 24x14 = 336 B, sprite lists 24x28 = 672 B. roomgen aborts the build if a region overflows.
- `EntranceData` rows 24-132 stay vanilla but are unreachable. `$0CC10C` block: see the A0 row above.

## E2 notes

- Free blocks used by E2: `$0EEE22-$0EF3FF` and `$0EFB64-$0EFFFF` (bank $0E, the NULL blocks after the dialogue text and the thunder palettes) and `$07FB00-$07FFFF` (the unclaimed tail of the bank-07 NULL block).
  **`$0EEE21` is deliberately not in the ledger and must stay `$FF`:** it terminates the dialogue-text scan (boot hung in the intro when code started at `$0EEE21`).
- E2 hook rows are exact byte ranges of the replaced instructions (`$05C155-$05C15C` 8 bytes, `$06ECB7-$06ECBB` and `$089815-$089819` 5 bytes each); the original bytes are in the hook file headers and were verified against `rom/vanilla.sfc`.
- Space used (symbols in `build/hush.sym`): `$0EEE22-$0EF2B6` (AI, ~0.9 KB of 1.5 KB), `$0EFB64-$0EFDDC` (vision + hooks, ~0.7 KB of 1.2 KB), `$07FB00-$07FC2D` (runtime, ~0.3 KB of 1.3 KB).
- `build/hush_dev.sfc` (the dev ROM, `make build-dev`) is checked against the same ledger (`tools/check_freespace.py --rom --rom-file`).
- E2 also edits `gfx/src/sprite/GFX_C5.png` tiles 60-63 (awareness icons, 8x8 placeholder glyphs; a gfx change, not a ROM-space change: `GFX_C5` is inside the existing A0 row `$16A275-$18BFB4`).

## E3 notes (visual variety)

- Three small in-place data rewrites, all for vanilla data HUSH never reads any more: tile words of the otherwise unused room-object data `obj0388`, `obj1F52`, `obj1F5A`
  and `UnderworldPaletteSets` rows 1-5 (only rows 0-5 can be selected by HUSH room headers). No code, no free space. Evidence: `rooms.asm`/`bank_01.asm` object tables
  (`DrawObjects.type1_data_offset`: objects `$07`, `$B8`, `$B9`, `$92`, `$93` point at these blocks) and no HUSH room can load a vanilla room.
- The tile ids chosen keep the vanilla tile type (collision) of the plain-wall build: the room test `visual_tiles` compares `$7F2000` with the grid.

## E4 notes (guard drawing)

- `$0DB0C1-$0DB0C3` (hook row): `SpriteData_OAMHarm` for the soldier types, `08 08 08` -> `04 04 04` (9 -> 5 OAM entries per guard). Vanilla bytes verified in `rom/vanilla.sfc` (`08 08 08` at file offset `$6B0C1`); the table is read only by `LoadSpriteProperties` (`bank_0D.asm:7835`).
- `$07FD00-$07FFFF` (free row, `src/hooks/guard_draw.asm`): `Hush_DrawGuard` + tables, `$07FD00-$07FEC7` used. It is the tail of the bank-07 NULL block that used to be one row `$07FB00-$07FFFF` (E2 runtime, ends at `$07FC2D`); the E2 row now ends at `$07FCFF`.
- `gfx/src/sprite/GFX_BC.png` (placeholder blocks in the new layout) is a graphics change inside the existing A0 row `$14FFFC-$16A26D`/`$16A275-$18BFB4`, no ROM-space change.

## E5 notes (decoration variants)

- One new 19-byte routine in the 36-byte free block `NULL_01B53C` (bank 01: the object routine table is read with `JMP.w ($000E)`, so the routine has to live in bank 01), two routine-table words and one data-offset word of unused diagonal objects, and a 256-byte window of
  `RoomDrawObjectData` (the 10-byte data blocks of the diagonal objects $09-$20; no HUSH room can load a vanilla room, and only ids $09/$0A are used with the new routine). Evidence: `rom/vanilla.sfc` bytes checked, `DrawObjects` tables `bank_01.asm:7-300`, grep of `RoomDrawObjectData.obj04xx` references (only the type-1 table rows of those ids).
- Collision unchanged: every variant uses tile ids of the vanilla tile type the replaced cell had (floor `$00` / solid `$01`, `UnderworldTileTypes`, `bank_0E.asm:274`); `tests/smoke/visual_tiles.lua` still compares `$7F2000` with the grid.

## Ledger history

- A0 (graphics overhaul): nine `hook` rows added, all for `tools/gfx_insert.py` (not asm). They are
  vanilla graphics/palette data replaced **in place**: same addresses, same lengths, no pointer
  changes, no free space consumed. Evidence: every region is a vanilla asset listed in
  `vendor/usdasm/graphics.asm` / the palette tables cited in `docs/gfx/formats.md`; compressed
  sheets are padded with $FF to their vanilla slot size, so no neighbour is touched. Regenerate
  the exact merged ranges with `.venv/bin/python tools/gfx_insert.py ledger`.
- E1 (foundation): hook rows for the camera lock (`$02885E`, `$02BA31`), the frame controller (`$0287BA`) and the title START branch (`$0CC130`); free rows in bank 07 (`$07F89D-$07F9FF`, `$07FA00-$07FAFF`,
  the head of `NULL_07F89D`); and the generated room-data rows (pointer-table tails, EntranceData rows 0-23 of 17 tables, room data regions). `$07FB00-$07FFFF` remains unclaimed free space.
- E2 (stealth AI): hook rows `$05C155` (guard entry), `$06ECB7` (arrow damage), `$089815` (bomb damage) and three free rows: `$0EEE22-$0EF3FF`, `$0EFB64-$0EFFFF`, `$07FB00-$07FFFF` (all `$FF` in the vanilla ROM, no references in `vendor/usdasm`).
- E5 (decoration variants): free row `$01B53C-$01B54E`, hook rows `$018212`, `$018014` and the variant table window `$009F72-$00A071`.
- E4 (guard drawing): hook row `$0DB0C1-$0DB0C3` (OAM entries per soldier type) and free row `$07FD00-$07FFFF` (`Hush_DrawGuard`; the E2 runtime row shrank to `$07FB00-$07FCFF`).
