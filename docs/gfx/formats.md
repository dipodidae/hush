# Graphics formats and ROM locations (verified)

Owner: engine. Every fact below cites `vendor/usdasm/` (file:line of the line
that proves it) and was cross-checked against `rom/vanilla.sfc` by
`tools/gfx_refdump.py` (it decompresses every sheet; all sizes come out as
exact whole numbers of tiles). Addresses are LoROM SNES addresses.

## Answer to "compressed 3bpp, Link uncompressed 4bpp?"

**Mostly right, with four corrections.**

| Claim | Verdict |
|---|---|
| Most sheets are compressed 3bpp | **Correct.** `GFX_00`..`GFX_D9` (except the 12 below) are 3bpp sheets, stored compressed (`graphics.asm:25-257`, suffix `.3bppc`). Each decompresses to `$0600` bytes = 64 tiles x 24 bytes. |
| Link is uncompressed 4bpp | **Correct.** `LinkGraphics` `$108000`, `link.4bpp` (`graphics.asm:5-6`), `$7000` bytes = 896 tiles x 32 bytes (size = distance to the next asset `GFX_73` at `$10F000`, `graphics.asm:11`). DMA'd straight from ROM by the frame-update code (`bank_00.asm:1766-1800`, `LDA.b #^LinkGraphics`, DMA from `LinkOAM_*Addresses` offsets `bank_00.asm:3462-4106`). |
| (correction 1) | `GFX_73`..`GFX_7E` are **uncompressed** 3bpp, `$0600` bytes each (`graphics.asm:9-23`, suffix `.3bpp`, "Uncompressed" banner). They are in the same pointer table. |
| (correction 2) | The HUD sheets `GFX_DA`..`GFX_DE` are **compressed 2bpp** (`graphics.asm:249-254`, `.2bppc`). They decompress to `$0800` bytes = 128 tiles x 16 bytes. |
| (correction 3) | The text/dialogue font `TheFont` is **uncompressed 2bpp**, `$0E8000`, `$1000` bytes = 256 tiles (`bank_0E.asm:5-6`; the next data, `CustomTileTypesOffset`, starts at `$0E9000`, `bank_0E.asm:12-13`). |
| (correction 4) | The world map is **uncompressed 8bpp Mode 7** at `$18C000` (`graphics.asm:281`, `bank_00.asm:11985-12010` `TransferMode7Characters`). |
| 3bpp in VRAM | 3bpp sheets are **expanded to 4bpp** on upload. Plane 3 is 0 ("LeftPalette") or the OR of planes 0-2 ("RightPalette", i.e. colours 9-15) (`bank_00.asm:12439-12470` `Expand3bppToVRAM_RightPalette`, `:12557-12612` `Expand3bppToVRAM_LeftPalette`). So a 3bpp sheet has colours 0-7 (0 = transparent): **7 opaque colours**. |

## 3bpp / 2bpp / 4bpp tile layout

SNES planar, 8x8 tiles. ALttP 3bpp tile = 24 bytes: for each of 8 rows two bytes
(planes 0,1 interleaved by row, 16 bytes), then 8 bytes of plane 2 (one per row).
Evidence: `LoadCommonSprites` reads 16 bytes as word pairs into VMDATA, then 8
single bytes for the third plane (`bank_00.asm:12651-12720`). 2bpp tile = 16
bytes (the first 16 bytes of the above). 4bpp tile = 32 bytes: planes 0,1
interleaved (16 bytes) then planes 2,3 interleaved (16 bytes)
(`tools/gfx_convert.py:encode_4bpp`, already used by M0).

## Sheet pointer table

`GFXSheetPointers` at `$00CF80` (`bank_00.asm:8383`) is six consecutive byte tables:
`.background_bank` `$00CF80` (`:8385`), `.sprite_bank` `$00CFF3` (`:8504`),
`.background_high` `$00D05F` (`:8616`), `.sprite_high` `$00D0D2` (`:8735`),
`.background_low` `$00D13E` (`:8847`), `.sprite_low` `$00D1B1` (`:8966`).
Background tables have `$73` entries (`GFX_00..GFX_72`), sprite tables `$6C`
entries (`GFX_73..GFX_DE`). **Sprite-table index `i` is sheet `GFX_(73+i)`**
(`bank_00.asm:8505`: `.sprite_bank` entry 0 is `^GFX_73`; `:8978` `.sprite_low`
entry `$0B` is `<GFX_7E`).
Background entries `$71` and `$72` are **aliases** of `GFX_DD` and `GFX_DE`
(they point at `$18B520` / `$18B953`; confirmed from the ROM).
Callers: `Decompress_background_*` use the background table, `Decompress_sprite_*`
the sprite table (`bank_00.asm:12788-12856`). Example: `LoadFileSelectGraphics`
passes `Y=$5E`/`$5F` to `Decompress_sprite_low` (`bank_00.asm:12271-12290`), i.e.
`GFX_D1`/`GFX_D2`.

The pointer tables themselves are **not changed by A0** unless a relocation
is needed (none planned; see "Slot capacity").

## Compression (all `.3bppc` / `.2bppc` sheets)

`Decompress` at `bank_00.asm:12857` (loop `.next_command` `:12862`). Stream of commands, `$FF` ends it:

```
CCCLLLLL            cmd CCC, length = LLLLL+1 (1..32)         (bank_00.asm:12862-12878)
111CCCLL LLLLLLLL   expanded: cmd = CCC, length = LL:next+1   (`.expanded` bank_00.asm:12893)
cmd 0 ($00) raw copy        n bytes follow                     (.raw_copy :12949)
cmd 1 ($20) repeat byte     1 byte                             (.repeating_byte :12965)
cmd 2 ($40) repeat word     2 bytes, alternating               (.repeating_word :12983)
cmd 3 ($60) incrementing    1 byte, +1 each output byte        (.incremental :12930)
cmd 4 ($80) copy from output at absolute 16-bit little-endian offset  (.copy_past :13013)
```

The command decode is `AND #$E0`/`ASL` ladder at `bank_00.asm:12874-12929`.
`tools/gfx_compress.py` implements an optimal-parse compressor for exactly this
format. `python tools/gfx_compress.py --selftest` round-trips synthetic data and
vanilla sheets (`--full`: all 209 compressed sheets: decompress(ours(x)) == x;
our output is slightly smaller than the vanilla compressor's in total).

## Slot capacity (does compressed data fit?)

Compressed sheets are packed back to back (`graphics.asm`: each address equals the
previous address + size). **There is no slack between sheets**, so a replacement
must compress to **at most the vanilla compressed length of its slot**
(`build/ref/meta/assets.json: capacity`). Tightest slots: `GFX_DB` 46 bytes,
`GFX_C7` 415, `GFX_07` 681 (`graphics.asm` sizes). The 17 "blank" sheets
`GFX_61..GFX_70` and `GFX_9E` are 7 bytes (an empty stream) and are left untouched.
The placeholder generator picks, per sheet, the most detailed drawing that
compresses into its slot and reports the fallback it used. If a sheet cannot be
reduced enough the build stops and a relocation plan goes to the human (none needed so far).
Uncompressed slots (`GFX_73..GFX_7E`, `LINK`, `FONT`) are fixed size and fit by construction.

## Palettes

All sprite/BG/HUD/Link palettes live in one block, `PaletteData`
(`bank_1B.asm:4646` to `SwordPaletteOffsets` `bank_1B.asm:5879`), `$1BD218`..`$1BEBB3`:
459 `dw` rows of 7 colours (colours 1-7 of a 16-colour palette; BGR555 little-endian;
colour 0 comes from elsewhere) in labelled groups (`.sprite_00`, `.Link`
`.link_00`.., `.spritepal0_*`, `.environment_*`, `.spriteaux_*`, `.sword_*`,
`.shield_*`, `.hud_*`, `.dungeon_*`, `.owanim_*`, `.owmain_*`, `.owaux_*`).
Palette selectors (`PaletteIDtoOffset*`, `bank_1B.asm:5897-6031`) are offsets into
this block, so replacing the colour words **in place** changes no pointers.
`tools/gfx_refdump.py` writes the row layout to `build/ref/meta/palette_layout.json`.
Separate palette tables: `Palettes_LWMAP`/`Palettes_DWMAP` (`bank_0A.asm:3620-3670`,
256 bytes each, map screen), `Palettes_Triforce` (`bank_0C.asm:538`, 16 bytes),
`Palettes_BlueThunder1-5` and `Palettes_GanonTowerFlash` (`bank_0E.asm:12290-12320`).
Colours hard-coded as immediates in code (text colours, fades) are **not** in tables;
the leak detector (CGRAM dump) is how those get found.

## Not graphics pixels (untouched)

Tilemaps (title/file-select/dungeon-map BG3 tilemaps, `bank_00.asm:3433-3449`),
Map16 definitions (`bank_0F.asm:5`), room/object data, OAM frame tables
(`LinkOAM_*Addresses`) are index data, not pixels, and stay vanilla.
They reference tile numbers; the placeholders keep every tile position, so they
still index the right tiles.

## Sprite sheets in VRAM (how a placeholder meets the game)

BG tilesets: `SheetsTable_AA1/AA2` (`bank_00.asm:11562`, `:11158`) list 8 background
sheets per tileset; sheet `k` of a tileset is loaded to VRAM tile slot `k`
(64 tiles each, `InitializeTilesets` `bank_00.asm:11607-11811`; `$7EC2F8-FB` override
slots 3-6). Sprite sets: `SheetsTable_AA3` (`bank_00.asm:11010`) lists 4 sprite
sheets per set (index space = sprite table, add `$73`), sets `$40`+ are the
underworld sets (comment text `0x40 - 0x00 for underworld`). Equipment: sword
and shield graphics are decoded from `GFX_D1`/`GFX_D2`
(`DecompressSwordGraphics`/`DecompressShieldGraphics`, `bank_00.asm:9214`/`:9271`,
`LDY #$5F`/`#$5E`).

## Gotcha: uncompressed sheets are also fed to the decompressor

`GFX_73..GFX_7E` are stored uncompressed (`graphics.asm:9-23`) but the sprite-set table
`SheetsTable_AA3` can still list them: row `$7D` (used by the intro, `$0AA3 = $7D`, `bank_00.asm:11076`
and `Intro_InitializeDefaultGFX`, `bank_0C.asm:168`) has `$08` = `GFX_7B`, and `InitializeTilesets`
calls `LoadSpriteGraphics` -> `Decompress_sprite_arbitrary` on it (`bank_00.asm:11676-11688`, `:12406`).
So the raw bytes are parsed as a compressed stream. Vanilla's bytes happen to terminate harmlessly.
An arbitrary placeholder does not: the stream ran past its end, wrote through `$7E:C300` and wiped the
intro palettes (found with a write watchpoint: `[$00],Y` store at `$00E836`). Rule enforced by
`tools/gfx_insert.py`: an uncompressed 3bpp sheet must start with `$FF` (the end-of-stream command),
which means tile 0 row 0 is drawn as colour 1 (`tools/gfx_placeholder.py` does this). Anyone painting
over these sheets must keep that row.
