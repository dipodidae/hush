; =============================================================================
; HOOK: intro_skip  (boot -> title screen, no triforce / sword animation)
;
; Site 1 - Module00_Intro entry
; Address:  $0CC120 (SNES LoROM), PC offset 0x06120, 4 bytes
; Replaces: `LDA.b $11 : CMP.b #$08`   (A5 11 C9 08)
;           vendor/usdasm/bank_0C.asm:15-17 (Module00_Intro; the BCC at $0CC124 follows)
; Does:     JSL IntroSkip. IntroSkip ends with the same LDA/CMP so the vanilla BCC still works.
;
; Site 2 - intro submodule jump table, entry 8
; Address:  $0CC151, 3 bytes
; Replaces: `dl Intro_TrianglesBeforeAttract`  (vendor/usdasm/bank_0C.asm:33)
; Does:     submodule 8 (the title screen, waiting for START) now runs an existing RTL ($0CC2EF) (just RTL):
;           no triforce animation, no logo-sword sprites, and no timeout into the attract scenes.
;           START is still handled by the vanilla check at the top of Module00_Intro
;           ($0CC126-$0CC130: submodule >= 8 and a start/A/B press -> FadeMusicAndResetSRAMMirror).
;
; IntroSkip: the first time the intro reaches submodule 3 (after init) it skips the triforce
;   animation (submodules 3-4) and runs only the PALETTE parts of submodules 5-7 in a loop
;   (logo fade-in, then title-card fade-in) while the screen is force-blanked, then sets $11 = 8,
;   turns the screen on and hides every sprite (HideSprites). The vanilla handlers cannot simply
;   be looped: each one runs the software-3D triforce renderer (about one frame per pass).
;   Callees: IntroLogoPaletteFadeIn $00ED7C, IntroTitleCardPaletteFadeIn $00ED8F (bank_00.asm:13975-13990).
;
; Space:    src/FREESPACE.md rows: hooks $0CC120, $0CC151; free blocks $0CFFB1 (NULL_0CFFB1, 0x4F,
;           bank_0C.asm:9340-9342), $00E852 (NULL_00E852, 0x2E, bank_00.asm:13064) and $0CC10C (NULL_0CC10C, 0x14, bank_0C.asm:6-9); all $FF in vanilla.
; =============================================================================

org $0CC120
    JSL IntroSkip

org $0CC151
    dl $0CC2EF                          ; an existing RTL (Intro_TrianglesBeforeAttract .exit, bank_0C.asm:~318)

org $0CFFB1
IntroSkip:
    SEP #$30
    LDA.b $10 : BNE .out                 ; only inside Module00 (intro)
    LDA.b $11
    CMP.b #$03 : BCC .out                ; submodules 0-2 run as vanilla
    CMP.b #$08 : BCS .out                ; already at the title
    LDA.b #$80 : STA.b $13               ; forced blank while the rest of the intro is applied
    LDA.b #$10 : STA.b $1C               ; end of Intro_TriforceTerminateSpin (bank_0C.asm:704-742): the state the
    LDA.b #$05 : STA.b $1D               ; triforce animation leaves behind for submodule 5
    LDA.b #$02 : STA.b $99
    LDA.b #$31 : STA.b $9A
    STZ.b $B0
    INC.b $15
    LDA.b #$03 : STA.b $14               ; NMI uploads the logo / background tilemaps (stripes)
.fade_logo                               ; submodule 5, Intro_FadeLogoIn core (bank_0C.asm:203-222)
    JSL $00ED7C                          ; IntroLogoPaletteFadeIn: one step, $7EC007--, $15++
    LDA.l $7EC007
    CMP.b #$0D : BNE +
    LDA.b #$15 : STA.b $1C               ; main screen layers
    STZ.b $1D
+   LDA.l $7EC007 : BNE .fade_logo
    JSL FinishTitle
.out
    LDA.b $11 : CMP.b #$08
    RTL

; FinishTitle (free block $00E852): the rest of the intro, then the title is up.
org $00E852
FinishTitle:
    LDA.b #$02 : STA.b $99               ; submodule 6 end state (Intro_SwordStab, bank_0C.asm:285-296)
    LDA.b #$22 : STA.b $9A
    LDA.b #$1F : STA.l $7EC007
    LDA.b #$02 : STA.b $1D
.fade_card                               ; submodule 7, Intro_PopSubtitleCard core (bank_0C.asm:240-251)
    JSL $00ED8F                          ; IntroTitleCardPaletteFadeIn: one step, $7EC007--, $15++
    LDA.l $7EC007 : BNE .fade_card
    LDA.b #$08 : STA.b $11               ; title screen, waiting for START
    LDA.b #$0F : STA.b $13               ; screen on
    JSL HideSprites
    RTL

; HideSprites (free block $0CC10C): Y = $F0 for all 128 OAM buffer entries ($0801,$0805..$09FD).
org $0CC10C
HideSprites:
    REP #$10
    LDX.w #$01FC
    LDA.b #$F0
.next
    STA.w $0801,X
    DEX #4
    BPL .next
    SEP #$10
    RTL
