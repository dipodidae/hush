; =============================================================================
; guard_draw.asm  (E4: the HUSH guard drawing; replaces the vanilla soldier draw Guard_HandleAllAnimation)
; Not a hook of its own: Hush_DrawGuard is JSL'd from Hush_GuardAI (guard_ai.asm), which used to JSL the vanilla
; Guard_HandleAllAnimation_long ($05C676: head + body + weapon + shadow = 9 OAM entries from 60 cells with many flips).
; The matching OAM allocation (5 entries instead of 9) is the SpriteData_OAMHarm hook in guard_ai.asm.
;
; Hush_DrawGuard (JSL, X = sprite slot, M = X = 8 bit; preserves X, DB and P as the caller left them):
;   Palette: OBJ row 4 (SpriteData_OAMProp & $0F, name table 1) or OBJ row 6 while ALERT (Hush_SetPalettes); asleep = calm row.
;   Cells (docs/gfx/art_map.md section 5, tile = $40 + cell index in GFX_BC). The sprite origin (X0, Y0) is the top-left of the 16x16 box;
;   the figure is 16 wide x 24 tall with its feet at the bottom of the box. OAM entries of the guard's 5-entry allocation
;   ($90 = low table, $92 = size / x bit 8 table, one byte per entry):
;     entry 0  HEAD     16x16 at (X0, Y0-8)       head_down $40, head_up $42, head_side $44 (facing left; right = H flip), head_sleep $46
;     entry 1  LANTERN  8x8   at (X0+dx, Y0+dy)   lantern frame 0 / 1 = tile $68 / $69, frame alternates every 12 frames (flicker)
;     entry 2  BODY     16x16 at (X0, Y0)         by facing and walk phase (below)
;     entry 3  ICON     8x8   at (X0+4, Y0-22)    '?' '!' 'Z' = GFX_C5 tiles $FC / $FD / $FE (state + $FB), attribute $29; hidden while UNAWARE
;     entry 4  SHADOW   16x16 at (X0, Y0+$0A/$0C) vanilla shadow (tile $6C, name table 0), exactly what DrawSpriteShadow_custom draws
;   The lower OAM index is in front: head over lantern over body over icon over shadow.
;   Facing = $0DE0 (0 right, 1 left, 2 down, 3 up); pose class f = facing, 4 = asleep.
;   Walk phase = ($0E80 >> 3) & 3 (the AI counts $0E80 only on frames the guard really moved) while the guard moved last frame
;   (velocity $0D40 / $0D50 non-zero), else 0 (standing). Body index p = f * 4 + phase, asleep p = 16.
;   Phases: down / up = A, B, A, B (H flipped); side = A, B, A, C. Lantern offsets: right (13, 6), left (-5, 6), down (10, 6), up (-3, 6),
;   asleep (10, 10) with frame 1 (no flicker).
;
; Culling: GetScreenCoordinates (the vanilla routine) is replaced by the two subtractions $0D30:$0D10 - $E2 and $0D20:$0D00 - $E8
;   (guards never fly: $0F70 = 0). The drawing is exact for X0 in [8, 232) and Y0 in [24, 200): then every part lies completely inside
;   the 256 x 224 screen and x bit 8 is always 0, so no per-part clipping is needed. HUSH guards always are (rooms keep rows 0-1 and 13,
;   columns 0 and 15 walls; a guard stops 14 px before a wall tile: X0 >= 14, <= 226, Y0 >= 30, <= 194). Outside that window the
;   vanilla GetScreenCoordinates runs (it flags / kills a sprite far outside the screen exactly as before) and all five entries are hidden.
; Cost: tests/dev/guard_cost.lua (CPU cycles per guard per frame): vanilla draw 1745, E4 draw: see docs/engine_notes.md 11.12.
;
; Space:    src/FREESPACE.md row $07FD00-$07FFFF (the unclaimed tail of NULL_07F89D, "FREE ROM: 0x763", bank_07.asm:23958)
; =============================================================================

org $07FD00
Hush_DrawGuard:
    PHB : PHK : PLB                      ; DB = $07: the tables below
    LDA.w $0E60,X : AND.b #$0F           ; palette bits (OAMProp low nibble)
    LDY.w $0D80,X : STY.b $0A            ; state: icon, pose
    CPY.b #$02
    BNE +
    AND.b #$F1 : ORA.b #$0C              ; ALERT: palette row 6 = amber
+   STA.w $0F50,X
    EOR.w $0B89,X : STA.b $05            ; attribute bits as GetScreenCoordinates leaves them: palette, name table, layer priority

    LDA.w $0D30,X : XBA : LDA.w $0D10,X  ; screen position of the sprite origin
    REP #$20
    SEC : SBC.b $E2 : STA.b $00
    SEC : SBC.w #$0008 : CMP.w #$00E0    ; X0 in [8, 232)
    BCC .x_ok
    JMP .outside
.x_ok
    SEP #$20
    LDA.w $0D20,X : XBA : LDA.w $0D00,X
    REP #$20
    SEC : SBC.b $E8 : STA.b $02
    SEC : SBC.w #$0018 : CMP.w #$00B0    ; Y0 in [24, 200)
    SEP #$20
    BCC .y_ok
    JMP .outside
.y_ok
    STZ.w $0F00,X                        ; on screen

    STX.b $0B                            ; slot
    CPY.b #$03
    BEQ .asleep
    LDA.w $0DE0,X : AND.b #$03 : STA.b $06           ; pose class f = facing
    ASL A : ASL A : STA.b $07                        ; body index p = f * 4 + phase
    LDA.w $0D40,X : ORA.w $0D50,X
    BEQ .flicker                                     ; did not move last frame: standing, phase 0
    LDA.w $0E80,X : LSR A : LSR A : LSR A : AND.b #$03 : ORA.b $07 : STA.b $07
.flicker
    TXA : ASL A : ASL A : CLC : ADC.b $1A            ; frame counter, staggered by slot
    STA.w $4202 : LDA.b #43 : STA.w $4203            ; * 43 / 512 = / 11.9: bit 0 of the quotient flips every ~12 frames
    LDA.w $0DE0,X : AND.b #$03 : TAY                 ; (fills the 8 cycles the hardware multiplier needs)
    LDA.w Hush_ShadowY,Y : STA.b $09
    LDA.w $4217 : LSR A : AND.b #$01 : CLC : ADC.b #$68 : STA.b $08    ; lantern tile $68 / $69
    BRA .write
.asleep
    LDA.b #$04 : STA.b $06                           ; pose class 4
    LDA.b #$10 : STA.b $07                           ; body index 16
    LDA.b #$69 : STA.b $08                           ; lantern frame 1, no flicker
    LDA.w $0DE0,X : AND.b #$03 : TAY
    LDA.w Hush_ShadowY,Y : STA.b $09

.write
    LDX.b $06                            ; X = f for the head and lantern tables
    LDY.b #$00
    LDA.b $00 : STA.b ($90),Y : INY                  ; entry 0: head
    LDA.b $02 : SEC : SBC.b #$08 : STA.b ($90),Y : INY
    LDA.w Hush_HeadTile,X : STA.b ($90),Y : INY
    LDA.w Hush_HeadFlip,X : ORA.b $05 : STA.b ($90),Y : INY
    LDA.b $00 : CLC : ADC.w Hush_LanternDX,X : STA.b ($90),Y : INY   ; entry 1: lantern
    LDA.b $02 : CLC : ADC.w Hush_LanternDY,X : STA.b ($90),Y : INY
    LDA.b $08 : STA.b ($90),Y : INY
    LDA.b $05 : STA.b ($90),Y : INY
    LDX.b $07                            ; X = p for the body tables
    LDA.b $00 : STA.b ($90),Y : INY                  ; entry 2: body
    LDA.b $02 : STA.b ($90),Y : INY
    LDA.w Hush_BodyTile,X : STA.b ($90),Y : INY
    LDA.w Hush_BodyFlip,X : ORA.b $05 : STA.b ($90),Y : INY
    LDA.b $0A                            ; entry 3: awareness icon
    BEQ .no_icon
    LDA.b $00 : CLC : ADC.b #$04 : STA.b ($90),Y : INY
    LDA.b $02 : SEC : SBC.b #$16 : STA.b ($90),Y : INY
    LDA.b $0A : CLC : ADC.b #$FB : STA.b ($90),Y : INY   ; $FC '?', $FD '!', $FE 'Z' (GFX_C5 tiles 60-62)
    LDA.b #$29 : STA.b ($90),Y : INY                     ; priority 2, palette 4, name table 1 (not recoloured while alert)
    BRA .shadow
.no_icon
    LDY.b #$0D : LDA.b #$F0 : STA.b ($90),Y              ; Y = $F0: not on screen
    LDY.b #$10
.shadow                                  ; entry 4: shadow, as DrawSpriteShadow_custom ($06DC66) draws a not-small one
    LDA.b $00 : STA.b ($90),Y : INY
    LDA.b $02 : CLC : ADC.b $09 : STA.b ($90),Y : INY
    LDA.b #$6C : STA.b ($90),Y : INY
    LDA.b $05 : AND.b #$30 : ORA.b #$08 : STA.b ($90),Y
    LDA.b #$02                                           ; size bytes: x bit 8 = 0 for every part (see Culling)
    LDY.b #$00 : STA.b ($92),Y
    LDY.b #$02 : STA.b ($92),Y
    LDY.b #$04 : STA.b ($92),Y
    LDA.b #$00
    LDY.b #$01 : STA.b ($92),Y
    LDY.b #$03 : STA.b ($92),Y
    LDX.b $0B
    PLB
    RTL

.outside
    SEP #$20
    JSL $06E416                          ; GetScreenCoordinates_long: flags / kills a sprite outside the screen (C = 1)
    LDA.b #$F0                           ; hide the five entries
    LDY.b #$01 : STA.b ($90),Y
    LDY.b #$05 : STA.b ($90),Y
    LDY.b #$09 : STA.b ($90),Y
    LDY.b #$0D : STA.b ($90),Y
    LDY.b #$11 : STA.b ($90),Y
    PLB
    RTL

; Tables (DB = $07). Tiles = $40 + cell index of the block's top-left cell in GFX_BC.
Hush_HeadTile:                           ; by pose class f: right, left, down, up, asleep
    db $44, $44, $40, $42, $46
Hush_HeadFlip:                           ; OAM flip bits: the side head is drawn facing left, right = H flip
    db $40, $00, $00, $00, $00
Hush_LanternDX:                          ; lantern offset from the sprite origin (signed): right, left, down, up, asleep
    db 13, -5, 10, -3, 10
Hush_LanternDY:
    db  6,  6,  6,  6, 10
Hush_BodyTile:                           ; body index p = f * 4 + phase (phases: stand, step, stand, step 2)
    db $60, $62, $60, $64                ; right: side_A, side_B, side_A, side_C (all H flipped)
    db $60, $62, $60, $64                ; left
    db $48, $4A, $48, $4A                ; down: down_A, down_B, down_A, down_B (H flipped)
    db $4C, $4E, $4C, $4E                ; up: up_A, up_B, up_A, up_B (H flipped)
    db $66                               ; asleep: body_sleep
Hush_BodyFlip:
    db $40, $40, $40, $40
    db $00, $00, $00, $00
    db $00, $00, $00, $40
    db $00, $00, $00, $40
    db $00
Hush_ShadowY:                            ; vanilla DrawGuardShadow .shadow_type ($05C69E): right, left, down, up
    db $0C, $0C, $0A, $0A
Hush_Draw_End:
