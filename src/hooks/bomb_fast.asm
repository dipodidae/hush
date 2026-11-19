; =============================================================================
; HOOK: bomb_fast  (E7, B-006: the held ink cloud costs 2250 CPU cycles per frame per pot, ~14 scanlines)
;
; Address:  $08955A (SNES LoROM), 4 bytes: the first two instructions of Ancilla07_Bomb (the bomb ancilla main routine)
; Replaces: `LDA.b $11 : BEQ .main`   (A5 11 F0 30)   vendor/usdasm/bank_08.asm:4515-4518 ($08955A-$08955D; .main = $08958E, the
;           next instruction $08955E `CMP.b #$08 : BEQ .staircase` is the non-zero-submodule path, kept)
; Does:     JML Hush_BombEntry. For a bomb in its HELD explosion frame (phase $0C5E = 8 while the cloud lives, hush_ink_t != 0;
;           guard_hooks.asm Hush_BombHook keeps $039F = 2 to hold it) the vanilla routine does, every frame for 300 frames,
;               Ancilla_HandleLiftLogic, Ancilla_LatchYCoordToZ, Ancilla_CheckTileCollision_Class2 (tile types, conveyor, pit, water),
;               the state decrement and the draw
;           although the bomb lies still: its Y is put back by Ancilla_SetYFrom_DP72, Link cannot carry it any more, and the only effect of
;           the state code is `$039F := 2, DEC $039F` = 1 (Hush_BombHook + the timer decrement). Hush_BombEntry does exactly that:
;           `$039F := 1` and the draw (AncillaDraw_Bomb, then RTS to EXIT_0897B5), skipping the rest. Every other case (fuse burning,
;           explosion frames 1-7, 9-10, cloud over, non-zero submodule) takes the vanilla path unchanged.
; Verified:  tests/dev/pot_oam_diff.lua (OAM buffer + ancilla RAM per frame, vanilla path vs this hook, 3 rooms): OAM identical; the ancilla RAM differs only in
;           $0C68,X (the pit / water re-entry guard of the bomb's own tile code; it is 0 or 2 on floor tiles, nothing reads it on floor).
; Cost:     tests/dev/lag_profile.lua (B-006 replay): see docs/engine_notes.md section 15.
;
; Space:    src/FREESPACE.md rows: hook $08955A-$08955D; free $07FF80-$07FFA9 (the tail of NULL_07F89D "FREE ROM: 0x763", bank_07.asm:23958;
;           all $FF in vanilla ROM, no references in vendor/usdasm)
; =============================================================================

pushpc
org $08955A
    JML Hush_BombEntry
pullpc

org $07FF80
Hush_BombEntry:
    LDA.b $11
    BEQ .play
    JML $08955E                          ; the vanilla non-zero-submodule path
.play
    LDA.w $0C5E,X
    CMP.b #$08
    BNE .vanilla                         ; only the largest explosion frame is held
    LDA.l !hush_ink_t
    ORA.l !hush_ink_t+1
    BEQ .vanilla                         ; the cloud is over: the explosion finishes as in vanilla
    LDA.b #$01
    STA.w $039F,X                        ; what Hush_BombHook (:= 2) and the timer decrement leave
    PEA.w $0897B4                        ; AncillaDraw_Bomb's RTS lands on the RTS at EXIT_0897B5 ($0897B5) = the caller
    JML $089E9E                          ; AncillaDraw_Bomb
.vanilla
    JML $08958E                          ; .main
Hush_BombFast_End:
assert pc() <= $07FFAA                       ; the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
