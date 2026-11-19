; =============================================================================
; HOOK: menu_ui  (E7: item menu / text box polish requested by the art agent, docs/gfx/hud_map.md section 9)
;
; 1. Solid text box (hud_map.md 9.1)
; Address:  $0ED387 (2 bytes) and $0ED397 (2 bytes), bank $0E data
; Replaces: `dw $387F` in RenderText_BorderTiles (middle row interior, `dw $28C8, $387F, $68C8`, bank_0E.asm:10273-10277 = $0ED385-$0ED38A)
;           and `dw $387F` in RenderText_ClearTileFill (bank_0E.asm:10284-10285 = $0ED397); vanilla bytes 7F 38 in both (checked in rom/vanilla.sfc).
;           $387F = tile $07F (blank, transparent: the room shows through), palette 6, priority 1.
; Does:     `dw $38F5` in both: tile $0F5 in palette 6 is the flat DARK 0A1028 fill (art agent), so the text box interior is opaque.
;
; 2. Pause menu hides the room (hud_map.md 9.2)
; Address:  $008174 and $008265 (5 bytes each), the two copies of the main-screen register write in the NMI (bank_00.asm:338, :492)
; Replaces: `LDA.b $1C : STA.w TM`   (A5 1C 8D 2C 21)
; Does:     `JSL Hush_NmiTM : NOP`. Hush_NmiTM writes TM ($212C) = $04 (BG3 only: the menu windows and the HUD layer) while module $10 = $0E and
;           submodule $11 = 1 (Module0E_01_ItemMenu, the START menu), else the shadow $1C as before. $1C itself is untouched, so closing the menu
;           needs no restore: the next NMI after the module changes writes $1C again. The room (BG1 / BG2) and the sprites (OBJ: the guards, Link)
;           are not shown behind / between the menu windows any more; the gaps between the windows show the backdrop colour.
;
; 3. FLOORS sockets (hud_map.md 9.3)
; Does:     Hush_SetPendants (JSL from Hush_GrantTools in room_ctrl.asm, i.e. on every room load and every fast restart) sets
;           $7EF374 (pendant flags: bit 0 green, bit 1 blue, bit 2 red) = 1 / 3 / 7 for floor 1 / 2 / 3 (ROOM TABLE +22): the pendants window of the
;           menu (DrawPendantsWindow, bank_0D.asm:15170) lights one socket per floor reached. Vanilla readers of $7EF374 (all grepped in
;           vendor/usdasm): the pendant / crystal prize tags (RoomTag_PrizeTriggerDoor bank_01.asm:12825, :13241: room tags HUSH rooms do not have),
;           the music fade of vanilla rooms $0007 / $0017 (bank_02.asm:2374, :3312: room ids HUSH never loads), NPC sprites (priest, fortune teller,
;           Sahasrahla, Aginah, bank_05 / bank_0D: never spawned), the overworld map (bank_0A) and the item-get table (bank_09:1223): none runs in HUSH.
;           `$7EF3C5 = 2` (new_game.asm) keeps the pendants window (not the crystals one) in the menu.
;
; Space:    src/FREESPACE.md rows: hooks $0ED387-$0ED388, $0ED397-$0ED398, $008174-$008178, $008265-$008269; free $07FFAA-$07FFFF
;           (the tail of NULL_07F89D "FREE ROM: 0x763", bank_07.asm:23958; all $FF in vanilla ROM, no references in vendor/usdasm)
; =============================================================================

pushpc
org $0ED387
    dw $38F5
org $0ED397
    dw $38F5
org $008174
    JSL Hush_NmiTM
    NOP
org $008265
    JSL Hush_NmiTM
    NOP
pullpc

org $07FFAA
Hush_NmiTM:                              ; M = 8 bit (NMI), DB = $00
    LDA.b $10
    CMP.b #$0E
    BNE .room
    LDA.b $11
    CMP.b #$01
    BNE .room
    LDA.b #$04                           ; the item menu: BG3 only
    BRA .write
.room
    LDA.b $1C                            ; the replaced instruction
.write
    STA.w $212C                          ; TM
    RTL

Hush_SetPendants:                        ; JSL from Hush_GrantTools; keeps P
    PHP
    REP #$30
    LDA.l !hush_room : AND.w #$00FF
    ASL #5
    TAX                                  ; ROOM TABLE record
    LDA.l Hush_RoomTable+22,X : AND.w #$0003
    TAX                                  ; floor 0..3 (a room without a floor: no socket)
    SEP #$20
    LDA.l Hush_PendTab,X : STA.l $7EF374
    PLP
    RTL
Hush_PendTab:
    db $00, $01, $03, $07                ; floor 1: green, floor 2: + blue, floor 3: + red
Hush_MenuUI_End:
assert pc() <= $080000                       ; the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
