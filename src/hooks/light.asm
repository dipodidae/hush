; =============================================================================
; light.asm  (L1: lantern light = guard sight, design/lighting.md; docs/engine_notes.md section 16)
;
; Not a hook file of its own: three existing HUSH routines call in (no new vanilla bytes are replaced):
;   roomload.asm  Hush_AttrSet   end `STZ.w $0200 : RTL` -> `JML Hush_LightInit` (which does the STZ and the RTL): after the collision map is built,
;                                in the forced blank of Module06 -> light state reset, cell solidity from $7F2000, BG1 window := no light (VRAM upload)
;   meter.asm     Hush_MeterFrame `.out` -> `JSL Hush_LightWork` (end of every Module07 frame, after the guards and Link ran)
;   menu_ui.asm   Hush_NmiTM      -> `JSL Hush_LightNmi` first (NMI, before the TM / TS writes of the vanilla NMI)
;
; Technique (the vanilla castle-escape lamp: BG1 cone added onto the dark room, OrientLampLightCone bank_00.asm:15413, RoomDraw_LampCones bank_01.asm:5679):
;   BG1 (hidden in HUSH rooms, its buffer $7E4000 still holds the floor that transition.asm copies) is put on the SUB screen ($1D bit 0) and colour math
;   ADDS it to BG2 + the backdrop ($99 = $02 sub screen addend, $9A = $22). Where BG1 is transparent the addend is the fixed colour (COLDATA = 0): no change.
;   OBJ and BG3 (sprites, HUD) take no colour math: they are never tinted.
;   BG1 tile words come from Hush_LightWords (tools/autotile.py light_words: steps 0..6 amber, violet 1, 2; BG palette row 2, colours 9-12 written here).
;
; Model (per 16x16 cell of the 16 x 14 grid; padded grid 32 x 30 so ray offsets need no bounds checks, p = (cy + 8) * 32 + cx + 8):
;   SOL[p]   bit 0 solid (catches light, blocks), bit 6 ink cloud (dark, blocks), bit 7 outside the grid (dark, blocks)
;   per guard slot g (0-7): GMAP[g][i] = its light step per inner cell i = cy * 16 + cx; COMP[i] = max over g; VIO[i] = player glow 0..2
;   a guard's light is rebuilt as a JOB when its signature (class, facing, cell) differs from the committed one:
;     clear SCR -> origin + 1 wedge (cone) or 4 wedges (all around) from the generated ray tables (each entry lit iff its parent entry is lit and
;     not solid: light travels outwards, the first solid cell catches it) -> commit row by row (GMAP diff, COMP max, tile words, dirty rows)
;   The work is time-sliced: units of <= ~15 scanlines run only while the PPU V counter is below LIGHT_VMAX (the frame's spare time), so lighting
;   never causes a lag frame. NMI uploads <= 4 dirty cell rows (= 8 tile rows, 512 bytes) per frame (measured: the NMI reaches here at line ~250).
;
; Space:    src/FREESPACE.md rows $1FB780-$1FC3FF (this code) and $1FC400-$1FC9FF (build/rooms_gen.asm: Hush_LightTab, Hush_LightWords): vanilla
;           room object data of rooms HUSH never loads (RoomDataTiles_00A1 .. , rooms.asm:750+), same evidence as the E1 room-data rows.
; RAM:      $7ECA00-$7EE7FF (docs/ram_map.md "HUSH lighting"); direct page $00-$0F scratch (end of frame / Module06 only, never in the NMI).
; =============================================================================

!L_SOL    = $CA00        ; 960  padded solidity
!L_SCR    = $CDC0        ; 960  padded scratch steps of the current job
!L_GMAP   = $D180        ; 1792 [g * 224 + i] committed steps per guard slot
!L_COMP   = $D880        ; 224  max over the guards
!L_VIO    = $D960        ; 224  player glow
!L_TILES  = $DA40        ; 1792 BG1 window tile words, 28 rows x 32
!L_VIS    = $E140        ; 200  [2 * entry] ray visibility of the current wedge; entry 99 = the origin (always 1)
!L_DELTA  = $E210        ; 792  copied from Hush_LightTab: [facing * 198 + 2 * entry] padded offset
!L_PAR    = $E528        ; 198  [2 * entry] 2 * parent entry
!L_DIST   = $E5EE        ; 198  [2 * entry] d | $80 cone diagonal
!L_LVL    = $E6B4        ; 96   [(class - 1) * 32 + lit * 16 + d] step
!L_WORDS  = $E714        ; 18   tile words
!L_TABLEN = 1302         ; bytes of Hush_LightTab (99 entries per wedge: d <= 9)
!L_ON     = $E740        ; 1  lighting active (set by Hush_LightInit)
!L_DIRTY  = $E742        ; 2  cell rows (bits 0-13) whose tile words changed since their last upload
!L_SIGC   = $E748        ; 32 committed signature per slot: class, facing, p (2)
!L_TSIG   = $E768        ; 4  signature being tested
!L_JSIG   = $E76C        ; 4  signature of the running job
!L_JOB    = $E770        ; 1  slot of the running job, $FF = idle
!L_JPH    = $E771        ; 1  job phase: 0 clear, 1 wedges, 2 commit
!L_JWN    = $E772        ; 1  wedges left
!L_JF     = $E773        ; 1  current wedge facing
!L_JE     = $E774        ; 2  2 * next entry
!L_JEND   = $E776        ; 2  2 * entries within the range + fringe
!L_JLVL   = $E778        ; 2  address of the step row
!L_JEDGE  = $E77A        ; 1  1 = cone (diagonal one step dimmer), 0 = all around
!L_JROW   = $E77B        ; 1  commit half row
!L_RR     = $E77C        ; 1  round-robin slot
!L_LCELL  = $E77E        ; 2  player glow cell i, $FFFF = none
!L_INKP   = $E780        ; 2  ink cloud centre p, 0 = none
!L_PALREQ = $E782        ; 1  write the light colours into the palette buffers
!L_V0     = $E784        ; 2  V counter when the worker started

!LIGHT_VMAX = 195        ; no new unit at or after this scanline (NMI at 225; a unit is <= ~10 lines, the rest of the frame ~5-10)
!LIGHT_NMIROWS = 4       ; cell rows uploaded per NMI

org $1FB780
; -----------------------------------------------------------------------------
; Hush_LightInit: JML from the end of Hush_AttrSet (Module06, forced blank), M = X = 8. Does the replaced `STZ.w $0200 : RTL`.
Hush_LightInit:
    STZ.w $0200
    PHB : PHP
    REP #$30
    PEA $7E7E : PLB : PLB
    LDX.w #$0000
-   LDA.l Hush_LightTab,X : STA.w !L_DELTA,X
    INX : INX : CPX.w #!L_TABLEN : BCC -
    LDX.w #$0000 : LDA.w #$8080
-   STA.w !L_SOL,X : INX : INX : CPX.w #960 : BCC -
    LDX.w #$0000 : TXA
-   STA.w !L_SCR,X : INX : INX : CPX.w #(!L_TILES-!L_SCR) : BCC -     ; SCR, GMAP, COMP, VIO
    LDX.w #$0000
-   STA.w !L_VIS,X : INX : INX : CPX.w #200 : BCC -
    INC A : STA.w !L_VIS+198                                         ; the origin
    LDX.w #$0000 : LDA.w !L_WORDS
-   STA.w !L_TILES,X : INX : INX : CPX.w #1792 : BCC -
    ; solidity of the 16 x 14 cells: collision of the top-left tile of each cell ($7F2000, row stride 64; cell (0,0) = tile (16,18))
    LDY.w #(8*32+8)
    LDX.w #(18*64+16)
    LDA.w #14 : STA.b $00
.srow
    LDA.w #16 : STA.b $02
.scol
    SEP #$20
    LDA.l $7F2000,X : BEQ +
    LDA.b #$01
+   STA.w !L_SOL,Y
    REP #$20
    INY : INX : INX
    DEC.b $02 : BNE .scol
    TYA : CLC : ADC.w #16 : TAY
    TXA : CLC : ADC.w #(128-32) : TAX
    DEC.b $00 : BNE .srow
    ; bit 1 = "face": a solid cell with an open cell below it (wall faces, pillar fronts). Only faces catch light; wall tops and
    ; the void around the room stay dark (they still block). Row 13 has no cell below inside the grid: never a face.
    LDX.w #(8*32+8)
    LDY.w #(13*16)
.face
    SEP #$20
    LDA.w !L_SOL,X : AND.b #$01 : BEQ +
    LDA.w !L_SOL+32,X : AND.b #$01 : BNE +
    LDA.w !L_SOL,X : ORA.b #$02 : STA.w !L_SOL,X
+   REP #$20
    INX
    TXA : AND.w #$001F : CMP.w #24 : BCC +
    TXA : CLC : ADC.w #16 : TAX          ; next padded row
+   DEY : BNE .face
    ; variables
    LDX.w #$0000 : TXA
-   STA.w !L_SIGC,X : INX : INX : CPX.w #32 : BCC -                  ; every slot: committed "no light" (GMAP is 0)
    STA.w !L_DIRTY : STA.w !L_INKP : STA.w !L_JE
    DEC A : STA.w !L_LCELL
    SEP #$20
    LDA.b #$FF : STA.w !L_JOB
    STZ.w !L_RR
    LDA.b #$01 : STA.w !L_PALREQ : STA.w !L_ON
    ; BG1 window := no light (28 tile rows, forced blank)
    PEA $0000 : PLB : PLB
    REP #$30
    JSR Hush_LightDmaSetup
    LDA.w #$0000
-   PHA
    JSR Hush_LightUpRow
    PLA : INC A : CMP.w #28 : BCC -
    PLP : PLB
    RTL

; -----------------------------------------------------------------------------
; Hush_LightDmaSetup / Hush_LightUpRow: DB = $00, M = X = 16. UpRow: A = tile row 0..27 (window row; tilemap row 18 + A), 2 DMAs of 16 words
; (left screen: tiles 16..31, right screen: tiles 32..47; BG1 tilemap at VRAM word $1000, 2 x 2 screens of 32 x 32, as Hush_BuildRoom .layer).
Hush_LightDmaSetup:
    SEP #$20
    LDA.b #$80 : STA.w $2115             ; VMAIN: increment after the high byte
    LDA.b #$7E : STA.w $4304             ; DMA0 source bank
    REP #$20
    LDA.w #$1801 : STA.w $4300           ; DMA0: mode 1 to VMDATA
    RTS

Hush_LightUpRow:
    PHA
    ASL A : ASL A : ASL A : ASL A : ASL A : ASL A
    CLC : ADC.w #!L_TILES : STA.w $4302
    PLA
    CLC : ADC.w #18
    CMP.w #32 : BCS .bottom
    ASL A : ASL A : ASL A : ASL A : ASL A
    CLC : ADC.w #($1000+16)
    BRA .addr
.bottom
    SBC.w #32                            ; C = 1 here
    ASL A : ASL A : ASL A : ASL A : ASL A
    CLC : ADC.w #($1800+16)
.addr
    STA.w $2116
    PHA
    LDA.w #32 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    PLA : CLC : ADC.w #($0400-16) : STA.w $2116      ; the right screen, column 0 (the DMA source has advanced by 32)
    LDA.w #32 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    RTS

; -----------------------------------------------------------------------------
; Hush_LightNmi: JSL from Hush_NmiTM (NMI, before `LDA $1C : STA TM` and `LDA $1D : STA TS`). M = 8, DB = $00. Keeps A? no: Hush_NmiTM reloads A.
;   module 7: upload up to LIGHT_NMIROWS dirty cell rows.  Item menu (module $0E, submodule 1): $1D := 0 for this frame (no light behind the menu;
;   Hush_LightWork sets bit 0 again in the next gameplay frame).
Hush_LightNmi:
    PHP : PHB
    SEP #$20
    LDA.l $7E0000+!L_ON : BEQ .out
    LDA.b $10 : CMP.b #$07 : BEQ .room
    CMP.b #$0E : BNE .out
    LDA.b $11 : CMP.b #$01 : BNE .out
    STZ.b $1D
    BRA .out
.room
    REP #$30
    PHX : PHY
    LDA.l $7E0000+!L_DIRTY : BEQ .done
    JSR Hush_LightDmaSetup
    LDY.w #!LIGHT_NMIROWS
    LDX.w #$0000                         ; X = 2 * cell row = the first of its two tile rows
.scan
    LDA.l Hush_LightBit,X
    PEA $7E7E : PLB : PLB
    BIT.w !L_DIRTY : BEQ .skip
    TRB.w !L_DIRTY
    PEA $0000 : PLB : PLB
    TXA : JSR Hush_LightUpRow
    TXA : INC A : JSR Hush_LightUpRow
    DEY : BEQ .done
.skip
    PEA $0000 : PLB : PLB
    INX : INX : CPX.w #28 : BCC .scan
.done
    PLY : PLX
.out
    PLB : PLP
    RTL

Hush_LightBit:
    dw $0001, $0002, $0004, $0008, $0010, $0020, $0040, $0080, $0100, $0200, $0400, $0800, $1000, $2000

Hush_LightCols:                          ; BG row 2 colours 9..12 (BGR555, added): amber edge (5,2,0), mid (10,5,0), core (17,10,1); violet glow (4,1,8)
    dw $0045, $00AA, $0551, $2024

; -----------------------------------------------------------------------------
; Hush_LightWipe: JSL from the submodule $0F hook ($02931D, transition.asm; it called Hush_Wipe directly before L1). Runs Hush_Wipe, then, once per
; room load, the light palette (Hush_LightPal) so the first fade-in frame already shows the soft shadow. Keeps A, X, Y, P as Hush_Wipe left them.
Hush_LightWipe:
    JSL Hush_Wipe
    PHP
    REP #$30
    PHA : PHX : PHY
    PHB
    PEA $7E7E : PLB : PLB
    SEP #$20
    LDA.w !L_ON : BEQ +
    LDA.w !L_PALREQ : BEQ +
    JSR Hush_LightPal
+   PLB
    REP #$30
    PLY : PLX : PLA
    PLP
    RTL

; -----------------------------------------------------------------------------
; Hush_LightWork: JSL from Hush_MeterFrame (end of the Module07 frame), any M/X, keeps P.
Hush_LightWork:
    PHP : PHB
    SEP #$20 : REP #$10
    PEA $7E7E : PLB : PLB
    LDA.b $10 : CMP.b #$07 : BNE .exit
    LDA.w !L_ON : BEQ .exit
    LDA.w $C903 : BNE +                  ; hush_flash ($7EC903): the caught flash owns the colour-math registers (feedback.asm)
    LDA.b #$02 : STA.b $99               ; CGWSEL: the sub screen is the addend
    LDA.b #$22 : STA.b $9A               ; CGADSUB: add to BG2 and the backdrop
    LDA.b $1D : ORA.b #$01 : STA.b $1D   ; TS: BG1 (the light) on the sub screen
+   REP #$20
    LDA.w $C552 : CMP.l Hush_LightCols : SEP #$20 : BEQ +
    LDA.b #$01 : STA.w !L_PALREQ         ; the palette buffer was reloaded (room load, menu): light colours + soft shadow again
+   JSR Hush_LightV : STA.w !L_V0
    CMP.w #!LIGHT_VMAX : BCS .exit       ; no spare time this frame: everything waits (the colour-math shadows above are set every frame)
    SEP #$20
    LDA.w !L_PALREQ : BEQ +
    REP #$20 : LDA.w !L_V0 : CMP.w #150 : SEP #$20 : BCS +   ; ~20 lines of work: only early in the frame
    JSR Hush_LightPal
+   JSR Hush_LightInk
    JSR Hush_LightAura
    JSR Hush_LightV
    CMP.w #!LIGHT_VMAX : BCS .exit
.unit
    SEP #$20
    JSR Hush_LightStep : BCC .exit
    JSR Hush_LightV
    CMP.w !L_V0 : BCC .exit              ; wrapped into the next frame
    CMP.w #!LIGHT_VMAX : BCC .unit
.exit
    PLB : PLP
    RTL

; V counter -> A (M = 16 on return). The latch / flip-flop sequence of the vanilla scanline wait (bank_00.asm:15152).
Hush_LightV:
    SEP #$20
    LDA.l $002137
    LDA.l $00213F
    LDA.l $00213D : XBA
    LDA.l $00213D : AND.b #$01 : XBA
    REP #$20
    RTS

Hush_LightPal:                           ; M = 8, X = 16. Light colours (BG row 2, colours 9-12) + the soft shadow: room rows 3-7 dimmed
    STZ.w !L_PALREQ
    REP #$20
    LDX.w #$0000
-   LDA.l Hush_LightCols,X
    STA.w $C552,X : STA.w $C352,X        ; $7EC500 / $7EC300 + row 2 * 32 + colour 9 * 2
    INX : INX : CPX.w #8 : BCC -
    LDA.w $C900 : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX
    LDA.l Hush_RoomTable+19,X : LSR A    ; bit 0: lit room
    LDA.w #Hush_DimDark : BCC +
    LDA.w #Hush_DimLit
+   STA.b $04
    LDA.w #(Hush_DimDark>>16) : STA.b $06
    LDX.w #(3*32+2)                      ; rows 3..7, colours 1..15 (the room tiles; rows 0-1 are the HUD, row 2 the light)
.col
    LDA.w $C500,X : STA.b $00
    AND.w #$001F : TAY
    LDA.b [$04],Y : AND.w #$001F : STA.b $02
    LDA.b $00 : LSR A : LSR A : LSR A : LSR A : LSR A : AND.w #$001F : TAY
    LDA.b [$04],Y : AND.w #$001F : ASL A : ASL A : ASL A : ASL A : ASL A : TSB.b $02
    LDA.b $00 : XBA : LSR A : LSR A : AND.w #$001F : TAY
    LDA.b [$04],Y : AND.w #$001F : XBA : ASL A : ASL A : TSB.b $02
    LDA.b $02 : STA.w $C500,X : STA.w $C300,X
    INX : INX
    TXA : AND.w #$001F : BNE +
    INX : INX                            ; skip colour 0 of the next row
+   CPX.w #(8*32) : BCC .col
    SEP #$20
    LDA.b #$01 : STA.b $15               ; palette upload (as Hush_SetPalettes)
    RTS

Hush_DimDark:                            ; v * 11 / 16: dark rooms, soft shadow
    db $00, $00, $01, $02, $02, $03, $04, $04, $05, $06, $06, $07, $08, $08, $09, $0A, $0B, $0B, $0C, $0D, $0D, $0E, $0F, $0F, $10, $11, $11, $12, $13, $13, $14, $15
Hush_DimLit:                             ; v * 13 / 16: lit rooms are brighter
    db $00, $00, $01, $02, $03, $04, $04, $05, $06, $07, $08, $08, $09, $0A, $0B, $0C, $0D, $0D, $0E, $0F, $10, $11, $11, $12, $13, $14, $15, $15, $16, $17, $18, $19

; -----------------------------------------------------------------------------
; Hush_LightInk: the ink cloud's 3 x 3 cells (|centre - cloud| <= 24 px: the cloud cell and its 8 neighbours) are dark and block light.
; A change aborts the running job and invalidates every committed signature (all guards are rebuilt). M = 8, X = 16.
Hush_LightInk:
    REP #$20
    LDA.w #$0000 : STA.b $04             ; new centre p (0 = none)
    LDA.w $C90C : BEQ .have              ; hush_ink_t
    LDA.w $C908 : SEC : SBC.b $E2 : CMP.w #$0100 : BCS .have
    LSR A : LSR A : LSR A : LSR A : STA.b $00
    LDA.w $C90A : SEC : SBC.b $E8 : CMP.w #$00E0 : BCS .have
    AND.w #$00F0 : ASL A : CLC : ADC.b $00 : CLC : ADC.w #(8*32+8) : STA.b $04
.have
    LDA.b $04 : CMP.w !L_INKP : BEQ .same
    LDX.w !L_INKP : BEQ +
    LDA.w #$BFBF : JSR .box              ; clear bit 6 around the old centre
+   LDX.b $04 : STX.w !L_INKP : BEQ +
    LDA.w #$4040 : JSR .box              ; set it around the new one
+   SEP #$20
    LDA.b #$FF : STA.w !L_JOB
    LDX.w #$0000
-   STA.w !L_SIGC,X : INX : INX : INX : INX : CPX.w #32 : BCC -
    RTS
.same
    SEP #$20
    RTS
.box                                     ; X = centre p, A = $BFBF (AND) or $4040 (ORA); M = 16 on entry; 3 rows of 3 cells (2 bytes + 1 byte)
    STA.b $06
    LDY.w #$0003
    TXA : SEC : SBC.w #33 : TAX
.brow
    LDA.b $06 : CMP.w #$4040 : BEQ .bor
    LDA.w !L_SOL,X : AND.b $06 : STA.w !L_SOL,X
    SEP #$20 : LDA.w !L_SOL+2,X : AND.b $06 : STA.w !L_SOL+2,X : REP #$20
    BRA .bnext
.bor
    LDA.w !L_SOL,X : ORA.b $06 : STA.w !L_SOL,X
    SEP #$20 : LDA.w !L_SOL+2,X : ORA.b $06 : STA.w !L_SOL+2,X : REP #$20
.bnext
    TXA : CLC : ADC.w #32 : TAX
    DEY : BNE .brow
    RTS

; -----------------------------------------------------------------------------
; Hush_LightAura: the player's glow (VIO 2 on Link's cell, 1 on its 8 neighbours). Link's point = his box centre (x + 8, y + 16). M = 8, X = 16.
Hush_LightAura:
    REP #$20
    LDA.w #$FFFF : STA.b $04
    LDA.b $22 : CLC : ADC.w #8 : SEC : SBC.b $E2 : CMP.w #$0100 : BCS .have
    LSR A : LSR A : LSR A : LSR A : STA.b $00
    LDA.b $20 : CLC : ADC.w #16 : SEC : SBC.b $E8 : CMP.w #$00E0 : BCS .have
    AND.w #$00F0 : ORA.b $00 : STA.b $04
.have
    LDA.b $04 : CMP.w !L_LCELL : BEQ .same
    LDA.w !L_LCELL : BMI +
    STZ.b $08 : JSR .ring                ; old cells: no glow
    SEP #$20
    LDY.w !L_LCELL
    LDA.b #$00 : STA.w !L_VIO,Y
    JSR Hush_LightTile
    REP #$20
+   LDA.b $04 : STA.w !L_LCELL : BMI .same
    LDA.w #$0001 : STA.b $08
    LDA.b $04 : JSR .ring
    SEP #$20
    LDY.w !L_LCELL
    JSR Hush_LightFloor : BNE .same
    LDA.b #$02 : STA.w !L_VIO,Y
    JSR Hush_LightTile
.same
    SEP #$20
    RTS
.ring                                    ; A = centre i (M = 16), $08 = value: the 4 orthogonal neighbours inside the grid; the value is only set on
    STA.b $06                            ; floor cells (0 = clear: always)
    LDX.w #$0006
.rn
    LDA.b $06 : AND.w #$00F0 : LSR A : LSR A : LSR A : LSR A : CLC : ADC.l Hush_LightRingDY,X
    CMP.w #14 : BCS .rnext
    ASL A : ASL A : ASL A : ASL A : STA.b $02
    LDA.b $06 : AND.w #$000F : CLC : ADC.l Hush_LightRingDX,X
    CMP.w #16 : BCS .rnext
    ORA.b $02 : TAY
    SEP #$20
    LDA.b $08 : BEQ .rset
    JSR Hush_LightFloor : BNE .rskip
    LDA.b $08
.rset
    STA.w !L_VIO,Y
    JSR Hush_LightTile
.rskip
    REP #$20
.rnext
    DEX : DEX : BPL .rn
    RTS

Hush_LightFOff:
    dw 0, 198, 396, 594
Hush_LightRingDX:
    dw $0000, $FFFF, $0001, $0000
Hush_LightRingDY:
    dw $FFFF, $0000, $0000, $0001

; Hush_LightFloor: Y = cell i (M = 8, X = 16) -> Z = 1 when the cell is floor (not solid; the ink cloud does not matter). Keeps X, Y.
Hush_LightFloor:
    PHY
    REP #$20
    TYA : AND.w #$00F0 : ASL A : STA.b $0E
    TYA : AND.w #$000F : CLC : ADC.b $0E : CLC : ADC.w #(8*32+8) : TAY
    SEP #$20
    LDA.w !L_SOL,Y
    PLY
    AND.b #$81
    RTS

; -----------------------------------------------------------------------------
; Hush_LightTile: Y = cell i (X = 16, M = 8): the 4 tile words of the cell from COMP / VIO; marks its cell row dirty. Keeps X, Y; uses $0E.
Hush_LightTile:
    PHX
    LDA.w !L_COMP,Y : BNE .w
    LDA.w !L_VIO,Y : BEQ .w
    CLC : ADC.b #$06
.w
    REP #$20
    AND.w #$000F : ASL A : TAX
    LDA.w !L_WORDS,X : PHA
    TYA : AND.w #$00F0 : ASL A : ASL A : ASL A : STA.b $0E
    TYA : AND.w #$000F : ASL A : ASL A : CLC : ADC.b $0E : TAX
    PLA
    STA.w !L_TILES,X : STA.w !L_TILES+2,X : STA.w !L_TILES+64,X : STA.w !L_TILES+66,X
    TYA : LSR A : LSR A : LSR A : AND.w #$001E : TAX         ; 2 * (i >> 4)
    LDA.l Hush_LightBit,X : TSB.w !L_DIRTY
    SEP #$20
    PLX
    RTS

; -----------------------------------------------------------------------------
; Hush_LightSig: X = slot (16-bit index, M = 8) -> L_TSIG = class (0 none, 1 cone, 2 suspicious, 3 alert), facing (cone only), p.
; Guard centre = origin + (8, 8) (Hush_Geom, guard_vision.asm).
Hush_LightSig:
    REP #$20
    STZ.w !L_TSIG : STZ.w !L_TSIG+2
    SEP #$20
    LDA.w $0DD0,X : CMP.b #$09 : BNE .none
    LDA.w $0E20,X : CMP.b #$41 : BNE .none
    LDA.w $0D80,X : CMP.b #$03 : BCS .none                 ; asleep (3) or anything else: no light
    INC A : STA.b $08
    LDA.w $0D30,X : XBA : LDA.w $0D10,X
    REP #$20
    CLC : ADC.w #8 : SEC : SBC.b $E2 : CMP.w #$0100 : BCS .none16
    LSR A : LSR A : LSR A : LSR A : STA.b $00
    SEP #$20
    LDA.w $0D20,X : XBA : LDA.w $0D00,X
    REP #$20
    CLC : ADC.w #8 : SEC : SBC.b $E8 : CMP.w #$00E0 : BCS .none16
    AND.w #$00F0 : ASL A : CLC : ADC.b $00 : CLC : ADC.w #(8*32+8) : STA.w !L_TSIG+2
    SEP #$20
    LDA.b $08 : STA.w !L_TSIG
    CMP.b #$01 : BNE .none
    LDA.w $0DE0,X : AND.b #$03 : STA.w !L_TSIG+1
.none
    RTS
.none16
    SEP #$20
    RTS

; -----------------------------------------------------------------------------
; Hush_LightStep: one unit of work (M = 8, X = 16). C = 0: nothing to do.
Hush_LightStep:
    LDA.w !L_JOB : BPL .job
    ; idle: find the next slot whose light is out of date (round robin)
    LDA.b #$08 : STA.b $0A
    LDA.w !L_RR : AND.b #$07 : STA.b $0B
.pick
    REP #$20 : LDA.b $0B : AND.w #$0007 : TAX : SEP #$20
    JSR Hush_LightSig
    REP #$20
    LDA.b $0B : AND.w #$0007 : ASL A : ASL A : TAX
    LDA.w !L_TSIG : CMP.w !L_SIGC,X : BNE .start
    LDA.w !L_TSIG+2 : CMP.w !L_SIGC+2,X : BNE .start
    SEP #$20
    INC.b $0B
    DEC.b $0A : BNE .pick
    CLC
    RTS
.start
    LDA.w !L_TSIG : STA.w !L_JSIG
    LDA.w !L_TSIG+2 : STA.w !L_JSIG+2
    SEP #$20
    LDA.b $0B : AND.b #$07 : STA.w !L_JOB
    INC A : STA.w !L_RR
    STZ.w !L_JPH
    SEC
    RTS
.job
    LDA.w !L_JPH : BEQ .clear
    CMP.b #$01 : BNE +
    JMP Hush_LightWedge
+   JMP Hush_LightCommit

.clear                                   ; scratch := 0 over the 14 x 16 inner cells, then the job set-up
    REP #$20
    LDX.w #(8*32+8)
    LDY.w #14
-   STZ.w !L_SCR,X : STZ.w !L_SCR+2,X : STZ.w !L_SCR+4,X : STZ.w !L_SCR+6,X
    STZ.w !L_SCR+8,X : STZ.w !L_SCR+10,X : STZ.w !L_SCR+12,X : STZ.w !L_SCR+14,X
    TXA : CLC : ADC.w #32 : TAX
    DEY : BNE -
    STZ.w !L_JE
    SEP #$20
    LDA.b #$02 : STA.w !L_JPH            ; no light: straight to the commit
    STZ.w !L_JROW
    LDA.w !L_JSIG : BEQ .done            ; class 0
    LDX.w !L_JSIG+2
    LDA.w !L_SOL,X : AND.b #$C0 : BNE .done                 ; the guard stands in the ink cloud: no light
    ; range: lit room = hush_range >= 128 (R = 8: 80 entries), dark (R = 5: 35 entries)
    REP #$20
    LDA.w $C900 : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX     ; hush_room -> ROOM TABLE record (not hush_range: Hush_Tick
    LDA.l Hush_RoomTable+19,X : LSR A                                         ; only updates it in submodule 0; the worker also runs in the fade-in)
    LDA.w #96 : LDY.w #$0000             ; dark: d <= 6 (R = 5 + the fringe) = 48 entries
    BCC +
    LDA.w #198 : LDY.w #$0010            ; lit: d <= 9 (R = 8 + the fringe) = 99 entries
+   STA.w !L_JEND
    STY.b $00
    LDA.w !L_JSIG : AND.w #$00FF : DEC A
    ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $00 : CLC : ADC.w #!L_LVL : STA.w !L_JLVL
    SEP #$20
    LDY.w !L_JLVL
    LDA.w $0000,Y                        ; step at d = 0
    LDX.w !L_JSIG+2
    STA.w !L_SCR,X                       ; the guard's own cell
    LDA.b #$01 : STA.w !L_JPH
    LDA.w !L_JSIG : CMP.b #$01 : BNE .round
    STA.w !L_JEDGE : STA.w !L_JWN
    LDA.w !L_JSIG+1 : STA.w !L_JF
    SEC
    RTS
.round
    STZ.w !L_JEDGE : STZ.w !L_JF
    LDA.b #$04 : STA.w !L_JWN
.done
    SEC
    RTS

; -----------------------------------------------------------------------------
; Hush_LightWedge: up to 12 ray entries of the current wedge (M = 8, X = 16). DP: $00 guard p, $02 facing * 160, $04 stop, $06 p, $08 step row, $0A edge.
Hush_LightWedge:
    REP #$20
    LDA.w !L_JSIG+2 : STA.b $00
    LDA.w !L_JF : AND.w #$0003 : ASL A : TAX
    LDA.l Hush_LightFOff,X : STA.b $02   ; facing * 198 (bytes of one facing's delta table)
    LDA.w !L_JLVL : STA.b $08
    LDA.w !L_JE : TAX : CLC : ADC.w #24     ; 12 entries per unit
    CMP.w !L_JEND : BCC +
    LDA.w !L_JEND
+   STA.b $04
    SEP #$20
    LDA.w !L_JEDGE : STA.b $0A
.loop
    CPX.b $04 : BCS .chunk
    LDY.w !L_PAR,X
    LDA.w !L_VIS,Y : BEQ .hide
    REP #$20
    TXA : CLC : ADC.b $02 : TAY
    LDA.w !L_DELTA,Y : CLC : ADC.b $00 : TAY
    STY.b $06
    SEP #$20
    TDC                                  ; C := 0 (D = $0000): B must be 0 for the TAY below (X = 16)
    LDA.w !L_SOL,Y : BIT.b #$C0 : BNE .hide
    AND.b #$01 : EOR.b #$01 : STA.w !L_VIS,X                ; floor: the ray goes on; solid: it stops here
    BNE .lit
    LDA.w !L_SOL,Y : AND.b #$02 : BEQ .next                 ; a wall top / the void: no light; a face catches it
.lit
    LDA.w !L_DIST,X : BPL .plain
    AND.b #$0F : TAY : LDA.b ($08),Y : SEC : SBC.b $0A
    BRA .have
.plain
    TAY : LDA.b ($08),Y
.have
    LDY.b $06
    CMP.w !L_SCR,Y : BCC .next
    STA.w !L_SCR,Y
.next
    INX : INX
    BRA .loop
.hide
    STZ.w !L_VIS,X
    INX : INX
    BRA .loop
.chunk
    STX.w !L_JE
    CPX.w !L_JEND : BCC .more
    REP #$20 : STZ.w !L_JE : SEP #$20
    LDA.w !L_JF : INC A : AND.b #$03 : STA.w !L_JF          ; (all around: the next of the 4 wedges)
    DEC.w !L_JWN : BNE .more
    LDA.b #$02 : STA.w !L_JPH
    STZ.w !L_JROW
.more
    SEC
    RTS

; -----------------------------------------------------------------------------
; Hush_LightCommit: half a cell row (8 cells) of the job's scratch -> GMAP[slot], COMP, tile words (M = 8, X = 16). After half row 27 the signature is committed.
Hush_LightCommit:
    REP #$20
    LDA.w !L_JOB : AND.w #$0007 : STA.b $00
    ASL A : ASL A : ASL A : SEC : SBC.b $00 : ASL A : ASL A : ASL A : ASL A : ASL A        ; slot * 224
    CLC : ADC.w #!L_GMAP : STA.b $0C
    LDA.w !L_JROW : AND.w #$00FF : STA.b $00                ; half rows 0..27: cells (JROW & 1) * 8 .. + 7 of row JROW / 2
    ASL A : ASL A : ASL A : TAY                            ; i = half row * 8
    LDA.b $00 : AND.w #$0001 : ASL A : ASL A : ASL A : STA.b $02
    LDA.b $00 : LSR A : CLC : ADC.w #8 : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.w #8 : CLC : ADC.b $02 : TAX     ; p
    LDA.w #8 : STA.b $02
    SEP #$20
.cell
    LDA.w !L_SCR,X : CMP.b ($0C),Y : BEQ .next
    STA.b ($0C),Y
    LDA.w !L_GMAP+(0*224),Y
    CMP.w !L_GMAP+(1*224),Y : BCS + : LDA.w !L_GMAP+(1*224),Y
+   CMP.w !L_GMAP+(2*224),Y : BCS + : LDA.w !L_GMAP+(2*224),Y
+   CMP.w !L_GMAP+(3*224),Y : BCS + : LDA.w !L_GMAP+(3*224),Y
+   CMP.w !L_GMAP+(4*224),Y : BCS + : LDA.w !L_GMAP+(4*224),Y
+   CMP.w !L_GMAP+(5*224),Y : BCS + : LDA.w !L_GMAP+(5*224),Y
+   CMP.w !L_GMAP+(6*224),Y : BCS + : LDA.w !L_GMAP+(6*224),Y
+   CMP.w !L_GMAP+(7*224),Y : BCS + : LDA.w !L_GMAP+(7*224),Y
+   CMP.w !L_COMP,Y : BEQ .next
    STA.w !L_COMP,Y
    JSR Hush_LightTile
.next
    INX : INY
    DEC.b $02 : BNE .cell
    LDA.w !L_JROW : INC A : STA.w !L_JROW
    CMP.b #28 : BCC .more
    ; done: commit the signature
    REP #$20
    LDA.w !L_JOB : AND.w #$0007 : ASL A : ASL A : TAX
    LDA.w !L_JSIG : STA.w !L_SIGC,X
    LDA.w !L_JSIG+2 : STA.w !L_SIGC+2,X
    SEP #$20
    LDA.b #$FF : STA.w !L_JOB
.more
    SEC
    RTS
Hush_Light_End:
assert pc() <= $1FC400                   ; src/FREESPACE.md row $1FB780-$1FC3FF
