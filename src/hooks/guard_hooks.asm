; =============================================================================
; HOOK: guard_hooks  (E2: arrows put an unaware guard to sleep, bombs become ink pots)
;
; Site 1 - CheckAncillaDamageToSprite
; Address:  $06ECB7 (SNES LoROM), 5 bytes
; Replaces: `LDY.w $0EF0,X : BPL CheckAncillaDamageToSprite_aggressive`   (BC F0 0E 10 01)
;           vendor/usdasm/bank_06.asm:21177-21180; the `RTL` at $06ECBC and the _aggressive entry $06ECBD stay
; Does:     JML Hush_AncillaHit + NOP. Entered with JSL (callers: arrow / hookshot / bomb collision,
;           Ancilla_CheckSpriteCollision_Single $088E60, Bomb_CheckSpriteDamage $088309): A = ancilla type
;           ($0C4A,X of the ancilla, arrow = $09, bomb = $07), X = sprite slot.
;           For a guard ($41-$43): an ARROW on an UNAWARE guard (state 0) puts it to sleep (state 3, 240 + 240 frames);
;           everything else (suspicious / alert / asleep guard, bomb, ...) does nothing. The caller treats the arrow as
;           having hit something, so the arrow is consumed. Other sprites run the vanilla code (JML _aggressive).
;
; Site 2 - Bomb_CheckSpriteAndPlayerDamage
; Address:  $089815 (SNES LoROM), 5 bytes
; Replaces: `LDA.w $0C5E,X : BEQ .no_damage`   (BD 5E 0C F0 24)   vendor/usdasm/bank_08.asm:5069-5072
;           (JSR'd from Bomb_HandleState $089722 with X = ancilla slot; the rest of the routine hurt sprites and Link)
; Does:     JML Hush_BombHook + NOP. The vanilla damage code is never reached: an explosion hurts neither guards nor
;           Link and does no recoil. Hush_BombHook turns the explosion into an INK CLOUD:
;             * phase $0C5E = 1 (first explosion frame): cloud centre := the bomb position ($0C18:$0C04, $0C0E:$0BFA,
;               the centre of the 48x48 vanilla damage box), timer := 300 frames (hush_ink_t, decremented by Hush_Tick);
;             * phase 8 (the largest explosion frame) is held (the phase timer $039F is kept above 1) while the
;               cloud lives, so the vanilla explosion graphic stays on screen as the visible cloud; when hush_ink_t
;               reaches 0 the ancilla finishes normally (phases 9, 10, gone).
;           Returns with JML to the RTS at EXIT_0897B5 ($0897B5).
;           The bomb count ($7EF343) decreases as in vanilla; Hush_GrantTools refills it on every room load.
;
; Space:    src/FREESPACE.md rows: hooks $06ECB7, $089815; free block $0EFB64 (guard_vision.asm)
; =============================================================================

pushpc
org $06ECB7
    JML Hush_AncillaHit
    NOP
org $089815
    JML Hush_BombHook
    NOP
pullpc

Hush_AncillaHit:
    PHA
    LDA.w $0E20,X
    CMP.b #$41 : BCC .vanilla
    CMP.b #$44 : BCS .vanilla
    PLA                                  ; a guard
    CMP.b #$09 : BNE .done               ; only arrows act
    LDA.w $0D80,X : BNE .done            ; only an UNAWARE guard falls asleep
    LDA.b #$03 : STA.w $0D80,X
    LDA.b #$0B : JSL $0DBB8A             ; E6: SFX3.0B, the soft pickup chime = "he sleeps" (QueueSpriteSFX3WithPan; feedback.asm)
    LDA.b #240 : STA.w $0DF0,X
    LDA.b #$01 : STA.w $0D90,X           ; one more chunk of 240 frames
    STZ.w $0D50,X : STZ.w $0D40,X
.done
    RTL
.vanilla
    PLA
    LDY.w $0EF0,X                        ; the replaced instructions
    BPL .aggressive
    RTL
.aggressive
    JML $06ECBD

Hush_BombHook:
    LDA.w $0C5E,X
    BEQ .rts                             ; the fuse is still burning
    CMP.b #$09 : BCS .rts                ; debris phase
    CMP.b #$01 : BNE .hold
    LDA.w $0C04,X : STA.l !hush_ink_x
    LDA.w $0C18,X : STA.l !hush_ink_x+1
    LDA.w $0BFA,X : STA.l !hush_ink_y
    LDA.w $0C0E,X : STA.l !hush_ink_y+1
    LDA.b #$2C : STA.l !hush_ink_t       ; 300 = $012C
    LDA.b #$01 : STA.l !hush_ink_t+1
    BRA .rts
.hold
    CMP.b #$08 : BNE .rts
    LDA.l !hush_ink_t : ORA.l !hush_ink_t+1 : BEQ .rts
    LDA.b #$02 : STA.w $039F,X           ; keep the big explosion frame on screen while the cloud lives
.rts
    JML $0897B5
Hush_Hooks_End:
assert pc() <= $0EFE00                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
