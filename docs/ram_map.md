# HUSH RAM map (US 1.0, A Link to the Past)

Addresses the tests (`tests/lib/hush.lua`) need. Every row cites the
disassembly file and line it was taken from. Nothing here is from memory.

**This file is machine-read.** `tests/lib/hush.lua` parses the table rows below
(rows of the form ``| `name` | `$7Exxxx` | bytes | ...``). Keep that shape.
Add rows freely; don't change the column order.

All addresses are full WRAM addresses. In Mesen's Lua API they are read with
`emu.memType.snesWorkRam` using the offset `addr - 0x7E0000`. Direct-page
variables (`$00`-`$FF`) are `$7E00xx`; the disassemblies state this explicitly.

Sources (all under `vendor/`, see `tools/fetch_vendor.sh`):

- **A** = `AsarUSALTTPDisassembly/General/WRAM.asm`  (primary, labelled)
- **M** = `alttp-disassembly/Zelda_3_RAM.log`  (MathOnNapkins, cross-check)
- **S** = `alttp-disassembly/Zelda_3_SRM.log`  (save-data offsets)
- **B7** = `AsarUSALTTPDisassembly/Bank07.asm`  (code that proves the use)

Line numbers refer to the commits pinned in `tools/fetch_vendor.sh`.

## Player

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `link_y` | `$7E0020` | 2 | Link Y coordinate (16-bit, little endian) | A `WRAM.asm:236` (`.PlayerYCoord`), M `Zelda_3_RAM.log:168`; mirror at `$0FC4` (A `WRAM.asm:7717`) |
| `link_x` | `$7E0022` | 2 | Link X coordinate (16-bit, little endian) | A `WRAM.asm:240` (`.PlayerXCoord`), M `Zelda_3_RAM.log:172`; mirror at `$0FC2` (A `WRAM.asm:7713`) |
| `link_layer` | `$7E00EE` | 1 | Dungeon layer: 0 = upper (BG2), 1 = lower (BG1). Only meaningful in a dungeon | A `WRAM.asm:1633` (`.PlayerDunLayer`), M `Zelda_3_RAM.log:838` |
| `health_max` | `$7EF36C` | 1 | Health capacity; `$08` per heart | S `Zelda_3_SRM.log:341`; save data maps to `$7EF000+` per S `Zelda_3_SRM.log:98`; used at B7 `Bank07.asm:4606` |
| `health` | `$7EF36D` | 1 | Current health; `$08` per heart, `$04` half heart | S `Zelda_3_SRM.log:345`; B7 `Bank07.asm:3410` (damage subtracts one heart here) |

## Game state

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `game_mode` | `$7E0010` | 1 | Main module. `0x07` = dungeon, `0x09` = overworld, `0x12` = death, `0x0E` = text/menu/map | A `WRAM.asm:82` (`.Module`, values listed at 84-112), M `Zelda_3_RAM.log:30` |
| `submodule` | `$7E0011` | 1 | Submodule of the current module (`0x00` = normal gameplay in dungeon mode) | A `WRAM.asm:115` (`.Submodule`), M `Zelda_3_RAM.log:64` |
| `sub_submodule` | `$7E00B0` | 1 | Sub-submodule index (submodules of `$11`) | A `WRAM.asm:1199` |
| `room_id` | `$7E00A0` | 2 | Current dungeon room index (296 rooms; high byte 0 or 1) | A `WRAM.asm:1113` (`.DunRoomIndex`), M `Zelda_3_RAM.log:742` |
| `floor` | `$7E00A4` | 2 | Current dungeon floor (`0x00` = 1F, `0xFF` = B1, ...) | A `WRAM.asm:1124` (`.DunFloor`) |
| `frame_counter` | `$7E001A` | 1 | Frame counter, wraps at 255; used by the determinism test | A `WRAM.asm:193` (`.FrameCounter`), M `Zelda_3_RAM.log:122` |

## Sprite slot arrays (16 slots each, index 0 to 15)

Read slot `i` at `base + i`.

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `spr_type` | `$7E0E20` | 16 | Sprite type id. See soldier ids below | A `WRAM.asm:7022` (`.SprType`), M `Zelda_3_RAM.log:3860` |
| `spr_state` | `$7E0DD0` | 16 | Sprite state: `0x00` dead/unused, `0x09` active, `0x0B` stunned (full list below) | A `WRAM.asm:6914` (`.SprState`), M `Zelda_3_RAM.log:3741` |
| `spr_y_lo` | `$7E0D00` | 16 | Sprite Y low byte | A `WRAM.asm:6837` (`.SprLowYPos`), M `Zelda_3_RAM.log:3707` |
| `spr_x_lo` | `$7E0D10` | 16 | Sprite X low byte | A `WRAM.asm:6842` (`.SprLowXPos`), M `Zelda_3_RAM.log:3708` |
| `spr_y_hi` | `$7E0D20` | 16 | Sprite Y high byte | A `WRAM.asm:6847` (`.SprHighYPos`), M `Zelda_3_RAM.log:3709` |
| `spr_x_hi` | `$7E0D30` | 16 | Sprite X high byte | A `WRAM.asm:6852` (`.SprHighXPos`), M `Zelda_3_RAM.log:3710` |
| `spr_health` | `$7E0E50` | 16 | Sprite hit points | A `WRAM.asm:7313` (`.SprHealth`), M `Zelda_3_RAM.log:4145` |

Sprite position = `(hi << 8) | lo`, same coordinate space as Link.

## Sprite arrays likely needed once the awareness hooks exist (not used by M0 tests)

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `spr_dir` | `$7E0DE0` | 16 | Misc C; generally the facing direction | A `WRAM.asm:6938` (`.SprMiscC`), M `Zelda_3_RAM.log:3770` |
| `spr_timer_a` | `$7E0DF0` | 16 | Main sprite delay timer (counts down) | A `WRAM.asm:7001` (`.SprTimerA`), M `Zelda_3_RAM.log:3846` |
| `spr_misc_b` | `$7E0DB0` | 16 | Misc B; per-sprite variable | A `WRAM.asm:6902` (`.SprMiscB`), M `Zelda_3_RAM.log:3733` |
| `spr_head_dir` | `$7E0EB0` | 16 | Head direction for sprites with a head | A `WRAM.asm:7367` (`.SprHeadDir`) |
| `spr_floor` | `$7E0F20` | 16 | Which floor each sprite is on | A `WRAM.asm:7425` (`.SprFloor`) |
| `spr_ignore_proj` | `$7E0BA0` | 16 | Non-zero: ignore all projectile interactions | A `WRAM.asm:6387` (`.SprIgnoreProjectiles`) |

## Value tables

### Sprite state (`spr_state`), from A `WRAM.asm:6914-6937`

| Value | Meaning |
|---|---|
| `0x00` | Dead / inactive, no code runs |
| `0x01` | Falling into pit (generic) |
| `0x02` | Turning into a puff of smoke |
| `0x03` | Falling into deep water |
| `0x04` | Boss death |
| `0x05` | Falling into pit (special, e.g. soldiers) |
| `0x06` | Normal creature death |
| `0x07` | Burning |
| `0x08` | Spawning; prep routine runs for one frame |
| `0x09` | Active, AI code runs |
| `0x0A` | Carried by Link |
| `0x0B` | Frozen / stunned |

### Soldier sprite types (`spr_type`), from A `WRAM.asm:7096-7107`

| Value | Sprite |
|---|---|
| `0x41` | Green Soldier |
| `0x42` | Blue Soldier |
| `0x43` | Red Spear Soldier |
| `0x44` | Crazy Blue Killer Soldier |
| `0x45` | Crazy Red Spear Soldier |
| `0x46` | Blue Archer Soldier |
| `0x47` | Green Bush Archer Soldier |
| `0x48` | Red Javelin Trooper |
| `0x49` | Red Bush Javelin Soldier |
| `0x4A` | Red Bomb Soldier |
| `0x4B` | Weak Green Soldier |

## Caveats

- `$7E00EE` is shared by a polyhedral-renderer variable (A `WRAM.asm:1640`);
  `link_layer` is only valid in dungeon mode (`game_mode == 0x07`).
- `$7E0022` is also the attract-mode step counter (A `WRAM.asm:244`); only
  valid as Link X during gameplay.
- Health lives in the save-data mirror at `$7EF000-$7EF4FF` (A `WRAM.asm:8829`).
- The AsarUSALTTPDisassembly is a work in progress. If a row looks wrong in a
  test, cross-check it against `vendor/usdasm/` (`bank_XX.asm`) before
  trusting it, and fix this file in the same change.
