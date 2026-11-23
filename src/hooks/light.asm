; =============================================================================
; light.asm  (L1: lantern light = guard sight, design/lighting.md; docs/engine_notes.md section 16)
;
; Not a hook file of its own: three existing HUSH routines call in (no new vanilla bytes are replaced):
;   roomload.asm  Hush_AttrSet   end `STZ.w $0200 : RTL` -> `JML Hush_LightInit` (which does the STZ and the RTL): after the collision map is built,
;                                in the forced blank of Module06 -> light state reset, cell solidity from $7F2000, BG1 window := no light (VRAM upload)
;   meter.asm     Hush_MeterFrame `.out` -> `JSL Hush_LightWork` (end of every Module07 frame, after the guards and Link ran)
;   menu_ui.asm   Hush_NmiTM      -> `JSL Hush_LightNmi` first (NMI, before the TM / TS writes of the vanilla NMI)
;   transition.asm Hush_InitTilesets `JSL $00E19B` -> `JSL Hush_LightTilesets` (InitializeTilesets, then the light tiles again: it rewrites slots 0-7)
;   transition.asm submodule $0F hook -> `JSL Hush_LightWipe` (Hush_Wipe + the light palette)
;
; Technique (the vanilla castle-escape lamp: BG1 cone added onto the dark room, OrientLampLightCone bank_00.asm:15413, RoomDraw_LampCones bank_01.asm:5679):
;   BG1 (hidden in HUSH rooms, its buffer $7E4000 still holds the floor that transition.asm copies) is put on the SUB screen ($1D bit 0) and colour math
;   ADDS it to BG2 + the backdrop ($99 = $02 sub screen addend, $9A = $22). Where BG1 is transparent the addend is the fixed colour (COLDATA = 0): no change.
;   OBJ and BG3 (sprites, HUD) take no colour math: they are never tinted.
;   Smooth look (design/lighting.md section 4, revision 2): the per-cell steps are samples at the cell centres; every 8x8 BG1 tile shows a
;   precomputed bilinear + Bayer gradient between its 4 corner levels (tools/autotile.py, build/light_gen.asm: Hush_LightLutA / LutV map a
;   corner tuple to a tile word incl. H/V flips, Hush_LightChr = 192 raw 4bpp tiles at BG tile ids $100-$1BF, Hush_LightRamp = BG row 2
;   colours 1-15). Tile (tx, ty) of cell (cx, cy) = (tx >> 1, ty >> 1), quadrant (tx & 1, ty & 1); C = the cell, H / V / D = its horizontal /
;   vertical / diagonal neighbour on the quadrant's side (outside the 16 x 14 grid = 0); corners: centre C, edge toward V (C+V+1)>>1, edge
;   toward H (C+H+1)>>1, cell corner (C+H+V+D+2)>>2 (= Q of lighting.md 4.1 for N = 7). Amber (COMP) wins; else violet (VIO, same formulas,
;   levels 0..2); else the empty tile.
;   A change of COMP / VIO of a cell updates the pair grids in bank $7F (Hush_LightAmb / Hush_LightVio, see "Pair grids" below) and marks
;   the 4 x 4 tile block around it in a tile bitmap (the commit collects a row segment's columns: Hush_LightMarkRow; the glow ring marks its
;   8 x 8 block once, Hush_LightMarkBlock).
;   Time-sliced render units (Hush_LightRender, one bitmap byte = up to 8 tiles per unit) recompute the marked tiles - per tile 2 grid loads,
;   1 add and 1 LUTF load (+ the violet lookup when there is no amber) - and mark their cell rows for the NMI upload.
;   BG character slots 4-6 (VRAM byte $6000-$77FF) are never drawn by a room (docs/gfx/art_map.md 2.1); Hush_LightChrUp loads the light
;   tiles there on every room load (Hush_LightInit) and after every full tileset load (Hush_LightTilesets, from transition.asm Hush_InitTilesets),
;   and moves the vanilla per-frame animated-tile upload (NMI `LDX $0134 : STX VMADDR`, $400 bytes, bank_00.asm:1936-1946; $0134 = $3B00 set
;   by DecompressAnimatedUnderworldTiles, bank_00.asm:9365) from word $3B00 (= tiles $1B0-$1CF, would overwrite the last 16 light tiles every
;   frame) to word $3C00 (tiles $1C0-$1DF, slot 7: never drawn by a room either).
;
; Model (per 16x16 cell of the 16 x 14 grid; padded grid 32 x 30 so ray offsets need no bounds checks, p = (cy + 8) * 32 + cx + 8):
;   SOL[p]   bit 0 solid (catches light, blocks), bit 6 ink cloud (dark, blocks), bit 7 outside the grid (dark, blocks)
;   per guard slot g (0-7): GMAP[g][i] = its light step per inner cell i = cy * 16 + cx; COMP[i] = max over g; VIO[i] = player glow 0..2
;   a guard's light is rebuilt as a JOB when its signature (class, facing, cell) differs from the committed one:
;     clear SCR in the job box -> origin + 1 wedge (cone) or 4 wedges (all around) from the generated ray tables (each entry lit iff its parent
;     entry is lit and not solid: light travels outwards, the first solid cell catches it) -> commit the job box row segment by row segment
;     (GMAP diff, COMP, pair grids, tile marks). The job box (Hush_LightBox) = the cells the slot's committed light or its new light can reach
;     (distance <= R + 1, a cone only on its facing side); outside it both are 0, so nothing else is cleared or compared. A job still in its
;     ray phase is restarted once when its guard already has a newer signature (Hush_LightStale).
;   The work is time-sliced: units start only while the PPU V counter is below LIGHT_VMAX, and the long ones (commit, render, job pick) also
;   stop at it (Hush_LightLate), so lighting never causes a lag frame. Order: a running guard job first (its tile marks collect and are
;   rendered once), then pending render work, then the next job. The glow (Hush_LightAura) updates in two halves (old ring off, new ring
;   on), each only when it starts before LIGHT_VMAX - 14.
;   NMI uploads <= 6 dirty cell rows (= 12 tile rows, 768 bytes) per frame (measured: the NMI reaches here at line ~250; vblank ends at 261).
;   light_job ($7EE770): slot 0-7 = a guard job runs, $FE = no job but render work pending, $FF = idle (the tile buffer matches COMP / VIO).
;   light_dirty ($7EE742): bits 0-13 = cell rows to upload, bit 15 = render work pending; 0 = the BG1 VRAM window equals light_tiles.
;
; Space:    src/FREESPACE.md rows $1FB780-$1FC3FF (this code), $1FC400-$1FC9FF (build/rooms_gen.asm: Hush_LightTab, Hush_LightWords - the
;           old per-cell words, no longer read) and $1FCA00-$1FFFFF (build/light_gen.asm, the render tables and the code that did not fit the
;           code row: Hush_LightGrids / ZeroGrids / Build / Amb / Vio; all bank $1F, so JSR works): vanilla room object data of rooms HUSH never
;           loads (rooms.asm:750-870) + the $FF tail NULL_1FFF4E, same evidence as the E1 room-data rows.
; RAM:      $7ECA00-$7EE7FF and $7F8000-$7FB3F1 (docs/ram_map.md "HUSH lighting"); direct page $00-$0F scratch (end of frame / Module06 only,
;           never in the NMI). Vanilla $7E0134 (animated tile VRAM word, see above). DMA channel 5 + WMDATA (grid reset; unused by vanilla).
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
!L_WORDS  = $E714        ; 18   old per-cell tile words (part of the Hush_LightTab copy; no longer read)
!L_TABLEN = 1302         ; bytes of Hush_LightTab (99 entries per wedge: d <= 9)
!L_ON     = $E740        ; 1  lighting active (set by Hush_LightInit)
!L_DIRTY  = $E742        ; 2  bits 0-13: cell rows whose tile words changed since their last upload; bit 15: render work pending (L_TD)
!L_SIGC   = $E748        ; 32 committed signature per slot: class, facing, p (2)
!L_TSIG   = $E768        ; 4  signature being tested
!L_JSIG   = $E76C        ; 4  signature of the running job
!L_JOB    = $E770        ; 1  slot of the running job; $FE = no job, render pending; $FF = idle
!L_JPH    = $E771        ; 1  job phase: 0 clear, 1 wedges, 2 commit
!L_JWN    = $E772        ; 1  wedges left
!L_JF     = $E773        ; 1  current wedge facing
!L_JE     = $E774        ; 2  2 * next entry
!L_JEND   = $E776        ; 2  2 * entries within the range + fringe
!L_JLVL   = $E778        ; 2  address of the step row
!L_JEDGE  = $E77A        ; 1  1 = cone (diagonal one step dimmer), 0 = all around
!L_JROW   = $E77B        ; 1  commit: cell row (L_JBY0 .. L_JBY1; > L_JBY1 = all rows done)
!L_RR     = $E77C        ; 1  round-robin slot
!L_LCELL  = $E77E        ; 2  player glow cell i, $FFFF = none
!L_INKP   = $E780        ; 2  ink cloud centre p, 0 = none
!L_PALREQ = $E782        ; 1  write the light colours into the palette buffers
!L_V0     = $E784        ; 2  V counter when the worker started
!L_TD     = $E786        ; 112 tile render bitmap: byte ty * 4 + (tx >> 3), bit tx & 7 (1 = recompute this BG1 tile)
!L_RCUR   = $E7F6        ; 2  render scan cursor (even byte offset into L_TD)
!L_JBX0   = $E7F8        ; 1  job box: first cell column (0..15)
!L_JBX1   = $E7F9        ; 1  job box: last cell column
!L_JBY0   = $E7FA        ; 1  job box: first cell row (0..13); an empty box has JBY0 = 1 > JBY1 = 0
!L_JBY1   = $E7FB        ; 1  job box: last cell row
!L_JCX    = $E7FC        ; 1  commit: next cell column of row L_JROW
!L_RSCN   = $E7FD        ; 2  render: L_TD words found empty in a row since the last mark (56 = the whole bitmap: render done)
!L_JRST   = $E7FF        ; 1  the running job was restarted once (Hush_LightStale) already

; bank $7F (DB = $7F while used; docs/ram_map.md light_pgrid / light_lutf / light_lutok): pair grids, 16 padded rows x 64 bytes each
!LP_AW98  = $8000
!LP_AW2   = $8400
!LP_AE98  = $8800
!LP_AE2   = $8C00
!LP_VW18  = $9000
!LP_VW2   = $9400
!LP_VE18  = $9800
!LP_VE2   = $9C00                ; .. $9FFF: the 8 grids are zeroed by one 8 KB DMA on every room load
!LP_LUTF  = $A000                ; 2401 words: (C, H, V, D) -> amber NW tile word
!LP_LUTFV = $B300                ; 81 words: violet
!LP_OK    = $B3F0                ; $4C48 = LUTF / LUTFV built

!LIGHT_VMAX = 200        ; no new unit at or after this scanline; long units also stop at it (Hush_LightLate). After LightWork the frame still
                         ; runs HandleFloorIndicator + PrepareOAMForTransfer (bank_02.asm:1509, bank_00.asm:76). Measured (tests/dev/nmi_probe.lua,
                         ; final room): end of logic max 219 of 225, 0 lag frames (204: max 223, too close; 196: r19 light latency too long)
!LIGHT_NMIROWS = 6       ; cell rows uploaded per NMI (768 bytes in 12 DMAs, ~7 lines from line ~250: ends before the vblank does at 261)

; -----------------------------------------------------------------------------
; Data: build/light_gen.asm (tools/roomgen.py from tools/autotile.py; data only, defines !HUSH_LIGHT_*) + the render tables.
; First in the file: the !HUSH_LIGHT_* defines are used by the code below.
org $1FCA00
Hush_LightGfx:
incsrc "!HUSH_LIGHT_GEN"
Hush_LightM98:                           ; [ab] 2 * 49 * ab: byte offset of the amber LUT row (a * 7 + b) * 49
    dw 0*98, 1*98, 2*98, 3*98, 4*98, 5*98, 6*98, 7*98, 8*98, 9*98, 10*98, 11*98, 12*98, 13*98, 14*98, 15*98
    dw 16*98, 17*98, 18*98, 19*98, 20*98, 21*98, 22*98, 23*98, 24*98, 25*98, 26*98, 27*98, 28*98, 29*98, 30*98, 31*98
    dw 32*98, 33*98, 34*98, 35*98, 36*98, 37*98, 38*98, 39*98, 40*98, 41*98, 42*98, 43*98, 44*98, 45*98, 46*98, 47*98
    dw 48*98
Hush_LightColMask:                       ; [4 * cx] tiles tx 2cx-1 .. 2cx+2 (clipped to 0..31) of one L_TD row: 2 words (tx 0-15, tx 16-31)
    dw $0007, $0000,  $001E, $0000,  $0078, $0000,  $01E0, $0000,  $0780, $0000,  $1E00, $0000,  $7800, $0000,  $E000, $0001
    dw $8000, $0007,  $0000, $001E,  $0000, $0078,  $0000, $01E0,  $0000, $0780,  $0000, $1E00,  $0000, $7800,  $0000, $E000
Hush_LightColMask3:                      ; [4 * cx] tiles tx 2cx-3 .. 2cx+4 (clipped): the glow ring of cell cx and its neighbours (Hush_LightMarkBlock)
    dw $001F, $0000,  $007F, $0000,  $01FE, $0000,  $07F8, $0000,  $1FE0, $0000,  $7F80, $0000,  $FE00, $0001,  $F800, $0007
    dw $E000, $001F,  $8000, $007F,  $0000, $01FE,  $0000, $07F8,  $0000, $1FE0,  $0000, $7F80,  $0000, $FE00,  $0000, $F800
Hush_LightT14:                           ; [v] 14 v
    dw 0, 14, 28, 42, 56, 70, 84
Hush_LightT686:                          ; [k] 686 k
    dw 0, 686, 1372, 2058, 2744, 3430, 4116
Hush_LightM18:                           ; [ab] 18 ab (violet: a * 3 + b <= 8)
    dw 0, 18, 36, 54, 72, 90, 108, 126, 144
Hush_LightT6:                            ; [v] 6 v
    dw 0, 6, 12
Hush_LightT54:                           ; [k] 54 k
    dw 0, 54, 108
Hush_LightZero:                          ; DMA fill source
    db $00

; Hush_LightGrids: JSR from Hush_LightInit (Module06, forced blank; same bank $1F), M = X = 16, any DB (kept). Zeroes the pair grids
; (Hush_LightZeroGrids) and builds LUTF / LUTFV once per power-on (light_lutok != $4C48; the intro's WRAM clear, Intro_Clear1kbBlocksOfWRAM
; bank_0C.asm:88-113, zeroes it, so a new game after the ending rebuilds them). (Code in the data row: the code row $1FB780-$1FC3FF is full.)
Hush_LightGrids:
    PHB
    JSR Hush_LightZeroGrids              ; ~48 scanlines of the forced-blank load pass
    PEA $7F7F : PLB : PLB
    LDA.w !LP_OK : CMP.w #$4C48 : BEQ +
    JSR Hush_LightBuild
    LDA.w #$4C48 : STA.w !LP_OK
+   PLB
    RTS

; Hush_LightZeroGrids: JSR, any M / X / DB (P kept). The 8 pair grids ($7F8000-$7F9FFF) := 0 by DMA channel 5 from a fixed zero byte to
; WMDATA ($2180): 8 KB, ~48 scanlines. Channel 5 and WMADD/WMDATA are used nowhere in vanilla (grep of vendor/usdasm: no DMA5* / $435x
; operand, no WMADD / $2181-$2183 operand) nor in src/.
Hush_LightZeroGrids:
    PHP
    REP #$20
    LDA.w #$8000 : STA.l $002181         ; WMADDL / WMADDM
    LDA.w #$8008 : STA.l $004350         ; DMAP5 $08 (A -> B, fixed source, 1 register), BBAD5 $80 (WMDATA)
    LDA.w #Hush_LightZero : STA.l $004352
    LDA.w #$2000 : STA.l $004355
    SEP #$20
    LDA.b #$01 : STA.l $002183           ; WMADDH: bank $7F
    LDA.b #Hush_LightZero>>16 : STA.l $004354
    LDA.b #$20 : STA.l $00420B           ; channel 5
    PLP
    RTS

; Hush_LightBuild: M = X = 16, DB = $7F, DP $00-$0B. LUTF[2 * (343C + 49H + 7V + D)] = Hush_LightLutA[686k + 98eV + 14eH + 2C] and
; LUTFV[2 * (27C + 9H + 3V + D)] = Hush_LightLutV[54k + 18eV + 6eH + 2C] (byte offsets) with k = (C+H+V+D+2) >> 2, eV = (C+V+1) >> 1,
; eH = (C+H+1) >> 1 (design/lighting.md 4.1: the NW tile of a cell C with west H, north V, north-west D: a = k, b = eV, c = eH, d = C).
Hush_LightBuild:
    LDY.w #$0000 : STZ.b $00
.c  STZ.b $02
.h  STZ.b $04
.v  LDA.b $00 : CLC : ADC.b $04 : INC A : LSR A : ASL A : TAX : LDA.l Hush_LightM98,X : STA.b $08      ; 98 eV
    LDA.b $00 : CLC : ADC.b $02 : INC A : LSR A : ASL A : TAX : LDA.l Hush_LightT14,X : CLC : ADC.b $08 : STA.b $08
    LDA.b $00 : ASL A : CLC : ADC.b $08 : STA.b $08                                                     ; + 2C
    LDA.b $00 : CLC : ADC.b $02 : ADC.b $04 : INC A : INC A : STA.b $0A                                  ; C + H + V + 2
    STZ.b $06
.d  LDA.b $0A : CLC : ADC.b $06 : LSR A : LSR A : ASL A : TAX
    LDA.l Hush_LightT686,X : CLC : ADC.b $08 : TAX
    LDA.l Hush_LightLutA,X : STA.w !LP_LUTF,Y : INY : INY
    INC.b $06 : LDA.b $06 : CMP.w #7 : BCC .d
    INC.b $04 : LDA.b $04 : CMP.w #7 : BCC .v
    INC.b $02 : LDA.b $02 : CMP.w #7 : BCC .h
    INC.b $00 : LDA.b $00 : CMP.w #7 : BCS .violet
    JMP .c
.violet
    LDY.w #$0000 : STZ.b $00
.vc STZ.b $02
.vh STZ.b $04
.vv LDA.b $00 : CLC : ADC.b $04 : INC A : LSR A : ASL A : TAX : LDA.l Hush_LightM18,X : STA.b $08      ; 18 eV
    LDA.b $00 : CLC : ADC.b $02 : INC A : LSR A : ASL A : TAX : LDA.l Hush_LightT6,X : CLC : ADC.b $08 : STA.b $08
    LDA.b $00 : ASL A : CLC : ADC.b $08 : STA.b $08
    LDA.b $00 : CLC : ADC.b $02 : ADC.b $04 : INC A : INC A : STA.b $0A
    STZ.b $06
.vd LDA.b $0A : CLC : ADC.b $06 : LSR A : LSR A : ASL A : TAX
    LDA.l Hush_LightT54,X : CLC : ADC.b $08 : TAX
    LDA.l Hush_LightLutV,X : STA.w !LP_LUTFV,Y : INY : INY
    INC.b $06 : LDA.b $06 : CMP.w #3 : BCC .vd
    INC.b $04 : LDA.b $04 : CMP.w #3 : BCC .vv
    INC.b $02 : LDA.b $02 : CMP.w #3 : BCC .vh
    INC.b $00 : LDA.b $00 : CMP.w #3 : BCC .vc
    RTS

; -----------------------------------------------------------------------------
; Pair grids (bank $7F, docs/ram_map.md light_pgrid): padded cell grid, offset G = (cy + 1) * 64 + (cx + 1) * 2 (row -1 and 14, column -1 and 16
; are padding = 0). For cell c with value C and its west / east neighbour W / E (0 outside the grid):
;   AW98[G] = 98 * (7C + W), AW2[G] = 2 * (7C + W), AE98[G] = 98 * (7C + E), AE2[G] = 2 * (7C + E)        (amber, COMP)
;   VW18[G] = 18 * (3C + W), VW2[G] = 2 * (3C + W), VE18 / VE2 the same with E                            (violet, VIO)
; Tile NW of cell G = LUTF[AW98[G] + AW2[G - 64]] = LUTF[2 * (343C + 49W + 7N + NW)]; NE: AE98[G] + AE2[G - 64], then H flip; SW: AW98[G] +
; AW2[G + 64], V flip; SE: AE98[G] + AE2[G + 64], H + V flip. LUTF[(C, H, V, D)] = the word of the NW tile of a cell with these cells (built
; once, Hush_LightBuild): the corner tuple of the other quadrants is the NW tuple of their own (C, H, V, D) mirrored, hence the flips.
; Tile render, inline (Hush_LightRender): Y = G of the cell, DB = $7F, M = X = 16, $06 = L_TILES offset of the cell's west tile of this row.
; Amber word from LUTF (pairs <a98>[G] + <a2>[G <off>]), else the violet word from LUTFV, else the empty tile; <flip> = the quadrant's H/V
; flip (not applied to the empty tile). Stored at L_TILES + $06 + <toff> if it changed ($0A += 1). Keeps Y.
macro lighttile(a98, a2, v18, v2, off, flip, toff)
    LDA.w <a98>,Y : CLC : ADC.w <a2><off>,Y : TAX
    LDA.w !LP_LUTF,X : CMP.w #!HUSH_LIGHT_EMPTY : BNE ++
    LDA.w <v18>,Y : CLC : ADC.w <v2><off>,Y : TAX
    LDA.w !LP_LUTFV,X : CMP.w #!HUSH_LIGHT_EMPTY : BEQ +
++  EOR.w #<flip>
+   LDX.b $06
    CMP.l $7E0000+!L_TILES+<toff>,X : BEQ +
    STA.l $7E0000+!L_TILES+<toff>,X
    INC.b $0A
+
endmacro
macro lightcode(a, b, m)                 ; M = 8 -> X = 2 * (m * <a> + <b>) (m = 7 or 3), M = 8 on exit
    LDA.b <a>
    if <m> == 7
        ASL A : ASL A : ASL A : SEC : SBC.b <a>
    else
        ASL A : CLC : ADC.b <a>
    endif
    CLC : ADC.b <b>
    REP #$20 : AND.w #$00FF : ASL A : TAX : SEP #$20
endmacro
macro lightpairs(src, m, tab, w98, w2, e98, e2)   ; Y = cell i, M = 8, X = 16, DB = $7E; uses $0A, $0B, $0E and the stack; Y := G, DB := $7E again
    LDA.w <src>,Y : STA.b $0A            ; C
    STZ.b $0B : STZ.b $0E
    TYA : AND.b #$0F : BEQ +
    LDA.w <src>-1,Y : STA.b $0B          ; W
+   TYA : AND.b #$0F : CMP.b #$0F : BEQ +
    LDA.w <src>+1,Y : STA.b $0E          ; E
+   REP #$20
    TYA : AND.w #$000F : ASL A : PHA
    TYA : AND.w #$00F0 : ASL A : ASL A : CLC : ADC $01,S : ADC.w #66 : TAY : PLA
    SEP #$20
    PHB : PEA $7F7F : PLB : PLB
    %lightcode($0A, $0B, <m>)            ; (C, W): this cell's west pair
    REP #$20 : LDA.l <tab>,X : STA.w <w98>,Y : TXA : STA.w <w2>,Y : SEP #$20
    %lightcode($0B, $0A, <m>)            ; (W, C): the west neighbour's east pair
    REP #$20 : LDA.l <tab>,X : STA.w <e98>-2,Y : TXA : STA.w <e2>-2,Y : SEP #$20
    %lightcode($0A, $0E, <m>)            ; (C, E): this cell's east pair
    REP #$20 : LDA.l <tab>,X : STA.w <e98>,Y : TXA : STA.w <e2>,Y : SEP #$20
    %lightcode($0E, $0A, <m>)            ; (E, C): the east neighbour's west pair
    REP #$20 : LDA.l <tab>,X : STA.w <w98>+2,Y : TXA : STA.w <w2>+2,Y : SEP #$20
    PLB
endmacro

; Hush_LightAmb / Hush_LightVio: Y = cell i (M = 8, X = 16, DB = $7E): COMP / VIO of the cell changed -> the amber / violet pair grids.
; Keep X, Y; use $0A, $0B, $0E. JSR from the code row (same bank $1F). Hush_LightVio sets no tile marks: Hush_LightAura marks the whole ring.
Hush_LightAmb:
    PHX : PHY
    %lightpairs(!L_COMP, 7, Hush_LightM98, !LP_AW98, !LP_AW2, !LP_AE98, !LP_AE2)
    PLY : PLX
    RTS
Hush_LightVio:
    PHX : PHY
    %lightpairs(!L_VIO, 3, Hush_LightM18, !LP_VW18, !LP_VW2, !LP_VE18, !LP_VE2)
    PLY : PLX
    RTS

; -----------------------------------------------------------------------------
; Hush_LightBox: JSR from the job's clear phase (M = 8, X = 16, DB = $7E). The job box = the cells the slot's committed light (L_SIGC) or the
; job's new light (L_JSIG) can reach: a light only reaches Chebyshev distance e = R + 1 from its guard cell (6 dark, 9 lit, design/lighting.md
; section 3), a cone (class 1) only on its facing side. Invalid committed signature ($FF, after an ink change): the whole grid. Then
; scratch := 0 inside the box (the wedges write only there; the commit reads only there). Uses $00-$0B. (Data row: the code row is full.)
Hush_LightBox:
    REP #$20
    LDA.w $C900 : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX
    LDA.l Hush_RoomTable+19,X
    SEP #$20
    LSR A
    LDA.b #6 : BCC +
    LDA.b #9
+   STA.b $06
    LDA.b #$FF : STA.w !L_JBX0 : STA.w !L_JBY0
    STZ.w !L_JBX1 : STZ.w !L_JBY1
    LDA.w !L_JSIG : STA.b $00 : LDA.w !L_JSIG+1 : STA.b $01
    REP #$20 : LDA.w !L_JSIG+2 : STA.b $02 : SEP #$20
    JSR .sig                             ; the new light
    REP #$20 : LDA.w !L_JOB : AND.w #$0007 : ASL A : ASL A : TAX : SEP #$20
    LDA.w !L_SIGC,X : CMP.b #$FF : BNE +
    LDA.b #16 : STA.w !L_JBX0 : STA.w !L_JBY0               ; invalid: the whole grid (coordinates + 16)
    LDA.b #31 : STA.w !L_JBX1
    LDA.b #29 : STA.w !L_JBY1
    BRA .clip
+   STA.b $00 : LDA.w !L_SIGC+1,X : STA.b $01
    REP #$20 : LDA.w !L_SIGC+2,X : STA.b $02 : SEP #$20
    JSR .sig                             ; the committed light
.clip
    LDA.w !L_JBX1 : BNE +
    STZ.w !L_JBX0 : STZ.w !L_JBX1 : STZ.w !L_JBY1           ; neither light exists: empty box
    LDA.b #$01 : STA.w !L_JBY0
    RTS
+   LDA.w !L_JBX0 : CMP.b #16 : BCS +
    LDA.b #16
+   SEC : SBC.b #16 : STA.w !L_JBX0
    LDA.w !L_JBX1 : CMP.b #32 : BCC +
    LDA.b #31
+   SEC : SBC.b #16 : STA.w !L_JBX1
    LDA.w !L_JBY0 : CMP.b #16 : BCS +
    LDA.b #16
+   SEC : SBC.b #16 : STA.w !L_JBY0
    LDA.w !L_JBY1 : CMP.b #30 : BCC +
    LDA.b #29
+   SEC : SBC.b #16 : STA.w !L_JBY1
    LDA.w !L_JBY0 : STA.b $08
.crow                                    ; scratch := 0 on the box rows (all 16 cells of a row: 8 word stores, cheaper than a byte loop)
    REP #$20
    LDA.b $08 : AND.w #$00FF : CLC : ADC.w #8 : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.w #8 : TAX
    STZ.w !L_SCR,X : STZ.w !L_SCR+2,X : STZ.w !L_SCR+4,X : STZ.w !L_SCR+6,X
    STZ.w !L_SCR+8,X : STZ.w !L_SCR+10,X : STZ.w !L_SCR+12,X : STZ.w !L_SCR+14,X
    SEP #$20
    LDA.b $08 : INC A : STA.b $08
    CMP.w !L_JBY1 : BEQ .crow : BCC .crow
    RTS
.sig                                     ; $00 class (0: none), $01 facing, $02 p -> merged into the box (coordinates + 16, still unclipped)
    LDA.b $00 : BNE +
    RTS
+   LDA.b $02 : AND.b #$1F : CLC : ADC.b #8 : STA.b $04     ; gx + 16 (p & 31 = gx + 8)
    REP #$20 : LDA.b $02 : LSR A : LSR A : LSR A : LSR A : LSR A : SEP #$20
    CLC : ADC.b #8 : STA.b $05                              ; gy + 16 (p >> 5 = gy + 8)
    LDA.b $04 : SEC : SBC.b $06 : STA.b $08
    LDA.b $04 : CLC : ADC.b $06 : STA.b $09
    LDA.b $05 : SEC : SBC.b $06 : STA.b $0A
    LDA.b $05 : CLC : ADC.b $06 : STA.b $0B
    LDA.b $00 : CMP.b #$01 : BNE .merge  ; a cone covers only its facing side (facing 0 right, 1 left, 2 down, 3 up; tools/roomgen.py rot)
    LDA.b $01 : AND.b #$03 : BNE +
    LDA.b $04 : STA.b $08 : BRA .merge
+   CMP.b #$01 : BNE +
    LDA.b $04 : STA.b $09 : BRA .merge
+   CMP.b #$02 : BNE +
    LDA.b $05 : STA.b $0A : BRA .merge
+   LDA.b $05 : STA.b $0B
.merge
    LDA.b $08 : CMP.w !L_JBX0 : BCS +
    STA.w !L_JBX0
+   LDA.b $09 : CMP.w !L_JBX1 : BCC +
    STA.w !L_JBX1
+   LDA.b $0A : CMP.w !L_JBY0 : BCS +
    STA.w !L_JBY0
+   LDA.b $0B : CMP.w !L_JBY1 : BCC +
    STA.w !L_JBY1
+   RTS

; Hush_LightLate: M = 8 (kept), X = 16; keeps X, Y. C = 1: the frame's light time is over (V counter >= LIGHT_VMAX or wrapped into the next
; frame). Lets the long units (commit, job pick) stop in the middle.
Hush_LightLate:
    JSR Hush_LightV                      ; M = 16
    CMP.w !L_V0 : BCC +
    CMP.w #!LIGHT_VMAX
    SEP #$20
    RTS
+   SEP #$20
    SEC
    RTS

; Hush_LightStale: JSR from Hush_LightStep (wedge phase; M = 8, X = 16). C = 1: the job's guard has a new signature already -> L_JSIG := it,
; phase 0 (the job restarts; nothing was committed yet, so the job box of the restart covers everything). C = 0: still current.
Hush_LightStale:
    REP #$20 : LDA.w !L_JOB : AND.w #$0007 : TAX : SEP #$20
    JSR Hush_LightSig
    REP #$20
    LDA.w !L_TSIG : CMP.w !L_JSIG : BNE .new
    LDA.w !L_TSIG+2 : CMP.w !L_JSIG+2 : BNE .new
    SEP #$20
    CLC
    RTS
.new
    LDA.w !L_TSIG : STA.w !L_JSIG
    LDA.w !L_TSIG+2 : STA.w !L_JSIG+2
    SEP #$20
    STZ.w !L_JPH
    SEC
    RTS
Hush_LightGfx_End:
assert !HUSH_LIGHT_LN == 7               ; the index arithmetic below (x 7, x 3) and the Q formulas assume these
assert !HUSH_LIGHT_LNV == 3
assert Hush_LightChr_End-Hush_LightChr == !HUSH_LIGHT_CHRSIZE
assert !HUSH_LIGHT_TILEBASE+(!HUSH_LIGHT_CHRSIZE/32) <= $1C0           ; slots 4-6 only (slot 7 takes the animated tiles)
assert pc() <= $1FFFFF                   ; src/FREESPACE.md row $1FCA00-$1FFFFF

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
    LDX.w #$0000 : LDA.w #!HUSH_LIGHT_EMPTY
-   STA.w !L_TILES,X : INX : INX : CPX.w #1792 : BCC -
    LDX.w #$0000 : TXA
-   STA.w !L_TD,X : INX : INX : CPX.w #112 : BCC -                    ; nothing to render
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
    STA.w !L_DIRTY : STA.w !L_INKP : STA.w !L_JE : STA.w !L_RCUR : STA.w !L_RSCN
    DEC A : STA.w !L_LCELL
    SEP #$20
    LDA.b #$FF : STA.w !L_JOB
    STZ.w !L_RR
    LDA.b #$01 : STA.w !L_PALREQ : STA.w !L_ON
    REP #$30
    JSR Hush_LightGrids                  ; pair grids := 0 (COMP / VIO are 0), LUTF built once
    SEP #$20
    JSL Hush_LightChrUp                  ; the light tiles (slots 4-6) + the animated tiles moved to slot 7
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
; Hush_LightChrUp: JSL, forced blank only (Module06), any M / X / DB, keeps P. DMA0: Hush_LightChr -> VRAM word $3000 (byte $6000 = BG tile
; !HUSH_LIGHT_TILEBASE: BG12NBA = $22, BG1/BG2 characters at word $2000, Intro_InitializeBackgroundSettings bank_02.asm:12633, the only write);
; then $0134 := $3C00 (the NMI's animated-tile upload, bank_00.asm:1936-1946, goes to slot 7 instead of over the light tiles $1B0-$1BF).
Hush_LightChrUp:
    PHP
    SEP #$20
    LDA.b #$80 : STA.l $002115           ; VMAIN: increment after the high byte
    LDA.b #Hush_LightChr>>16 : STA.l $004304
    REP #$20
    LDA.w #$2000+(!HUSH_LIGHT_TILEBASE*16) : STA.l $002116      ; word address of the first light tile (16 words per 4bpp tile)
    LDA.w #$1801 : STA.l $004300         ; DMA0: mode 1 to VMDATA
    LDA.w #Hush_LightChr : STA.l $004302
    LDA.w #!HUSH_LIGHT_CHRSIZE : STA.l $004305
    SEP #$20
    LDA.b #$01 : STA.l $00420B
    REP #$20
    LDA.w #$3C00 : STA.l $7E0134
    PLP
    RTL

; Hush_LightTilesets: JSL from Hush_InitTilesets (transition.asm, full load only, forced blank) instead of `JSL $00E19B`: InitializeTilesets
; rewrites BG slots 0-7, so the light tiles are loaded again after it.
Hush_LightTilesets:
    JSL $00E19B                          ; InitializeTilesets (bank_00.asm:11607)
    JSL Hush_LightChrUp
    RTL

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
    LDA.l $7E0000+!L_DIRTY : AND.w #$3FFF : BEQ .done        ; bit 15 (render pending) is not an upload
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
    LDA.w $C558 : CMP.l Hush_LightRamp+22 : SEP #$20 : BEQ +  ; row 2 colour 12 (the amber core)
    LDA.b #$01 : STA.w !L_PALREQ         ; the palette buffer was reloaded (room load, menu): light colours + soft shadow again
+   JSR Hush_LightV : STA.w !L_V0
    CMP.w #!LIGHT_VMAX : BCS .exit       ; no spare time this frame: everything waits (the colour-math shadows above are set every frame)
    SEP #$20
    LDA.w !L_PALREQ : BEQ +
    REP #$20 : LDA.w !L_V0 : CMP.w #150 : SEP #$20 : BCS +   ; ~20 lines of work: only early in the frame
    JSR Hush_LightPal
+   JSR Hush_LightInk
    REP #$20 : LDA.w !L_V0 : CMP.w #(!LIGHT_VMAX-14) : SEP #$20 : BCS +   ; the glow (one half: ~14 lines) only with room left
    JSR Hush_LightAura
+   JSR Hush_LightV
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

Hush_LightPal:                           ; M = 8, X = 16. Light colours (BG row 2, colours 1-15: Hush_LightRamp) + the soft shadow: room rows 3-7 dimmed
    STZ.w !L_PALREQ
    REP #$20
    LDX.w #$0000
-   LDA.l Hush_LightRamp,X
    STA.w $C542,X : STA.w $C342,X        ; $7EC500 / $7EC300 + row 2 * 32 + colour 1 * 2
    INX : INX : CPX.w #30 : BCC -
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
    JSR Hush_LightIdle                   ; abort the running job
    LDA.b #$FF
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
    JSR Hush_LightVio
    REP #$20
    LDA.w !L_LCELL : JSR Hush_LightMarkBlock
    LDA.w #$FFFF : STA.w !L_LCELL        ; no glow for now: the new ring is set by the next call (two halves of ~14 scanlines each)
    BRA .same
+   LDA.b $04 : STA.w !L_LCELL : BMI .same
    LDA.w #$0001 : STA.b $08
    LDA.b $04 : JSR .ring
    SEP #$20
    LDY.w !L_LCELL
    JSR Hush_LightFloor : BNE +
    LDA.b #$02 : STA.w !L_VIO,Y
    JSR Hush_LightVio
+   REP #$20
    LDA.w !L_LCELL : JSR Hush_LightMarkBlock
.same
    SEP #$20
    RTS
.ring                                    ; A = centre i (M = 16), $08 = value: the 4 orthogonal neighbours inside the grid; the value is only set on
    STA.b $06                            ; floor cells (0 = clear: always). No tile marks: the caller marks the whole ring (Hush_LightMarkBlock)
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
    JSR Hush_LightVio
.rskip
    REP #$20
.rnext
    DEX : DEX : BPL .rn
    RTS

; Hush_LightMarkBlock: A = cell i (M = 16, X = 16): the glow of cell i and its 4 neighbours changed -> marks every tile they can affect
; (tx 2cx-3 .. 2cx+4, ty 2cy-3 .. 2cy+4, clipped; one pass instead of 5 per-cell marks). Uses $0A-$0F, keeps $00-$09. Returns M = 16.
Hush_LightMarkBlock:
    PHA
    AND.w #$000F : ASL A : ASL A : TAX
    LDA.l Hush_LightColMask3,X : STA.b $0A
    LDA.l Hush_LightColMask3+2,X : STA.b $0E
    PLA : AND.w #$00F0 : LSR A : LSR A : LSR A                ; 2cy
    PHA
    CLC : ADC.w #4 : CMP.w #28 : BCC +
    LDA.w #27
+   STA.b $0C                                                  ; last tile row
    PLA : SEC : SBC.w #3 : BPL +
    LDA.w #$0000
+   PHA                                                        ; first tile row
    LDA.b $0C : SEC : SBC $01,S : INC A : TAX                  ; rows
    PLA : ASL A : ASL A : TAY
.row
    LDA.w !L_TD,Y : ORA.b $0A : STA.w !L_TD,Y
    LDA.w !L_TD+2,Y : ORA.b $0E : STA.w !L_TD+2,Y
    INY : INY : INY : INY
    DEX : BNE .row
    LDA.w #$8000 : TSB.w !L_DIRTY
    STZ.w !L_RSCN                        ; new marks: the render's empty-scan count starts again
    SEP #$20
    LDA.w !L_JOB : CMP.b #$FF : BNE +
    DEC A : STA.w !L_JOB                 ; $FE: no job, render pending
+   REP #$20
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
; Hush_LightMarkRow: from Hush_LightCommit (M = 8, X = 16, DB = $7E): the cells of cell row L_JROW whose COMP changed in this unit marked
; their tile columns (tx 2cx-1 .. 2cx+2) in $06 / $08 (32 bits); mark those columns in tile rows 2cy-1 .. 2cy+2 (clipped) of L_TD for
; Hush_LightRender (one pass per row segment instead of 4 rows per changed cell), set light_dirty bit 15 (render pending). The job runs,
; so light_job stays its slot. Clears the mask. Keeps X, Y; M = 8 on exit.
Hush_LightMarkRow:
    PHX : PHY
    REP #$20
    LDA.b $06 : ORA.b $08 : BEQ .none
    LDA.w !L_JROW : AND.w #$00FF : BEQ .top
    ASL A : ASL A : ASL A : SEC : SBC.w #4 : TAY             ; L_TD offset of tile row 2cy - 1
    LDX.w #4
    CPY.w #100 : BNE .row
    DEX                                                        ; cy = 13: rows 25..27
    BRA .row
.top
    LDY.w #$0000 : LDX.w #3                                    ; cy = 0: rows 0..2
.row
    LDA.w !L_TD,Y : ORA.b $06 : STA.w !L_TD,Y
    LDA.w !L_TD+2,Y : ORA.b $08 : STA.w !L_TD+2,Y
    INY : INY : INY : INY
    DEX : BNE .row
    LDA.w #$8000 : TSB.w !L_DIRTY
    STZ.w !L_RSCN                        ; new marks: the render's empty-scan count starts again
    STZ.b $06 : STZ.b $08
.none
    SEP #$20
    PLY : PLX
    RTS

; Hush_LightIdle: M = 8. No job running: light_job := $FE while render work is pending, else $FF.
Hush_LightIdle:
    LDA.b #$FF
    BIT.w !L_DIRTY+1 : BPL +
    DEC A
+   STA.w !L_JOB
    RTS

; -----------------------------------------------------------------------------
; Hush_LightRender: one unit (M = 8, X = 16): the next non-empty L_TD byte (up to 8 tiles of one tile row) is cleared and its tiles are
; recomputed (inline, %lighttile: 2 pair-grid loads + 1 LUTF load per tile, DB = $7F, one cell = 2 tiles per step). A full pass over L_TD
; without a marked byte (L_RSCN, at most 8 words scanned per unit) ends the render work (light_dirty bit 15 := 0, light_job $FE -> $FF).
; The V counter is checked every cell; unfinished bits go back into L_TD.
; C = 1. DP: $00 bits left, $02 tx, $04 G of column 0, $06 L_TILES offset, $08 4 * (ty & 1), $0A words changed, $0C ty, $0E temp.
Hush_LightRender:
    REP #$20
    LDX.w !L_RCUR
    LDY.w #8                             ; at most 8 words per unit (a full pass is 56 words: ~7 scanlines)
.scan
    LDA.w !L_TD,X : BNE .found
    INX : INX : CPX.w #112 : BCC +
    LDX.w #$0000
+   INC.w !L_RSCN
    DEY : BNE .scan
    STX.w !L_RCUR
    LDA.w !L_RSCN : CMP.w #56 : SEP #$20 : BCC +             ; not yet a whole empty pass: more next unit
    LDA.b #$80 : TRB.w !L_DIRTY+1        ; nothing marked: every tile matches COMP / VIO
    LDA.w !L_JOB : CMP.b #$FE : BNE +
    LDA.b #$FF : STA.w !L_JOB
+   SEC
    RTS
.found
    STZ.w !L_RSCN
    STX.w !L_RCUR
    SEP #$20
    LDA.w !L_TD,X : BNE .byte
    INX                                  ; the low byte is empty: the high one
    LDA.w !L_TD,X
.byte
    STZ.w !L_TD,X
    REP #$20
    AND.w #$00FF : STA.b $00                                   ; bits left
    TXA : ASL A : ASL A : ASL A : ASL A : STA.b $06            ; L_TILES offset of bit 0: 8 tiles per byte, 2 bytes per word
    TXA : LSR A : LSR A : STA.b $0C                            ; ty
    AND.w #$0001 : ASL A : ASL A : STA.b $08                   ; 4 * (ty & 1): quadrant row
    LDA.b $0C : AND.w #$00FE : INC A : INC A : XBA : LSR A : LSR A : LSR A : CLC : ADC.w #2 : STA.b $04   ; G of column 0: (cy + 1) * 64 + 2
    TXA : AND.w #$0003 : ASL A : ASL A : ASL A : STA.b $02     ; tx of bit 0
    STZ.b $0A                                                  ; no word changed yet
    PHB : PEA $7F7F : PLB : PLB          ; DB = $7F: the pair grids and LUTF
    LDA.b $02 : CLC : ADC.b $04 : TAY    ; G of the byte's first cell (tx of bit 0 is even); 2 tiles (bits) per cell
    LDA.b $08 : BEQ .even
    JMP .odd
.even                                    ; even tile row: NW, NE tiles of each cell (north pairs at G - 64)
    LSR.b $00 : BCC .e1
    %lighttile(!LP_AW98, !LP_AW2, !LP_VW18, !LP_VW2, -64, $0000, 0)
.e1
    LSR.b $00 : BCC .e2
    %lighttile(!LP_AE98, !LP_AE2, !LP_VE18, !LP_VE2, -64, $4000, 2)
.e2
    JSR .adv : BCC .ej
    JMP .out
.ej JMP .even
.odd                                     ; odd tile row: SW, SE tiles (south pairs at G + 64)
    LSR.b $00 : BCC .o1
    %lighttile(!LP_AW98, !LP_AW2, !LP_VW18, !LP_VW2, +64, $8000, 0)
.o1
    LSR.b $00 : BCC .o2
    %lighttile(!LP_AE98, !LP_AE2, !LP_VE18, !LP_VE2, +64, $C000, 2)
.o2
    JSR .adv : BCS .out
    JMP .odd
.adv                                     ; next cell; C = 1: no bits left or out of time (time checked every cell = 2 tiles)
    INY : INY
    LDA.b $06 : CLC : ADC.w #4 : STA.b $06
    INC.b $02 : INC.b $02
    LDA.b $00 : BEQ +
    JSR Hush_LightV                      ; M = 16
    CMP.l $7E0000+!L_V0 : BCC +          ; wrapped into the next frame
    CMP.w #!LIGHT_VMAX
    RTS
+   SEC
    RTS
.out
    LDA.b $00 : BEQ .done
.late                                    ; out of time: the bits not done yet go back into L_TD (shifted back by tx & 7)
    PLB                                  ; DB = $7E
    LDA.b $02 : AND.w #$0007 : TAX
    LDA.b $00
-   DEX : BMI +
    ASL A
    BRA -
+   STA.b $00
    LDA.b $0C : ASL A : ASL A : STA.b $0E
    LDA.b $02 : AND.w #$00FF : LSR A : LSR A : LSR A : CLC : ADC.b $0E : TAX     ; ty * 4 + (tx >> 3)
    SEP #$20
    LDA.b $00 : ORA.w !L_TD,X : STA.w !L_TD,X
    REP #$20
    BRA .mark
.done
    PLB                                  ; DB = $7E
.mark                                    ; M = 16: the cell row goes to the NMI if a word changed (after the words: the NMI may run in between)
    LDA.b $0A : BEQ +
    LDA.b $0C : AND.w #$00FE : TAX
    LDA.l Hush_LightBit,X : TSB.w !L_DIRTY
+   SEP #$20
    SEC
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
; Hush_LightStep: one unit of work (M = 8, X = 16). C = 0: nothing to do. A running guard job first (its tile marks collect in L_TD and are
; rendered once, deduplicated), then pending render work, then the next job.
Hush_LightStep:
    LDA.w !L_JOB : BPL .job
    BIT.w !L_DIRTY+1 : BPL +
    JMP Hush_LightRender
+
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
    DEC.b $0A : BEQ +
    JSR Hush_LightLate : BCC .pick       ; out of time: the round robin goes on from here next frame
    LDA.b $0B : STA.w !L_RR
    SEC
    RTS
+   CLC
    RTS
.start
    LDA.w !L_TSIG : STA.w !L_JSIG
    LDA.w !L_TSIG+2 : STA.w !L_JSIG+2
    SEP #$20
    LDA.b $0B : AND.b #$07 : STA.w !L_JOB
    INC A : STA.w !L_RR
    STZ.w !L_JPH
    STZ.w !L_JRST
    SEC
    RTS
.job
    LDA.w !L_JPH : BEQ .clear
    CMP.b #$01 : BNE +
    LDA.w !L_JRST : BNE ++               ; one restart per job: a guard that keeps moving must still get its light
    JSR Hush_LightStale : BCC ++         ; the guard moved again before its rays are done: restart with the new signature
    INC.w !L_JRST
    BRA .clear
++  JMP Hush_LightWedge
+   JMP Hush_LightCommit

.clear                                   ; the job box (cells the old or the new light can touch) -> scratch := 0 there, then the job set-up
    JSR Hush_LightBox
    STZ.w !L_JE : STZ.w !L_JE+1
    LDA.b #$02 : STA.w !L_JPH            ; no light: straight to the commit
    LDA.w !L_JBY0 : STA.w !L_JROW
    LDA.w !L_JBX0 : STA.w !L_JCX
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
    LDA.w !L_JE : TAX : CLC : ADC.w #16     ; 8 entries per unit
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
    LDA.w !L_JBY0 : STA.w !L_JROW        ; the commit starts at the top-left of the job box
    LDA.w !L_JBX0 : STA.w !L_JCX
.more
    SEC
    RTS

; -----------------------------------------------------------------------------
; Hush_LightCommit: one row segment of the job box (L_JCX .. L_JBX1 of row L_JROW), stopping early after a changed composite cell when the
; frame's time is up (a changed cell updates 4 grid pairs and marks 16 tiles, ~600 cycles) -> GMAP[slot], COMP, pair grids + tile marks (M = 8, X = 16). Only cells of the
; box can differ (outside it the old and the new light are both 0). After the last box row the signature is committed.
; COMP update without the 8-way max where possible: new >= COMP -> COMP = new; new < COMP and old < COMP -> unchanged (another slot holds the
; max); only old == COMP > new needs the max over the 8 slots.
Hush_LightCommit:
    LDA.w !L_JROW : CMP.w !L_JBY1 : BEQ + : BCC +
    JMP .end                             ; empty box or done
+   REP #$20
    LDA.w !L_JOB : AND.w #$0007 : STA.b $00
    ASL A : ASL A : ASL A : SEC : SBC.b $00 : ASL A : ASL A : ASL A : ASL A : ASL A        ; slot * 224
    CLC : ADC.w #!L_GMAP : STA.b $0C
    LDA.w !L_JROW : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : STA.b $00
    LDA.w !L_JCX : AND.w #$00FF : CLC : ADC.b $00 : TAY                       ; i = row * 16 + cx
    LDA.w !L_JROW : AND.w #$00FF : CLC : ADC.w #8 : ASL A : ASL A : ASL A : ASL A : ASL A : STA.b $00
    LDA.w !L_JCX : AND.w #$00FF : CLC : ADC.b $00 : ADC.w #8 : TAX            ; p
    SEP #$20
    LDA.w !L_JBX1 : SEC : SBC.w !L_JCX : INC A : STA.b $02                    ; cells left in the row segment
    STZ.b $06 : STZ.b $07 : STZ.b $08 : STZ.b $09                             ; tile columns to mark (32 bits, Hush_LightMarkRow)
.cell
    LDA.w !L_SCR,X : CMP.b ($0C),Y : BNE .chg
.next
    INX : INY
    DEC.b $02 : BNE .cell
    JSR Hush_LightMarkRow
    LDA.w !L_JBX0 : STA.w !L_JCX         ; row done: the next box row
    LDA.w !L_JROW : INC A : STA.w !L_JROW
    SEC
    RTS
.chg
    STA.b $04                            ; new
    LDA.b ($0C),Y : STA.b $05            ; old
    LDA.b $04 : STA.b ($0C),Y
    CMP.w !L_COMP,Y : BEQ .next
    BCS .set                             ; new > COMP
    LDA.b $05 : CMP.w !L_COMP,Y : BCC .next                 ; old < COMP: another slot holds the max
    LDA.w !L_GMAP+(0*224),Y              ; old was the max: the max over the 8 slots
    CMP.w !L_GMAP+(1*224),Y : BCS + : LDA.w !L_GMAP+(1*224),Y
+   CMP.w !L_GMAP+(2*224),Y : BCS + : LDA.w !L_GMAP+(2*224),Y
+   CMP.w !L_GMAP+(3*224),Y : BCS + : LDA.w !L_GMAP+(3*224),Y
+   CMP.w !L_GMAP+(4*224),Y : BCS + : LDA.w !L_GMAP+(4*224),Y
+   CMP.w !L_GMAP+(5*224),Y : BCS + : LDA.w !L_GMAP+(5*224),Y
+   CMP.w !L_GMAP+(6*224),Y : BCS + : LDA.w !L_GMAP+(6*224),Y
+   CMP.w !L_GMAP+(7*224),Y : BCS + : LDA.w !L_GMAP+(7*224),Y
+   CMP.w !L_COMP,Y : BEQ .next
.set
    STA.w !L_COMP,Y
    JSR Hush_LightAmb                    ; the amber pair grids
    PHX                                  ; its 4 tile columns (tx 2cx-1 .. 2cx+2) join the row's mark
    REP #$20
    TYA : AND.w #$000F : ASL A : ASL A : TAX
    LDA.l Hush_LightColMask,X : TSB.b $06
    LDA.l Hush_LightColMask+2,X : TSB.b $08
    SEP #$20
    PLX
    JSR Hush_LightLate : BCS +           ; out of time: stop after this cell
    JMP .next
+   JSR Hush_LightMarkRow
    INX : INY
    DEC.b $02 : BNE +
    LDA.w !L_JBX0 : STA.w !L_JCX
    LDA.w !L_JROW : INC A : STA.w !L_JROW
    SEC
    RTS
+   LDA.w !L_JBX1 : INC A : SEC : SBC.b $02 : STA.w !L_JCX                    ; cx of the next cell
    SEC
    RTS
.end
    REP #$20
    LDA.w !L_JOB : AND.w #$0007 : ASL A : ASL A : TAX
    LDA.w !L_JSIG : STA.w !L_SIGC,X
    LDA.w !L_JSIG+2 : STA.w !L_SIGC+2,X
    SEP #$20
    JSR Hush_LightIdle                   ; $FF, or $FE while its tiles still have to be rendered
    SEC
    RTS
Hush_Light_End:
assert pc() <= $1FC400                   ; src/FREESPACE.md row $1FB780-$1FC3FF
