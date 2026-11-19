; =============================================================================
; guard_vision.asm  (E2: geometry, cone + range + line-of-sight vision, ink cloud test)
; Not a hook: routines called (JSL) from guard_ai.asm. They live in the second free block of bank $0E.
;
; Space:    src/FREESPACE.md row $0EFB64 (NULL_0EFB64, "FREE ROM: 0x049C", bank_0E.asm:13307; all $FF in vanilla ROM,
;           no references in vendor/usdasm)
;
; Direct page scratch ($00-$0F) is free between vanilla calls; every routine here is a leaf (no vanilla call).
; The sprite slot X is preserved. Called with M = X = 8 bit, DB = $0E.
; =============================================================================

org $0EFB64

; Hush_Geom: guard -> Link vectors in WRAM pixels (the guard centre is its origin + (8, 8); Link's collision box centre
; is (x + 8, y + 16), docs/engine_notes.md section 1).
;   $00 dx = Lx - Gx  (centre to centre)   $02 dy = (Ly + 16) - (Gy + 8)   (16-bit, signed)
;   $04 |dx|   $06 |dy|   $08 Gx + 8   $0A Gy + 8
Hush_Geom:
    LDA.w $0D30,X : XBA : LDA.w $0D10,X
    REP #$20
    STA.b $08
    LDA.b $22 : SEC : SBC.b $08 : STA.b $00
    LDA.b $08 : CLC : ADC.w #$0008 : STA.b $08
    SEP #$20
    LDA.w $0D20,X : XBA : LDA.w $0D00,X
    REP #$20
    STA.b $0A
    LDA.b $20 : CLC : ADC.w #$0008 : SEC : SBC.b $0A : STA.b $02
    LDA.b $0A : CLC : ADC.w #$0008 : STA.b $0A
    %abs16($00, $04)
    %abs16($02, $06)
    SEP #$20
    RTL

; Hush_Vision: A = mode. C = 1: the guard sees Link (mode 0, 1) / the line is free of ink (mode 2).
;   mode 0  90-degree cone in front of the guard ($0DE0: 0 right, 1 left, 2 down, 3 up), range, line of sight
;   mode 1  the same without the cone (an investigating or alerted guard senses all around)
;   mode 2  only the ink cloud: no range, no cone, no tiles (is the line / the guard covered by the cloud?)
;   mode 3  (B-003) only the tiles: no range, no cone, no cloud. Used by Hush_SwordCheck: C = 0 when a solid tile lies between
;           the guard centre and Link's centre, so the knife does not kill through a wall
; Range = max(|dx|, |dy|) <= hush_range (80 px dark rooms, 128 px lit rooms; Hush_Tick sets it from the room table).
; Same layer as Link ($0F20,X = $EE). Line of sight: samples every 8 px along the major axis from the guard centre to
; Link ($7F2000 collision map: any non-zero tile blocks, docs/engine_notes.md section 3) and tests the ink cloud box
; (|px - cx| <= 24 and |py - cy| <= 24) at every sample (also at the guard itself).
Hush_Vision:
    PHA
    JSL Hush_Geom
    PLA : STA.b $0E
    BRA .start
.no16
    SEP #$20
.no
    CLC
    RTL
.yes
    SEC
    RTL
.start
    LDA.w $0F20,X : CMP.b $EE : BNE .no
    LDA.b $0E : CMP.b #$02 : BNE .full       ; (mode 3 takes the full path too)
    LDA.l !hush_ink_t : ORA.l !hush_ink_t+1
    BEQ .yes                             ; no cloud: the line is clear
.full
    REP #$20
    LDA.b $04 : CMP.b $06 : BCS .major
    LDA.b $06
.major
    STA.b $0C                            ; major = max(|dx|, |dy|)
    SEP #$20
    LDA.b $0E : CMP.b #$02 : BCS .los
    REP #$20
    LDA.l !hush_range : CMP.b $0C : BCC .no16
    SEP #$20
    LDA.b $0E : BNE .los                 ; mode 1: no cone
    LDA.w $0DE0,X : CMP.b #$02 : BCS .vertical
    REP #$20 : LDA.b $04 : CMP.b $06 : SEP #$20
    BCC .no                              ; facing left/right needs |dx| >= |dy|
    LDA.w $0DE0,X : BNE .left
    LDA.b $01 : BMI .no                  ; right: dx >= 0
    BRA .los
.left
    LDA.b $01 : BPL .no                  ; left: dx < 0
    BRA .los
.vertical
    REP #$20 : LDA.b $06 : CMP.b $04 : SEP #$20
    BCC .no                              ; facing up/down needs |dy| >= |dx|
    LDA.w $0DE0,X : CMP.b #$03 : BEQ .up
    LDA.b $03 : BMI .no                  ; down: dy >= 0
    BRA .los
.up
    LDA.b $03 : BPL .no                  ; up: dy < 0

.los
    PHX                                  ; the sprite slot (8 bit push)
    REP #$20
    LDA.b $0C : BEQ .norate
    LDA.b $06 : PHA
    LDA.b $04 : XBA : STA.w $4204        ; |dx| * 256 / major  (hardware divider, 8.8 fixed point, <= $100)
    SEP #$20 : LDA.b $0C : STA.w $4206
    JSR .wait
    REP #$20 : LDA.w $4214 : ASL A : ASL A : ASL A : STA.b $04   ; step per sample: $04 fraction, $05 whole pixels
    PLA : XBA : STA.w $4204
    SEP #$20 : LDA.b $0C : STA.w $4206
    JSR .wait
    REP #$20 : LDA.w $4214 : ASL A : ASL A : ASL A : STA.b $06   ; $06 fraction, $07 whole pixels
    BRA .go
.norate
    STZ.b $04 : STZ.b $06
.go
    REP #$10
    LDA.b $0C : LSR A : LSR A : LSR A : TAY      ; Y = number of 8 px steps
    STZ.b $0C                                    ; $0C / $0D: sub-pixel accumulators
    BRA .loop
.clear
    SEP #$30
    PLX
    SEC
    RTL
.blocked
    SEP #$30
    PLX
    CLC
    RTL
.loop
    LDA.b $0E : AND.w #$00FF : CMP.w #$0003 : BEQ .nocloud   ; mode 3 (sword) ignores the cloud
    LDA.l !hush_ink_t : BEQ .nocloud
    LDA.b $08 : SEC : SBC.l !hush_ink_x : BPL .cx : EOR.w #$FFFF : INC A
.cx
    CMP.w #$0019 : BCS .nocloud
    LDA.b $0A : SEC : SBC.l !hush_ink_y : BPL .cy : EOR.w #$FFFF : INC A
.cy
    CMP.w #$0019 : BCS .nocloud
    BRA .blocked
.nocloud
    SEP #$20
    LDA.b $0E : CMP.b #$02 : BEQ .next       ; mode 2 = cloud only: no tile test (modes 0, 1, 3 test the tiles)
    REP #$20
    LDA.b $0A : AND.w #$01F8 : ASL A : ASL A : ASL A : PHA      ; row * 64
    LDA.b $08 : AND.w #$01FF : LSR A : LSR A : LSR A
    CLC : ADC.b $01,S : TAX
    PLA
    SEP #$20
    LDA.l $7F2000,X : BNE .blocked
.next
    CPY.w #$0000 : BEQ .clear
    DEY
    LDA.b $0C : CLC : ADC.b $04 : STA.b $0C
    LDA.b $05 : ADC.b #$00 : STA.b $0F
    LDA.b $01 : BMI .xneg
    LDA.b $08 : CLC : ADC.b $0F : STA.b $08 : LDA.b $09 : ADC.b #$00 : STA.b $09
    BRA .ystep
.xneg
    LDA.b $08 : SEC : SBC.b $0F : STA.b $08 : LDA.b $09 : SBC.b #$00 : STA.b $09
.ystep
    LDA.b $0D : CLC : ADC.b $06 : STA.b $0D
    LDA.b $07 : ADC.b #$00 : STA.b $0F
    LDA.b $03 : BMI .yneg
    LDA.b $0A : CLC : ADC.b $0F : STA.b $0A : LDA.b $0B : ADC.b #$00 : STA.b $0B
    BRA .again
.yneg
    LDA.b $0A : SEC : SBC.b $0F : STA.b $0A : LDA.b $0B : SBC.b #$00 : STA.b $0B
.again
    REP #$20
    JMP .loop

.wait                                    ; the divider needs 16 machine cycles
    NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP
    RTS
Hush_Vision_End:
