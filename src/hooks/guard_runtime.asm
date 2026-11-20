; =============================================================================
; guard_runtime.asm  (E2: per-frame tick, fast restart, runtime palettes)
; Not a hook: routines called (JSL) from room_ctrl.asm (Hush_FrameHook / Hush_LoadRoom). Bank $07, next to room_ctrl.
;
; Hush_Tick (JSL from Hush_FrameHook, once per gameplay frame, M = X = 8):
;   1. hush_caught set by a guard -> Hush_FastRestart
;   2. hush_range := 128 (lit room) / 80 (dark room), from ROOM TABLE +19 bit 0
;   3. ink cloud timer (hush_ink_t) counts down
;   4. the amber / ink palettes are written into the live palette buffer once per room load (hush_pal)
;   5. the restart flash (E6: white-amber colour math over 5 frames, decaying; was 6 black frames), feedback.asm
; Hush_FastRestart (JSL): restart the CURRENT room without rebuilding it. The tilemaps, graphics and palettes stay;
;   all sprites, ancillae, garnish are cleared and the room's sprite list is loaded again (Underworld_ResetSprites,
;   bank_09.asm:13187-13250), Link goes back to the entrance position (EntranceData rows, written by roomgen),
;   tools are refilled, the room flags are cleared. docs/engine_notes.md has the measured frame count.
; Hush_ResetRuntime (JSL from Hush_LoadRoom): clears caught / flash / ink / palette flag for a full room load.
;
; Space:    src/FREESPACE.md row $07FB00 (the unclaimed tail of NULL_07F89D, "FREE ROM: 0x763", bank_07.asm:23958; all $FF)
; =============================================================================

!hush_flash   = $7EC903
!hush_pal     = $7EC904

org $07FB00
Hush_Tick:
    JSL Hush_TimeTick                    ; E6 (ending.asm): play time for the ending screen
    LDA.l !hush_caught
    BEQ .not_caught
    JSL Hush_FastRestart
.not_caught
    REP #$30
    LDA.l !hush_room : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX
    SEP #$20
    LDA.l Hush_RoomTable+19,X : AND.b #$01
    REP #$20
    BEQ .dark
    LDA.w #$0080
    BRA .set_range
.dark
    LDA.w #$0050
.set_range
    STA.l !hush_range
    LDA.l !hush_ink_t : BEQ .no_ink
    DEC A : STA.l !hush_ink_t
.no_ink
    SEP #$30
    LDA.l !hush_pal : BNE .pal_done
    JSR Hush_SetPalettes
    LDA.b #$01 : STA.l !hush_pal
.pal_done
    LDA.l !hush_flash : BEQ .done
    DEC A : STA.l !hush_flash
    JSL Hush_FlashStep                   ; feedback.asm: colour-math flash with a decaying intensity, restores the registers on the last frame
.done
    RTL

; -----------------------------------------------------------------------------
Hush_ResetRuntime:
    PHP
    SEP #$30
    LDA.l !hush_flash
    BEQ +
    LDA.b #$00
    JSL Hush_FlashStep                   ; a load interrupts a running flash: put the colour-math registers back
+   LDA.b #$00
    STA.l !hush_caught : STA.l !hush_flash : STA.l !hush_pal
    STA.l !hush_ink_t : STA.l !hush_ink_t+1
    PLP
    RTL

; -----------------------------------------------------------------------------
Hush_FastRestart:
    PHP
    SEP #$30
    LDA.b #$00 : STA.l !hush_caught
    STA.l !hush_ink_t : STA.l !hush_ink_t+1
    REP #$30
    LDA.b $A0 : ASL A : TAX                ; this room's save flags and sprite death flags (as Hush_LoadRoom)
    LDA.w #$0000
    STA.l $7EF000,X
    STA.l $7FDF80,X
    SEP #$30
    JSL $09C114                          ; Underworld_ResetSprites: clears sprites, ancillae, garnish; loads the sprite list
    JSL $07F1A3                          ; ResetLinkProperties_A (also B, C): recoil, sword, items, swimming ...
    REP #$30
    LDA.l !hush_room : AND.w #$00FF : ASL A : TAX
    LDA.l $02CF59,X : STA.b $20          ; EntranceData.y_coordinate / x_coordinate row = the start position
    LDA.l $02D063,X : STA.b $22
    SEP #$30
    STZ.b $5D                            ; Link state: walking
    STZ.w $0372                          ; not dashing
    LDA.l !hush_room : BNE +
    LDA.b #$02 : BRA ++                  ; room 0: Link faces down (as the vanilla entrance does), others: up
+   LDA.b #$00
++  STA.b $2F
    JSR Hush_GrantTools                  ; refill darts / ink pots
    JSL Hush_MeterRestart                ; M5 (meter.asm): Hush_CountRetry (E6, ending.asm: the ending screen shows the retries), then the meter refill
    LDA.b #$26 : STA.w $012E             ; SFX2.26: Link's hurt cry (bank_07.asm:153-156, the damage routine), the "caught" sound
    JSL Hush_FlashBegin                  ; feedback.asm: 6 frames (Hush_Tick), the first 5 with the white-amber colour-math flash
    PLP
    RTL

; -----------------------------------------------------------------------------
; Hush_SetPalettes: sprite palette rows written into the live and the cached palette buffer, then uploaded (NMI, $15).
;   row 6 = ALERT guard (amber); row 1 = ink cloud / bomb explosion (dark indigo smoke), colours 1-7 (BGR555).
Hush_SetPalettes:
    REP #$30
    LDX.w #$0000
.copy
    LDA.l Hush_PalAlert,X
    STA.l $7EC6C2,X : STA.l $7EC4C2,X
    LDA.l Hush_PalInk,X
    STA.l $7EC622,X : STA.l $7EC422,X
    INX : INX
    CPX.w #$000E
    BCC .copy
    SEP #$30
    LDA.b #$01 : STA.b $15
    RTS

Hush_PalAlert:                           ; outline, body, shade, highlight, lantern, glyph, violet (unused)
    dw $0C21, $0DD9, $090F, $331E, $2F5F, $6BDF, $79F5
Hush_PalInk:                             ; ink cloud: near-black indigo smoke (colours 1-5) with teal-cyan specks (colours 6, 7: $6B6B = 5ED8D0, $77D3 = 9CF0E8; E6)
    dw $0C21, $2043, $1822, $30A5, $4CE9, $6B6B, $77D3
Hush_Runtime_End:
assert pc() <= $07FC40                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
