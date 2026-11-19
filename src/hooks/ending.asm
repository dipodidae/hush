; =============================================================================
; HOOKS: ending  (E6: the ending screen after the last room, run statistics, SELECT disabled)
;
; After the last room's exit (Hush_FrameHook -> Hush_StartAdvance($FF) -> fade-out, transition.asm) the game used to soft-reset to the title. Now it runs
; a small module of its own:
;
; Hook 1  $008074 / $008090 / $0080AC (1 byte each): RunModule's jump table entry for module $13 (Module13_PendantBossVictory; low / high / bank byte tables,
;         bank_00.asm:61-137, `db <Module13...`, `db >...`, `db ^...` = $4A, $9C, $02, i.e. $029C4A). HUSH has no bosses and never runs module $13 -> Hush_EndingModule.
;         (Module0C / 0D, although labelled "Unused" in the disassembly, are the palette filter / mosaic modules and are not free.)
; Hook 2  $02891E (1 byte): Module07_00_PlayerControl `LDA.b $F0 : AND.b #$20 : BEQ .no_SELECTing` (A5 F0 29 20 F0 26, bank_02.asm:1665-1668): the immediate $20 (SELECT held) -> $00.
;         SELECT no longer opens the vanilla "save / continue" message box (engine_notes section 10); START still opens the item menu.
;
; Hush_BeginEnding (JSL from Hush_Wipe when the last fade-out ends): module := $13, submodule state $B0 := 0.
; Hush_EndingModule (module $13; $B0 = state):
;   0 init   forced blank; screen registers (no windows / colour math, main screen = BG3 only, black fixed colour); `$16` := 0 (the NMI must not upload the HUD buffer over
;            the text); TransferFontToVRAM ($00E556, bank_00.asm:12364: the 2bpp dialogue font to VRAM word $7000 = BG3 character base, the HUD tile graphics are replaced);
;            tile $FF (the bottom half of glyph code $7F, never drawn) zeroed = a guaranteed blank tile; BG3 tilemap (word $6000, 32 x 32) cleared; the text lines; song $13
;            (Song13_Fanfare: the dungeon-prize / Ganon-defeat fanfare, bank_09.asm:1952 and :20151) -> state 1
;   1 fade-in  $13 := 1 .. 15 (15 frames) -> state 2
;   2 wait   "PRESS START" blinks (CGRAM entry of palette group 2); START ($F4 bit 4, new press) after 90 frames -> song $F1 (fade out, bank_09.asm:21285) -> state 3
;   3 fade-out  8 frames -> Hush_Ending (the old soft reset: module 0 = the title) 
; Text: the dialogue font's glyph for code c is the 8x16 pair of tiles T(c) = ((c & $F0) << 1) | (c & $0F) (top) and T(c) + 16 (bottom), 16 tiles per sheet row
; (RenderText, bank_0E.asm:8626-8760); codes A-Z = $00-$19, a-z = $1A-$33, 0-9 = $34-$3D, ! $3E, ? $3F, - $40, . $41, space $59 (text.asm). asar translates the strings below
; through direct character assignments ('A' = $00 ...; they only affect `db "..."` strings, none exist elsewhere in src/).
; BG3 map words: tile | $2400 (palette group 1: white / violet, priority) or $2800 (group 2: teal, "PRESS START"); blank = $20FF.
; Stats: hush_retries (+1 per caught), hush_sec / hush_fsub (gameplay frames, seconds), reset by Hush_NewGame; shown as "RETRIES nnn" and "TIME mmM ssS" (the font has no ':').
;
; RAM: docs/ram_map.md (hush_retries, hush_sec, hush_fsub, hush_etimer, hush_ebuf). Space: src/FREESPACE.md rows (hooks above; free block $0EFE00).
; =============================================================================

!hush_gfx     = $7EC90E
!hush_trans   = $7EC90F
!hush_tcnt    = $7EC910
!hush_retries = $7EC912
!hush_sec     = $7EC914
!hush_fsub    = $7EC916
!hush_etimer  = $7EC917
!hush_ebuf    = $7EC920                   ; 16 bytes: RETRIES line; $7EC930: TIME line

; Hush_PutText call: $00-$02 = string, $04 = VRAM word address of the top-left cell (the palette bits come from $09)
macro puttext(label, bank, vram)
    REP #$20
    LDA.w #<label>&$FFFF : STA.b $00
    LDA.w #<vram> : STA.b $04
    SEP #$20
    LDA.b #<bank> : STA.b $02
    JSL Hush_PutText
endmacro

org $008074
    db Hush_EndingModule&$FF
org $008090
    db (Hush_EndingModule>>8)&$FF
org $0080AC
    db (Hush_EndingModule>>16)&$FF

org $02891E
    db $00                                ; AND.b #$20 -> AND.b #$00: SELECT does nothing

org $0EFE00
Hush_EndingModule:                        ; RTL to the main loop, once per frame
    SEP #$30
    LDA.b $B0
    CMP.b #$01 : BEQ .fade_in
    CMP.b #$02 : BEQ .wait
    CMP.b #$03 : BEQ .fade_out
    JMP.w .init

.fade_in
    LDA.l !hush_etimer : INC A : STA.l !hush_etimer
    STA.b $13                             ; 1 .. 15
    CMP.b #$0F
    BCC .rtl
    LDA.b #$02 : STA.b $B0
    LDA.b #$00 : STA.l !hush_etimer
.rtl
    RTL

.wait
    LDA.l !hush_etimer
    CMP.b #$FF : BEQ +
    INC A : STA.l !hush_etimer
+   AND.b #$20                            ; blink: 32 frames on, 32 off (bit 5 of the frame count)
    BNE .off
    LDA.l !hush_ebuf+$0E : STA.l $7EC512
    LDA.l !hush_ebuf+$0F : STA.l $7EC513
    BRA .blink_done
.off
    LDA.b #$00 : STA.l $7EC512 : STA.l $7EC513
.blink_done
    LDA.b #$01 : STA.b $15
    LDA.l !hush_etimer
    CMP.b #90
    BCC .rtl
    LDA.b $F4 : AND.b #$10                ; START (new press)
    BEQ .rtl
    LDA.b #$F1 : STA.w $012C              ; SONG F1: fade the music out
    LDA.b #$03 : STA.b $B0
    LDA.b #$00 : STA.l !hush_etimer
    RTL

.fade_out
    LDA.l !hush_etimer : INC A : STA.l !hush_etimer
    ASL A : STA.b $00
    LDA.b #$0F : SEC : SBC.b $00
    BCC .title
    BEQ .title
    STA.b $13
    RTL
.title
    JSL Hush_Ending                       ; module 0, submodule 0: the title screen again
    RTL

.init
    JSL $00893D                           ; EnableForceBlank
    SEP #$30
    STZ.b $96 : STZ.b $97 : STZ.b $98 : STZ.b $99 : STZ.b $9A
    LDA.b #$20 : STA.b $9C                ; fixed colour black (COLDATA red / green / blue planes)
    LDA.b #$40 : STA.b $9D
    LDA.b #$80 : STA.b $9E
    LDA.b #$04 : STA.b $1C                ; main screen: BG3
    STZ.b $1D
    STZ.b $16                             ; no HUD buffer upload
    JSL $00E556                           ; TransferFontToVRAM (VRAM word $7000, VMAIN = $80)
    REP #$30
    LDA.w #$77F8 : STA.w $2116            ; tile $FF = 8 words at $7000 + $FF * 8
    LDX.w #$0008
-   STZ.w $2118
    DEX
    BNE -
    LDA.w #$6000 : STA.w $2116            ; BG3 tilemap: 1024 blank words
    LDA.w #$20FF
    LDX.w #$0400
-   STA.w $2118
    DEX
    BNE -
    JSR Hush_FmtStats
    REP #$10
    LDX.w #$0000
.line                                     ; the five text lines of Hush_TextTab
    SEP #$20
    LDA.l Hush_TextTab,X   : STA.b $00
    LDA.l Hush_TextTab+1,X : STA.b $01
    LDA.l Hush_TextTab+2,X : STA.b $02
    LDA.l Hush_TextTab+3,X : STA.b $04
    LDA.l Hush_TextTab+4,X : STA.b $05
    LDA.l Hush_TextTab+5,X : STA.b $09
    PHX
    JSL Hush_PutText
    PLX
    INX : INX : INX : INX : INX : INX
    CPX.w #30
    BNE .line
    SEP #$30
    LDA.b #$00 : STA.l $7EC500 : STA.l $7EC501   ; backdrop (CGRAM 0) black
    LDA.l $7EC512 : STA.l !hush_ebuf+$0E          ; remember group 2 colour 1 (CGRAM 9: word at $7EC512) for the blink
    LDA.l $7EC513 : STA.l !hush_ebuf+$0F
    LDA.b #$01 : STA.b $15                ; upload CGRAM
    LDA.b #$13 : STA.w $012C              ; Song13_Fanfare
    LDA.b #$01 : STA.b $B0
    LDA.b #$00 : STA.l !hush_etimer
    RTL

; Hush_TextTab: string pointer (3 bytes), VRAM word address of the top-left cell (2), high byte of the BG3 map words (1: $24 palette group 1, $28 group 2).
Hush_TextTab:
    dl Hush_StrVault  : dw $6000+(6*32)+7  : db $24
    dl Hush_StrNobody : dw $6000+(9*32)+4  : db $24
    dl !hush_ebuf     : dw $6000+(14*32)+10 : db $24
    dl !hush_ebuf+$10 : dw $6000+(17*32)+10 : db $24
    dl Hush_StrPress  : dw $6000+(23*32)+10 : db $28

; -----------------------------------------------------------------------------
; Hush_FmtStats: the two stat lines in RAM ($7EC920 RETRIES, $7EC930 TIME) from the templates, digits filled in.
Hush_FmtStats:
    REP #$10
    SEP #$20
    LDX.w #$0000
-   LDA.l Hush_StrRetries,X : STA.l !hush_ebuf,X
    LDA.l Hush_StrTime,X    : STA.l !hush_ebuf+$10,X
    INX
    CPX.w #$000D
    BNE -
    REP #$20
    LDA.l !hush_retries
    JSL Hush_Dec3                         ; $00 hundreds, $02 tens, $04 ones (digit codes)
    SEP #$20
    LDA.b $00 : STA.l !hush_ebuf+8
    LDA.b $02 : STA.l !hush_ebuf+9
    LDA.b $04 : STA.l !hush_ebuf+10
    REP #$20
    LDA.l !hush_sec                       ; minutes = sec / 60 (at most 99), seconds = sec mod 60
    LDX.w #$FFFF
-   INX
    SEC : SBC.w #60
    BCS -
    CLC : ADC.w #60
    STA.b $0A                             ; seconds
    TXA
    CMP.w #100
    BCC +
    LDA.w #99
+   JSL Hush_Dec3
    SEP #$20
    LDA.b $02 : STA.l !hush_ebuf+$15
    LDA.b $04 : STA.l !hush_ebuf+$16
    REP #$20
    LDA.b $0A
    JSL Hush_Dec3
    SEP #$20
    LDA.b $02 : STA.l !hush_ebuf+$19
    LDA.b $04 : STA.l !hush_ebuf+$1A
    RTS

Hush_Ending_End:
assert pc() <= $0F0000                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)

; ---- the text writer lives in the free block NULL_04EC1C (bank_04.asm:4821-4823), JSL'd from the module ----
org $04EC1C
Hush_PutText:
    SEP #$20
    REP #$10
    STZ.b $06                             ; 0 = top halves, 1 = bottom halves
    STZ.b $07                             ; (X reads $06 and $07 as one word below)
.pass
    REP #$20
    LDA.b $04
    LDX.b $06                             ; 16 bit read: $07 is cleared below, so X = 0 or 1
    BEQ +
    CLC : ADC.w #32
+   STA.w $2116
    SEP #$20
    LDY.w #$0000
.char
    LDA.b [$00],Y
    CMP.b #$FF : BEQ .row_done
    CMP.b #$59 : BEQ .blank
    PHA
    AND.b #$F0 : ASL A : STA.b $08       ; T(c) = ((c & $F0) << 1) | (c & $0F)
    PLA
    AND.b #$0F : ORA.b $08
    LDX.b $06
    BEQ +
    CLC : ADC.b #$10                      ; bottom half: the tile one sheet row down
+   STA.w $2118
    LDA.b $09 : STA.w $2119
    BRA .next
.blank
    LDA.b #$FF : STA.w $2118
    LDA.b #$20 : STA.w $2119
.next
    INY
    BRA .char
.row_done
    INC.b $06
    STZ.b $07
    LDA.b $06
    CMP.b #$02
    BNE .pass
    RTL

; Hush_Ending (JSL; bank 04 block):  The old soft reset to the intro: module 0, submodule 0 (IntroSkip fast-forwards to the title, START starts a new game).
Hush_Ending:
    PHP
    REP #$20
    LDX.b #$0E
-   STZ.b $E0,X                          ; the BG scroll registers ($E0-$EF) hold the room window: the title must start unscrolled, as after a cold boot
    DEX : DEX
    BPL -
    STZ.w $011E : STZ.w $0120 : STZ.w $0122 : STZ.w $0124   ; the BG1 / BG2 scroll mirrors the NMI writes to the PPU (bank_00.asm:190-205)
    SEP #$30
    STZ.b $1B
    STZ.b $11
    STZ.b $10
    STZ.b $B0
    STZ.w $04AA
    PLP
    RTL
Hush_PutText_End:
assert pc() <= $04ECC0                   ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)

org $02FF6E
; -----------------------------------------------------------------------------
; Statistics (JSL from guard_runtime.asm / new_game.asm / Hush_Tick; these live in the free block NULL_02FF6E, bank_02.asm:21732-21736). M = X = 8 bit on entry, any state kept.
Hush_StatsReset:
    PHP
    REP #$20
    LDA.w #$0000
    STA.l !hush_retries
    STA.l !hush_sec
    SEP #$20
    STA.l !hush_fsub
    PLP
    RTL

Hush_CountRetry:
    PHP
    REP #$20
    LDA.l !hush_retries
    CMP.w #999
    BCS +
    INC A
    STA.l !hush_retries
+   PLP
    RTL

Hush_TimeTick:                            ; once per gameplay frame (Hush_Tick)
    PHP
    SEP #$20
    LDA.l !hush_fsub : INC A
    CMP.b #60
    BCC .store
    REP #$20
    LDA.l !hush_sec
    CMP.w #5999
    BCS +
    INC A
    STA.l !hush_sec
+   SEP #$20
    LDA.b #$00
.store
    STA.l !hush_fsub
    PLP
    RTL
; Hush_Dec3 (JSL; in the bank 02 block): A (16 bit, capped at 999) -> $00 / $02 / $04 = the hundreds / tens / ones digit CODES ($34 + digit, font code of '0'..'9').
Hush_Dec3:
    REP #$30
    CMP.w #1000
    BCC +
    LDA.w #999
+   LDY.w #$0000
    LDX.w #100 : STX.b $0C : JSR .digit
    LDX.w #10  : STX.b $0C : JSR .digit
    LDX.w #1   : STX.b $0C : JSR .digit
    RTL
.digit
    LDX.w #$0033
-   INX
    SEC : SBC.b $0C
    BCS -
    CLC : ADC.b $0C
    STX.b $00,Y
    INY : INY
    RTS

Hush_Stats_End:
assert pc() <= $030000                   ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)

; ---- strings: the tail of the bank 0F free block (after roomload.asm) ----
org $0FFFA0
'A' = $00
'B' = $01
'C' = $02
'D' = $03
'E' = $04
'F' = $05
'G' = $06
'H' = $07
'I' = $08
'J' = $09
'K' = $0A
'L' = $0B
'M' = $0C
'N' = $0D
'O' = $0E
'P' = $0F
'Q' = $10
'R' = $11
'S' = $12
'T' = $13
'U' = $14
'V' = $15
'W' = $16
'X' = $17
'Y' = $18
'Z' = $19
'0' = $34
'1' = $35
' ' = $59
Hush_StrVault:
    db "THE VAULT IS EMPTY", $FF
Hush_StrNobody:
    db "AND NOBODY HEARD A THING", $FF
Hush_StrPress:
    db "PRESS START", $FF
Hush_StrRetries:
    db "RETRIES 000", $FF
Hush_StrTime:
    db "TIME 00M 00S", $FF
cleartable
Hush_Strings_End:
assert pc() <= $100000                   ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
