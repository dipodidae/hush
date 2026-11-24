# Hooks

One file per hook. Include it from `src/main.asm`. Every hook file starts with
this header (copy it):

```asm
; =============================================================================
; HOOK: <short name>
; Address:  $BBAAAA (SNES LoROM), PC offset 0xXXXXX
; Replaces: <the exact vanilla instructions/bytes, e.g. `LDA $0DD0,X : CMP #$09`>
;           (cite vendor/ file:line where it was read)
; Does:     <one sentence>
; Space:    <ledger row in src/FREESPACE.md that covers the hook site and any
;            freespace routine it jumps to>
; =============================================================================
```

The hook site and any freespace routine must both have rows in
`src/FREESPACE.md`.

## Index

| File | Hook | Sites |
|---|---|---|
| `sa1_header.asm` | SA-1 step 1: cartridge header (map mode `$23`, type `$35`, 128 KB BW-RAM); checksum fixed by `tools/build.py` | `$00FFD5`, `$00FFD8` (+ `$00FFDC` build.py) |
| `sa1.asm` | SA-1 step 2: at boot, I-RAM / BW-RAM writes on, SA-1 reset vector, SA-1 released; the SA-1 idles (heartbeat, I-RAM mailbox); step 4: a command runs one light worker frame (`Hush_LightJob`, light.asm) | `$00802C`, blocks `$0089C2`, `$00CF46` |
| `anim_skip.asm` | SA-1 step 4: no animated-tile NMI upload in module 7 (slot 7 is never drawn by a room): vblank for the light rows | `$008B50`, block `$03EB80` |
| `intro_skip.asm` | A0: boot to the title, no triforce/sword intro; owns `Hush_TitleStart` | `$0CC120`, `$0CC151`, block `$0CC10C` |
| `camera_lock.asm` | E1: camera never scrolls, no edge transitions | `$02BA31`, `$02885E` |
| `room_ctrl.asm` | E1: per-frame controller (health, exits, room loads, restart, tools) | `$0287BA` |
| `new_game.asm` | E1: title START -> new file -> room 1 | `$0CC130` |
| `../build/rooms_gen.asm` | E1: GENERATED room data, room table, EntranceData rows (not a hook; checked against the ledger) | many, see FREESPACE.md |
| `guard_ai.asm` | E2: the stealth AI replaces vanilla `Guard_Main` for the soldier sprites `$41-$43` (states, patrol, chase); E4: also the `SpriteData_OAMHarm` rows of those types (5 OAM entries) | `$05C155`, `$0DB0C1` |
| `guard_vision.asm` | E2: guard -> Link geometry, cone / range / line-of-sight / ink cloud tests (not a hook; free block of bank `$0E`) | - |
| `guard_hooks.asm` | E2: arrows put an unaware guard to sleep; bombs become ink clouds, no damage | `$06ECB7`, `$089815` |
| `room_visuals.asm` | E3: tile data of the unused vanilla objects `$07`, `$B8/$92`, `$B9/$93` (wall face, pillar, exit marker) + `UnderworldPaletteSets` rows 1-5 (dark/lit x floor 1-3); data only | `$009EDA`, `$00BAA4`, `$0ED464` |
| `guard_runtime.asm` | E2: per-frame tick, fast restart, runtime palettes (not a hook; free block of bank `$07`, called from `room_ctrl.asm`) | - |
| `meter.asm` | M5: stealth meter (hits per awareness transition, cooldowns, refill on entry, empty = caught), HUD bar instead of hearts, vanilla damage dropped | `$07807F`, `$0DFB94` |
| `guard_draw.asm` | E4: the guard drawing `Hush_DrawGuard` (head, lantern, body, icon, shadow = 5 OAM entries from `GFX_BC`; replaces the vanilla soldier draw; not a hook, JSL'd from `guard_ai.asm`; free block of bank `$07`) | - |
