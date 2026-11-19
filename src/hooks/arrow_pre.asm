; =============================================================================
; HOOK: arrow_pre  (E7, B-006: an arrow in flight tests all sprites; a coarse distance test saves the hitbox set-up for the far guards)
;
; Address:  $088DAE (SNES LoROM), 4 bytes: the entry of Ancilla_CheckSpriteCollision_Single (called once per active sprite by
;           Ancilla_CheckSpriteCollision for every arrow, X = ancilla slot, Y = sprite slot, M = X = 8 bit)
; Replaces: `JSR Ancilla_SetupHitbox : PHY`   (20 AD 8E 5A)   vendor/usdasm/bank_08.asm:2900ff ($088DAE-$088DB1; the next instruction
;           $088DB2 is `PHX`)
; Does:     JML Hush_AncPre. For an ARROW (ancilla $09) and a GUARD (sprite $41-$43) whose position differs from the arrow's by 32 px or
;           more in x or in y it returns `CLC : RTS` (`.no_collision`, $088E73) at once, which is the result the full test gives: the arrow
;           box is `x+4 .. x+11` x `y+4 .. y+11` ($088E7D, direction 0-3), the guard box `x+2 .. x+13` x `y-3 .. y+13` (SpriteData_Hitbox $12:
;           offset 2 / -3, width 12, height 17, SpriteHitbox tables $06F72F ff), so they can only overlap within about 10 px.
;           Everything else (near guards, other sprites, other ancillae) runs the replaced instructions and continues at $088DB2.
; Cost:     the vanilla SetupHitbox + SetupSpriteHitbox + CheckIfHitboxesOverlap = ~250 CPU cycles per sprite and arrow and frame;
;           the coarse test ~90. tests/dev/lag_profile.lua; docs/engine_notes.md section 15.
;
; Space:    src/FREESPACE.md rows: hook $088DAE-$088DB1; free $07FA98-$07FAFF (the unused tail of the new_game block in NULL_07F89D "FREE ROM: 0x763", bank_07.asm:23958;
;           all $FF in vanilla ROM, no references in vendor/usdasm)
; =============================================================================

pushpc
org $088DAE
    JML Hush_AncPre
pullpc

org $07FA98
Hush_AncPre:
    LDA.w $0C4A,X
    CMP.b #$09
    BNE .vanilla                         ; arrows only
    LDA.w $0E20,Y
    CMP.b #$41 : BCC .vanilla
    CMP.b #$44 : BCS .vanilla            ; guards only ($41-$43)
    LDA.w $0D30,Y : XBA : LDA.w $0D10,Y  ; sprite x
    REP #$20 : STA.b $00 : SEP #$20
    LDA.w $0C18,X : XBA : LDA.w $0C04,X  ; arrow x
    REP #$20 : SEC : SBC.b $00
    CLC : ADC.w #$0020                   ; dx + 32 outside 0..63 (unsigned) = |dx| >= 32
    CMP.w #$0040
    BCS .reject
    SEP #$20
    LDA.w $0D20,Y : XBA : LDA.w $0D00,Y  ; sprite y
    REP #$20 : STA.b $00 : SEP #$20
    LDA.w $0C0E,X : XBA : LDA.w $0BFA,X  ; arrow y
    REP #$20 : SEC : SBC.b $00
    CLC : ADC.w #$0020                   ; dx + 32 outside 0..63 (unsigned) = |dx| >= 32
    CMP.w #$0040
    BCS .reject
    SEP #$20
.vanilla
    PHY                                  ; the replaced `JSR Ancilla_SetupHitbox : PHY`, in the other order (SetupHitbox keeps Y)
    PEA.w $088DB1                        ; its RTS lands on $088DB2
    JML $088EAD                          ; Ancilla_SetupHitbox
.reject
    SEP #$20
    JML $088E73                          ; .no_collision: CLC : RTS
Hush_AncPre_End:
assert pc() <= $07FB00
