# HUSH engine notes (E1: foundation, E2: stealth AI, E3-E5: room visuals)

Sections 1-10: everything the engine learned while building camera lock, the one-screen room format, new game, the room compiler and
the per-frame controller (E1). **Section 11 onwards: E2 (stealth AI, damage rules, caught -> fast restart, ink cloud, icons, test ROM)**, section 11.12 = E4 (the custom guard drawing);
**section 15 = E7 (B-003 knife line of sight, B-005 chase collision, B-006 frame budget with pots / arrows, menu polish)**; where E2 changed an E1 statement, the E1 text says so. Facts are cited (`bank_XX.asm:line` = `vendor/usdasm`) or were measured in MesenCE with the
scripts named in brackets. Nothing here is from memory.

## 1. The room model

A HUSH room is the **visible 256x224 window of one vanilla 512x512 room**. All HUSH rooms use vanilla layout 7
(`RoomLayout_07`, `bank_04.asm:5144-5199`: one big open room: walls only at tile x 2..6 / 58..62, y 4..8 / 58..62), so
the window is entirely inside the open interior and every wall inside it is drawn by us.

| Thing | Value |
|---|---|
| Room ids | `$128 + k` for the k-th room (0-based, order of `seq`). Ids `$128..$13F` are the unused tail of every 320-entry room pointer table; room flags `$7EF000 + 2*room` stay below `$7EF280`. Max 24 rooms |
| Room base (pixels) | `x = (id & 15) * 512`, `y = (id >> 4) * 512` (rooms `$128-$12F` are in room row `$12`, `$130-$13F` in row `$13`) |
| Window origin (room-local px) | `WIN_X = 128`, `WIN_Y = 144`; in 8x8 tiles `(16, 18)`. Constants live in `tools/roomgen.py` and are exported to asm as `!HUSH_WIN_X/Y` |
| Grid | 16 x 14 cells of 16x16 px. Cell `(cx, cy)` = pixels `base + (128 + 16*cx, 144 + 16*cy)` = tiles `(16 + 2cx, 18 + 2cy)` |
| Camera | `$E2 = base_x + 128`, `$E8 = base_y + 144` (also `$E0/$E6`), never changes. Verified constant while walking [`tests/smoke/newgame.lua`] |
| HUD | BG3, covers the top ~24 px (real art). The A0 *placeholder* HUD is taller (about 62 px, hex-labelled tiles) and hides Link when he starts near the top-left; grid rows 0-1 are walls anyway |

### Link and sprite coordinates

* Link's `(x, y)` = `$7E0022` / `$7E0020` is the top-left of a 16x16 box. His **tile-collision box is `x..x+15`, `y+8..y+23`**
  (measured: walking into the left wall stops at `x = cell_left`, into the top wall at `y = wall_bottom - 8` [probe]).
* To stand exactly in cell `(cx, cy)`: `x = cellX`, `y = cellY - 8`. roomgen uses this for the start position.
* The exit test point is the **centre of the box**: `(x + 8, y + 16)` (`!HUSH_FEET_DX/DY`). Touching an `X` cell means this point is inside it.
* Sprite positions in a room's sprite list are in 16-px units inside the 512 room: unit = `8 + cx`, `9 + cy` for cell `(cx, cy)`; the
  loader adds the room row/column (`LoadUnderworldSprites`, `bank_09.asm:13440-13480`, `LoadSingleUnderworldSprite`, `bank_09.asm:13602-13686`).

## 2. Camera lock (hooks in `src/hooks/camera_lock.asm`)

`HandleUnderworldCamera` ($02BA31) and `Underworld_TryScreenEdgeTransition` ($02885E) are each replaced by
`SEP #$20 : RTS` (E2 20 60), the exact exit state of the originals. Vanilla bytes checked in the ROM:
`C2 20 A9 01 00 ...` and `C2 20 A5 30 29 ...`. Scroll values then stay what `LoadUnderworldEntrance` wrote from
`EntranceData.horizontal_scroll/vertical_scroll`. Nothing else was needed: BG1/BG2 scroll registers read `$E2/$E8` and
`$E0/$E6`; sprites/Link are drawn relative to them.
BG3 (HUD) scroll is 0/0 (`$E4/$EA`) and stays so.

## 3. Collision (measured with `tests/dev/dump_collision.lua`, `$7F2000`)

* `$7F2000` is the collision map Link uses (64x64 bytes, one per 8x8 tile, row stride 64). `$7F3000` (second layer) stays all 0 for HUSH rooms.
* `$00` floor/walkable, `$01` solid. Our `$00` ceiling objects produce `$01` exactly on the cells they cover; the interior is `$00`.
* Dev room 1 (empty interior, `#` rim): window tiles x 16..47, y 18..45 (32 x 28 tiles); solid rows 18-21 and 44-45, solid columns 16-17 and 46-47; everything else is `$00`.
  **Walkable interior: 14 columns x 11 rows = 154 cells (39 424 px^2)** out of 224 cells in the grid (70 solid). Outside the window the map is `$00` (walkable) but unreachable behind the solid rim.
* Link cannot leave: pushing left for 180 frames stops at window x = 16 [`tests/smoke/newgame.lua`].
* Other values seen when probing other object ids (not used): `$02`, `$06`, `$07`.

### Object ids (type 1, `RoomDraw_DrawAllObjects`, `bank_01.asm:1251-1330`; table `DrawObjects`, `bank_01.asm:268`)

| id | draws | used by |
|---|---|---|
| `$00` | "Ceiling": 2x2 tiles per repeat to the right, size 1..15 = repeats, **size 0 = 32 repeats** (`RoomDraw_Rightwards2x2_1to15or32`). Solid (`$01`). One repeat = one grid cell | `#` and `p` cells (horizontal runs) |
| `$60` | same, downwards | `#`/`p` (vertical runs) |
| `$07`, `$08`, `$53`, `$B8`, `$B9` ... | other 2x2 shapes; `$53` = solid wall piece, `$07/$08` = dark tiles with collision `$00` | not used yet |

Object encoding: `b0 = XXXXXXss`, `b1 = YYYYYYss`, `b2 = id`; X, Y are 8-px tile coordinates 0-63 and `size = (b0 & 3) << 2 | (b1 & 3)`.
Stream: `b0` floor nibbles (we use `$22`), `b1 = layout << 2` (layout 7 -> `$1C`), list 1 objects `FF FF`, list 2 `FF FF`, list 3 `F0 FF` (door marker) then doors then `FF FF`.
HUSH rooms put every object in list 1 and have no doors (`F0 FF FF FF`); the door pointer (`RoomData_DoorDataPointers`) points at the final `FF FF`.
The placeholder art draws every non-wall, non-floor tile as hex-labelled text, which makes object experiments easy to read.

roomgen covers solid cells with the smaller of a horizontal-run and a vertical-run decomposition (runs split at 15). A simple 16x14 room takes about 28 objects
(~100 bytes); the worst case (checkerboard) stays well under the 12 KiB stream budget for 24 rooms.

**E3 (section 12):** `#`, `p` and `X` are no longer drawn alike: wall top `$00/$60`, wall face `$07`, pillar `$B8/$92`, exit marker `$B9/$93`, each with its own tile words; collision is unchanged.

## 4. Header, sprite list, pointer tables

* Header (14 bytes, `LoadRoomHeader`, `bank_01.asm:9986-10215`): `b0 = bg2mode << 5 | collision << 2 | dark(bit0)`, `b1` palette set (E3: UnderworldPaletteSets row 0-5 = dark/lit x floor 1-3, section 12), `b2` blockset (`$0AA2`), `b3` sprite gfx set (`+$40` -> `$0AA3`), `b4..b13` tags/warp/stairs.
  HUSH: `00 <palette row> 00 04 00...` (E3; was `00 00 00 04 00...`). `04` = the soldier sprite set used by all vanilla castle rooms with soldiers (`$50`, `$52`, `$60-$62` have palette 0 / blockset 0 / sprite set 4).
  The vanilla "dark room" bit is left 0: HUSH `lighting: lit|dark` is a guard-range rule, not the vanilla darkness effect.
* Sprite list: `00 | b0 b1 b2 ... | FF`; `b0 = l ss yyyyy`, `b1 = ttt xxxxx`, `b2 = sprite id`. `l` = layer, `yyyyy`/`xxxxx` = 16-px units in the 512 room,
  sub-type (`$0E30`) = `ss << 3 | ttt`. Guards use sprite `$41` (green soldier, `Guard_Main`, `bank_05.asm:12115`).
* Pointer tables rewritten in place for rooms `$128..`: object `$1F8000` (3 B), door `$1F83C0` (3 B), header `$04F502` (2 B, bank 04 hard-coded in `LoadRoomHeader`), sprites `$09D62E` (2 B, bank 09 hard-coded).
  The data they point to sits in vanilla regions of rooms that HUSH can never load (see `src/FREESPACE.md`). All other vanilla tables keyed by room id already have a shared "empty" entry for rooms `$128+` (pot items `$E6B0`, checked in the ROM).

## 5. Guard sprites (vanilla soldier AI, what E1 spawned; **replaced in E2, see section 11**)

`SpritePrep_StandardGuard` (`bank_06.asm:3445`) and `Guard_Main` (`bank_05.asm:12115`), measured with `tests/dev/guard_behaviour.lua`:

* Sub-type (`$0E30`, from the sprite-list bytes `ss << 3 | ttt`): values 1-4 set the initial direction `$0DE0 = (n - 1) xor 1`; guard direction codes are **0 right, 1 left, 2 down, 3 up**
  (`GuardSpeeds_X/Y`, `bank_05.asm:12317-12322`). So roomgen writes `left = 1, right = 2, up = 3, down = 4`. Verified for every guard of every room [`tests/smoke/guard_facing.lua`].
  Values 5-7 select "probe" sentries (`Guard_ShootProbeAndStuff`). Sub-type 0 = random looking-around. Guards spawn exactly on the grid cell (sprite origin = cell top-left).
* Observed AI (all indoor guards, sub-type 1): `$0D80` (AI state) cycles 0 idle (look around, timer) -> 1 **on patrol** (walks straight, ~95 px in 180 frames) -> 2 surveying (stops, looks around) -> 0 ... and turns around (`EOR 1`) when
  blocked. So vanilla indoor guards **do patrol along their facing axis**, they never stand still for long. "move: still" is therefore NOT implemented by E1 (both `patrol` and `still` spawn the same vanilla guard); the AI milestone must pin `$0D80`.
  **E2: `Guard_Main` is no longer run; `move: still` is sub-type bit 3 (section 11.2).**
* Vanilla detection works unmodified: when Link is in the probe line of sight the guard goes to state 4 (in pursuit, `$0D80 = 4`) and chases. Damage to Link is vanilla; health is refilled every frame so Link survives (see pitfalls).
* The guard's own "probe" sprites also report type `$41` in state 9 (slots 9/10 in the probe log): count `>= #guards`, not `==`.

## 6. New game: title START -> room 1 (`src/hooks/new_game.asm`)

START/A/B/X/Y on the title are handled at `$0CC126-$0CC130` (`bank_0C.asm:19-24`), which used to `JMP FadeMusicAndResetSRAMMirror` (-> file select).
Now it jumps to `Hush_TitleStart` ($0CC110, in the A0 block of `intro_skip.asm`) -> `Hush_NewGame`:

1. `JSL FadeMusicAndResetSRAMMirror` ($0CC2F0): fades music, clears `$20-$8F` and the whole save mirror `$7EF000-$7EF4FF`, sets `$10=1`.
2. Writes the start file straight into the mirror (no SRAM slot): `$7EF36C = $7EF36D = $18` (3 hearts), `$7EF3C5 = 2`.
   **Dossier correction: `$7EF3C5 = 2`, not 1.** Any non-zero value honours the entrance X/Y (`bank_02.asm:15607`) and skips the bed cutscene (`bank_02.asm:549`);
   values `< 2` start the **rain ambience** (`UnderworldAdjustRainSFX`, `bank_02.asm:586-607`, `$012D = 3`).
3. Repeats the non-SRAM part of `CopySaveToWRAM` (`bank_0C.asm:2636-2750`). **Pitfall found the hard way:** without `$0219 = $6040` (HUD VRAM destination)
   the NMI DMA writes the HUD buffer to VRAM `$0000`, i.e. into the BG2 tilemap, and no HUD shows. It also sets `$021D/$021F/$0221`, `$7EC00D/0F/13/15`, `$0204`, `$0710`, `$0AB2` and clears `$1AB0-$1AFF`.
4. `Hush_LoadRoom(0)`: Module 5.

Result: cold boot -> title (~frame 400 incl. the A0 title) -> START -> Link controllable in room 1 after **198 frames** (3.3 s, black screen for ~117 of them). Slot 0 SRAM is never read or written.
Dead code paths now: file select, name entry, Link's house, intro text, all overworld modules. (`tests/gfx/scenes_boot.lua` no longer dumps them.)
Music: **silent**. The title music is faded out by `FadeMusicAndResetSRAMMirror`; every EntranceData row carries song `$FF` ("keep", `LoadUnderworldSongBankIfNeeded` returns at once for `$FF`, `bank_02.asm:5375-5378`).
Sound effects still play (not audible in tests; not verified by ear).

## 7. Room loading, advance, restart (`src/hooks/room_ctrl.asm`)

* `Hush_FrameHook` replaces `JSL LoadChrHalfSlot` at $0287BA in `Module07_Underworld` (once per frame, submodule 0 only, `bank_02.asm:1393-1397`); it runs the original JSL first.
* **Entrance k loads room k**: `LoadUnderworldEntrance` (`bank_02.asm:15456`) reads 17 `EntranceData` tables by `$010E`; roomgen rewrites rows 0..N-1 (the tables are in `src/FREESPACE.md`).
  `$010E` is the room index. Link faces down in entrance 0 and up in the others (`bank_02.asm:15714-15722`; not configurable via the tables).
* `Hush_LoadRoom(A = index)` sets `hush_room`, `$010E`, `$010A = 1` (skips the "recache" block), `$04AA = 0` (not a respawn), `$B0 = 0`, `$10 = 5`, `$11 = 0`, grants the tools, and clears `$7EF000 + 2*room` and `$7FDF80 + 2*room`.
  Module 5 (`bank_02.asm:224`) falls straight into module 6 and the room is rebuilt completely (graphics, tilemaps, sprites, Link; **E6: the graphics are skipped while `hush_gfx` is set, the tilemaps / collision cover only the window, the iris is a 6-pass fade, section 14.1**).
  The rest of the current frame is allowed to finish (the return address is *not* discarded); module 5 is dispatched next frame.
* Clearing `$7FDF80 + 2*room` matters: it holds the "sprite killed" bits that `LoadSingleUnderworldSprite` (`bank_09.asm:13640-13660`) honours; without it a killed guard stays dead after a restart.
* **`Hush_RestartRoom`** (JSL, any M/X, preserves P) = `Hush_LoadRoom(hush_room)`. The guard AI calls this when a guard catches Link. [`tests/smoke/room_advance.lua` checks Link back at start and the death flags cleared.]
* Exit: each frame the centre of Link's box is tested against up to 4 pixel rectangles of the ROOM TABLE (`Hush_CheckExit`). Touching one -> room `hush_room + 1`; last room -> (E6) the ending screen
  (section 14.5; `Hush_Ending`, the old soft reset to Module 0 / submodule 0, is now what START on the ending screen runs; the A0 `IntroSkip` fast-forwards to the title, START starts a new game).
* **Timing (E6: superseded by section 14: advance = 23 frames, the text below is the E1 measurement of the unmodified Module05/06 + iris):** (E2: "caught" now uses `Hush_FastRestart`, 6 frames, section 11.6) a room load takes **~160 frames (2.7 s)**: Module 5+6 run as one very long frame (~117 frames, forced blank: graphics decompression, tilemap build), then the fade-in (~41 frames). `Hush_RestartRoom` therefore is *not* instant yet;
  the M5 "instant restart" work should skip `LoadDefaultGraphics`/`DecompressSwordGraphics`/palette reloads when the room did not change. [`tests/dev/room_load_timing.lua`]
* Debug jump: `hush_room_req = N + 1` -> next gameplay frame loads room N (out-of-range values are ignored). Also used for tests (`bot.jump_to_room`).
* Health: `$7EF36D := $7EF36C` every frame. **Risk:** a single hit larger than current health kills before the refill (3 hearts = `$18`; green soldiers deal 2 hearts at most; blue/red soldiers deal more). Death would go to the vanilla game-over module `$12`. (E2: the guard AI never damages Link at all.)

### Tools (per room, cumulative)

`ROOM TABLE +18` = OR of `tools_given` of rooms 0..k. On every load (`Hush_GrantTools`): bit0 shade_knife -> `$7EF359 = 1` (fighter sword);
bit1 hush_darts -> `$7EF340 = 2` (bow with arrows) and `$7EF377 = 8` arrows; bit2 ink_pots -> `$7EF343 = 8` (the bomb **count** itself lives at `$7EF343`, `Zelda_3_SRM.log:177`; capacity is `$7EF370` upgrades, default 10).
Tools not granted are set to 0 (a debug jump backwards removes later tools). No shield. Verified: sword swing runs (`$3C` counts 1..8 on B) and START opens the item menu (module `$0E`) [probe].
`$0202` (selected Y item) is not set: the player picks the item in the menu.
The A0 placeholder item menu shows tile-index text, so the icons were not judged visually.

## 8. RAM

`$7EC900` `hush_room`, `$7EC901` `hush_room_req` (documented in `docs/ram_map.md` with the evidence that vanilla never touches `$7EC9xx`: the only `$7E[C-E]xxxx` operands in
`usdasm` are the HUD/palette buffers `$7EC0xx-$7EC8xx` and the power-on full-WRAM clear in `bank_0C.asm:90-112`). Direct-page scratch used by the controller: `$00-$03`.

## 9. How to add a room

1. Write `design/rooms/<id>.yaml` from `design/rooms/_template.yaml` (fields `seq`, `grid`, guards with `id`/`move`; **quote every grid row**).
2. `make validate` (schema, border walls, one `S`, >= 1 `X`, guard letters, reachability warning), then `make rooms` -> `build/rooms_report.txt` (ASCII + byte sizes) and `build/rooms_gen.asm`.
3. `make build && make test` (`rooms_all_load` loads and screenshots every room; `room_advance` walks the whole chain by teleport; `walk_exit` walks the first guard-free room).
4. Nothing in `src/` changes. Limits: 24 rooms, <= 4 exit rectangles per room (adjacent `X` cells merge), <= 8 guards.
5. `HUSH_ROOMS_DIR=tests/dev/rooms make build` builds the engine dev set; with no real rooms in `design/rooms` roomgen falls back to it and says so.

## 10. Pitfalls and open problems

* ~~A full room load (exit -> next room) is still ~2.7 s~~ fixed in E6 (section 14.1: 23 frames); the restart after "caught" is 6 frames (E2, section 11.6).
* ~~`move: still` and `move: patrol` are the same in E1~~ fixed in E2 (sub-type bit 3).
* ~~No visual exit marker; `p` looks like `#`~~ fixed in E3 (section 12). A0 placeholder HUD hides the top-left ~62 px.
* ~~SELECT in a room opens the vanilla save/continue message~~ disabled in E6 (14.7); START opens the item menu (fine).
* `hush_room_req` also reloads the *current* room (restart); tests rely on it.
* Link starts facing up (down in room 1); the EntranceData tables cannot change that.
* `make test` now ends with the leak check; `tests/gfx/*.lua` were adapted to the new flow (no file select / name entry / house scenes; guard scenes use the HUSH rooms; death scenes cannot trigger any more because health is refilled).

## 11. E2: the stealth AI, damage rules, caught -> restart, ink, icons

Files: `src/hooks/guard_ai.asm` (hook + AI), `guard_vision.asm` (geometry, vision, line of sight), `guard_hooks.asm` (arrows, bombs),
`guard_runtime.asm` (per-frame tick, fast restart, palettes). RAM: `docs/ram_map.md` ("HUSH stealth AI variables", including the test API `spr_aware`).
Every vanilla address below was read in `vendor/usdasm` (file:line cited) and every hook byte checked against `rom/vanilla.sfc` before patching.

### 11.1 How the AI plugs in

* `Sprite_41/42/43` all start at **`$05C155`** (`LDA.w $0DB0,X : BNE Probe : JMP.w Guard_Main`, `bank_05.asm:11942-11946`; the three jump-table entries are one routine, run as a
  PHA/RTS dispatch from `SpriteModule_Active_bank05.main` `$05B5D3`, DB = `$05`, M = X = 8). The 8 bytes became `JML Hush_GuardEntry` + 4 NOPs. `Hush_GuardEntry` repeats the
  `$0DB0 != 0` test (probe sprites: `JML $05C15D`, the vanilla `Probe` code, untouched and unreachable in HUSH) and otherwise runs `Hush_GuardAI` with DB = `$0E`, then `JML $05C226`
  (the `RTS` at `EXIT_05C226`, `bank_05.asm:12112`) so the bank-05 caller continues as after `Guard_Main`.
* **Nothing of `Guard_Main` runs any more**: no `Guard_SendOutProbe`/`FireProbe` (probe sprites `$41` with `$0DB0 = parent + 1` are never spawned), no `CheckDamageToLink`
  (`bank_06.asm:22161`), no `ParrySwordAttacks` (the vanilla sword-vs-soldier code, `bank_06.asm:20887`), no `CheckSwordDamageToSprite`. Link is never hurt, knocked back or
  "tinked" by a guard: contact is our own box test.
* Why not hooks on `AlertSprites` ($088AB9) / `WeaponTink` ($088F8E), the `$0FDC = 3` "noise" setters? Their **only readers** are vanilla guard code
  (`bank_05.asm:12160` = `Guard_Main`, `:13924`, `bank_06.asm:804-807` the decrement). Our AI never reads `$0FDC`, so every thump, arrow and tink is silent without patching a byte.
* Code placement: free blocks (`src/FREESPACE.md`): `$0EEE22-$0EF3FF` AI (uses ~0.7 KB), `$0EFB64-$0EFFFF` vision + hooks (~0.7 KB), `$07FB00-$07FFFF` runtime (~0.3 KB).
  **Pitfall: `$0EEE21` must stay `$FF`.** It is the end marker of the dialogue text (`bank_0E.asm:11950` "see text.asm"): when the first byte of `NULL_0EEE21` held code, the intro hung
  in submodule 1 (the text loader scanned on). The block starts at `$0EEE22`.

### 11.2 States and variables (all per sprite slot)

| Variable | Meaning |
|---|---|
| `$0D80` `spr_aware` | **0 UNAWARE, 1 SUSPICIOUS, 2 ALERT, 3 ASLEEP.** Vanilla `Guard_Main` used it as its AI state; the array is ours now |
| `$0DE0` | facing, vanilla encoding: 0 right, 1 left, 2 down, 3 up. The walk counter `$0E80` (+1 per frame moved) selects the walk phase. E4: the vanilla head direction `$0EB0` and body frame `$0DC0` are no longer written or read (the draw in `guard_draw.asm` picks tiles from `$0DE0`, `$0E80` and the velocity) |
| `$0DF0` | suspicious: 60-frame investigation timer; asleep: 240-frame chunk |
| `$0E10` | "lost sight" timer: suspicious 120, alert 180 (reset to that value every time he sees Link) |
| `$0D90` | state 0: 1 = pausing at a wall; state 3: remaining 240-frame chunks (the dart sets 1: 240 + 1 + 240 = ~480 frames, measured 479) |
| `$0E00` | state 0: 60-frame wall pause |
| `$0EE0` | ink "stand still" timer (60) |
| `$0E30` | sub-type from the sprite list: bits 0-2 facing code (vanilla `SpritePrep_StandardGuard`, `AND #7`), **bit 3 = `move: still`** (`tools/roomgen.py` `STILL_SUBTYPE`, encoded in the `ss` bits of the sprite-list byte 0) |
| `$0DB0` | must stay 0 (non-zero = a vanilla probe) |

Transitions (`Hush_GuardAI`):

* **UNAWARE**: sword hit -> dies. Touching Link -> ALERT. Otherwise looks (`Hush_Vision`, mode 0: cone + range + line of sight): sees Link -> SUSPICIOUS (`$0DF0` 60, `$0E10` 120,
  stops, faces him). Not noticing: patrol (`move: patrol`) or stand (`move: still`).
* **SUSPICIOUS**: immune to the sword. Touching Link -> ALERT. Senses in all directions (mode 1: range + line of sight, no cone: the guard turns to the larger axis towards Link). While he senses Link,
  `$0E10` := 120 and when `$0DF0` has run out -> ALERT (`$0E10` := 180). `$0E10` reaching 0 -> UNAWARE.
* **ALERT**: immune to the sword. Touching Link -> **CAUGHT** (`hush_caught := 1`). Chases (see 11.4). Sees Link (mode 1) -> `$0E10` := 180; `$0E10` = 0 -> UNAWARE (he stays where he is).
* **ASLEEP**: ignores everything, dies to the sword, is a **solid obstacle** (`Hush_Solid`: Link is pushed out of the 16 x 16 overlap, smaller axis first; **E7: Link is put back to his position of the last frame instead, section 15.7**), wakes into UNAWARE after ~480 frames.
* Touching an UNAWARE or SUSPICIOUS guard makes him ALERT; since Link still overlaps him on the next frame, that frame is a catch. So *any* contact with an awake guard ends the room within two frames
  (tests: `ai_caught`). Contact box: guard 16 x 16 at its origin vs Link's collision box `(x, y+8)..(x+15, y+23)` = `|dx| < 16 and |dy| < 16` between the centres.

### 11.3 Vision (`Hush_Geom`, `Hush_Vision`)

* Coordinates: guard centre = origin + (8, 8), Link centre = (x + 8, y + 16) (section 1). `Hush_Geom` leaves `dx = Lx - Gx` (`$00`), `dy = Ly + 8 - Gy` (`$02`), `|dx|` `$04`, `|dy|` `$06`, guard centre `$08/$0A`.
* **Range** = `max(|dx|, |dy|) <= hush_range`: **80 px (5 cells) dark, 128 px (8 cells) lit** (`Hush_Tick` writes it from ROOM TABLE +19 bit 0). Square, not round: the cone makes the forward component the maximum.
* **Cone (mode 0)**: the forward axis must be the larger one (`|dx| >= |dy|` for left/right, `|dy| >= |dx|` for up/down: a 90-degree cone, edges inclusive) and Link must be on the correct side. Behind the guard = blind.
  Same layer as Link (`$0F20,X = $EE`).
* **Line of sight**: the straight segment guard centre -> Link centre is walked in 8-px steps along its major axis (minor axis by an 8.8 fixed-point rate from the hardware divider `$4204-$4206`, 16 cycles wait);
  at every sample the `$7F2000` collision map (`((y & $1FF) >> 3) * 64 + ((x & $1FF) >> 3)`, section 3) must read `$00`. Any non-zero tile blocks. The same loop tests the **ink cloud** box
  (`|px - cx| <= 24 and |py - cy| <= 24`, 3 x 3 cells like the vanilla bomb's 48 x 48 damage box). Mode 2 = cloud only (no range / cone / tiles): "does the line to Link, or the guard himself, touch the cloud?" **Mode 3 (E7) = tiles only (no range / cone / cloud): the knife's line of sight.**
* Staggering (frame budget, 11.8): unaware guards look every 2nd frame, suspicious / alert every 4th, offset by slot, so a notice takes up to 2 frames.

### 11.4 Movement

* `Hush_Step` = one frame of movement in one direction + the **vanilla tile collision** (`CheckSpriteTileCollision_long` `$06E496`, the soldier's tile box: it stops **14 px before a wall tile**, i.e. the 16-px sprite overlaps the wall by 2 px; measured with `ai_patrol`).
  Own `MoveAxis` (the `MoveSpriteY_bank05` body, `bank_05.asm:22234-22261`, the X arrays are the same arrays at X + $10). **When blocked the position and sub-pixels from before the move are restored**:
  the vanilla pushback alone let an alert guard creep through a pillar at 1 px / 8 frames (found by `ai_deescalate`; he reached Link behind the pillar).
* Speeds (1/16 px per frame): patrol **12 = 0.75 px/frame** (vanilla indoor patrol is 0.5), alert **18 = 1.125 px/frame = 1.5 x patrol** (vanilla `AppliedSpeed18`); Link walks about 1 px/frame, so a chase is not outrun for free.
* **Patrol**: walks along its facing axis; blocked -> stops 60 frames (`$0E00`) -> turns 180 degrees (`$0DE0 xor 1`) -> walks back. `still` never moves and keeps facing. Measured: 45 px in 60 frames, pause 59 frames (`ai_patrol`).
* **Chase** (`Hush_Chase`): step along the larger axis towards Link; if blocked and the other axis offset is >= 3 px, step along that axis (wall slide). A guard directly behind a pillar line stays stuck (he loses Link after 180 frames).
  Facing follows the movement. **E7 (B-005): every chase step also passes `Hush_BoxProbe` (section 15.2)**, so he no longer slides into a doorway corner.

### 11.5 Damage and noise

* **Sword** (Shade Knife): `Hush_SwordCheck` builds Link's sword box with the vanilla routines (`SetupActionHitbox_long` `$06F57E`, `SetupSpriteHitbox_long` `$0683EA`, `CheckIfHitboxesOverlap_long` `$0683E6`) only while Link
  swings or dashes (`$3C`/`$0372` non-zero). Unaware / asleep guard overlapped -> `SpawnPoofGarnish` ($05AB9C) + `$0DD0 := 0` (gone until the room restarts: a restart reloads the sprite list and clears `$7FDF80 + 2*room`).
  Suspicious / alert: no code runs at all: no damage, no flash, no tink. Reach measured with `tests/dev/sword_reach.lua`: Link 16-32 px from the guard (centre to centre dx) kills; 36 and more misses; < 16 is a contact.
  **E7 (B-003): the overlap only counts with a clear tile line of sight guard centre -> Link centre (`Hush_Vision` mode 3, section 15.1); a wall in between is a miss.**
* **Arrows** (Hush Darts): hook `$06ECB7` (`CheckAncillaDamageToSprite`, `JML Hush_AncillaHit`). Entered by JSL from `Ancilla_CheckSpriteCollision_Single` (`bank_08.asm:3078`) with A = ancilla type ($09 arrow) and X = sprite. For a guard:
  arrow + state 0 -> ASLEEP (240 + 240); anything else does nothing. The vanilla caller treats it as a hit, so the arrow stops (it becomes ancilla $0A, the stuck arrow, for a moment). Other sprite types run the vanilla code.
  `$7EF340 = 2` (bow with arrows) is enough; verified `ai_darts`. Item selection pitfall for tests: **`$0202` is the HUD slot, the item that is used is `$0303` = `MenuToEquipID[$0202]`** (`bank_0D.asm:17015`: bow 3, bombs 1); `UpdateEquippedItem` copies it
  only when the HUD rebuilds, so a test that pokes `$0202` must poke `$0303` too.
* **Bombs = ink pots**: hook `$089815` (`Bomb_CheckSpriteAndPlayerDamage`, `JML Hush_BombHook`). The vanilla damage code (sprites, Link, recoil) is never reached. Phase `$0C5E = 1`: cloud centre := bomb position (`$0C18:$0C04`, `$0C0E:$0BFA`;
  the bomb is placed ~14 px in front of Link), `hush_ink_t := 300`. Phase 8 (largest explosion frame, 6 OAM objects) is **held** (`$039F` kept at 2) while `hush_ink_t > 0`, so the vanilla explosion graphic is the visible cloud; then phases 9, 10 and the ancilla ends
  (measured: 157 frames from placing to the explosion, cloud 300 frames, ancilla gone ~345 frames after placing). Link is neither hurt nor pushed (tested with the bomb at his feet and a guard inside the blast box).
  A second bomb restarts the single global cloud. Colour: sprite palette row 1 (the explosion's `$22/$62` attribute bytes, `bank_08.asm:6040-6090`) is overwritten with dark indigo smoke colours at room load (`Hush_PalInk`).
* **Ink effect on guards**: suspicious / alert guards whose line to Link crosses the cloud, or who stand in it, become UNAWARE at once and stand still 60 frames (`$0EE0`); unaware guards do not see Link through it.

### 11.5b Not done / deviations from the task text

* `AlertSprites` / `WeaponTink` immediates were **not** patched (nothing reads `$0FDC` any more, 11.1).
* The icons are **not** in `GFX_BC`: in E2 every one of its 64 tiles was used by the vanilla soldier frames (head 16x16 at `$40/$42/$44`, body, weapon; checked against `GuardBodyObjectChar` etc.). E4 rebuilt that sheet (11.12) and left half of it free, but the icons stay in `GFX_C5` (tiles `$FC-$FE`). See 11.7.

### 11.6 Caught -> fast restart (`guard_runtime.asm`)

* Contact with an ALERT guard sets `hush_caught` (`$7EC902`). `Hush_Tick` (JSL from `Hush_FrameHook`, i.e. at the start of the next gameplay frame, before the sprites run) calls **`Hush_FastRestart`**:
  clear `$7EF000 + 2*room` and `$7FDF80 + 2*room`; `Underworld_ResetSprites` (`$09C114`, `bank_09.asm:13187`: deletes every sprite, ancilla, garnish and overlord and loads the room's sprite list again); `ResetLinkProperties_A` (`$07F1A3`);
  Link := EntranceData position of the room (`$02CF59` y / `$02D063` x rows written by roomgen) and facing; `Hush_GrantTools`; 6 black frames (`$13 := 0`, `hush_flash` counts down in `Hush_Tick`, then `$13 := $0F`).
  **Nothing is rebuilt**: tilemaps, graphics and palettes stay (the whole point: the vanilla Module05/06 load is ~117 frames of decompression and tilemap building, section 7).
* **Measured** (`tests/smoke/ai_caught.lua`, log line `RESTART:`): the guard's contact frame sets the flag; the restart runs on the next frame; **the screen is back at full brightness 6 frames after the contact frame**
  (6 black frames; Link, guards and tools are already reset on the first of them). Target was <= 20 frames with a 6-frame flash. Physical play (`ai_stealth`): noticed -> chased -> caught -> restart.
* Link is controllable (and can move) during the black frames; guards restart unaware and Link is at the start, so nothing can happen in 6 frames.
* **(E6: the full load of the next room is now 23 frames, section 14.1; only a new game still takes the old path.)** ~~Full load (exit to the next room, debug jump, new game) is unchanged: ~160 frames.~~ Ideas for a faster advance (not done): reuse the loaded graphics for a room with the same sprite/blockset (all HUSH rooms do) and call only the room-draw part of Module06;
  draw only the quadrant that is visible (`LoadAndDrawRoom` builds all four); skip the fade-in iris.

### 11.7 Icons and palettes

* Icons: entry 3 (byte offset `$0C`) of the guard's 5-entry OAM allocation (E4, 11.12; in E2 it was entry 7 of 9 written before the vanilla draw), 8 x 8 sprite, attribute `$29` (priority 2, palette 4, name table 1),
  written by `Hush_DrawGuard` (`guard_draw.asm`): tile `$FB` + awareness state ('?' `$FC`, '!' `$FD`, 'Z' `$FE`; `$FF` spare), offset (+4, -22); hidden (Y = `$F0`) while UNAWARE.
  **Tile region**: the loaded sheets of sprite set `$44` are `GFX_B9, GFX_BC, GFX_86, GFX_C5` (`SheetsTable_AA3` `$44` = `46 49 13 52` + `$73`, `bank_00.asm:11079`) in sprite tile slots `$00/$40/$80/$C0` of name table 1 (`attr bit 0`).
  `GFX_BC` (slot 1, the guard) had no free tile in E2 (it has since E4, but the icons stayed). `GFX_C5` (slot 3, 23 of the 80 underworld sprite sets, unused by anything HUSH draws) has: its tiles 60-63 (row 3, x 96..127 of `gfx/src/sprite/GFX_C5.png`) are the icons.
  Painted placeholder glyphs (`?` amber, `!` amber, `Z` near white, spare empty); `tools/gfx_convert.py check` and the leak check are clean. `GFX_C5.yaml` has an `engine_icons` note. **`make gfx` would overwrite the glyphs** (it regenerates the labelled placeholder).
  The director's `NEW_awareness_icons.png` only needs to land on those tiles (or the `$FB` / attribute / offset constants in `Hush_DrawGuard` change).
* Alert = amber: `$0F50` palette bits (`GetScreenCoordinates` ORs `$0F50` with `$0B89` into `$05`, `bank_06.asm:19362-19367`) := row 6 while ALERT, row 4 (`SpriteData_OAMProp & $0F`) otherwise.
  Rows 1-6 of the A0 placeholder palettes are identical (`gfx/src/palettes/sprites.yaml`), so `Hush_SetPalettes` writes **row 6 = amber guard colours** and **row 1 = ink smoke** into the live palette buffer `$7EC500` + `$100 + row*32`
  and the cached one `$7EC300 + ...`, once per room load (`hush_pal`), and sets `$15` (the NMI then uploads `$7EC500`, `bank_00.asm:1972-1990`). The real art should put these rows into `gfx/src/palettes/sprites.yaml` and drop `Hush_SetPalettes`.

### 11.8 CPU budget

`tests/dev/cpu_load.lua` reads the PPU scanline when the game loop ends (`$00805D`, `STZ $12`, `bank_00.asm:78`; NMI = line 225; later = the frame is lost = 30 fps):
**E2 numbers (vanilla soldier draw):** empty room line 114, 1 guard 129, 4 guards 178, **6 guards 211**, 7 guards overrun (every other frame lost; `$1A` advances 100 times in 200 frames). A chasing guard cost ~21 lines, an idle one ~16, **about 14 of them vanilla**
(`Guard_HandleAllAnimation`, sprite handling, shadow). **E4 (custom draw, section 11.12): ~8 lines per idle guard, 6 guards line 163, 8 guards line 179 - the 6-guard limit is gone** (8 idle or asleep guards fit; 6 chasing guards end at line 196-221).
The AI's own tricks: staggered looks (11.3), sword box only while swinging,
`$0BE0` bit 7 (skips the pit/water/conveyor tile checks in `CheckSpriteTileCollision`, `bank_06.asm:19549`), geometry computed once per frame.

### 11.9 Test infrastructure

* **Dev ROM**: `make build-dev` -> `build/hush_dev.sfc` = the same code and graphics with the rooms of `tests/dev/rooms` (`tools/build.py build --dev`: roomgen to `build/dev/`, `asar -DHUSH_ROOMS_GEN=...`, `src/main.asm` does `incsrc "!HUSH_ROOMS_GEN"`;
  `tools/check_freespace.py --rom --rom-file` checks its bytes against the ledger as well). `make test` builds both. A test script with the header tag **`-- @rom dev`** runs on it (`tools/run_test.py`, which also exports
  `HUSH_ROOMS_LUA` so `bot.rooms()` returns that ROM's rooms). Untagged tests run on `build/hush.sfc` (design rooms, or the dev rooms while `design/rooms` is empty).
* Dev rooms (`tests/dev/rooms`, play order = `seq`): `dev1-dev3` (E1), `ai4_dark` (still guard facing east, dark), `ai5_lit` (same, lit), `ai6_cover` (pillar column), `ai7_patrol` (patrol + still guard), `ai8_crowd` (8 guards).
* Helper `tests/lib/ai.lua` (`ai.enter(id)`, `ai.state`, `ai.link_to(slot, dx, dy)` = Link's centre `(dx, dy)` from the guard's centre, `ai.restart()` = poke `hush_caught`, which exercises the real fast restart between sub-tests).
* Tests (`tests/smoke/`): `ai_vision` (cone, edges, range dark/lit, behind, timing), `ai_los` (pillar), `ai_sword`, `ai_darts` (sleep 479 frames, solid sleeper, no effect on others), `ai_ink` (cloud blocks, calms, real bomb: no damage, 300 frames),
  `ai_caught` (contact, restart <= 20 frames and what is reset), `ai_deescalate` (120 / 180 frame timers), `ai_patrol` (speed, wall pause, turn, still, calm -> patrol again), `ai_stealth` (real button presses).
  Dev utilities: `tests/dev/cpu_load.lua`, `sword_reach.lua`, `ai_probe.lua`, `probe_gfx.lua`.
* Pitfalls while testing: `hush.screenshot` shows the frame **before** the last one (wait 4-8 frames after changing something before judging a screenshot); sprite coordinates of Link vs guard (11.3); a Link placed
  inside a wall column (guard at the room edge) is "behind" the wall for line of sight - keep test positions on floor cells.

### 11.10 Facts learned

* Collision map and sprite coordinates share the absolute pixel space; room-local = `& $1FF`. Hardware divider usable from bank `$0E` code (I/O at `$4204` is mapped in every bank `$00-$3F`).
* `GetScreenCoordinates_bank05` pops its caller's return address when the sprite is off screen (`bank_05.asm:22308-22316`) - the vanilla draw wrapper `Guard_HandleAllAnimation_long` `$05C676` was safe to call (E2). E4 replaced the draw; `GetScreenCoordinates_long` `$06E416` returns C = 1 instead of popping.
* Sprite palette bits come from `$0F50` (not `$0E60`); the hit flash `$0B89` is XORed on top.
* `$0DB0` of the soldier sprites is the probe parent index: never use it for AI state.
* Frame lag detection in tests: `$1A` is incremented once per main-loop pass (`bank_00.asm:70`); a pass that overruns NMI loses the next frame (`STZ $12`).

### 11.11 Open problems / not done

* ~~Room advance (exit -> next room) is still a ~160-frame full load~~ fixed in E6 (14.1: 23 frames).
* A guard cannot be "pushed" or distracted; no noise mechanic (by design: arrows and tinks are silent).
* Guards do not walk back to their post after an alert (spec: they stay where they are); `move: still` guards may end up facing a wall.
* ~~No sound effects for notice / alert / kill~~ E6 (14.2): notice, alert, knife kill, dart sleep, caught, clear. Still none: a tink (and spark) when the knife hits an alert guard (the hit is silently ignored).
* Real ink-cloud art: the vanilla explosion tiles in palette row 1 are the placeholder; `Hush_PalAlert/Ink` belong in `gfx/src/palettes/sprites.yaml` once the art is real.
* ~~More than 6 guards per room lag~~ fixed by E4 (11.8, 11.12): 8 guards fit. More than ~8 awake guards would need a cheaper `Hush_Vision` (16-px steps).
* Only sprite type `$41` is spawned by roomgen; `$42/$43` would run the same AI (palette bits come from their own OAMProp).
* The designer's rooms were not available while this was written (`design/rooms` held only the template); the main ROM is built from the dev rooms until they land. Everything is room-data independent except the ROOM TABLE flag bit 0 (lit).

### 11.12 E4: the custom guard drawing (head + body + lantern = 4 OAM entries per guard)

Files: `src/hooks/guard_draw.asm` (new, `Hush_DrawGuard`, bank `$07` `$07FD00-$07FEC7`), `src/hooks/guard_ai.asm` (the call, the `SpriteData_OAMHarm` hook, the removed vanilla draw), `gfx/src/sprite/GFX_BC.png/.yaml` (placeholder blocks),
sheet contract for the painter: `docs/gfx/art_map.md` section 5; test `tests/smoke/guard_draw.lua`; profilers `tests/dev/guard_cost.lua`, `tests/dev/oam_probe.lua`.

* **What was replaced.** `Hush_GuardAI` used to `JSL $05C676` (`Guard_HandleAllAnimation_long`): head (1 OAM entry, 16x16), body (2-4 entries from 7 different 16x16 / 8x16 pieces, many H/V flips), weapon (2-4 entries) + shadow = 9 allocated entries, 8 visible,
  drawn from 60 of the 64 cells of `GFX_BC`. Now `JSL Hush_DrawGuard`.
* **OAM allocation.** `DoSpriteOAMandTimers` (`bank_06.asm:909`) allocates `((n & $1F) + 1) * 4` bytes with `n = $0E40,X`, which `LoadSpriteProperties` (`bank_0D.asm:7835`) copies from `SpriteData_OAMHarm[type]`. `$0DB0C1-C3` (types `$41-$43`) went from `$08` to `$04`:
  5 entries. Verified a pure per-type table: its only reader is `LoadSpriteProperties` (grep over `vendor/usdasm`); `$0E40` of a guard is only read by `DoSpriteOAMandTimers` and the shadow routine (which draws into entry `$0E40 & $1F`, i.e. the last = entry 4). Ledger: hook row `$0DB0C1-$0DB0C3`.
* **Entries** (lower = in front): 0 head 16x16 at `(X, Y-8)`, 1 lantern 8x8, 2 body 16x16 at `(X, Y)`, 3 awareness icon 8x8 (hidden while UNAWARE), 4 shadow (the vanilla tile `$6C`, written inline with the same values `DrawSpriteShadow_custom` produces).
  Unaware guard = 4 visible entries, aware / asleep = 5. Same OAM priority bits (from `$0B89`: layer), same palette rows as before (OBJ row 4 calm and asleep, row 6 ALERT; `$0F50` is still written), same icons.
* **Tiles** (`tile = $40 + cell index`, final table; `f` = facing / pose class, side views are drawn facing LEFT, right = H flip of head and body):

| part | right | left | down | up | asleep |
|---|---|---|---|---|---|
| head | `$44` H | `$44` | `$40` | `$42` | `$46` |
| body phase 0 / 2 (standing) | `$60` H | `$60` | `$48` | `$4C` | `$66` |
| body phase 1 (step) | `$62` H | `$62` | `$4A` | `$4E` | - |
| body phase 3 (step 2) | `$64` H | `$64` | `$4A` H | `$4E` H | - |
| lantern frame 0 / 1 | `$68` / `$69` at (+13, +6) | at (-5, +6) | at (+10, +6) | at (-3, +6) | `$69` at (+10, +10), no flicker |

  Icon `$FC/$FD/$FE` (GFX_C5) at (+4, -22), shadow `$6C` (GFX_7D, name table 0) at (0, +10 down/up, +12 side). Walk phase = `($0E80 >> 3) & 3` while the guard moved on the previous frame (velocity `$0D40 | $0D50` non-zero; `Hush_Patrol` / `Hush_Chase` count `$0E80` only on frames
  they moved and clear the velocity otherwise), else 0. Lantern flicker: `((slot*4 + $1A) * 43 >> 9) & 1` via the hardware multiplier = a flip every 11.9 frames, phase staggered by slot.
* **Culling.** `GetScreenCoordinates` is replaced by two 16-bit subtractions (guard position - `$E2/$E8`; guards never fly, `$0F70` = 0). The routine is exact for a guard origin inside screen x `[8, 231]`, y `[24, 199]`: then every part is fully on screen and x bit 8 is always 0, so none needs
  clipping. Real guards always are inside (rows 0-1 and 13, columns 0 and 15 are walls and a guard stops 14 px before a wall tile: origin x 14..226, y 30..194; test: 4 rooms x 420 frames of natural play, 0 culled draws). Outside the window the vanilla `GetScreenCoordinates_long` runs (it flags or kills a sprite far off screen as before)
  and all 5 entries are hidden (Y = `$F0`). Tested at every window edge (`guard_draw`, section 5 of the script).
* **No flicker, same priorities.** The entries live in the guard's own contiguous allocation, so OAM order between guards is unchanged (slot order); the shadow stays the last entry (behind), the head the first (in front). Unwritten entries do not need clearing (`ClearOAMBuffer` runs in every main-loop pass, `bank_00.asm:72` / `:835`); the routine writes Y = `$F0` for the hidden ones anyway.
* **Cost** (CPU cycles per guard per frame, `tests/dev/guard_cost.lua`, 6 guards in `ai8_crowd`; 1 scanline ~ 155 of these cycles):

| | vanilla draw (E2) | E4 |
|---|---|---|
| draw (`Hush_DrawGuard` / `Guard_HandleAllAnimation_long`) | 1745 | **500** (asleep 495) |
| whole AI call (`Hush_GuardEntry` .. RTS) | 2307 (asleep 2333) | **957** (asleep 788) |

  Frame budget (`tests/dev/cpu_load.lua`, scanline where the logic ends, NMI at 225; `ai8_crowd`):

| guards | idle (E2 -> E4) | asleep (E2 -> E4) | chasing, all alert (E2 -> E4) |
|---|---|---|---|
| 0 | 114 -> 114 | | |
| 1 | 129 -> 121 | 130 -> 121 | lines 135 (median) -> 126 |
| 4 | 178 -> 146 | | **overrun** (median 208, 99 frames in 120) -> 177 (max 204), 120 frames |
| 6 | **211** -> **163** | **212** -> **157** | **overrun** (median 79 = lost frames) -> 196 (max 221), 120 frames |
| 8 | **overrun** (60 frames in 120) -> **179** | **overrun** -> **171** | overrun -> overrun (60 frames; 8 simultaneous chasers) |

* **B-001 (lag with 5-6 guards, sleepers)** is fixed: the real replays `r20` (5 guards, lit, sleepers) and `final` (6 guards, lit, sleepers) went from 130 / 463 lagged frames to **0 / 0** (`tests/solutions`), with 6 sleeping guards at line 157 instead of 212.
  Because those two replays had been recorded *under lag* (taps were lengthened), they desynchronised once the lag was gone; `r20.inputs` and `final.inputs` were re-recorded with `tools/solve_rooms.py solve r20 final` (fresh traces; 815 and 1069 frames instead of 946 and 1536). The other 19 replays are byte-identical and take the same number of frames.
* **Not touched:** AI timing, movement, collision, the vision stagger (the AI code only lost its `$0EB0` head-direction stores). `make gfx` is unaware of the new `GFX_BC` layout (the labelled placeholder blocks are hand-made, like the `GFX_C5` icons).


## 12. E3: visual variety of the room tiles (exit marker, pillar, wall face, palette sets)

Goal: every element of a room gets its own art slot so the director can paint it, with **zero change to collision**. Art coordinates, rows and priorities: `docs/gfx/art_map.md` sections 1, 3.1, 3.3 (the single source for the painter). Files: `src/hooks/room_visuals.asm`,
`tools/roomgen.py` (`cell_kinds`, `OBJ_KINDS`, `cover_runs`), `gfx/src/palettes/bg_dungeon.yaml` (groups 00-05), test `tests/smoke/visual_tiles.lua`. No code runs at room load: it is all data.

### 12.1 How (and why not a tilemap hook)

* **Collision lives in the tile ids, not in the object.** `LoadBasicObjectAttributess` (`bank_01.asm:10661`) turns every tile word of the BG2 tilemap buffer **`$7E2000`** (the layer list-1 objects draw to; `$7E4000` = BG1 holds the floor only, measured)
  into a collision byte with `UnderworldTileTypes[id]` (`bank_0E.asm:274`, copied to `$7EFE00`; ids `$140+` come from the blockset tables). So any tile whose vanilla type is `$01` is solid and any with `$00` is floor, whatever object drew it.
  The ids chosen (`$024 $025 $02C $02D $03C $03D` solid, `$0C0 $0C1 $0D0 $0D1` floor) were looked up in the ROM table; no tile-type byte is patched.
* **Objects instead of a post-draw hook.** The vanilla 2x2 objects `$07` (`obj0388`), `$B8`/`$92` (`obj1F52`) and `$B9`/`$93` (`obj1F5A`) are never used by HUSH, so their tile data (`RoomDrawObjectData`, `bank_00.asm:4864`, `:6952`, `:6957`) is rewritten in place
  (hook rows `$009EDA`, `$00BAA4`). Rightwards and downwards variants of a pair share their data, so the pillar and exit marker run in both directions; the wall face (only ever one row) uses the rightwards `$07` only.
  The stream stays plain vanilla object data: `object_bytes` encodes size `n` for the `1to15or32` routines and `n-1` for `$07` (`RoomDraw_Rightwards2x2_1to16`, `bank_01.asm:9043`).
  Tilemap upload to VRAM is the normal room build (module 6), nothing to patch. Streams grew from 2754 to 3084 bytes for the 21 rooms (budget 12 288).
* **Cell kinds** (`cell_kinds`): `#` with floor (anything not `#`/`p`) in the cell below -> `face`; other `#` -> `ceil`; `p` -> `pillar`; `X` -> `exit`. The cell below is out of the grid in the last row -> `ceil`. Run decomposition: `cover_runs` per kind (min of horizontal / vertical runs, faces horizontal only).
* **Priorities:** wall top/face 1 (as before), pillar 0 and exit 0.

### 12.2 Palette sets

Header byte 1 (`b1`) = `UnderworldPaletteSets` row (`bank_0E.asm:10412`, 4 bytes per row, `LoadRoomHeader` `bank_01.asm:10120-10130`: byte 0 -> `$0AB6` = BG palette id, bytes 1-3 -> `$0AAC-$0AAE` sprite palettes).
`PaletteLoad_UnderworldSet` (`bank_1B.asm:6409`) indexes `PaletteIDtoOffset_UW` with the byte as a word index, so id `2n` = `pal_dungeon_0n`. Rows 1-5 were rewritten to `(2n, 00, 03, 01)`; row 0 is vanilla `(00, 00, 03, 01)`. Sprite bytes identical in all six rows -> **OBJ palettes are the same
in every variant** (test: CGRAM `$100-$1FF` equal in all 21 rooms). Mapping: dark floor 1/2/3 = rows 0/1/2, lit floor 1/2/3 = rows 3/4/5 (`DARK_PAL_ROWS`/`LIT_PAL_ROWS` in `tools/roomgen.py`); `floor` outside 1-3 is a roomgen error. `rooms_gen.lua` exports `floor` and `pal_set` per room.
The yaml groups 01-05 are tinted copies of `pal_dungeon_00` (the director tunes them); `colours[0]` of every group stays identical because `PaletteLoad_UnderworldSet` also copies its first 7 colours to OBJ row 0 colours 9-15.

### 12.3 Test

`tests/smoke/visual_tiles.lua` (real ROM, all 21 rooms): for every cell of the 16x14 window the 4 tile words in `$7E2000` **and** in the VRAM BG2 tilemap equal the words predicted from the grid; `$7F2000` equals the grid (`#`/`p` = `$01` on all four 8x8 tiles, everything else `$00`);
the BG palette is the same within a palette set and different between sets; the OBJ half of CGRAM is identical in every room; each kind occurs at least once (only 2 `p` cells exist in the current rooms: r05 and r14).


## 13. E5: decoration variants (floor cracks/moss/runes, wall-top slabs, banners, torches, light pools) with zero collision change

Goal: the rooms were one brick block, one speckle tile and one face strip. E5 adds ~28 decoration "cells" that are drawn over the plain ones. Art, tile ids and palette rows: `docs/gfx/art_map.md` section 3.5. Everything is data + one 19-byte object routine.

### 13.1 How a variant gets on the screen

* **One cell (2x2 tiles) per object, drawn by a hijacked vanilla object routine.** The vanilla 2x2 objects are too few (`$00 $07 $08 $53 $60 $92 $93 $B8 $B9`) and each has fixed tile data, so E5 repurposes the unused *diagonal* objects `$09` and `$0A`:
  `DrawObjects.type1_routine[$09/$0A]` (`$018212/$018214`) -> `Hush_DrawVariant` (`$01B53C`, `src/hooks/room_visuals.asm`). The routine takes the object's **size field as the variant index**: `RoomDraw_RoomObject` (`bank_01.asm:1339-1351`) leaves `b0 & 3` in `$B2` and `b1 & 3` in `$B4` and jumps through `$000E`;
  the routine computes `X += 8 * (($B2 << 2) | $B4)` and tail-calls `RoomDraw_Rightwards2x2` (`$019895`), which stores TL, BL, TR, BR from `RoomDrawObjectData + X` into the BG2 buffer at the object's position. Id `$09` reads from obj0420 (`$009F72`), id `$0A` from obj0420 + 128 (type1_data_offset[$0A] rewritten to `$04A0`): 2 x 16 = 32 variants, 28 used.
* The table (8 bytes per variant) is emitted by `tools/roomgen.py` (`VARIANTS`) into `build/rooms_gen.asm` (`org $009F72`), the same list also goes to `build/rooms_gen.lua` (`variant_words`, `variant_kind`, per room `variants = {{cx, cy, name}, ...}`) so the tests predict the tile words from the same source.
* **Order.** roomgen emits the plain objects first (unchanged), then one 3-byte variant object per decorated cell; later objects overwrite the cell. Streams grew from 3084 to 9408 B of the 12 288 B budget (24 rooms of this density would need ~10.8 KB: still fits, but this is the limit: if more rooms or decorations are added, make the plain-run decoration merge runs or drop wall-top variants first) (roomgen fails if exceeded). No object count limit exists (the stream is read until `FF FF`).
* **Collision unchanged.** As in section 12 the collision byte comes from the final tile ids (`UnderworldTileTypes`). Every variant uses ids of the vanilla type of the cell it replaces (checked against `bank_0E.asm:274`):
  floor variants `$C4-$DD`, `$E9 $EA $F9 $FA`, `$EE $EF $FE $FF`, `$2E $2F $3E $3F` = type `$00`; wall variants `$00 $01 $02` (T1-T3), `$15`, `$80-$8D`, `$90-$95`, `$A0 $A1 $B0 $B1` = type `$01`. Flip bits never change the type.
  Free-id lists (so the next painter does not have to rediscover them): solid `$01` in the loaded slots: GFX_00 `$00 $01 $02 $05 $08 $09 $26 $36`; GFX_01 `$44 $46 $47 $49 $4A $4C $4F $54 $56 $57 $5D $60 $61 $72 $73 $74`; GFX_10 `$80-$8D $90-$99 $9D-$9F $A0 $A1 $A8 $B0-$BD`.
  Floor `$00`: GFX_06 `$C0-$CD $D0 $D1 $D4-$DD $E7-$EA $EC-$EF $F8-$FA $FC-$FF`; GFX_00 `$03 $07 $13 $14 $16 $17 $19 $1A $2E $2F $3E $3F`; GFX_01 `$40-$42 $59-$5B $5F $78 $79 $7C $7E $7F`; GFX_10 `$AB-$AF`.
* **Tile slots / sheets.** All variant art lives in sheets that are loaded in every HUSH room: slot 0 `GFX_00`, slot 2 `GFX_10`, slot 3 `GFX_06` (section 2.1 of the art map, all "right" expansion). `tests/smoke/visual_tiles.lua` reads the VRAM tilemap, not the characters, so tile *content* is checked by the screenshots.

### 13.2 Placement (`variant_plan` in `tools/roomgen.py`)

Deterministic: `sha256(room id / cx / cy / salt)` -> [0,1) (not CRC32: it is affine, equal-length salts correlate). Order: torches/sconces -> lit torch pools (+ warm faces) -> banners/sigils/cracks -> contact shadows under every face -> floor variants -> wall-top variants. Rules:

* **Torches only in lit rooms** (`lighting: lit`), ~every 5th face cell of a horizontal run (offset 2 + 5k, jitter 0/1), never within one column of an `X` below, never above a guard letter; **unlit sconces in dark rooms** (offset 3 + 6k): flames would contradict "dark".
* **Light pool** (lit rooms only): `f_glow` on the plain floor cell below the torch, `f_glow2` on its two side neighbours; `fc_warm` on the face cells beside the torch. Never on S/X/guard cells (a static glow near a patrolling guard would give its position away).
* **Floor variants**: 21% of the plain `.` cells; never `S`, `X`, guard cells, never directly below a wall (the contact shadow is the only decoration there), never next to another variant; at most 2 runes per room, 6+ cells apart. The contact shadow covers the cell below **every** face including `S`/guard cells so the line has no gaps (these cells are visible anyway); exit cells keep the exit marker.
* **Wall-top variants** on ~55% of the plain `ceil` cells (chip/speckle mixes 35%, slab seam 20%, crack 10% of those; seam/crack blocks never directly above a face).

### 13.3 Test and checks

`tests/smoke/visual_tiles.lua` (real ROM, 21 rooms): every cell's four tile words in `$7E2000` **and** VRAM equal the plain words of its kind or, for a cell listed in `variants`, the words of that variant; a variant must be of the cell's own base kind (floor variants only on `.`, except the shadow which may also cover S/guard cells; no lit torch in a dark room); `$7F2000` is still compared with the grid (`#`/`p` solid on all four 8x8 tiles, everything else `$00`).
The collision assertions were not touched. Full result in the final report of the E5 change (`make test`).

### 13.4 Palette and painting notes

`bg_dungeon.yaml` rows 3 and 6 of groups 00-05 got new idx 5/6/7 colours (moss, banner cloth, lit-room warm bevel/flame): table in art_map section 3.5. `tools/art/env_art.py apply` re-paints all new tiles (idempotent), `preview` renders them in the six palettes.
Perspective: wall top = the dark mass seen from above (row 7), the 8 px face strip (row 6) is the front; a torch is a whole 16x16 cell (dark top half in row 6 + sconce on the strip), a banner or sigil only decorates the strip.


## 14. E6: game feel (fast room advance, caught flash, sound, music, HUD, ending screen)

Files: `src/hooks/transition.asm` (fast load, fades, HUD cleanup), `roomload.asm` (window-only tilemap upload + collision), `feedback.asm` (music start, caught flash, SFX list), `ending.asm` (ending module, stats, SELECT),
`guard_ai.asm` / `guard_hooks.asm` / `guard_runtime.asm` (one `JSL` per sound / counter at the existing transitions), `tools/roomgen.py` (song bytes), RAM rows in `docs/ram_map.md` ("HUSH feel / polish variables").
Tests: `tests/smoke/{transition,feedback,music,hud,ending,ink_palette}.lua`, `tests/gfx/scenes_ending.lua` (leak check of the ending screen), dev tools `tests/dev/{room_load_profile,fastload_diff,phase_probe,flash_probe,ending_probe,title_diff,hud_probe}.lua`.

### 14.1 Room advance speed: ~160 -> 23 frames

Measured with `tests/dev/room_load_profile.lua` (master clock between the JSL / JSR calls of Module05/06; 1 frame = 357 368 master clocks). **Before** (vanilla Module05 -> Module06 -> submodule `$0F` iris), debug jump -> control 158 frames, exit touch -> control 158-160 frames:

| step | frames | step | frames |
|---|---|---|---|
| `LoadDefaultGraphics` | 16.9 | `LoadAndDrawRoom` (objects 2.2, floors 4.8, 8 quadrant builds + uploads ~5) | 12.0 |
| `DecompressSwordGraphics` + Shield + `LoadFollowerGraphics` | 15.1 | `LoadEveryObjectAttributeSet` | 14.8 |
| `DecompressAnimatedUnderworldTiles` | 6.2 | `InitializeTilesets` | 42.2 |
| `ResetAllSprites` + `Underworld_ResetSprites` | 1.5 | `EraseTilemaps`, HUD rebuild, entrance, palettes | 2.0 |
| iris spotlight (submodule `$0F`) | 44 | | |

**After**: exit touched -> Link controllable in the next room **23 frames** (`tests/smoke/transition.lua`, log line `exit touched -> Link controllable ...`; asserts <= 45), debug jump (`hush_room_req`) -> AI running 17 frames. Brightness `$13` while it happens:
`15 12 9 6 3 0 | 0 | $80 x 9 (the load, forced blank) | 2 5 8 11 14 | 15`. How:

1. **Graphics are not reloaded** (`transition.asm`, hooks 1-3). All 21 rooms use blockset `$00` and sprite set `$04` (room header, roomgen), so after the first load VRAM / the WRAM buffers already hold what a load would produce. `hush_gfx` (`$7EC90E`) = 1 once `InitializeTilesets`
   ran; while it is set `Hush_M05Gfx` (hook on the first of Module05's 7 JSLs) runs only `Sprite_LoadGraphicsProperties`, `LoadDefaultTileTypes`, `InitializeLink` (0.1 frame) and skips `LoadDefaultGraphics`, `DecompressSword / ShieldGraphics`, `LoadFollowerGraphics`;
   `Hush_DecompAnim` and `Hush_InitTilesets` (hooks on the two Module06 JSLs) skip the animated tile sheet and the tileset upload. `Hush_NewGame` and the ending clear it (title / font graphics are in VRAM then): **a new game still takes the full path (~200 frames), only that first room.**
   **Proof it is the same load:** `tests/smoke/transition.lua` restores a snapshot twice, jumps to room 5 and to room 13 once with `hush_gfx = 1` and once with 0, and requires identical VRAM (all 64 KiB), CGRAM, the BG1 tile buffer, the BG2 tile buffer inside the window, the collision map, the tile-type table and the palette buffer.
2. **Only the visible window is built** (`roomload.asm`). The scroll never changes, so only tiles x 16..47, y 18..45 are ever seen (section 1). `Hush_BuildRoom` (hook in `LoadAndDrawRoom`) DMAs the 28 window rows of both tile buffers straight into the two VRAM tilemaps (112 DMAs of 32 bytes, forced blank,
   0.25 frame) instead of the 8 quadrant copies + uploads; **VRAM layout verified against `TilemapUpload_HighBytes`: BG2 tilemap at word `$0000`, BG1 at `$1000`** (the table's "VRAM $2000" comments are byte addresses; my first version wrote BG1 to word `$2000`, i.e. over the BG chr data, and only the fast-vs-full diff caught it).
   `Hush_AttrSet` computes the collision map `$7F2000` for the 896 window tiles (same rule as the vanilla loop incl. the "types $10-$1B take the flip bits" case; 1.9 frames vs 14.8, most of it the vanilla stairs / door passes it still calls through `Hush_AttrTail`).
   **Differences to a vanilla load, outside the window only:** `$7F2000` is 0 (the vanilla loop gave walls to the rim outside; unreachable), the BG2 tile buffer and the VRAM tilemaps keep the previous room's tiles there. Compared against a ROM with the vanilla routines (rooms 5 and 14): window VRAM words 1792/1792 equal, collision window 0 differences.
3. **The floor fill is skipped / copied** (`Hush_FloorChunks`, 4.8 -> 0.6 frame): see the hook 6 comment in `transition.asm`.
4. **Fades instead of the iris** (hook 4, `Hush_Wipe`): submodule `$0F` (which used to run `IrisSpotlight_open` / `_ConfigureTable`: 44 frames) is now a 6-pass brightness ramp, in after every load (`hush_trans = 2`) and out before an advance (`hush_trans = 1`, started by `Hush_StartAdvance` from `Hush_FrameHook`).
   While `$11 = $0F` the guards' AI returns early and Link does not move (as in the iris), the guards are still drawn (`HandleAllSprites` runs in `Hush_Wipe`). After the fade-out `Hush_LoadRoom` runs (Module05 next pass); `$11` stays `$0F` for the rest of that pass so `Hush_FrameHook` cannot fire a second time while Link still stands on the exit; `Hush_FrameHook` also returns at once when `$10 != 7`.
5. **Replays stay valid.** The guards look at `(slot xor $1A) & 1 / & 3`, and `$1A` counts main-loop passes. The old flow (poke the request -> AI running) was 20 passes, the new one is 8 (6 fade-in passes + the load pass + the request pass), so the AI starts on the same `$1A` phase (`tests/dev/phase_probe.lua`: `$1A` mod 4 = 0 at the first AI pass, old and new).
   **`N_IN + 2` must stay a multiple of 4** or all 21 `tests/solutions/*.inputs` desynchronise. All 21 replays pass unchanged (11 388 frames).

Remaining cost of a load (frames, `room_load_profile.lua`): objects 2.2, `ResetAllSprites` + `Underworld_ResetSprites` 1.8, attributes 1.9, floor 0.6, palettes 0.6, tilemap erase 0.5, HUD 0.5, window DMA 0.25: ~9 frames of forced blank. Possible later: erase only what is needed, trim the object drawing.

### 14.2 Caught feedback and sound effects

* **Flash** (`feedback.asm`): `Hush_FastRestart` (6 frames, unchanged) no longer blanks the screen. `Hush_FlashBegin` saves `$99 $9A $9C $9D $9E` (`hush_cmsave`); for 5 frames `Hush_FlashStep` sets CGWSEL `$99 = 0` (fixed colour), CGADSUB `$9A = $3B` (add to BG1, BG2, OBJ, backdrop; the HUD layer BG3 is left out)
  and COLDATA `$9C-$9E` to a white-amber that decays (R G B = 31 26 12, 22 18 9, 14 12 6, 8 7 3, 4 3 1); the 6th frame restores the registers. The room is already reset under the first flash frame, so the cut is hidden. Test `smoke/feedback.lua` reads `$99/$9A/$9C` every frame
  and the PPU state (`tests/dev/flash_probe.lua`: `fixedColor` 13151 = `$335F` -> 1124 over the 5 frames, `colorMathEnabled` = 59). **Seeing it:** `emu.takeScreenshot` / `emu.getScreenBuffer` lag the emulation by ~3 frames and in `--testRunner` mode repeat frames, so a per-frame look is not possible; the flash frames in the screenshots are a pale warm-grey wash of the room with Link at the start.
* **Sound effects** (all vanilla ids; the NMI copies `$012D/$012E/$012F` to APU ports `$2141/$2142/$2143`, `bank_00.asm:263-291`; `$012C` = song -> `$2140`). `QueueSpriteSFX{2,3}WithPan` = `$0DBB7C / $0DBB8A` (bank_0D.asm:8432-8460, adds the pan bits for the sprite's screen position):

| event | id | port | why this id (vanilla use) |
|---|---|---|---|
| guard notices ('?') | SFX2.3C | `$012E` | `PotionShopBeep` (`bank_05.asm:21896`), `ArcheryGameTarget` (`bank_05.asm:880`), 13 uses: a short bleep |
| guard turns ALERT ('!') | SFX3.04 | `$012F` | the soldier's own whistle when it chases: `Guard_InPursuit` (`bank_05.asm:12626`), `BoltGuard_TriggerChaseTheme` (`:13559`) |
| knife takedown | SFX3.08 | `$012F` | `ApplyDamageToSprite` default "sprite hit" (`bank_06.asm:21559-21570`) |
| dart sleep | SFX3.0B | `$012F` | the soft pickup chime of hearts / ammo / fairy (the Absorbable table comments, `bank_06`); SFX2 is not used because the arrow itself writes SFX2.08 in the same frame (`bank_08.asm:6894`) |
| caught | SFX2.26 | `$012E` | Link's hurt cry, `bank_07.asm:153-156` |
| room cleared (exit touched) | SFX3.1B | `$012F` | the secret / door-unlock chime, `RoomTag_OperateKillDoor` (`bank_01.asm:12737`) and 27 more |

  Not played: no tink when the knife hits a suspicious / alert guard (would need the sword box test in states 1 and 2). **Not verified by ear**, only that the ids reach the ports (`smoke/feedback.lua` write callbacks on `$2140-$2143`, low 6 bits = id, bits 6-7 = pan).
* `Hush_Wipe` plays the room clear chime from `Hush_StartAdvance` (`$012F := $1B`).

### 14.3 Music

Songs are vanilla underworld-bank ids (`sound.asm:1021-1115`, `SongBank_Underworld_Main`; the bank is uploaded to the SPC by `LoadUnderworldSongBankIfNeeded` the first time `$0132` is not `$FF/$F2/$03/$07/$0E`, `bank_02.asm:5375-5400`). `tools/roomgen.py` writes `EntranceData.song`:
**floor 1 `$10` Hyrule Castle** (the castle guard theme; vanilla entrances 3-5 and the throne / prison room use it, `bank_02.asm:15322-15324`, `:16056-16058`), **floor 2 `$11` Pendant Dungeon** (the dungeon theme of entrances 8-12, `:15327-15331`), **floor 3 `$16` Crystal Dungeon** (entrances 21, 24, 25 ..., `:15340`),
**the heist room `$1C` Suspense** (`SetBossMusic` default, `bank_02.asm:3286`, `:4017`). The ending plays `$13` Fanfare (`ITEMGET` dungeon prize `bank_09.asm:1952`, after Ganon `bank_09.asm:20151`) and START fades it with `$F1` (`bank_09.asm:21285`). The id choice is by name / vanilla use, **not heard**; change `FLOOR_SONG` / `SONG_FINAL` in `tools/roomgen.py` to swap a track.
Only the first room of a floor and the last room carry a song, all others `$FF` = keep playing (so the track is not restarted per room); `Hush_RoomMusic` writes `$012C := $0132` when the fade-in ends. The dev rooms (test ROM) stay silent (the first upload of the song bank takes tens of frames).
**Verification** (`smoke/music.lua`): write callback on `$2140`: `$10` is sent once after the new game, `$0130` (current song) / `$0133` (last song sent, `bank_00.asm:239-262`) follow, the NMI clears the port afterwards (it only does so when the SPC echoed the id, `:239-247`), no write while moving inside a floor, exactly one at rooms 6, 14 and the last room, none at rooms 4, 9 and 17 (same floor as the one before). Cold boot to the first song: the SPC upload happens in the first room load (new game ~200 frames).

### 14.4 HUD cleanup

`Hush_HudClean` (`transition.asm`) writes the blank word `$207F` into the HUD buffer `$7EC700` (uploaded every frame: `$16` stays set after `RebuildHUD`, `bank_00.asm:1951`): the gem counter always (icon `$7EC712`, digits `$7EC750-54`), the ink pot counter (icon `$7EC718/1A`, digits `$7EC758/5A`) until the room's cumulative tool mask has bit 2,
the dart counter (icon `$7EC71E/20`, digits `$7EC75E/60`) until bit 1 (cells: `docs/gfx/hud_map.md`). **The vanilla `HandleItemRefills` rewrites the digits every frame, after `Hush_FrameHook` in the same pass**, so the clean-up is a hook on that call (`$028856`, `Hush_Refills`) and also runs in every `Hush_Wipe` pass (the first visible fade-in frame is clean).
Hearts, the item box and the (empty) magic meter box are untouched. Test `smoke/hud.lua` reads the BG3 tilemap in VRAM for r01, r03, r07, r10 and the last room.

### 14.5 Ending screen and stats

After the last exit `Hush_Wipe` ends its fade-out with `Hush_BeginEnding`: module `$13` (**`Module13_PendantBossVictory`; its three entries in `RunModule`'s tables are rewritten**, the "Unused" modules `$0C/$0D` are the palette filter / mosaic, not free). `Hush_EndingModule` states (`$B0`): init (forced blank, `$1C = $04` BG3 only, `$16 = 0` so the HUD upload does not overwrite the text,
`TransferFontToVRAM` `$00E556` = the dialogue font at VRAM word `$7000`, tile `$FF` zeroed as the blank tile, BG3 tilemap `$6000` cleared, five text lines, backdrop black, song `$13`), fade-in 15 frames, wait (PRESS START blinks by toggling a palette colour; START is accepted after 90 frames), fade-out, `Hush_Ending` (module 0 = title).
Text: the font glyph of code `c` is the tile pair `T(c) = ((c & $F0) << 1) | (c & $0F)` on top and `T(c) + 16` below (`RenderText`, `bank_0E.asm:8626-8760`); codes A-Z `$00-$19`, a-z `$1A-$33`, 0-9 `$34-$3D`, `!` `$3E`, `?` `$3F`, `-` `$40`, `.` `$41`, space `$59` (`text.asm`). The art agent's real font only has to keep this layout.
Lines: `THE VAULT IS EMPTY` / `AND NOBODY HEARD A THING` / `RETRIES 002` / `TIME 03M 47S` (the font has no `:`) / `PRESS START`. Stats: `hush_retries` (+1 per fast restart, saturating 999), `hush_sec` + `hush_fsub` (gameplay frames = `Hush_Tick` calls, i.e. no fades or loads; 1 s = 60 of them, saturating 99:59), both reset by `Hush_NewGame`.
**Pitfall found:** after the ending the title appeared scrolled (the BG1/BG2 scroll mirrors `$011E-$0125` and `$E0-$EF` still held the room window); `Hush_Ending` zeroes them (`tests/dev/title_diff.lua` compares the PPU scroll registers of a cold-boot title and the title after the ending). `smoke/room_advance.lua`, `solutions/all_rooms.lua` and `smoke/mustnot2.lua` expected "title" after the last exit and now expect module `$13` (spec change).
`smoke/ending.lua` reads the text back from VRAM, checks stats against RAM, the early START is ignored, the title returns, a new game resets the stats. `tests/gfx/scenes_ending.lua` dumps the screens for the leak check.

### 14.6 Ink cloud palette

`Hush_PalInk` colours 6 and 7 (the specks) are teal-cyan `$6B6B` (5ED8D0) and `$77D3` (9CF0E8); smoke fill and rim stay indigo / violet (`docs/gfx/art_map.md` section 7 updated). `smoke/ink_palette.lua` checks CGRAM and takes the screenshot of a real cloud.

### 14.7 SELECT

`$02891E`: the `AND.b #$20` of the SELECT test in `Module07_00_PlayerControl` -> `AND.b #$00`: SELECT no longer opens the save / continue message (`smoke/ending.lua` presses it for 8 frames).

### 14.8 Pitfalls found while doing E6

* **asar does not report overlapping `org` blocks.** Two E6 mistakes went unnoticed by `make build`: `Hush_RoomMusic` placed at `$07FC2E` overwrote the last colours of `Hush_PalInk` (`$07FC23-$07FC30`) and the growing `room_ctrl.asm` pushed `Hush_Ending` over the start of `Hush_NewGame`. Every block now ends with `assert pc() <= <end of its ledger row>` (`warnpc` is deprecated and fails the build).
* `xkas style left to right math`: `$6000+6*32+7` is evaluated left to right; write `$6000+(6*32)+7`.
* DMA from WRAM to WRAM through `$2180` does not work; use MVN (`Hush_FloorChunks`).
* `NMI` skips its DMA work while the main loop is still in the same pass (`$12 != 0`), so direct VRAM writes in a module pass (the ending, `Hush_BuildRoom`) are safe in forced blank.
* Test timing: the endFrame Lua callback sees `$13` and the variables of pass N together with the VRAM of pass N-1 (the NMI that applies pass N's brightness runs after the callback): sample one frame later when checking what is displayed.

## 15. E7: knife line of sight (B-003), chase collision (B-005), frame budget with ancillae (B-006), menu / text box polish

Files: `src/hooks/guard_vision.asm` + `guard_ai.asm` (B-003), `guard_box.asm` (B-005), `bomb_fast.asm`, `arrow_pre.asm` (B-006), `menu_ui.asm` (art requests), RAM: none new. Tools: `tests/dev/lag_profile.lua`, `tests/dev/pot_oam_diff.lua`, `tests/dev/menu_probe.lua`.

### 15.1 B-003: the Shade Knife needs a line of sight

`Hush_SwordCheck` (the vanilla sword box vs the guard box, section 11.5) now calls `Hush_Vision` in **mode 3** before it accepts a kill: the same 8-px walk along the major axis from the guard centre to Link's centre as the vision (section 11.3), testing the `$7F2000`
collision map at every sample, no range, no cone, **no ink cloud** (a guard inside the cloud still dies: that is what the pot is for). A solid tile on the way = a miss: no poof, no sound, the guard's state is untouched, the knife box does nothing (`C = 0`).
Changes to `Hush_Vision`: mode 3 takes the full path of `.start`, skips the cloud test in the loop (`$0E == 3`) and still tests the tiles (the tile test is now skipped for mode 2 only). +6 bytes in the AI block, +10 in the vision block (19 bytes left there).
Why Link's centre and not the sword tip: the tip lies inside the wall when Link stands flush against it (the case of B-003); the segment from the centre crosses the wall cell in 2 of its 5 samples (the guard behind a 16-px wall is 32 px away). The 8-px sampling can slip through a one-tile (8 px) corner; that is a missed block, never a false one.
**Verified:** `tests/smoke/mustnot2.lua` family `K` (22 cases computed from the grids): all pass (10 were XFAIL(B-003); the `KNOWN` entry was removed, QA file edited only for that); all 21 solutions replay unchanged (11 388 frames; knife kills in r03 r06 r07 r10 r17 r19 still kill); `ai_sword` (dev ROM) passes; the repro `B-003_knife_through_wall_r11` now ends with guard a alive.

### 15.2 B-005: the chase no longer slides into a doorway corner

Cause (read in `bank_06.asm:19442-19520`, `CheckTileInDirection` `:19829`, `CheckSpriteTileProperty` `:19861`): the vanilla soldier tile test probes ONE point per direction (up `x+8, y+6`, down `x+8, y+20`, left `x+2, y+13`, right `x+14, y+13`), only for the axis the sprite moves in. A guard moving down past a doorway corner has its centre line in the doorway while up to 10 px of its body are over the wall column; sliding sideways along the wall tests only `y+13`.
Fix: **`Hush_Step` calls `Hush_BoxProbe` (JSL, `guard_box.asm`, bank `$07`) after the vanilla test for ALERT steps only** (`Hush_Step` base 8; patrol, base 0, is untouched: the recorded solutions depend on the patrol stops).
`Hush_BoxProbe` tests the leading edge of the guard's feet box `x+2..x+12, y+6..y+14` in `$7F2000` with 3 probes (5-px spacing; a tile column or row cannot be skipped): right `x+12`, left `x+2` at `y+6 / 10 / 14`; down `y+14`, up `y+6` at `x+2 / 7 / 12`. The box lies inside everything the vanilla probes allow (a patrol guard rests with `x+2` free on its left and `x+14` on its right, `y+6` free below a wall above, `y+14` free above a wall below), so a flat wall is still met by the vanilla probe first and
speed, timing and facing are unchanged (blocked = the same "restore the position and sub-pixels" path of `Hush_Step`); only corners are new. A resting guard overlaps a wall by at most 2 px on the left, 3 px on the right. +2 sub-steps per chase frame (about 230 CPU cycles per chasing guard).
**Verified:** the repro `B-005_guard_in_wall_r19` replays with `HUSH_CHAOS_STRICT=1` (it failed at frame 1701 before), `HUSH_CHAOS_STRICT=1 make chaos` (section 15.6), all 21 solutions (no recorded solution has an alert guard: max awareness 0 / 1), `ai_deescalate`, `ai_stealth`, `ai_caught`, `ai_patrol` (patrol stops unchanged), `ai_los`.

### 15.3 B-006: where the frame goes with pots and arrows (profiling)

`tests/dev/lag_profile.lua` replays a repro (`HUSH_REPLAY=...`) and records per frame the scanline where the logic ends, the live ancilla types, instruction counts per 16-byte bucket (`build/lag_profile_<group>.txt`, mapped to the `vendor/usdasm` labels by hand) and the CPU cycles of every `HandleSingleAncilla` call by type. Facts:
* The loop is **not** slow because of a HUSH routine: with 5 live ancillae (2 pots + arrows) in the 6-guard lit room `final` the logic ends at scanline 205-224 (idle: 170); a pass that crosses the NMI (line 225) loses the next frame and, once an arrow flies, every following pass does the same: 30 fps for as long as the arrow flies (stuck in `[07,07,09,0A,0A]`: 44 of 150 frames lagged).
* CPU cycles per `HandleSingleAncilla` call (vanilla code): pot (`$07`) **~2000-2500** (fuse 1900, held explosion 2450: 6 objects through `AncillaDraw_Explosion` / `Ancilla_SetOAM_XY_safe`, plus tile / lift logic), arrow in flight (`$09`) **2270** (52 % = `Ancilla_CheckSpriteCollision` testing all 6 guards: SetupHitbox + SetupSpriteHitbox + overlap per guard and frame, 30 % = draw), lodged arrow (`$0A`) **873** (draw).
* HUSH's own hooks are negligible there: `Hush_BombHook` 13 instructions per frame, `Hush_AncillaHit` runs only on a real overlap.

### 15.4 B-006: what was cut

1. **`Hush_BombEntry`** (`bomb_fast.asm`, hook `$08955A`): the held explosion frame (phase 8 while the cloud lives) no longer runs `Ancilla_HandleLiftLogic`, `Ancilla_LatchYCoordToZ`, `Ancilla_CheckTileCollision_Class2` and the state code for a bomb that lies still; it sets `$039F := 1` (what the hook + decrement leave) and calls `AncillaDraw_Bomb` directly (bomb 2449 -> 2022 cycles in the held phase). Everything else takes the vanilla path.
   **Verified identical:** `tests/dev/pot_oam_diff.lua` (a pot + an arrow, 440 frames, r10 / r12 / final, old ROM vs new ROM, per frame: OAM buffer CRC, ancilla array CRC, ink timer, ancilla types): OAM identical on all frames, ancilla RAM identical except `$0C68,X` (the bomb's pit / water re-entry guard, 0 or 2 on a floor, read only by its pit / water branches).
2. **`Hush_AncPre`** (`arrow_pre.asm`, hook `$088DAE`, 104 bytes): in `Ancilla_CheckSpriteCollision_Single`, for an ARROW and a GUARD, a position difference of >= 32 px in x or y returns "no collision" before the hitbox set-up. The real boxes (arrow `x+4..x+11` x `y+4..y+11`, guard `x+2..x+13` x `y-3..y+13`, both read from the ROM tables) can only touch within ~10 px. Arrow in flight 2270 -> 1219 cycles. Darts tests pass (`ai_darts`, `mustnot2` family D / P, the replays with darts).
3. Not done (needs ~190 bytes of free ROM in one bank-`$07` piece, only 86 + 104 are left): a hand-written draw for the held cloud (6 objects of tile `$86`, the rules of `Ancilla_SetOAM_XY_safe` written out: ~600 instead of ~2000 cycles per pot, the biggest remaining item: 2 clouds = ~26 scanlines); a shorter life of the lodged arrow (`$08A4C9`, visual change); a cheaper `PrepareOAMForTransfer` (3000 cycles, vanilla).

**Result** (B-006 repro, final room, 1825 frames of pot / dart spam, the same input file; the timeline differs a little because lag changes what the inputs do):

| | before (E6 + B-003 / B-005) | after |
|---|---|---|
| lagged frames | 280 | **115** |
| arrow in flight (cycles per call) | 2270 | 1219 |
| held pot (cycles per call) | 2449 | 2022 |
| logic ends at scanline, 2 pots only `[07,07]` | 198 | 191 |
| `[07,07,0A,0A,0A]` (2 pots, 3 lodged arrows) mean / max | 214.8 / 224 | 208.6 / 222 |
| `[07,07,09,0A,0A]` (+ one arrow in flight) mean | 214.2 (60 of 76 frames lagged) | 215.4 (44 of 150) |
| no ancilla | 168.8 | 169.6 |

`chaos_spam` seeds (frames lagged of the run, before -> after): r10 0 -> 0, r12 1 -> 1, r14 96 -> 4, r20 181 -> 104, final 236 -> 195, r19 92 -> 71 (the seeds replay different timelines, so these are indicative).

A burst of 2 pots + 3-4 arrows in the 5-6 guard rooms still reaches the NMI line now and then (B-006 stays open as "mitigated", residual = the vanilla draw of the two held clouds). 1 pot, or up to 3 arrows without pots, or any burst in a room with <= 4 guards (`r14` 4 guards, `r16`, `r19`) stays under line 200.

### 15.5 Menu / text box (art agent requests, `docs/gfx/hud_map.md` section 9)

* **Solid text box**: `RenderText_BorderTiles` middle-row interior and `RenderText_ClearTileFill` (`$0ED387`, `$0ED397`, vanilla `$387F` = blank tile `$07F`, palette 6) -> `$38F5` (tile `$0F5`, palette 6 = the flat DARK fill). Verified in the ROM bytes (`F5 38` at both); the text box only appears for the (disabled) SELECT message in HUSH, so no screenshot exists.
* **Pause menu hides the room**: the NMI writes TM (`$212C`) in two places (`$008174`, `$008265`: `LDA.b $1C : STA.w TM`), both now `JSL Hush_NmiTM`: TM = `$04` (BG3 only) while module `$10 = $0E` and submodule `$11 = 1` (the START item menu; the dungeon map / potion submodules are not affected), else `$1C`. `$1C` is never touched, so the room is back the frame after the menu closes. The gaps between the windows now show the backdrop.
  **Verified** (`tests/dev/menu_probe.lua`): the PPU main-screen mask is `4` in the menu and the room's value (`$22`) again 60 frames after START closes it, for floors 1-3; screenshots in `build/test-results/dev_menu_probe/menu_floor{1,2,3}.png` (read with the image viewer: windows only, no strip of the room). The sprites (guards, Link) are not shown in the menu either (they are OBJ; the cursor ring and the item icons are BG3).
* **FLOORS sockets**: `Hush_SetPendants` (called by `Hush_GrantTools`, i.e. on every room load and fast restart) writes `$7EF374` = 1 / 3 / 7 for floor 1 / 2 / 3 (ROOM TABLE +22). Every vanilla reader of `$7EF374` was checked (grep over `vendor/usdasm`): prize room tags, the music fade of vanilla rooms `$0007` / `$0017`, NPC sprites, the overworld map, the item-get table; none can run in a HUSH room (list in the `menu_ui.asm` header). `$7EF3C5 = 2` keeps the pendants window. The ending screen is its own module (no menu), so "all lit at the ending" is not applicable.
  Verified: `$7EF374` = `01 / 03 / 07` in rooms of floors 1 / 2 / 3 (`menu_probe.lua`), screenshot of floor 2 shows two lit sockets and one empty.

### 15.7 Found by the final chaos run: a sleeping guard pushed Link into a wall (fixed)

`chaos_spam` r14 seed 303 (it passed before E7; the timing change of B-006 moved the run to a new situation) failed with "Link is inside a wall" at frame 1417: Link stood flush under a wall (y = 9960), walked right and touched the corner of a sleeping guard 2 px / 2 px: the E2 `Hush_Solid`
pushed him out along the smaller overlap axis, the tie went to y, and the 2-px push moved his box 2 px into the wall above him. **Fix** (`Hush_Solid`, `guard_ai.asm`): when Link's box overlaps a sleeper he is put back where he was at the end of the last frame (`hush_lx` / `hush_ly`, `docs/ram_map.md`), a position that is known to be free of walls,
unless he already overlapped the sleeper there (the guard fell asleep on him): then he stays where he is (a push could end in a wall; undoing every move would trap him). The position is saved by `Hush_SaveLink` (`feedback.asm`), called from `Hush_Refills` (hook `$028856`): **the very end of the gameplay frame, after Link moved and the guards ran**
(my first version saved it in `Hush_Tick`, which runs before the sprites but after Link's move, so the saved position equalled the current one and nothing blocked: `ai_darts` "Link stops at the sleeping guard" caught it).
Verified: the repro replays clean (`HUSH_REPLAY=... chaos_replay.lua`), `ai_darts` (sleeper solid), `mustnot2` family S (400 frames of pushing in the r07 corridor), all replays, the chaos suite (15.6).
QA: this is a bug that was latent since E2 (not in `docs/bugs.md`); the engine agent did not add an entry.

### 15.6 Results

See the final report of the E7 change (`make build`, `make test`, `make chaos`, `HUSH_CHAOS_STRICT=1 make chaos`): pasted there, not here, because the numbers belong to the run.

## 16. T0: autotiled background (design/tiles.md)

Replaces sections 12-13 for the room tiles (the object-based draw, the E5 variant objects and the tile-id collision constraints). Collision and placement now follow the grid.

* **Data**: `tools/roomgen.py` calls `tools/autotile.py place()` per room: 32 x 28 chars (one per 8x8 tile), regrouped into 16 x 14 cells of 4 tile words. A global dictionary (`Hush_CellWords`, 8 bytes per distinct cell, 81 for the 21 rooms) plus per room a RLE of cell ids (pairs count / id, `0,0` ends; 4.4 KB for all rooms) replace the object streams. The vanilla object stream of each room is an empty stub (floor byte + layout 7). Whole ROM data: 5.7 KB of the 12 032 B row `$1F8780-$1FB67F`.
* **Decoder**: `Hush_BuildRoom` calls `Hush_Blit` (`$1FB680`, 256 B carved from the room-data row) right after `LoadAndBuildRoom`; it writes 4 words per cell into `$7E2000` at (tile 16, 18) with a 128-byte row stride, using only DP `$00-$0F`. The DMA of the window is unchanged.
* **Collision**: `UnderworldTileTypes` (`$0E9659`, 256 B) is rewritten by roomgen: `$00` / `$01` per tile id of the new tileset (GFX_00 ids 0-63, GFX_10 ids 128-191). `Hush_AttrSet` still derives `$7F2000` from `$7EFE00 + id`, so guard vision, guard box, knife and arrows see the same `$00` / `$01` map as before. `Hush_AttrSet` lost the unused "types `$10-$1B` take the flip bits" rule to make room for the 4-byte `JSL Hush_Blit` (the `$0FFE72` block is full).
* **Tile ids are free** now: no vanilla type constraint. Palette rows are unchanged (floor 3, exit 4, pillar and water 5, face 6, roof and pit 7). Sheets: `tools/art/autotile_art.py apply`.
* **Gallery**: `tests/dev/rooms/gallery.yaml` (dev ROM only) exercises every case, including pit and water, which no shipped room uses (no sight / arrow semantics defined, see `design/tiles.md` Decisions).
* **Verified**: `make test` (26 pass, 2 pre-existing savestate skips; unit autotile test; `visual_tiles` 18 816 tiles + collision vs the grid; `visual_gallery`; leakcheck clean). Before / after: `docs/gfx/screenshots/env_r05_f1_dark.png` vs `t0_r05_f1_dark.png`, `env_r09_f2_lit.png` vs `t0_r09_f2_lit.png`.

## 16. L1: lantern light = guard sight (`src/hooks/light.asm`, design/lighting.md)

* **Technique** (vanilla castle-escape lamp: `OrientLampLightCone` `bank_00.asm:15413`, `RoomDraw_LampCones` `bank_01.asm:5679`, a BG1 cone added by colour math):
  BG1 goes on the sub screen (`$1D` bit 0), `CGWSEL $99 = $02` (sub screen addend), `CGADSUB $9A = $22` (add to BG2 + backdrop; not OBJ, not BG3). Where BG1 is
  transparent the addend is COLDATA = 0, so the room is unchanged. Measured in a room before L1: `TM $16`, `TS $00`, `$99 $02`, `$9A $20`, BG1 hidden and holding the floor copy
  that `transition.asm` reuses as the BG2 floor source, so the light never touches the `$7E4000` buffer: it has its own WRAM tile buffer and uploads only the BG1 **VRAM** window.
* **Calls (no new vanilla bytes):** `Hush_AttrSet` ends with `JML Hush_LightInit` (collision ready, forced blank: state reset, solidity + faces, BG1 window := no light);
  the submodule-$0F hook calls `Hush_LightWipe` = `Hush_Wipe` + the light palette (row 2 colours 9-12, rooms rows 3-7 dimmed to 11/16 dark, 13/16 lit) before the first fade-in
  frame (`LoadUnderworldPalettes` runs after `Hush_AttrSet`, `bank_02.asm:426`); `Hush_MeterFrame` ends with `JSL Hush_LightWork`; `Hush_NmiTM` starts with `JSL Hush_LightNmi`.
* **Frame budget:** the worker runs at the end of the gameplay frame and spends only spare time: before each unit it reads the V counter (latch `$2137`, `$213F`, `$213D` twice,
  as `bank_00.asm:15150`) and stops at line 195 or when the counter wrapped. Units: pick (8 signatures), clear, 12 ray entries, half a cell row of commit; each <= ~10 lines.
  Measured (`tests/dev/nmi_probe.lua`, 180 frames walking, final / r20 / r19): end of logic max 213 / 212 / 212 with light, 205 / 187 / 177 without; **0 lag frames**.
  The NMI reaches `Hush_NmiTM` at line 250; <= 4 dirty cell rows (512 bytes) are uploaded per NMI.
* **Correctness:** `tests/smoke/lighting.lua` compares every guard's committed light map with an independent Lua oracle of design/lighting.md (all 21 rooms, an ink case),
  checks the composite, glow, tile words, the BG1 VRAM window, liveness (light catches up with its guard) and the colour-math shadows.
* **Range:** the job reads the lit flag from the ROOM TABLE (+19 bit 0), not `hush_range`: `Hush_Tick` only updates that in submodule 0.
* **Item menu:** `Hush_LightNmi` clears `$1D` while module `$0E` submodule 1 runs (TM is BG3 only there, and the backdrop would still get the light added).
