; =============================================================================
; HOOK: room_ctrl  (per-frame game controller: health, exits, room loads, restart, tools)
;
; Address:  $0287BA (SNES LoROM), 4 bytes, in Module07_Underworld (runs once per frame, submodule 0)
; Replaces: `JSL LoadChrHalfSlot`   (22 FA E3 00)  vendor/usdasm/bank_02.asm:1396 ($00E3FA, bank_00.asm:12086)
; Does:     JSL Hush_FrameHook. It performs the replaced JSL first, then
;             1. refills health ($7EF36D := $7EF36C) so Link never dies;
;             2. `hush_room_req` != 0 (value N+1): load room N (test/debug jump);
;             3. Link's feet inside an exit rectangle of the current room: Hush_StartAdvance (transition.asm: fade out, fast load of the next
;                room, or the ending screen after the last one).
;           The module is switched to 5 (load file) which rebuilds the room through
;           LoadUnderworldEntrance; the rest of the current frame is harmless (module is re-dispatched
;           next frame), so the return address is NOT discarded.
;
; Public routines (JSL from other hooks, e.g. the guard AI):
;   Hush_LoadRoom     A = room index (8-bit M). Sets everything for a reload of that room (FULL rebuild, ~160 frames).
;   Hush_RestartRoom  full reload of the current room (same entrance). "Caught" does NOT use it: guard_runtime.asm has the
;                     fast restart (Hush_FastRestart, ~7 frames) that keeps the room's tiles and graphics.
;   (Hush_Ending, the soft reset to the title, moved to ending.asm; the last room's exit starts the ending module there.)
;
; RAM (docs/ram_map.md): hush_room $7EC900, hush_room_req $7EC901. Scratch: $00-$03.
; Data: Hush_RoomTable and the !HUSH_* defines come from build/rooms_gen.asm (tools/roomgen.py).
;
; Space:    src/FREESPACE.md rows: hook $0287BA; free block $07F89D (NULL_07F89D, "FREE ROM: 0x763",
;           bank_07.asm:23958-23960; all $FF in vanilla ROM, no references in vendor/usdasm).
; =============================================================================

!hush_room = $7EC900
!hush_req  = $7EC901

org $0287BA
    JSL Hush_FrameHook

org $07F89D
Hush_FrameHook:
    JSL $00E3FA                          ; LoadChrHalfSlot (the replaced vanilla call)
    PHP
    SEP #$30
    LDA.b $10 : CMP.b #$07
    BNE .module_changed                  ; a load / the ending was started earlier in this pass (transition.asm): nothing more to do
    LDA.l $7EF36C : STA.l $7EF36D        ; never die: current health := capacity
    JSL Hush_Tick                        ; E2 (guard_runtime.asm): caught -> fast restart, lit range, ink timer, palettes, flash

    LDA.l !hush_req
    BEQ .no_req
    PHA
    LDA.b #$00 : STA.l !hush_req
    PLA
    DEC A
    CMP.b #!HUSH_ROOM_COUNT
    BCS .no_req                          ; out of range: ignored
    JSL Hush_LoadRoom
    BRA .done

.no_req
    JSR Hush_CheckExit
    BCC .done
    LDA.l !hush_room
    INC A
    CMP.b #!HUSH_ROOM_COUNT
    BCC .advance
    LDA.b #$FF                           ; after the last room: the ending
.advance
    JSL Hush_StartAdvance                ; transition.asm: fade out, then Hush_LoadRoom (fast) or the ending
.done
.module_changed
    PLP
    RTL

; -----------------------------------------------------------------------------
; Hush_CheckExit: C = 1 when Link's feet point (x+FEET_DX, y+FEET_DY) is inside an exit rect of
; the current room. Rects are window-relative pixels (ROOM TABLE +0..15). Returns M=X=8-bit.
Hush_CheckExit:
    REP #$30
    LDA.b $22 : CLC : ADC.w #!HUSH_FEET_DX : AND.w #$01FF : SEC : SBC.w #!HUSH_WIN_X
    BMI .no
    CMP.w #$0100 : BCS .no
    STA.b $00
    LDA.b $20 : CLC : ADC.w #!HUSH_FEET_DY : AND.w #$01FF : SEC : SBC.w #!HUSH_WIN_Y
    BMI .no
    CMP.w #$00E0 : BCS .no
    STA.b $02
    LDA.l !hush_room : AND.w #$00FF
    ASL #5                               ; * ROOM_REC (32)
    TAX
    SEP #$20
    LDY.w #$0004
.rect
    LDA.b $00
    CMP.l Hush_RoomTable+0,X : BCC .skip
    CMP.l Hush_RoomTable+2,X : BEQ .xok : BCS .skip
.xok
    LDA.b $02
    CMP.l Hush_RoomTable+1,X : BCC .skip
    CMP.l Hush_RoomTable+3,X : BEQ .hit : BCC .hit
.skip
    INX #4
    DEY
    BNE .rect
.no
    SEP #$30
    CLC
    RTS
.hit
    SEP #$30
    SEC
    RTS

; -----------------------------------------------------------------------------
; Hush_LoadRoom: A = room index (0-based). Reload through Module05 -> LoadUnderworldEntrance (entrance
; row k = room k). All state is restored: P (so callable with any M/X), nothing else is changed except
; the listed game state.
Hush_LoadRoom:
    PHP
    SEP #$30
    STA.l !hush_room
    STA.w $010E                          ; entrance index (EntranceData rows 0..N-1)
    LDA.b #$01 : STA.w $010A             ; skip the "recache" branch of LoadUnderworldEntrance
    STZ.w $04AA                          ; not a respawn: use the EntranceData row
    STZ.b $B0
    LDA.b #$05 : STA.b $10               ; Module05_LoadFile (forced blank; graphics skipped while hush_gfx is set, transition.asm)
    STZ.b $11
    LDA.b #$02 : STA.l !hush_trans       ; transition.asm: Hush_Wipe fades the loaded room in (submodule $0F)
    LDA.b #$00 : STA.l !hush_tcnt
    JSR Hush_GrantTools
    JSL Hush_ResetRuntime                ; E2: caught / flash / ink cloud / palette flag cleared
    REP #$30
    LDA.l !hush_room : AND.w #$00FF : CLC : ADC.w #!HUSH_ROOM_FIRST : ASL A
    TAX
    LDA.w #$0000
    STA.l $7EF000,X                      ; this room's save flags (doors/chests/quadrants)
    STA.l $7FDF80,X                      ; its sprite death flags: killed guards return on restart
    PLP
    RTL

Hush_RestartRoom:
    PHP
    SEP #$30
    LDA.l !hush_room
    JSL Hush_LoadRoom
    PLP
    RTL

; -----------------------------------------------------------------------------
; Hush_GrantTools: cumulative tool mask of the current room -> inventory + refills.
; ROOM TABLE +18: bit0 knife -> sword $7EF359=1; bit1 darts -> bow $7EF340=2 + 8 arrows $7EF377;
; bit2 ink -> bombs $7EF343=8.
Hush_GrantTools:
    PHP
    REP #$30
    LDA.l !hush_room : AND.w #$00FF
    ASL #5
    TAX
    SEP #$20
    LDA.l Hush_RoomTable+18,X : STA.b $00
    AND.b #$01 : STA.l $7EF359
    LDA.b #$00 : STA.l $7EF340 : STA.l $7EF377 : STA.l $7EF343
    LDA.b $00 : AND.b #$02 : BEQ .no_darts
    LDA.b #$02 : STA.l $7EF340
    LDA.b #$08 : STA.l $7EF377
.no_darts
    LDA.b $00 : AND.b #$04 : BEQ .no_ink
    LDA.b #$08 : STA.l $7EF343
.no_ink
    JSL Hush_SetPendants                 ; E7 (menu_ui.asm): the FLOORS sockets of the item menu = floors reached
    PLP
    RTS
Hush_RoomCtrl_End:
assert pc() <= $07FA00                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
