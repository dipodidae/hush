; =============================================================================
; guard_box.asm  (E7, B-005: the chase wall-slide collision)
; Not a hook: Hush_BoxProbe is called (JSL) from Hush_Step (guard_ai.asm) for ALERT guards only.
;
; Space:    src/FREESPACE.md row $07FEC8-$07FF7F (the tail of the bank-07 NULL block NULL_07F89D "FREE ROM: 0x763", bank_07.asm:23958;
;           all $FF in vanilla ROM, no references in vendor/usdasm)
; =============================================================================

org $07FEC8
; Hush_BoxProbe (B-005): Y = base + direction (0 right, 1 left, 2 down, 3 up; base 8). A = 0 free / 1 blocked, X preserved, M = X = 8 bit, DB = $0E (called with JSL from Hush_Step).
; The vanilla soldier tile test (CheckSpriteTileCollision) probes ONE point per direction (x+8 for up / down, y+13 for left / right):
; at a doorway corner the guard slid along with up to 10 px of his body over the wall column. This tests the leading edge of the
; guard's feet box x+2..x+12, y+6..y+14 (3 probes; spacing <= 5 px < 8 px tile, so no tile column / row is missed) in the $7F2000
; collision map. The box is inside everything the vanilla test allows (patrol stops: x+2 / y+6 up, x+14 / y+20 down are free), so a flat
; wall is still met by the vanilla probe first; only the corners are new. Resting guards overlap a wall by at most 2 px.
Hush_BoxProbe:
    PHX
    TYA : AND.b #$03 : ASL A : ASL A : STA.b $08 ; table row (4 bytes per direction)
    LDA.w $0D30,X : XBA : LDA.w $0D10,X
    REP #$20 : STA.b $00 : SEP #$20              ; guard x
    LDA.w $0D20,X : XBA : LDA.w $0D00,X
    REP #$20 : STA.b $02 : SEP #$20              ; guard y
    LDX.b $08
    LDA.l Hush_BoxTab,X   : STA.b $04            ; first probe: x offset, y offset, step x, step y
    LDA.l Hush_BoxTab+1,X : STA.b $05
    LDA.l Hush_BoxTab+2,X : STA.b $06
    LDA.l Hush_BoxTab+3,X : STA.b $07
    REP #$30
    LDA.b $04 : AND.w #$00FF : CLC : ADC.b $00 : STA.b $00
    LDA.b $05 : AND.w #$00FF : CLC : ADC.b $02 : STA.b $02
    LDA.b $06 : AND.w #$00FF : STA.b $04
    LDA.b $07 : AND.w #$00FF : STA.b $06
    LDY.w #$0003
.probe
    LDA.b $02 : AND.w #$01F8 : ASL A : ASL A : ASL A : STA.b $08      ; row * 64
    LDA.b $00 : AND.w #$01FF : LSR A : LSR A : LSR A
    CLC : ADC.b $08 : TAX
    SEP #$20
    LDA.l $7F2000,X
    BNE .blocked
    REP #$20
    LDA.b $00 : CLC : ADC.b $04 : STA.b $00
    LDA.b $02 : CLC : ADC.b $06 : STA.b $02
    DEY
    BNE .probe
    SEP #$30
    PLX
    LDA.b #$00
    RTL
.blocked
    SEP #$30
    PLX
    LDA.b #$01
    RTL

Hush_BoxTab:                             ; per direction: first probe (dx, dy) from the guard origin, step (sx, sy) of the other two probes
    db 12, 6, 0, 4                       ; right: x+12, y+6 / 10 / 14
    db  2, 6, 0, 4                       ; left
    db  2,14, 5, 0                       ; down:  y+14, x+2 / 7 / 12
    db  2, 6, 5, 0                       ; up:    y+6
Hush_Box_End:
assert pc() <= $07FF80                       ; the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
