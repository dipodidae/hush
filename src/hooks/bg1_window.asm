; =============================================================================
; HOOK: bg1_window  (SA-1 step 5a: the light window is one contiguous VRAM block; assembled only with !LIGHT_WIN0 = 1, light.asm)
; Address:  $008188 (SNES LoROM), PC offset 0x00188, 6 bytes, NoIRQThread in the NMI; and $008279, PC offset 0x00279, 6 bytes, the
;           second copy in SwitchThread
; Replaces: `LDA.w $0120 : STA.w BG1HOFS` (AD 20 01 8D 0D 21), vendor/usdasm/bank_00.asm:350-351 ($008188) and :506-507 ($008279).
;           The rest of the BG1 scroll block (`LDA $0121 : STA BG1HOFS : LDA $0124 : STA BG1VOFS : LDA $0125 : STA BG1VOFS`,
;           bank_00.asm:353-360 / :509-516, up to $00819F / $008290) is jumped over and stays in the ROM unchanged.
; Does:     `JSL Hush_NmiBg1 : BRA +$12` (to $0081A0 / $008291, the BG2HOFS write). Hush_NmiBg1 writes BG1HOFS / BG1VOFS. In a HUSH
;           room (module 7, or module $0E over it) BG1 holds only the light (light.asm), and its window moves from tilemap tiles
;           16..47 x 18..45 to tiles 0..31 x 0..27 of the top-left screen (VRAM words $1000-$137F, 1792 contiguous bytes): the PPU gets
;           $0120 - 128 and $0124 - 144 ($E0 / $E6 = room base + 128 / + 144, base a multiple of 512 = the 64 x 64 tilemap width:
;           docs/engine_notes.md section 1, "Camera" row; camera_lock.asm keeps them). The shake offsets $011A / $011C are part of $0120 /
;           $0124 (bank_02.asm:1441-1455), so the light still shakes with BG2. Every other module (title, ending, loads): the vanilla values.
;           $0120 / $0124 themselves are not changed (a lag frame's NMI writes the same values again).
; Space:    src/FREESPACE.md rows $008188-$00818D, $008279-$00827E (hooks), $02C4C0-$02C4FF (Hush_NmiBg1; NULL_02C4C0 "FREE ROM: 0x40",
;           bank_02.asm:12603-12613: all $FF in the listing; grep of vendor/usdasm finds only the label, no `$02C4Cx-Fx` operand)
; =============================================================================

if !LIGHT_WIN0
pushpc
org $008188
    JSL Hush_NmiBg1
    db $80, $0081A0-($00818C+2)          ; BRA to the BG2HOFS write
org $008279
    JSL Hush_NmiBg1
    db $80, $008291-($00827D+2)
pullpc

pushpc
org $02C4C0
; Hush_NmiBg1: JSL from the NMI (M = 8: `SEP #$30`, bank_00.asm:235; DB = $00: `PHK : PLB`, :232-233). Returns M = 8; uses A only
; (the vanilla code after the hook reloads A). 64 bytes: no PHP / PLP (M is 8 on entry and on exit, the flags are not used after).
Hush_NmiBg1:
    REP #$20
    LDA.w $0120 : PHA                    ; 3,S = BG1 H
    LDA.w $0124 : PHA                    ; 1,S = BG1 V
    SEP #$20
    LDA.b $10 : CMP.b #$07 : BEQ +       ; module 7 runs only HUSH rooms, after Hush_LightInit (light_on is then always 1, not read:
    CMP.b #$0E : BNE .w                  ; 64 bytes); module $0E (item menu / text box) is entered only from module 7
+   REP #$20
    LDA $03,S : SEC : SBC.w #128 : STA $03,S
    LDA $01,S : SEC : SBC.w #144 : STA $01,S
.w  SEP #$20
    PLA : STA.w $210E : PLA : STA.w $210E                         ; BG1VOFS low, high
    PLA : STA.w $210D : PLA : STA.w $210D                         ; BG1HOFS low, high
    RTL
Hush_NmiBg1_End:
assert pc() <= $02C500                   ; src/FREESPACE.md row $02C4C0-$02C4FF
pullpc
endif
