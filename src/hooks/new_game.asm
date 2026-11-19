; =============================================================================
; HOOK: new_game  (title START -> new file -> room 1, no file select / name entry / intro)
;
; Address:  $0CC130 (SNES LoROM), 3 bytes, in Module00_Intro
; Replaces: `JMP.w FadeMusicAndResetSRAMMirror`   (4C F0 C2)  vendor/usdasm/bank_0C.asm:19-24, 328
;           (the START/A/B/X/Y check at $0CC126-$0CC12E decides to leave the title screen)
; Does:     JMP.w Hush_TitleStart ($0CC110, inside the A0 block $0CC10C, see intro_skip.asm), which
;           JSL Hush_NewGame and RTLs back to the main loop exactly like the vanilla JMP target would.
;
; Hush_NewGame: JSL FadeMusicAndResetSRAMMirror ($0CC2F0: fades the music, clears $20-$8F and the whole
;   save mirror $7EF000-$7EF4FF, $10=1,$11=0,$04AA=1), then writes the start file straight into the
;   mirror (no SRAM slot is touched): 3 hearts ($7EF36C/$7EF36D = $18), $7EF3C5 = 2 (non-zero: EntranceData
;   X/Y are honoured and the bed cutscene is skipped, bank_02.asm:15607 and :549; >= 2: no rain ambience, bank_02.asm:586-607), everything else 0
;   (no items: Hush_GrantTools adds the tools of the room). It also repeats the non-SRAM part of vanilla
;   CopySaveToWRAM (HUD VRAM destination $0219 etc.). Then Hush_LoadRoom(0) sets Module05.
;
; Hush_HideSprites: the former HideSprites of the A0 title (intro_skip.asm); moved out of the A0 block
;   to make room for Hush_TitleStart. Y = $F0 for all 128 OAM buffer entries ($0801,$0805..$09FD).
;
; Space:    src/FREESPACE.md rows: hook $0CC130; A0 block $0CC10C (intro_skip.asm); free block $07FA00.
; =============================================================================

org $0CC130
    JMP.w Hush_TitleStart

org $07FA00
Hush_NewGame:
    JSL $0CC2F0                          ; FadeMusicAndResetSRAMMirror
    SEP #$30
    LDA.b #$18
    STA.l $7EF36C                        ; health capacity: 3 hearts
    STA.l $7EF36D                        ; health
    LDA.b #$02
    STA.l $7EF3C5                        ; game phase 2: X/Y honoured, no bed cutscene, NO rain SFX (<2 plays it)
    STZ.w $04AA
    ; what CopySaveToWRAM ($0CCFBB, bank_0C.asm:2636-2750) sets up besides copying the SRAM slot:
    ; the HUD upload destination ($0219 = VRAM $C080: without it the NMI writes the HUD buffer to VRAM $0000, i.e. into the BG2 tilemap)
    LDX.b #$0F
    LDA.b #$00
.clear_1ab0
    STA.l $001AC0,X : STA.l $001AE0,X
    STA.l $001AB0,X : STA.l $001AD0,X : STA.l $001AF0,X
    DEX
    BPL .clear_1ab0
    REP #$20
    LDA.w #$0007 : STA.l $7EC00D : STA.l $7EC013
    LDA.w #$0000 : STA.l $7EC00F : STA.l $7EC015
    LDA.w #$6040 : STA.w $0219           ; VRAM $C080 (BG3 HUD tilemap)
    LDA.w #$4841 : STA.w $021D
    LDA.w #$007F : STA.w $021F
    LDA.w #$FFFF : STA.w $0221
    SEP #$20
    LDA.b #$80 : STA.w $0204
    STZ.w $0710
    STZ.w $0AB2
    LDA.b #$00
    STA.l !hush_req
    JSL Hush_LoadRoom                    ; A = 0: room 1, Module05
    RTL

Hush_HideSprites:
    REP #$10
    LDX.w #$01FC
    LDA.b #$F0
.next
    STA.w $0801,X
    DEX #4
    BPL .next
    SEP #$10
    RTL
