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
| `bg1_x` | `$7E00E2` | 2 | BG1/BG2 horizontal scroll (HUSH locks it to the room window: room base + 128) | A `WRAM.asm:1586` (`.BG2HPos`; written as the BG1 scroll register) |
| `bg1_y` | `$7E00E8` | 2 | BG1/BG2 vertical scroll (HUSH: room base + 144) | A `WRAM.asm:1609` (`.BG2VPos`) |
| `link_dir` | `$7E002F` | 1 | Link facing: 0 up, 2 down, 4 left, 6 right | A `WRAM.asm:347` (`.PlayerHeading`) |
| `frame_counter` | `$7E001A` | 1 | Frame counter, wraps at 255; used by the determinism test | A `WRAM.asm:193` (`.FrameCounter`), M `Zelda_3_RAM.log:122` |

## HUSH engine variables (E1; written by src/hooks/room_ctrl.asm)

`$7EC900-$7EE7FF` is documented as "seemingly Free RAM (nearly 8K!)" (A `WRAM.asm:8823`). Verified for HUSH: no
instruction in `vendor/usdasm/bank_*.asm` addresses `$7EC9xx`..`$7EE7xx` (grep of every `$7E[C-E]xxx` operand: only
`$7EC0xx-$7EC8xx` HUD/palette buffers and the boot-time full-WRAM clear loop `bank_0C.asm:90-112`, which runs once at
power-on and zeroes them). HUSH owns `$7EC900-$7EC9FF`.

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `hush_room` | `$7EC900` | 1 | Current HUSH room index, 0-based (room id = `$128 + hush_room`; entrance row = index). Set by `Hush_LoadRoom`; tests may read it, and poking it does NOT load a room (use `hush_room_req`) | E1 `src/hooks/room_ctrl.asm`; free per the note above |
| `hush_room_req` | `$7EC901` | 1 | Debug/test room jump: write N+1 and the controller loads room N on the next gameplay frame (module 7, submodule 0), then clears it. 0 = none; values > room count are ignored | E1 `src/hooks/room_ctrl.asm` |

## HUSH stealth AI variables (E2; src/hooks/guard_ai.asm, guard_hooks.asm, guard_runtime.asm)

`spr_aware` is the **debug/test API** of the AI: one byte per sprite slot in the vanilla sprite array `$0D80` (`.SprAIState`, A `WRAM.asm:6879`:
the "sprite AI state index"; HUSH replaces the whole guard routine, so the array is ours for sprite types `$41-$43`).
Nothing else in HUSH writes `$0D80`: no other sprite type exists in a HUSH room (probes `$41` with `$0DB0 != 0` are never spawned).
The other guard variables are listed in the header of `src/hooks/guard_ai.asm`.

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `spr_aware` | `$7E0D80` | 16 | Guard awareness per sprite slot: 0 unaware, 1 suspicious (`?`), 2 alert (`!`), 3 asleep (`Z`). Vanilla `Guard_Main` used this array as its AI state (`bank_05.asm:12160-12177`, `.vectors` `$05C2C6`); replaced by E2 | A `WRAM.asm:6879` (`.SprAIState`), M `Zelda_3_RAM.log:3723`, E2 `src/hooks/guard_ai.asm` |
| `spr_timer_lost` | `$7E0E10` | 16 | Guard "lost sight" timer (suspicious 120, alert 180 frames, decremented by `DoSpriteOAMandTimers`, `bank_06.asm:431-437`) | A `WRAM.asm:7015` (`.SprTimerC`), E2 `guard_ai.asm` |
| `spr_aux` | `$7E0D90` | 16 | Guard aux byte: 1 = pausing at a wall (state 0); remaining 240-frame chunks of a sleep (state 3) | A `WRAM.asm:6892` (`.SprFrame`, "misc uses"), E2 `guard_ai.asm` (vanilla only clears it with ResetSpriteProperties at spawn, `bank_0D.asm:7926`) |
| `spr_subtype` | `$7E0E30` | 16 | Sprite sub-type from the sprite list: bits 0-2 facing code (1 left, 2 right, 3 up, 4 down), bit 3 = `move: still` (roomgen) | `bank_09.asm:13607-13651`, `tools/roomgen.py` |
| `hush_caught` | `$7EC902` | 1 | 1 = a guard caught Link; `Hush_Tick` runs the fast restart on the next gameplay frame and clears it. Tests poke it to trigger a restart | E2 `guard_runtime.asm` |
| `hush_flash` | `$7EC903` | 1 | Restart flash: 6 .. 1 frames left (screen brightness `$13` = 0), 0 = none | E2 `guard_runtime.asm` |
| `hush_pal` | `$7EC904` | 1 | 0 = the runtime sprite palettes (alert amber row 6, ink row 1) still have to be written for this room load | E2 `guard_runtime.asm` |
| `hush_range` | `$7EC906` | 2 | Guard vision range in pixels: 80 dark room, 128 lit room (`Hush_Tick`, from ROOM TABLE +19 bit 0) | E2 `guard_runtime.asm` |
| `hush_ink_x` | `$7EC908` | 2 | Ink cloud centre X (absolute pixels, the exploded bomb position `$0C18:$0C04`) | E2 `guard_hooks.asm` |
| `hush_ink_y` | `$7EC90A` | 2 | Ink cloud centre Y (`$0C0E:$0BFA`) | E2 `guard_hooks.asm` |
| `hush_ink_t` | `$7EC90C` | 2 | Ink cloud frames left (300 at the explosion); 0 = no cloud | E2 `guard_hooks.asm`, `guard_runtime.asm` |

## HUSH feel / polish variables (E6; src/hooks/transition.asm, ending.asm, feedback.asm)

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `hush_gfx` | `$7EC90E` | 1 | 1 = the HUSH room graphics are resident in VRAM / WRAM, so a room load skips the graphics work (fast load); 0 = full load. Set by the first full load (`Hush_InitTilesets`), cleared by `Hush_NewGame` and when the ending takes the screen. Tests poke 0 to force a full load | E6 `transition.asm` |
| `hush_trans` | `$7EC90F` | 1 | Room transition state in submodule `$0F`: 0 none, 1 fading out (before an advance), 2 fading in (after a load) | E6 `transition.asm` |
| `hush_tcnt` | `$7EC910` | 1 | Pass counter of the running fade | E6 `transition.asm` |
| `hush_next` | `$7EC911` | 1 | Room index to load when the fade-out ends; `$FF` = the ending | E6 `transition.asm` |
| `hush_retries` | `$7EC912` | 2 | Times caught in this run (saturates at 999); reset by `Hush_NewGame`; shown on the ending screen | E6 `ending.asm` |
| `hush_sec` | `$7EC914` | 2 | Play time of this run in seconds (gameplay frames only, saturates at 5999) | E6 `ending.asm` |
| `hush_fsub` | `$7EC916` | 1 | Frames within the current second (0-59) | E6 `ending.asm` |
| `hush_etimer` | `$7EC917` | 1 | Frame counter of the ending module states | E6 `ending.asm` |
| `hush_cmsave` | `$7EC919` | 5 | `$99 $9A $9C $9D $9E` saved while the caught flash runs | E6 `feedback.asm` |
| `hush_lx` | `$7EC940` | 2 | Link's x (`$22`) at the end of the last gameplay frame (written by `Hush_SaveLink`, `feedback.asm`, called by `Hush_Refills` = the end of the frame, after Link moved and the guards ran); `Hush_Solid` puts Link back there when he moves into a sleeping guard | E7 `feedback.asm`, `guard_ai.asm` |
| `hush_ly` | `$7EC942` | 2 | Link's y (`$20`) at the end of the last gameplay frame (see `hush_lx`) | E7 `feedback.asm`, `guard_ai.asm` |
| `hush_ebuf` | `$7EC920` | 32 | Ending screen text buffers: RETRIES line at `+0`, TIME line at `+$10`, the saved PRESS START colour at `+$0E` (overlaps the RETRIES template padding) | E6 `ending.asm` |

Vanilla variables the E6 code relies on (documented where used): `$012C` song request, `$012D/$012E/$012F` SFX1/2/3 requests (NMI: `bank_00.asm:239-291`),
`$0130` current song, `$0132` entrance song, `$0133` last song sent to the APU, `$0136` underworld song bank loaded, `$13` screen brightness, `$16` HUD upload flag, `$F4` new button presses.

## HUSH stealth meter (design/pillars.md "Stealth meter"; defines in src/ram.asm)

Block `$7EC950-$7EC98F`, inside HUSH's `$7EC900-$7EC9FF` (free per the E1 note above and A `WRAM.asm:8823`). Re-verified
for these bytes: no `$7EC9xx` operand anywhere in `vendor/usdasm/`, and every `$C95x-$C98x` match in `vendor/usdasm/` is a
`dw` tile / MAP16 data word (`bank_00.asm:4927-7155`, `bank_0F.asm:1054-3542`, `bank_0C.asm:5614`), not a RAM operand.
No other HUSH hook uses them (E1-E7 use `$7EC900-$7EC943`; grep of `src/`). Per-guard arrays are indexed by sprite slot
like `spr_aware` (16 slots, `base + slot`).

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `hush_meter` | `$7EC950` | 1 | Stealth meter, 0..32, always a multiple of 4; 32 on every room entry (new game, advance, restart). A hit to 0 sets `hush_caught` | pillars.md:42-75; `src/ram.asm` |
| `hush_mflash` | `$7EC951` | 1 | HUD hit flash: 16 .. 1 frames left (lost cells drawn amber), 0 = none | pillars.md:92; `src/ram.asm` |
| `hush_mlost` | `$7EC952` | 1 | Meter value before the last hit; while `hush_mflash` > 0 the cells between `hush_meter` and this value are amber | pillars.md:92; `src/ram.asm` |
| `hush_cd_small` | `$7EC960` | 16 | Per sprite slot: small (4) hit cooldown, 121 .. 0. Set to 121 by a hit in frame H; decremented at the start of each meter check, then tested (0 = allowed), so H+1..H+120 are blocked and H+121 is allowed; cleared on room entry | pillars.md:65-70, :107-109; `src/ram.asm`; `src/hooks/meter.asm` (B-007) |
| `hush_cd_big` | `$7EC970` | 16 | Per sprite slot: big (16) hit cooldown, 121 .. 0, same rule as `hush_cd_small`; cleared on room entry | pillars.md:65-70; `src/ram.asm`; `src/hooks/meter.asm` (B-007) |
| `hush_aprev` | `$7EC980` | 16 | Per sprite slot: the `spr_aware` value seen at the last meter check (a hit fires on 0->1 small, 0->2 / 1->2 big); reset on room entry | pillars.md:52-59; `src/ram.asm` |

Vanilla bytes the meter code (`src/hooks/meter.asm`) relies on: `$0373` Link's pending damage, zeroed before `LinkControlHandler` applies it (`bank_07.asm:109-130`);
`$7EF36C` / `$7EF36D` health max / health (copied at the end of every gameplay frame); `$16` HUD upload flag (`bank_00.asm:1951`); `$1A` frame counter (low-meter blink, bit 4);
HUD buffer cells `$7EC768-$7EC777` (BG3 row 3, cols 20-27, `docs/gfx/hud_map.md:37`). Scratch: `$00`.

## HUSH lighting (L1, `src/hooks/light.asm`, design/lighting.md)

Block `$7ECA00-$7EE7FF`, inside the "seemingly Free RAM" `$7EC900-$7EE7FF` (A `WRAM.asm:8823`; the E1 note above: no `$7EC9xx-$7EE7xx`
operand in `vendor/usdasm/` except the power-on clear). Not used by any other HUSH hook (E1-M5 use `$7EC900-$7EC98F`; grep of `src/`).
The light code runs with DB = `$7E` and addresses these as `$CA00..`.

| Name | Address | Bytes | Meaning | Source |
|---|---|---|---|---|
| `light_sol` | `$7ECA00` | 960 | Padded light grid (32 x 30, `p = (cy + 8) * 32 + cx + 8`): bit 0 solid, bit 1 face (solid with an open cell below: catches light), bit 6 ink cloud, bit 7 outside the 16 x 14 grid | L1 `src/hooks/light.asm` |
| `light_scr` | `$7ECDC0` | 960 | Padded scratch: light steps of the running job | L1 `src/hooks/light.asm` |
| `light_gmap` | `$7ED180` | 1792 | Committed light step per guard slot and cell: `slot * 224 + cy * 16 + cx` (slots 0-7) | L1 `src/hooks/light.asm` |
| `light_comp` | `$7ED880` | 224 | Composite light step per cell (max over the guards), 0..6 | L1 `src/hooks/light.asm` |
| `light_vio` | `$7ED960` | 224 | Player glow per cell: 2 Link's cell, 1 orthogonal neighbours (floor only), 0 none | L1 `src/hooks/light.asm` |
| `light_tiles` | `$7EDA40` | 1792 | BG1 window tile words, 28 rows x 32 (uploaded by the NMI, dirty cell rows only) | L1 `src/hooks/light.asm` |
| `light_vis` | `$7EE140` | 200 | Ray visibility of the current wedge, `[2 * entry]`; entry 99 = the origin (always 1) | L1 `src/hooks/light.asm` |
| `light_tab` | `$7EE210` | 1302 | Copy of `Hush_LightTab` (ray deltas per facing, parents, distances, steps, tile words; 99 entries per wedge), made by `Hush_LightInit` | L1 `src/hooks/light.asm` |
| `light_on` | `$7EE740` | 1 | 1 = lighting active (set by `Hush_LightInit` on every room load) | L1 `src/hooks/light.asm` |
| `light_dirty` | `$7EE742` | 2 | Cell rows (bits 0-13) whose tile words wait for the NMI upload (worker `TSB`, NMI `TRB`) | L1 `src/hooks/light.asm` |
| `light_sigc` | `$7EE748` | 32 | Committed signature per slot: class (0 none, 1 cone, 2 suspicious, 3 alert, $FF invalid), facing, padded cell (2) | L1 `src/hooks/light.asm` |
| `light_job` | `$7EE768` | 30 | Worker state: tested / job signature, job slot (`$7EE770`, $FF idle), phase, wedges, entry, range end, step row, edge, commit half-row, round robin, glow cell (`$7EE77E`), ink centre, palette request, V counter at entry | L1 `src/hooks/light.asm` |

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
