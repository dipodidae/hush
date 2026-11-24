; =============================================================================
; HOOK: anim_skip  (SA-1 step 4: vblank time for the light rows)
; Address:  $008B50 (SNES LoROM), PC offset 0x00B50, 6 bytes, in DoNMIUpdates (NMI)
; Replaces: `LDX.w $0ADC : STX.w DMA0ADDRL`   (AE DC 0A 8E 02 43)   vendor/usdasm/bank_00.asm:1935-1937
;           (.no_update_swagduck: the first two instructions of the per-frame animated-tile upload, bank_00.asm:1935-1946:
;           $400 bytes from [$0ADC] to VRAM word [$0134] by DMA channel 0, every NMI with $0710 = 0)
; Does:     `JML Hush_AnimGate : NOP : NOP`. In module 7 (a HUSH room) while light rows wait for the NMI (light_dirty != 0) the upload is
;           skipped (JML to .skip_sprite_updates, $008B67, bank_00.asm:1950); otherwise the two replaced instructions run and the upload
;           follows as before ($008B56). (Skipping it in every room frame left slot 7 different after a fast and a full room load:
;           tests/smoke/transition.lua compares all of VRAM; with the gate the upload resumes as soon as the light is idle.)
;           Why it is useless in a room: $0134 = $3C00 there (Hush_LightChrUp, light.asm), i.e. BG tiles $1C0-$1DF = slot 7, which no
;           room draws (docs/gfx/art_map.md 2.1: "slot 7 ... drawn by the rooms? no", verified by decoding every VRAM cell); vanilla
;           would put it at $3B00 (DecompressAnimatedUnderworldTiles, bank_00.asm:9365) over the light tiles. Saves $400 bytes of NMI DMA
;           (~6 scanlines of vblank) for the light rows (light.asm LIGHT_NMIROWS).
; Space:    src/FREESPACE.md rows $008B50-$008B55 (hook) and $03EB80-$03EB9F (Hush_AnimGate; the tail of NULL_03EB05,
;           bank_03.asm:4559-4581: all $FF in the vanilla listing, no reference in vendor/usdasm)
; =============================================================================

pushpc
org $008B50
    JML Hush_AnimGate
    NOP : NOP
pullpc

pushpc
org $03EB80
; Hush_AnimGate: JML from $008B50 (NMI: M = 8, X = 16 after `REP #$10`, bank_00.asm:1746; DB = $00, D = $0000). A is free here (the next
; instructions load it: `LDA.b #$01` at $008B62, `LDA.b $16` at $008B67).
Hush_AnimGate:
    LDA.b $10 : CMP.b #$07 : BNE .run    ; not a room: as vanilla
    LDA.l !LB+!L_DIRTY : ORA.l !LB+!L_DIRTY+1 : BNE .skip  ; light rows wait for this NMI (light_dirty, bits 14 / 15 never set): no upload
.run
    LDX.w $0ADC : STX.w $4302            ; the replaced instructions (DMA0ADDRL = $4302)
    JML $008B56                          ; `LDX.w $0134` ...
.skip
    JML $008B67                          ; .skip_sprite_updates
Hush_AnimGate_End:
assert pc() <= $03EBA0                   ; src/FREESPACE.md row $03EB80-$03EB9F
pullpc
