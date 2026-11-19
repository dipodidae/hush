; =============================================================================
; feedback.asm (E6): room music, the "caught" flash, sound-effect notes
;
; Not a hook (no vanilla bytes changed here): routines JSL'd from room_ctrl / transition / guard_runtime / guard_ai.
; Space: free block $07FC40-$07FCFF (the end of the unclaimed NULL_07F89D tail, bank_07.asm:23958; all $FF), ledger row src/hooks/feedback.asm.
;
; Sound effects (vanilla ids only; each is the sound the vanilla code plays for a comparable event, docs/engine_notes.md section 14):
;   notice '?'      SFX2.3C $012E via QueueSpriteSFX2WithPan ($0DBB7C)  the short bleep of PotionShopBeep (bank_05.asm:21896) / ArcheryGameTarget (:880)
;   alert '!'       SFX3.04 $012F via QueueSpriteSFX3WithPan ($0DBB8A)  the soldier's own "noticed you" whistle, Guard_InPursuit (bank_05.asm:12626) / BoltGuard (:13559)
;   knife takedown  SFX3.08 $012F via QueueSpriteSFX3WithPan            default "sprite takes a hit" sound, ApplyDamageToSprite (bank_06.asm:21559-21570)
;   dart sleep      SFX3.0B $012F via QueueSpriteSFX3WithPan            the soft pickup chime (hearts / ammo / fairy refill table)
;   caught          SFX2.26 $012E direct                                Link's hurt cry (bank_07.asm:153-156)
;   room cleared    SFX3.1B $012F direct                                the secret / door-unlock chime of RoomTag_OperateKillDoor (bank_01.asm:12737) etc. (28 uses)
;   $012D / $012E / $012F are the three SFX channels sent to the APU ports $2141 / $2142 / $2143 by the NMI (bank_00.asm:263-291); $012C is the song.
;
; Music: Hush_RoomMusic starts the song of the entrance row ($0132; roomgen writes the floor song on the first room of a floor, $FF elsewhere = keep playing).
; =============================================================================

!hush_cmsave = $7EC919                   ; 5 bytes: $99 $9A $9C $9D $9E saved by Hush_FlashBegin

org $07FC40
; Hush_RoomMusic: JSL (M = X = 8). Called when a room's fade-in ends (Hush_Wipe).
Hush_RoomMusic:
    LDA.w $0132
    CMP.b #$FF
    BEQ .keep
    STA.w $012C                          ; the NMI sends it to APUIO0 (bank_00.asm:239-262) and keeps the id in $0133 / $0130
.keep
    RTL

; Hush_FlashBegin: JSL from Hush_FastRestart. Saves the colour-math registers, arms the 6-frame counter.
Hush_FlashBegin:
    LDA.b $99 : STA.l !hush_cmsave+0
    LDA.b $9A : STA.l !hush_cmsave+1
    LDA.b $9C : STA.l !hush_cmsave+2
    LDA.b $9D : STA.l !hush_cmsave+3
    LDA.b $9E : STA.l !hush_cmsave+4
    LDA.b #$06 : STA.l !hush_flash       ; Hush_Tick counts it down; 5 frames of flash, the 6th restores
    RTL

; Hush_FlashStep: JSL from Hush_Tick with A = frames left after the decrement (5..1 flash, 0 = end).
; Colour math: CGWSEL $99 = 0 (fixed colour), CGADSUB $9A = $3B (add the fixed colour to BG1, BG2, OBJ and the backdrop, not the HUD layer).
Hush_FlashStep:
    CMP.b #$00
    BEQ .end
    DEC A : STA.b $00
    ASL A : CLC : ADC.b $00 : TAX        ; (A - 1) * 3
    LDA.b #$00 : STA.b $99
    LDA.b #$3B : STA.b $9A
    LDA.l Hush_FlashTab,X     : ORA.b #$20 : STA.b $9C
    LDA.l Hush_FlashTab+1,X   : ORA.b #$40 : STA.b $9D
    LDA.l Hush_FlashTab+2,X   : ORA.b #$80 : STA.b $9E
    RTL
.end
    LDA.l !hush_cmsave+0 : STA.b $99
    LDA.l !hush_cmsave+1 : STA.b $9A
    LDA.l !hush_cmsave+2 : STA.b $9C
    LDA.l !hush_cmsave+3 : STA.b $9D
    LDA.l !hush_cmsave+4 : STA.b $9E
    LDA.b #$0F : STA.b $13
    RTL

Hush_FlashTab:                           ; R, G, B (0-31) for 1..5 frames left: a white-amber flash that decays
    db  4,  3,  1
    db  8,  7,  3
    db 14, 12,  6
    db 22, 18,  9
    db 31, 26, 12

; Hush_SaveLink (E7): Link's x / y at the very end of a gameplay frame (JSL from Hush_Refills, hook $028856: after Link moved and the guards ran) -> hush_lx / hush_ly;
; Hush_Solid undoes a move into a sleeping guard by putting Link back there. Keeps P.
Hush_SaveLink:
    PHP
    REP #$20
    LDA.b $20 : STA.l !hush_ly
    LDA.b $22 : STA.l !hush_lx
    PLP
    RTL
Hush_Feedback_End:
assert pc() <= $07FD00                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
