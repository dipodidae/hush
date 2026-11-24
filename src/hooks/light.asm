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
;   L3 B1 (src/dev/L3_REPORT.md): the L2 cell-pair renderer (pair grids, LUTF, tile marks, Hush_LightRender) is removed. Each carrier
;   (guard slot 0-7, glow 8) now has its own 4.1 lattice in bank $7F (L3_* below): a guard job's phase 3 (Hush_L3Lat, one lattice row per
;   unit) builds it from the job scratch; the glow update (Hush_LightAura; D4: one step, lattice from L3_GTAB) rebuilds the glow lattice.
;   L3 B2d: the region driver (Hush_L3Unit / RegStep / Pick, end of the code row) re-renders a carrier's drawn box U its new displaced box,
;   one row segment per unit (C3: sized by the scanlines left), alternating with the guard job units; light_done ($7EE7F6) = render complete.
;   D3 (B-010, director: src/dev/L3_REPORT.md "## D3"): amber is L2's direct cell-to-tile renderer again (rev 4 amber = rev 2). A committed
;   light_comp cell updates the amber pair grids (Hush_LightAmb, padded cell grids LP_A98 / LP_A2, W and E pairs interleaved) and the
;   commit marks the 4 x 4 tile block of the row segment's changed cells (Hush_LightMarkRow -> light_tdirty spans, rows in L3_ADB);
;   Hush_L3TPass derives them. Per tile (Hush_L3Tile, shared by the amber pass and the glow region's commit): the amber word
;   LUTF[pairs] (built once per power-on, 0 when every amber corner is 0) with the quadrant's flip, else the violet word of the glow's
;   composite (IV index -> LutV), else the empty tile. Regions: glow only (L3 4.5, carrier 8).
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
;     (GMAP diff, COMP) -> the job ends (D2; was phase 3: the slot's lattice). The job box (Hush_LightBox) = the cells the slot's committed light or its new light can reach
;     (distance <= R + 1, a cone only on its facing side); outside it both are 0, so nothing else is cleared or compared. A job still in its
;     ray phase is restarted once when its guard already has a newer signature (Hush_LightStale).
;   The work is time-sliced: units start only while the PPU V counter is below LIGHT_VMAX (a lattice row: LIGHT_VMAX - 10), and the long
;   ones (commit, job pick) also stop at it (Hush_LightLate). Order: a running guard job first, then the next job. D4: the glow cell update
;   (Hush_LightAura) is one step (old ring off, new ring on, the glow lattice copied from the 32-pattern table L3_GTAB), only when the frame's
;   light work starts before LIGHT_VMAX - L3_AGATE; then the glow region gets a guaranteed slice (Hush_L3GSlice) before the job units.
;   NMI uploads <= 6 dirty cell rows (= 12 tile rows, 768 bytes) per frame (measured: the NMI reaches here at line ~250; vblank ends at 261).
;   light_job ($7EE770): slot 0-7 = a guard job runs, $FF = idle ($FE is no longer used).
;   light_dirty ($7EE742): bits 0-13 = cell rows to upload (none are set until B2); 0 = the BG1 VRAM window equals light_tiles.
;
; Space:    src/FREESPACE.md rows $1FB780-$1FC3FF (this code), $1FC400-$1FC9FF (build/rooms_gen.asm: Hush_LightTab, Hush_LightWords - the
;           old per-cell words, no longer read) and $1FCA00-$1FFFFF (build/light_gen.asm, the L3 tables and the code that did not fit the
;           code row: Hush_LightGrids / ZeroGrids / L3*; all bank $1F, so JSR works): vanilla room object data of rooms HUSH never
;           loads (rooms.asm:750-870) + the $FF tail NULL_1FFF4E, same evidence as the E1 room-data rows. C3: $1BB340-$1BB7FF (D4: Hush_L3GRun,
;           Hush_L3GPick, Hush_L3GChg, Hush_L3Commit; JSL from bank $1F; the unclaimed tail of NULL_1BB1E0, bank_1B.asm:6-209).
; RAM:      $7ECA00-$7EE7FF and $7F8000-$7FDBBF (docs/ram_map.md "HUSH lighting" / L3); direct page $00-$0F scratch (end of frame / Module06 only,
;           never in the NMI). Vanilla $7E0134 (animated tile VRAM word, see above). DMA channel 5 + WMDATA (lattice reset; unused by vanilla).
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
!L_DIRTY  = $E742        ; 2  bits 0-13: cell rows whose tile words changed since their last upload (bit 15: unused since L3 B1)
!L_SIGC   = $E748        ; 32 committed signature per slot: class, facing, p (2)
!L_TSIG   = $E768        ; 4  signature being tested
!L_JSIG   = $E76C        ; 4  signature of the running job
!L_JOB    = $E770        ; 1  slot of the running job; $FF = idle
!L_JPH    = $E771        ; 1  job phase: 0 clear, 1 wedges, 2 commit (D2: phase 3 removed)
!L_JWN    = $E772        ; 1  wedges left
!L_JF     = $E773        ; 1  current wedge facing
!L_JE     = $E774        ; 2  2 * next entry
!L_JEND   = $E776        ; 2  2 * entries within the range + fringe
!L_JLVL   = $E778        ; 2  address of the step row
!L_JEDGE  = $E77A        ; 1  1 = cone (diagonal one step dimmer), 0 = all around
!L_JROW   = $E77B        ; 1  commit: cell row (L_JBY0 .. L_JBY1; > L_JBY1 = all rows done); phase 3: lattice row j
!L_RR     = $E77C        ; 1  round-robin slot
!L_LCELL  = $E77E        ; 2  player glow cell i, $FFFF = none
!L_INKP   = $E780        ; 2  ink cloud centre p, 0 = none
!L_PALREQ = $E782        ; 1  write the light colours into the palette buffers
!L_V0     = $E784        ; 2  V counter when the worker started
!L_TD     = $E786        ; 112 D2: amber tile rows pending: [4 ty] = first tile + 1, [4 ty + 1] = last tile + 1 (0 = none; Hush_L3TMark / Hush_L3TPass)
!L_JBX0   = $E7F8        ; 1  job box: first cell column (0..15)
!L_JBX1   = $E7F9        ; 1  job box: last cell column
!L_JBY0   = $E7FA        ; 1  job box: first cell row (0..13); an empty box has JBY0 = 1 > JBY1 = 0
!L_JBY1   = $E7FB        ; 1  job box: last cell row
!L_JCX    = $E7FC        ; 1  commit: next cell column of row L_JROW
!L_JRST   = $E7FF        ; 1  the running job was restarted once (Hush_LightStale) already

; L3 glued light (design/lighting.md 4.5; src/dev/L3_REPORT.md "Step A1 RAM map"; docs/ram_map.md light_l3*), bank $7F, DB = $7F.
; Lattice point (i, j), i = -2..35, j = -2..31: G(i,j) = (j + 2) * 38 + (i + 2); padding stays 0. Carriers 0-7 = guard slots, 8 = glow.
; L3_LAT takes the old L2 pair-grid / LUTF area ($7F8000-$7FB3F1; L2 removed in L3 B1).
!L3_LATSZ = 1292                 ; bytes per padded lattice (34 rows x 38)
!L3_LAT   = $8000                ; lattice base: carrier c at $8000 + c * 1292; D3: only carrier 8 (the glow, $7FA860-$7FAD6B) exists,
                                 ; pair-coded (B2b): P(i, j) = 8 l(i, j) + l(i + 1, j), l = level 0..2; P indexes a 64-byte LERP row directly
; D3 amber (L2 restored, docs/ram_map.md light_pgrid / light_lutf): padded cell grids, G = (cy + 1) * 128 + (cx + 1) * 4 (+2: east pair),
; cy -1..14, cx -1..16, padding 0. Cell C with west / east neighbour W / E: A98[G] = 98 (7C + W), A2[G] = 2 (7C + W), A98[G + 2] =
; 98 (7C + E), A2[G + 2] = 2 (7C + E). Tile (tx, ty): X = 2 tx; index = A98[row cy] + A2[row cy - 1 (even ty) / cy + 1 (odd ty)] =
; 2 (343C + 49H + 7V + D) of the quadrant (H, V, D = its horizontal / vertical / diagonal neighbours); word = LUTF[index] with the
; quadrant's flip (H for odd tx, V for odd ty).
!LP_A98   = $8000                ; 2048
!LP_A2    = $8800                ; 2048
!LP_LUTF  = $9000                ; 4802 (2401 words): (C, H, V, D) -> the amber NW tile word (Hush_LightLutA), 0 if every corner is 0
!L3_CV    = $B910                ; 1292 composite violet lattice, same G
!L3_GTAB  = $AE00                ; 2240 D4: 32 glow lattice patterns x 7 rows x 10 bytes (Hush_L3GTab; docs/ram_map.md light_l3gtab)
!L3_PVIO  = $BE20                ; 960  padded copy of light_vio (32 x 30, p = (cy + 8) * 32 + cx + 8), glow lattice source
!L3_LERP  = $C200                ; 512  [t * 64 + a * 8 + b] = floor(((8 - t)a + tb + 4) / 8), t = 0..7, a, b = 0..7
!L3_LIST  = $C640                ; D4: the running glow region's constants (Hush_L3GPick; C3's carrier list is gone): +0 word K = B - (CV + 78),
                                 ;      B = glow lattice + 38 (f + 2) + e + 2 (P(i + e, j + f) = B + 38 j + i = K + CV row j address + i),
                                 ;      +4 word LERP_s row (0: s = 0, the s = 0 loop Hush_L3PF). Bytes +2, +3, +6..+127 unused
; per carrier, 16-byte arrays indexed by carrier 0..8 (bytes 9-15 unused)
!L3_CELL  = $C700                ; lattice cell i (0..223), $FF = no lattice
!L3_RDX   = $C710                ; rendered dx (signed, px)
!L3_RDY   = $C720                ; rendered dy
!L3_WDX   = $C730                ; wanted dx (clamped +-16, quantized)
!L3_WDY   = $C740                ; wanted dy
!L3_DBX0  = $C750                ; drawn box (lattice i / j, inclusive); empty: DBY0 > DBY1
!L3_DBX1  = $C760
!L3_DBY0  = $C770
!L3_DBY1  = $C780
!L3_LBX0  = $C790                ; lattice bbox (non-zero points, conservative); empty: LBY0 > LBY1
!L3_LBX1  = $C7A0
!L3_LBY0  = $C7B0
!L3_LBY1  = $C7C0
!L3_OK    = $C7D0                ; 2  $4C35 (D4; D3 $4C34) = LERP / LERP8 / L3_D tables, the RAM code, (D3) LUTF and (D4) L3_GTAB built (cleared by the intro WRAM clear,
                                 ;    bank_0C.asm:110-112, which also zeroes LUTF's block: bank_0C.asm:88-113)
!L3_REG   = $C7E0                ; 32 region / scheduler state (B2d, Hush_L3RegStep):
!L3_RC    = !L3_REG+0            ;    carrier of the running region, $FF = none
!L3_RKIND = !L3_REG+1            ;    its kind: 0 amber (carriers 0-7), 1 violet (8)
!L3_RI0   = !L3_REG+2            ;    region columns iA .. iB (lattice i, 0..32)
!L3_RI1   = !L3_REG+3
!L3_RJA   = !L3_REG+4            ;    region rows jA .. jB (lattice j, 0..28)
!L3_RJB   = !L3_REG+5
!L3_RJ    = !L3_REG+6            ;    next row j
!L3_RRR   = !L3_REG+7            ;    round-robin carrier of the pick (ties)
!L3_RDM   = !L3_REG+8            ;    word: bit c = carrier c's lattice changed since its last region (Hush_L3Mark)
!L3_RTURN = !L3_REG+10           ;    0 = a guard job unit next, 1 = a region unit next (Hush_L3Unit)
!L3_RIC   = !L3_REG+12           ;    first column of the next row segment (iA .. iB)
!L3_RSA0  = !L3_REG+15           ;    C4: pending tile span of tile row RJ - 1 (tx lo / hi, 0..31; empty: lo $FF > hi 0)
!L3_RSA1  = !L3_REG+16
!L3_RSB0  = !L3_REG+17           ;    C4: pending tile span of tile row RJ (rolled into RSA at the end of row RJ)
!L3_RSB1  = !L3_REG+18
!L3_GLIM  = !L3_REG+20           ;    D4: word, V counter at which Hush_L3GRun stops (set by Hush_L3GSlice / Hush_L3GStep)
!L3_GDID  = !L3_REG+22           ;    D4: Hush_L3GRun did a pick or a row this call
!L3_GCVR  = !L3_REG+24           ;    D4: word, CV(0, RJ) address = CV + 38 (RJ + 2) + 2 (Hush_L3GPick, Hush_L3GRun; read by Hush_L3Commit)
!L3_GIVO  = !L3_REG+26           ;    D4: word, IV offset of tile (0, RJ) = 68 (RJ + 1) + 2
!L3_GSLICE = 12                  ; D4: the glow's guaranteed slice per light frame, scanlines (Hush_L3GSlice, before the guard jobs; 4 / 8 / 12 / 16
                                 ;     measured, src/dev/L3_REPORT.md "## D4")
!L3_GUNIT = 8                    ; D4: scanlines of one glow unit in Hush_L3Unit's rotation (Hush_L3GStep)
!L3_GMARGIN = 8                  ; D4: hard limit LIGHT_VMAX - L3_GMARGIN: no glow pick / row starts after it, a changed point stops the row there
!L3_AGATE = 24                   ; D4: Hush_LightAura (a glow cell change: ring off + on + 7 lattice rows) only when V0 < LIGHT_VMAX - L3_AGATE
!L3_TROWS = 28                   ; D2: tile rows per amber tile unit at most (Hush_L3TPass; 2 was worse, as above)
!L_RDONE  = $E7F6                ; 1 ($7E) light_done: 1 = render complete (Hush_L3Done)
!L_RIDLE  = $E7F7                ; 1 ($7E) C2: 1 = this frame's idle job scan found every slot current (Hush_LightStep); 0 at LightWork entry
!L3_LERP8 = $C800                ; 512  [t * 64 + p] = 8 * LERP[t * 64 + p] (B2b; built with LERP)
!L3_CODE  = $CA00                ; 256  RAM copy of Hush_L3Code (D4: Hush_L3GF / PF, C4: Hush_L3Tile; operands patched per row; B2b)
!L3_IV    = $D2F8                ; 2040 C4: violet LUT byte index per BG1 tile, padded: (tx, ty) at (ty + 1) * 68 + (tx + 1) * 2, tx -1..32,
                                 ;      ty -1..28: 54 a + 18 b + 6 c + 2 d of the CV corners (deltas in Hush_L3Commit). D3: $7FCB00-$7FD2F7
                                 ;      (C4's amber index / D2's amber pair words) is free
!L3_D     = $DAF0                ; 208  C4: [kind * 104 + (delta + 6) * 8 + 2 corner] = delta * (686, 98, 14, 2 | 54, 18, 6, 2) (D3: violet half read)
!L3_ADB   = $DBC0                ; 4    amber tile rows pending in light_tdirty (D3: marked by Hush_LightMarkRow): +0 first, +1 last (empty:
                                 ;      +0 = $FF, +1 = 0); +2 / +3 unused. Consumed row by row by Hush_L3TPass
!L3_STAMP = $DBC4                ; 1    unused since D2 (kept $FF by Hush_L3RegInit, with light_l3pk +0)
!L3_LPR   = $DC18                ; 2    D3: no amber lattice exists; kept $FF / 0 ("no lattice row pending") by Hush_L3RegInit for the readers
                                 ;      of docs/ram_map.md light_l3lpr. $7F8000-$7F8FFF: D3 pair grids (was D1a L3_AL + D1 light_pcomp)

!LIGHT_VMAX = 200        ; no new unit at or after this scanline; long units also stop at it (Hush_LightLate). After LightWork the frame still
                         ; runs HandleFloorIndicator + PrepareOAMForTransfer (bank_02.asm:1509, bank_00.asm:76). Measured (tests/dev/nmi_probe.lua,
                         ; final room): end of logic max 219 of 225, 0 lag frames (204: max 223, too close; 196: r19 light latency too long)
!LIGHT_NMIROWS = 6       ; cell rows uploaded per NMI (768 bytes in 12 DMAs, ~7 lines from line ~250: ends before the vblank does at 261)
!LIGHT_JOBQ = 4          ; D3 (B-010): guard job units run first until 3/4 of the frame's unit lines are used (L_VJOB), then the rotation
assert !LIGHT_JOBQ == 4  ; Hush_LightWork divides by 4 with two LSR
!L_VJOB   = $E7FD        ; 2  D3: V counter up to which Hush_L3Unit runs the guard job first (set by Hush_LightWork every light frame)

; -----------------------------------------------------------------------------
; Data: build/light_gen.asm (tools/roomgen.py from tools/autotile.py; data only, defines !HUSH_LIGHT_*) + the render tables.
; First in the file: the !HUSH_LIGHT_* defines are used by the code below.
org $1FCA00
Hush_LightGfx:
incsrc "!HUSH_LIGHT_GEN"
Hush_LightZero:                          ; DMA fill source
    db $00
Hush_LightM98:                           ; [ab] 98 * ab (D3, as L2): the A98 pair value of code ab = 7C + W, and 686 k = [7k]
    dw 0*98, 1*98, 2*98, 3*98, 4*98, 5*98, 6*98, 7*98, 8*98, 9*98, 10*98, 11*98, 12*98, 13*98, 14*98, 15*98
    dw 16*98, 17*98, 18*98, 19*98, 20*98, 21*98, 22*98, 23*98, 24*98, 25*98, 26*98, 27*98, 28*98, 29*98, 30*98, 31*98
    dw 32*98, 33*98, 34*98, 35*98, 36*98, 37*98, 38*98, 39*98, 40*98, 41*98, 42*98, 43*98, 44*98, 45*98, 46*98, 47*98
    dw 48*98

; Hush_LightGrids: JSR from Hush_LightInit (Module06, forced blank; same bank $1F), M = X = 16, any DB (kept). D3: the amber pair grids,
; the glow lattice (carrier 8), CV + light_pvio and IV := 0 (DMA, forced blank), every carrier: no lattice (CELL $FF, empty bbox); the
; L3 tables + LUTF once per power-on (L3_OK; the intro's WRAM clear, Intro_Clear1kbBlocksOfWRAM bank_0C.asm:88-113, zeroes it).
Hush_LightGrids:
    PHB
    LDA.w #!LP_A98 : LDX.w #4096 : JSR Hush_LightZeroGrids                  ; D3: A98 + A2 (LUTF at $7F9000 is kept)
    LDA.w #!L3_LAT+(8*!L3_LATSZ) : LDX.w #!L3_LATSZ : JSR Hush_LightZeroGrids   ; the glow lattice
    LDA.w #!L3_CV : LDX.w #(!L3_PVIO+960-!L3_CV) : JSR Hush_LightZeroGrids   ; CV (B2d: light_tiles is reset to empty) + light_pvio
    LDA.w #!L3_IV : LDX.w #2040 : JSR Hush_LightZeroGrids                   ; C4: violet tile indexes (= CV all 0)
    PEA $7F7F : PLB : PLB
    LDX.w #$000E
-   LDA.w #$FFFF : STA.w !L3_CELL,X      ; CELL $FF (bytes 9-15 unused)
    LDA.w #$0101 : STA.w !L3_LBY0,X      ; empty bbox: LBY0 = 1 > LBY1 = 0
    STZ.w !L3_LBY1,X
    DEX : DEX : BPL -
    JSR Hush_L3RegInit                   ; B2d: drawn boxes empty, rendered d = 0, no region
    LDA.w !L3_OK : CMP.w #$4C35 : BEQ +  ; L3 tables + LUTF (D4: + the glow patterns, $4C34 -> $4C35), once per power-on (same intro-clear rule, L3_OK at $7FC7D0)
    JSR Hush_L3Tables
    LDA.w #$4C35 : STA.w !L3_OK
+   PLB
    RTS

; Hush_L3Row: M = 16, X = 16 on entry; A = lattice row j (-2..30), X = lattice base (bank $7F), $08 = source grid address (padded 32 x 30,
; p = (cy + 8) * 32 + cx + 8; bank in $0A), $0B = k0 + 2, $0D = column count n (cell columns k = k0 .. k0 + n - 1, k0 >= -1, k0 + n <= 17).
; design/lighting.md 4.1, N = 7: from cell rows (j - 1) >> 1 and j >> 1 (the same row for odd j): c[k] = rowA[k] + rowB[k];
; point 2k = (c[k-1] + c[k] + 2) >> 2, point 2k + 1 = (c[k] + 1) >> 1 (= the 4/2/1-weight sum + 2, >> 2). Writes points 2k0 .. 2(k0 + n) - 1
; only (outside them the caller knows the lattice is 0). Uses $00-$07, $0D, Y; keeps $08-$0C, $0E-$0F, DB. Returns M = 8, X = 16.
; Pair-coded (L3 B2b): writes P(p) = 8 l(p) + l(p + 1) for p = 2k0 - 1 .. 2(k0 + n) - 1 (the point left of the range pairs with the new
; l(2k0); the last one pairs with l(2(k0 + n)) = E(k0 + n), recomputed from the source: unchanged there, so it equals the stored level).
; With E(k) = (c[k-1] + c[k] + 2) >> 2 = l(2k), O(k) = (c[k] + 1) >> 1 = l(2k + 1): P(2k - 1) = 8 O(k-1) + E(k), P(2k) = 8 E(k) + O(k).
; k0 = -1 (glow at cx = 0, n >= 2) starts at k0 = 0: points -2 / -1 are padding (l = 0) and P(-2) stays 0.
; Cost (CPU cycles, M = 8, X = 16, D = 0) 93 per column (was ~70 with plain l) + ~0.6 scanline set-up.
Hush_L3Row:
    PHB
    PHA
    CLC : ADC.w #15 : LSR A : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.w #6 : CLC : ADC.b $08 : STA.b $00   ; row (j - 1) >> 1, column -2
    LDA $01,S : CLC : ADC.w #16 : LSR A : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.w #6 : CLC : ADC.b $08 : STA.b $03   ; row j >> 1
    PLA : INC A : INC A : STA.b $06                          ; m = j + 2
    ASL A : CLC : ADC.b $06 : ASL A : PHA                    ; 6m
    LDA.b $06 : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC $01,S : STA.b $06 : PLA   ; 38m
    LDA.b $0B : AND.w #$00FF : CMP.w #2 : BCS +              ; k0 = -1: start at column 0, one column less
    SEP #$20 : DEC.b $0D : REP #$20
    LDA.w #2
+   TAY                                                      ; Y = k0 + 2 (source column index from column -2)
    ASL A : DEC A : DEC A : CLC : ADC.b $06 : STA.b $06      ; G(2k0, j) = 38m + 2k0 + 2
    TXA : CLC : ADC.b $06 : TAX
    SEP #$20
    LDA.b $0A : PHA : PLB                ; DB = source bank: (dp),Y below
    DEY
    LDA.b ($00),Y : CLC : ADC.b ($03),Y : STA.b $06          ; c[k0 - 1]
    INC A : LSR A : ASL A : ASL A : ASL A : STA.b $02        ; 8 O(k0 - 1)
    INY
.k  LDA.b ($00),Y : CLC : ADC.b ($03),Y : STA.b $07          ; c[k] (sums <= 24: C stays 0)
    ADC.b $06 : ADC.b #2 : STA.b $06                         ; c[k-1] + c[k] + 2
    LSR A : LSR A : ORA.b $02 : STA.l $7F0000-1,X            ; P(2k - 1) = 8 O(k-1) + E(k)
    LDA.b $06 : AND.b #$FC : ASL A : STA.b $06               ; 8 E(k)
    LDA.b $07 : INC A : LSR A : ORA.b $06 : STA.l $7F0000,X  ; P(2k) = 8 E(k) + O(k)
    AND.b #$07 : ASL A : ASL A : ASL A : STA.b $02           ; 8 O(k)
    LDA.b $07 : STA.b $06
    INX : INX : INY
    DEC.b $0D : BNE .k
    LDA.b ($00),Y : CLC : ADC.b ($03),Y : ADC.b $06 : ADC.b #2 : LSR A : LSR A   ; E(k0 + n)
    ORA.b $02 : STA.l $7F0000-1,X        ; P(2(k0 + n) - 1)
    PLB
    RTS

; Hush_L3Glow: JSR from Hush_L3GTab (D4: power-on pattern build only; was Hush_LightAura), M = 8, X = 16. A (16 bit) = glow cell i ($FFFF: none -> nothing). Rebuilds glow lattice
; (carrier 8) points i = 2cx - 2 .. 2cx + 5, j = 2cy - 2 .. 2cy + 4 from light_pvio: every point the ring of cell i can reach. Uses $00-$0F.
Hush_L3Glow:
    REP #$20
    BMI .out
    PHA
    AND.w #$00F0 : LSR A : LSR A : LSR A : DEC A : DEC A : STA.b $0E      ; j = 2cy - 2 (word $0E)
    LDA.w #!L3_PVIO : STA.b $08
    PLA : AND.w #$000F : INC A           ; k0 + 2 = cx + 1
    SEP #$20
    STA.b $0B
    LDA.b #$7F : STA.b $0A
    LDA.b #7 : STA.b $0C                 ; rows left
.r  LDA.b #4 : STA.b $0D                 ; columns cx - 1 .. cx + 2
    REP #$20
    LDX.w #!L3_LAT+(8*!L3_LATSZ)
    LDA.b $0E : JSR Hush_L3Row           ; M = 8 on return
    REP #$20 : INC.b $0E : SEP #$20
    DEC.b $0C : BNE .r
    LDX.w #8 : JSR Hush_L3Mark           ; B2d: the glow lattice changed -> a region
.out
    SEP #$20
    RTS

; Hush_LightZeroGrids: JSR, M = X = 16 (P kept), A = bank $7F address, X = byte count: := 0 by DMA channel 5 from a fixed zero byte to
; WMDATA ($2180). Channel 5 and WMADD/WMDATA are used nowhere in vanilla (grep of vendor/usdasm: no DMA5* / $435x operand, no WMADD /
; $2181-$2183 operand) nor in src/.
Hush_LightZeroGrids:
    PHP
    REP #$30
    STA.l $002181                        ; WMADDL / WMADDM
    TXA : STA.l $004355
    LDA.w #$8008 : STA.l $004350         ; DMAP5 $08 (A -> B, fixed source, 1 register), BBAD5 $80 (WMDATA)
    LDA.w #Hush_LightZero : STA.l $004352
    SEP #$20
    LDA.b #$01 : STA.l $002183           ; WMADDH: bank $7F
    LDA.b #Hush_LightZero>>16 : STA.l $004354
    LDA.b #$20 : STA.l $00420B           ; channel 5
    PLP
    RTS

; Hush_L3Tables: JSR from Hush_LightGrids, M = X = 16, DB = $7F; uses $00-$0C; returns M = X = 16. Writes only $7FC200-$7FC3FF,
; $7FC800-$7FCAFF, $7FDAF0-$7FDBBF (L3 RAM map: LERP, LERP8, the RAM code, C4: L3_D) and D3: LUTF ($7F9000-$7FA2C1, Hush_LightBuild).
; LERP[t * 64 + a * 8 + b] = floor(((8 - t)a + tb + 4) / 8) for t, a, b = 0..7: n = (8 - t)a + 4 + tb, stepped by t per b and (8 - t) per a.
; (D3: the PH / PL / PHV / PLV index tables of C4 / D2 are gone; Hush_L3PQ stays the L3_D source: 686k + 98eV + 14eH + 2C, 54k + 18eV +
; 6eH + 2C, the LUT layout of tools/autotile.py, k = corner, eV / eH = edges, C = centre.)
Hush_L3Tables:
    LDX.w #$0000
    SEP #$20
    LDA.b #$08 : STA.b $00               ; 8 - t
    STZ.b $01                            ; t
.t  LDA.b #$04 : STA.b $02               ; n at b = 0 of row a
.a  LDA.b $02 : STA.b $03
    LDY.w #$0008
.b  LDA.b $03 : LSR A : LSR A : LSR A : STA.w !L3_LERP,X : INX
    LDA.b $03 : CLC : ADC.b $01 : STA.b $03
    DEY : BNE .b
    LDA.b $02 : CLC : ADC.b $00 : STA.b $02
    TXA : AND.b #$3F : BNE .a
    INC.b $01 : DEC.b $00 : BNE .t
    REP #$20
    LDX.w #$01FE                         ; LERP8 := 8 LERP (word-wise: every byte <= 7, no carry between the bytes)
-   LDA.w !L3_LERP,X : ASL A : ASL A : ASL A : STA.w !L3_LERP8,X
    DEX : DEX : BPL -
    LDY.w #$0000                         ; C4: L3_D [kind * 104 + (delta + 6) * 8 + 2c] = delta * Hush_L3PQ[kind * 4 + c], delta = -6..6
.dk TYX : LDA.l Hush_L3PQ,X : STA.b $00 ; k
    ASL A : CLC : ADC.b $00 : ASL A      ; 6k
    EOR.w #$FFFF : INC A : STA.b $02     ; v = -6k
    TYA : AND.w #$0006 : STA.b $04       ; 2c
    TYA : AND.w #$0008 : BEQ +
    LDA.w #104
+   CLC : ADC.b $04 : TAX
    LDA.w #13 : STA.b $06
-   LDA.b $02 : STA.w !L3_D,X
    CLC : ADC.b $00 : STA.b $02
    TXA : CLC : ADC.w #8 : TAX
    DEC.b $06 : BNE -
    INY : INY : CPY.w #16 : BCC .dk
    SEP #$20
    LDX.w #Hush_L3Code_End-Hush_L3Code-1 ; RAM code: Hush_L3Code -> $7FCA00
-   LDA.l Hush_L3Code,X : STA.w !L3_CODE,X
    DEX : BPL -
    REP #$20
    JSR Hush_L3GTab                      ; D4: the 32 glow lattice patterns
    JMP Hush_LightBuild                  ; D3: LUTF (RTS there)
Hush_L3PQ:
    dw 686, 98,  14, 2,  54, 18,  6, 2

; Hush_L3GTab (D4): JSR from Hush_L3Tables (once per power-on; M = X = 16, DB = $7F; Hush_LightGrids zeroed light_pvio and the glow lattice
; before, both are 0 again on return, and L3_RDM := 0). The glow lattice of a glow cell depends only on its 5 glow cells (light_vio:
; centre 2 if floor, the 4 orthogonal neighbours 1 if floor and inside the grid, else 0; Hush_LightAura). For each pattern p (bit 0 centre,
; 1 north, 2 south, 3 west, 4 east) it builds the lattice of cell (4, 4) with Hush_L3Glow from a synthetic light_pvio and stores the bytes
; Hush_L3GZero / Hush_L3GSet address (7 rows x 10) at L3_GTAB + 70 p. Uses $00-$0F, L3_LIST +6 (p).
Hush_L3GTab:
    STZ.w !L3_LIST+6
.p  SEP #$20
    LDA.w !L3_LIST+6 : AND.b #$01 : ASL A : STA.w !L3_PVIO+(12*32+12)    ; centre (cell (4, 4): p0 = (4 + 8) * 32 + 4 + 8)
    LDA.w !L3_LIST+6 : LSR A : PHA : AND.b #$01 : STA.w !L3_PVIO+(12*32+12)-32   ; north
    PLA : LSR A : PHA : AND.b #$01 : STA.w !L3_PVIO+(12*32+12)+32        ; south
    PLA : LSR A : PHA : AND.b #$01 : STA.w !L3_PVIO+(12*32+12)-1         ; west
    PLA : LSR A : AND.b #$01 : STA.w !L3_PVIO+(12*32+12)+1               ; east
    REP #$20
    LDA.w #$0044 : JSR Hush_L3Glow       ; M = 8 on return
    REP #$30
    LDA.w !L3_LIST+6 : JSR Hush_L3GOff : TAY                              ; 70 p
    LDA.w #$0044 : JSR Hush_L3GAdr       ; X = lattice address of the box
    LDA.w #$0007 : STA.b $0E
-   LDA.w $0000,X : STA.w !L3_GTAB,Y
    LDA.w $0002,X : STA.w !L3_GTAB+2,Y
    LDA.w $0004,X : STA.w !L3_GTAB+4,Y
    LDA.w $0006,X : STA.w !L3_GTAB+6,Y
    LDA.w $0008,X : STA.w !L3_GTAB+8,Y
    TYA : CLC : ADC.w #10 : TAY
    TXA : CLC : ADC.w #38 : TAX
    DEC.b $0E : BNE -
    LDA.w #$0044 : JSR Hush_L3GZero
    LDA.w !L3_LIST+6 : INC A : STA.w !L3_LIST+6
    CMP.w #32 : BCS +
    JMP .p
+   STZ.w !L3_PVIO+(12*32+12)-32 : STZ.w !L3_PVIO+(12*32+12)+32          ; words: also zero bytes that were 0 already
    STZ.w !L3_PVIO+(12*32+12)-1 : STZ.w !L3_PVIO+(12*32+12)+1
    STZ.w !L3_RDM
    RTS
Hush_L3GOff:                             ; M = 16: A = p (< 32) -> A = 70 p; uses $00, $02
    STA.b $02
    ASL A : STA.b $00 : ASL A : CLC : ADC.b $00 : STA.b $00                ; 6p
    LDA.b $02 : XBA : LSR A : LSR A : CLC : ADC.b $00                      ; 64p + 6p
    RTS

; Hush_LightBuild (D3: L2's, restored; JMP from Hush_L3Tables): M = X = 16, DB = $7F, uses $00-$0C. LUTF[2 (343C + 49H + 7V + D)] =
; Hush_LightLutA[686k + 98eV + 14eH + 2C] (byte offsets) with k = (C+H+V+D+2) >> 2, eV = (C+V+1) >> 1, eH = (C+H+1) >> 1 (design/lighting.md
; 4.1: the NW tile of a cell C with west H, north V, north-west D: corners a = k, b = eV, c = eH, d = C), and 0 instead of the empty tile
; word: LutA gives the empty tile exactly when every corner is 0 (tools/autotile.py light_lut: `if max(t) else LIGHT_EMPTY_WORD`), so
; LUTF = 0 <=> no amber corner > 0, and Hush_L3Tile takes the violet word then (design/lighting.md 4.3 "amber wins").
Hush_LightBuild:
    LDY.w #$0000 : STZ.b $00             ; C
.c  STZ.b $02                            ; H
.h  STZ.b $04                            ; V
.v  LDA.b $00 : CLC : ADC.b $04 : INC A : LSR A : ASL A : TAX : LDA.l Hush_LightM98,X : STA.b $08   ; 98 eV
    LDA.b $00 : CLC : ADC.b $02 : INC A : LSR A : ASL A : STA.b $0A                         ; 2 eH
    ASL A : ASL A : ASL A : SEC : SBC.b $0A : CLC : ADC.b $08 : STA.b $08                   ; + 14 eH
    LDA.b $00 : ASL A : CLC : ADC.b $08 : STA.b $08                                         ; + 2C
    LDA.b $00 : CLC : ADC.b $02 : ADC.b $04 : INC A : INC A : STA.b $0A                    ; C + H + V + 2
    STZ.b $06                            ; D
.d  LDA.b $0A : CLC : ADC.b $06 : LSR A : LSR A : ASL A : STA.b $0C                        ; 2k
    ASL A : ASL A : ASL A : SEC : SBC.b $0C : TAX                                           ; 14k: M98[7k] = 686k
    LDA.l Hush_LightM98,X : CLC : ADC.b $08 : TAX
    LDA.l Hush_LightLutA,X : CMP.w #!HUSH_LIGHT_EMPTY : BNE +
    LDA.w #$0000
+   STA.w !LP_LUTF,Y : INY : INY
    INC.b $06 : LDA.b $06 : CMP.w #7 : BCC .d
    INC.b $04 : LDA.b $04 : CMP.w #7 : BCC .v
    INC.b $02 : LDA.b $02 : CMP.w #7 : BCC .h
    INC.b $00 : LDA.b $00 : CMP.w #7 : BCS +
    JMP .c
+   RTS
assert !HUSH_LIGHT_EMPTY != 0

; Hush_LightAmb (D3): JSR from Hush_LightCommit .set (M = 8, X = 16, DB = $7E), Y = cell i whose light_comp changed: grows the commit
; unit's changed-cell column span ($06 = first cx, $FF none; $07 = last cx; cells come in increasing cx within a row segment). The pair
; grids follow once per unit (Hush_LightAmbRow from Hush_LightMarkRow; L2 updated 4 pairs per changed cell, ~360 cycles: a run of k
; changed cells rewrote 4k pairs where 2 (k + 2) suffice). C = 1: out of time, the unit stops after this cell (Hush_LightLateC). The time
; is read at the unit's first changed cell only when that is before LIGHT_VMAX - 56 ($03 := 1: the rest of a row, <= 16 cells x ~250 +
; the deferred pairs and marks, ~6.7k cycles = ~40 lines, fits); else after every changed cell. Keeps X, Y; uses A, $03.
Hush_LightAmb:
    TYA : AND.b #$0F
    BIT.b $06 : BPL .more                ; ($06 = $FF: none yet)
    STA.b $06                            ; first changed cx of the unit
    STA.b $07
    JSR Hush_LightV                      ; M = 16
    CMP.w !L_V0 : BCC .late              ; wrapped
    CMP.w #!LIGHT_VMAX-56 : BCS .late
    SEP #$20
    LDA.b #$01 : STA.b $03
    CLC
    RTS
.more
    STA.b $07                            ; last
    LDA.b $03 : BEQ .chk
    CLC
    RTS
.late
    SEP #$20
    STZ.b $03
.chk
    JMP Hush_LightLateC

; Hush_LightAmbRow (D3; L2's pair formulas): JSR from Hush_LightMarkRow (M = 8, X = 16, DB = $7E), $06 / $07 = first / last changed cx of
; cell row L_JROW. Rewrites both pairs of every cell cx = max($06 - 1, 0) .. min($07 + 1, 15) of that row from light_comp (layout at the
; defines: A98[G] = 98 (7C + W), A2[G] = 2 (7C + W), +2: the same with E; W / E = 0 outside the grid): every pair that reads a changed
; cell. Uses A, X, Y, $08-$0F (not $06 / $07). ~150 cycles per cell.
Hush_LightAmbRow:
    PHB : PEA $7F7F : PLB : PLB
    LDA.b $06 : BEQ +
    DEC A
+   STA.b $08                            ; x
    LDA.b $07 : CMP.b #15 : BCS +
    INC A
+   STA.b $09                            ; last x
    REP #$20
    LDA.l $7E0000+!L_JROW : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : STA.b $0C    ; 16 cy
    ASL A : ASL A : ASL A : STA.b $0E                                                    ; 128 cy
    LDA.b $08 : AND.w #$00FF : CLC : ADC.b $0C : STA.b $0C                               ; i = 16 cy + x
    LDA.b $08 : AND.w #$00FF : ASL A : ASL A : CLC : ADC.b $0E : ADC.w #132 : STA.b $0E   ; G = (cy + 1) * 128 + (x + 1) * 4
    SEP #$20
.x  LDX.b $0C
    LDA.l $7E0000+!L_COMP,X : STA.b $0A                                                  ; C
    ASL A : ASL A : ASL A : SEC : SBC.b $0A : STA.b $0B                                  ; 7C
    LDA.b $08 : BEQ +                    ; x = 0: W = 0 (A = 0)
    LDA.l $7E0000+!L_COMP-1,X
+   CLC : ADC.b $0B                      ; 7C + W
    REP #$20 : AND.w #$00FF : ASL A : TAX
    LDY.b $0E
    LDA.l Hush_LightM98,X : STA.w !LP_A98,Y : TXA : STA.w !LP_A2,Y                      ; west pair
    LDX.b $0C
    SEP #$20
    LDA.b $08 : CMP.b #15 : LDA.b #$00 : BCS +   ; x = 15: E = 0
    LDA.l $7E0000+!L_COMP+1,X
+   CLC : ADC.b $0B                      ; 7C + E
    REP #$20 : AND.w #$00FF : ASL A : TAX
    LDA.l Hush_LightM98,X : STA.w !LP_A98+2,Y : TXA : STA.w !LP_A2+2,Y                  ; east pair
    INC.b $0C
    TYA : CLC : ADC.w #4 : STA.b $0E
    SEP #$20
    LDA.b $08 : INC A : STA.b $08
    CMP.b $09 : BEQ .x : BCC .x
    PLB
    RTS

; Hush_LightMarkRow (D3; L2's, for light_tdirty spans): JSR from Hush_LightCommit (M = 8, X = 16, DB = $7E) at the end of each commit unit:
; the cells cx $06 .. $07 of cell row L_JROW changed ($06 = $FF: none) -> tiles tx max(2 $06 - 1, 0) .. min(2 $07 + 2, 31) of tile rows
; max(2cy - 1, 0) .. min(2cy + 2, 27) (every tile with a corner that reads a changed cell, 4.1) are pending (Hush_L3TMark). $06 := $FF.
; Keeps X, Y; uses $08-$0F (D3: first the pair grids of the changed cells, Hush_LightAmbRow).
Hush_LightMarkRow:
    LDA.b $06 : CMP.b #$FF : BEQ .r
    PHX : PHY
    JSR Hush_LightAmbRow
    LDA.b $06 : ASL A : BEQ +
    DEC A
+   INC A : STA.b $08                    ; lo + 1
    LDA.b $07 : ASL A : INC A : INC A : CMP.b #32 : BCC +
    LDA.b #31
+   INC A : STA.b $09                    ; hi + 1
    LDA.w !L_JROW : ASL A : INC A : INC A : CMP.b #28 : BCC +
    LDA.b #27
+   STA.b $07                            ; last tile row
    LDA.w !L_JROW : ASL A : BEQ +
    DEC A
+   STA.b $06                            ; first
-   LDA.b $06 : JSR Hush_L3TMark
    LDA.b $06 : INC A : STA.b $06
    CMP.b $07 : BEQ - : BCC -
    PLY : PLX
    LDA.b #$FF : STA.b $06
.r  RTS

; Hush_L3PVio: Y = cell i (M = 8, X = 16, DB = $7E): light_pvio[p] := light_vio[i] (the padded copy the glow lattice reads). Keeps X, Y; uses $0E.
Hush_L3PVio:
    PHX
    REP #$20
    TYA : AND.w #$00F0 : ASL A : STA.b $0E
    TYA : AND.w #$000F : CLC : ADC.b $0E : TAX
    SEP #$20
    LDA.w !L_VIO,Y : STA.l $7F0000+!L3_PVIO+(8*32+8),X
    PLX
    RTS

; Hush_L3TMark (D2; D3: inputs in $08 / $09): JSR from Hush_LightMarkRow (M = 8, X = 16, any DB), A = tile row ty (0..27), $08 = lo + 1,
; $09 = hi + 1 (tile columns): light_tdirty span of row ty grows to cover them, light_l3adb (pending tile rows) grows to cover ty. Uses X.
Hush_L3TMark:
    CMP.l $7F0000+!L3_ADB : BCS +
    STA.l $7F0000+!L3_ADB
+   CMP.l $7F0000+!L3_ADB+1 : BCC +
    STA.l $7F0000+!L3_ADB+1
+   REP #$20 : AND.w #$00FF : ASL A : ASL A : TAX : SEP #$20
    LDA.l $7E0000+!L_TD,X : BEQ + : CMP.b $08 : BCC ++
+   LDA.b $08 : STA.l $7E0000+!L_TD,X
++  LDA.l $7E0000+!L_TD+1,X : CMP.b $09 : BCS +
    LDA.b $09 : STA.l $7E0000+!L_TD+1,X
+   RTS

; (D3: Hush_L3TRow, the tile-row driver of both renderers, is in the $1FC916 row.)

; (D3: Hush_L3Amb, Hush_L3LPass, Hush_L3LGate, Hush_L3LSpan, Hush_L3LPtr, Hush_L3LMark, Hush_L3ADirty and Hush_L3LRow removed: no amber lattice.)

; -----------------------------------------------------------------------------
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
    LDA.w !L_JBY0 : CLC : ADC.b #8 : STA.b $08                ; padded row cy + 8 of cy = JBY0
    LDA.w !L_JBY1 : CLC : ADC.b #8 : STA.b $09                ; .. of cy = JBY1 (D3: the box rows only again, as L2)
.crow                                    ; scratch := 0 on these rows (all 16 cells of a row: 8 word stores, cheaper than a byte loop)
    REP #$20
    LDA.b $08 : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.w #8 : TAX
    STZ.w !L_SCR,X : STZ.w !L_SCR+2,X : STZ.w !L_SCR+4,X : STZ.w !L_SCR+6,X
    STZ.w !L_SCR+8,X : STZ.w !L_SCR+10,X : STZ.w !L_SCR+12,X : STZ.w !L_SCR+14,X
    SEP #$20
    LDA.b $08 : INC A : STA.b $08
    CMP.b $09 : BEQ .crow : BCC .crow
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

; Hush_LightLateC (D3): Hush_LightLate for the commit, LIGHT_VMAX - 16: the unit's deferred pair update (Hush_LightAmbRow, <= 16 cells x
; ~150 cycles) and tile marks still follow the stop (~15 lines at most).
Hush_LightLateC:
    JSR Hush_LightV                      ; M = 16
    CMP.w !L_V0 : BCC +
    CMP.w #!LIGHT_VMAX-16
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

; Hush_L3Want: JSR from Hush_LightWork (every light frame, before the units), M = 8, X = 16, DB = $7E; uses $00-$05; returns M = 8, X = 16.
; design/lighting.md 4.5 item 2, D = 1: per carrier c, WDX / WDY[c] (bank $7F) = carrier centre - (16cx + 8, 16cy + 8) of its lattice cell,
; clamped to +-16 (screen px, both relative to $E2 / $E8). Lattice cell = L3_CELL[c] (i = cy * 16 + cx, the cell the carrier's lattice was
; built from; $FF: no lattice -> 0). Centres as Hush_LightSig (sprite origin + 8, 8) and
; Hush_LightAura (Link x + 8, y + 16): Link dx = x - $E2 - 16cx, dy = y + 8 - $E8 - 16cy.
; D1 (design/lighting.md revision 4, "Hybrid: smooth glow only"): guard carriers 0-7 always have WDX / WDY = 0 (amber is never displaced;
; D2: no longer rewritten every frame: nothing else writes them, the intro WRAM clear zeroes $7FC000+, bank_0C.asm:110-112).
; D4: also JSR from Hush_LightAura after a glow cell change (the new lattice cell gets its d in the same frame).
Hush_L3Want:
    REP #$20
    LDX.w #$0008
    JSR .cell : BCS .lz                  ; X = 8: the glow
    LDA.b $22 : SEC : SBC.b $E2 : SEC : SBC.b $00 : JSR .clamp : STA.b $04
    LDA.b $20 : CLC : ADC.w #8 : SEC : SBC.b $E8 : SEC : SBC.b $02 : JSR .clamp
    BRA .ls
.lz LDA.w #$0000 : STA.b $04
.ls JSR .store
    SEP #$20
    RTS
.cell                                    ; M = 16, X = carrier: C = 1 no lattice; else $00 = 16cx, $02 = 16cy
    LDA.l $7F0000+!L3_CELL,X : AND.w #$00FF : CMP.w #$00FF : BCS +
    PHA : AND.w #$000F : ASL A : ASL A : ASL A : ASL A : STA.b $00
    PLA : AND.w #$00F0 : STA.b $02
    CLC
+   RTS
.store                                   ; M = 16: A = dy, $04 = dx, X = carrier -> bank $7F bytes; M = 16 on return
    SEP #$20
    STA.l $7F0000+!L3_WDY,X
    LDA.b $04 : STA.l $7F0000+!L3_WDX,X
    REP #$20
    RTS
.clamp                                   ; M = 16: A (signed) := clamp(A, -16, 16)
    BMI .cn
    CMP.w #17 : BCC +
    LDA.w #16
+   RTS
.cn CMP.w #$FFF0 : BCS +
    LDA.w #$FFF0
+   RTS

; (C3: Hush_L3Compose and Hush_L3Commit moved to the bank $1B row at the end of this file; Hush_L3Pick moved here from the code row.)

; Hush_L3GSlice (D4): JSR from Hush_LightWork after the glow cell update, before the guard jobs (M = 8, X = 16, DB = $7E; returns M = 8):
; the glow region runs (Hush_L3GRun) until V = min(V + L3_GSLICE, LIGHT_VMAX - L3_GMARGIN): a guaranteed glow slice in every light frame.
; Hush_L3GStep (D4): the glow unit of Hush_L3Unit's rotation: Hush_L3GRun up to min(V + L3_GUNIT, LIGHT_VMAX - L3_GMARGIN); C = 1: it did
; a pick or a row, or (nothing done) the frame's light time is over (Hush_LightLate).
Hush_L3GSlice:
    JSR Hush_LightV                      ; M = 16
    CLC : ADC.w #!L3_GSLICE
    CMP.w #!LIGHT_VMAX-!L3_GMARGIN : BCC Hush_L3GStep_run
    BRA Hush_L3GStep_max
Hush_L3GStep:
    JSR Hush_LightV                      ; M = 16
    CLC : ADC.w #!L3_GUNIT
    CMP.w #!LIGHT_VMAX-!L3_GMARGIN : BCC .run
.max
    LDA.w #!LIGHT_VMAX-!L3_GMARGIN
.run
    STA.l $7F0000+!L3_GLIM
    SEP #$20
    JSL Hush_L3GRun
    BCS +
    JSR Hush_LightLate                   ; nothing done: C = 1 when the frame is over, so Hush_L3Unit returns instead of falling through to a
+   RTS                                  ; job unit at V >= LIGHT_VMAX (src/dev/L3_REPORT.md "## D4": r20 lag frame, commit started at line 201)

Hush_L3Bit:                              ; [2r] light_dirty bit of cell row r
    dw $0001, $0002, $0004, $0008, $0010, $0020, $0040, $0080, $0100, $0200, $0400, $0800, $1000, $2000

; Hush_L3Code: ROM image of the RAM code at $7FCA00 (L3_CODE; copied by Hush_L3Tables). D4: the glow loops Hush_L3GF (s > 0) / Hush_L3PF
; (s = 0), entered by RTL from Hush_L3Commit: M = X = 8, DB = $7F, X = i0; per point i: V = the displaced glow lattice value (4.5 item 3;
; one carrier, so V is the violet composite itself), compared with CV(i, j); a change calls Hush_L3GChg (bank $1B: CV, IV deltas, span,
; time). Returns by RTL. Operands patched by Hush_L3GPick (tables, once per region) and Hush_L3Commit (rows, end). Table rows are 64-byte
; aligned and the index is <= 63. Cycles per unchanged point (65816 timings, 8-bit index): GF 34, PF 22.
Hush_L3Code:
base $7F0000+!L3_CODE
Hush_L3GF:                               ; s > 0: V = LERP_s[LERP8_t[P0] | LERP_t[P1]]
Hush_L3GF_P0:
    LDY.w $0000,X                        ; 4  P0 = P(i + e, j0)
Hush_L3GF_L8:
    LDA.w $0000,Y                        ; 4  8 H0
Hush_L3GF_P1:
    LDY.w $0000,X                        ; 4  P1 = P(i + e, j0 + 1)
Hush_L3GF_LT:
    ORA.w $0000,Y                        ; 4  + H1
    TAY                                  ; 2
Hush_L3GF_LS:
    LDA.w $0000,Y                        ; 4  V
Hush_L3GF_CV:
    CMP.w $0000,X                        ; 4  CV(i, j)
    BEQ +                                ; 3
    JSL Hush_L3GChg
+   INX                                  ; 2
Hush_L3GF_E:
    CPX.b #$00 : BCC Hush_L3GF           ; 2 + 3
    RTL
Hush_L3PF:                               ; s = 0: V = H0 = LERP_t[P0]
Hush_L3PF_P0:
    LDY.w $0000,X
Hush_L3PF_LT:
    LDA.w $0000,Y
Hush_L3PF_CV:
    CMP.w $0000,X
    BEQ +
    JSL Hush_L3GChg
+   INX
Hush_L3PF_E:
    CPX.b #$00 : BCC Hush_L3PF
    RTL
; D3: Hush_L3Tile, entered by RTL from Hush_L3TRow (operands patched there): M = X = 16, DB = $7F, D = 0, X = 2 tx of the first tile; even tx
; enter at Hush_L3Tile (west quadrant), odd tx at Hush_L3Tile_1 (east). Per tile: amber index A98[_A] + A2[_B] (2 (343C + 49H + 7V + D) of
; the quadrant), word = LUTF[index] EOR the quadrant's flip (_F; LUTF 0 = no amber corner > 0: then the violet word LutV[IV(tx, ty)] via
; [$06], LutV[0] = the empty tile; design/lighting.md 4.3 "amber wins"); light_tiles row (_C / _S, bank $7E) written only on change, then
; $0C := the word (non-zero: every LUT word has a tile id >= $100). _E = end = 2 (hi + 1). Returns by RTL.
; Cycles per tile (65816 timings, 16-bit M / X: abs,X / abs,Y 6, ADC abs,X 6, EOR # 3, long,X 6, [dp],Y 7): amber 45, violet 61, + 14 changed.
Hush_L3Tile:
    CLC                                  ; 2
Hush_L3Tile_A0:
    LDA.w $0000,X                        ; 6  A98 row cy: 98 (7C + H)
Hush_L3Tile_B0:
    ADC.w $0000,X                        ; 6  A2 row cy -/+ 1: 2 (7V + D)
    TAY                                  ; 2
    LDA.w !LP_LUTF,Y                     ; 6
    BEQ Hush_L3Tile_V0                   ; 2
Hush_L3Tile_F0:
    EOR.w #$0000                         ; 3  flip (V for odd ty)
Hush_L3Tile_C0:
    CMP.l $7E0000,X                      ; 6  light_tiles
    BEQ Hush_L3Tile_N0                   ; 3
Hush_L3Tile_S0:
    STA.l $7E0000,X                      ; 6
    STA.b $0C                            ; 4  changed
Hush_L3Tile_N0:
    INX : INX                            ; 4
Hush_L3Tile_E0:
    CPX.w #$0000 : BCS Hush_L3Tile_X     ; 3 + 2
Hush_L3Tile_1:                           ; odd tx: east quadrant (H flip)
    CLC
Hush_L3Tile_A1:
    LDA.w $0000,X
Hush_L3Tile_B1:
    ADC.w $0000,X
    TAY
    LDA.w !LP_LUTF,Y
    BEQ Hush_L3Tile_V1
Hush_L3Tile_F1:
    EOR.w #$0000
Hush_L3Tile_C1:
    CMP.l $7E0000,X
    BEQ Hush_L3Tile_N1
Hush_L3Tile_S1:
    STA.l $7E0000,X
    STA.b $0C
Hush_L3Tile_N1:
    INX : INX
Hush_L3Tile_E1:
    CPX.w #$0000 : BCC Hush_L3Tile
Hush_L3Tile_X:
    RTL
Hush_L3Tile_V0:
    LDA.w $0000,X                        ; 6  IV row ty
    TAY                                  ; 2
    LDA.b [$06],Y                        ; 7  LutV
    BRA Hush_L3Tile_C0                   ; 3
Hush_L3Tile_V1:
    LDA.w $0000,X
    TAY
    LDA.b [$06],Y
    BRA Hush_L3Tile_C1
base off
Hush_L3Code_End:
assert Hush_L3Code_End-Hush_L3Code <= 256   ; L3_CODE is 256 bytes ($7FCA00-$7FCAFF; C4, was 128)

; L3 B2d region driver helpers (the driver itself, Hush_L3Unit / RegStep / Pick, is at the end of the code row).
; Hush_L3RegInit: JSR from Hush_LightGrids (room load), M = X = 16, DB = $7F. Drawn boxes empty, rendered d = 0 (= the wanted d of a carrier
; without a lattice), no region, nothing marked, light_done = 0.
Hush_L3RegInit:
    LDX.w #$000E
-   LDA.w #$0101 : STA.w !L3_DBY0,X      ; empty: DBY0 = 1 > DBY1 = 0
    STZ.w !L3_DBY1,X : STZ.w !L3_RDX,X : STZ.w !L3_RDY,X
    DEX : DEX : BPL -
    LDX.w #$001E
-   STZ.w !L3_REG,X : DEX : DEX : BPL -
    LDA.w #$00FF : STA.w !L3_RC          ; RC $FF, RKIND 0
    STA.w !L3_ADB : STA.w !L3_ADB+2      ; D2: no amber tile row pending (+0 $FF, +1 0; +2 / +3 unused)
    STA.w !L3_LPR                        ; D3: constant $FF / 0 (no amber lattice)
    LDA.w #$FFFF : STA.w !L3_STAMP       ; D2: stamp and light_l3pk +0 unused, kept $FF ("no parked region" for tests/dev/b010_light_done.lua)
    LDA.w #$0000 : STA.l $7E0000+!L_RDONE  ; + the free byte after it
    RTS

; Hush_L3Mark: JSR (bank $1F), any M / X (P, X kept), X = carrier 0..8: L3_RDM |= 1 << c (its lattice changed).
Hush_L3Mark:
    PHP
    REP #$30
    PHX
    TXA : AND.w #$000F : ASL A : TAX
    LDA.l Hush_L3Bit,X : ORA.l $7F0000+!L3_RDM : STA.l $7F0000+!L3_RDM
    PLX
    PLP
    RTS

; (D2: Hush_L3Done moved to the end of the code row: the data row is full.)

; Hush_L3GZero (D4): JSR from Hush_LightAura (M = 16, X = 16, any DB; returns M = 16), A = old glow cell i (valid). The glow lattice
; (carrier 8) := 0 over every byte Hush_L3Glow writes for cell i: rows j = 2cy - 2 .. 2cy + 4, P(2cx - 3) .. P(2cx + 6) (10 bytes:
; G = 38 (j + 2) + i + 2, from base + 76cy + 2cx - 1; the outermost byte may be padding of the next / previous row, which stays 0; at
; cx = cy = 0 the first byte is $7FA85F, free RAM, docs/ram_map.md). Uses $0E, X, Y.
Hush_L3GZero:
    JSR Hush_L3GAdr
    LDY.w #$0007
-   LDA.w #$0000
    STA.l $7F0000,X : STA.l $7F0002,X : STA.l $7F0004,X : STA.l $7F0006,X : STA.l $7F0008,X
    TXA : CLC : ADC.w #38 : TAX
    DEY : BNE -
    RTS
Hush_L3GAdr:                             ; M = 16: A = glow cell i -> X = glow lattice + 76cy + 2cx - 1 (G of P(2cx - 3), row 2cy - 2); uses $0E
    PHA
    AND.w #$00F0 : LSR A : LSR A : STA.b $0E                ; 4cy
    ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0E : ADC.b $0E : ADC.b $0E : STA.b $0E   ; 76cy
    PLA : AND.w #$000F : ASL A : CLC : ADC.b $0E : ADC.w #!L3_LAT+(8*!L3_LATSZ)-1 : TAX
    RTS

; Hush_L3GSet (D4): JSR from Hush_LightAura (M = 16, X = 16, DB = $7E; returns M = 8), A = new glow cell i (valid; its glow cells are set in
; light_vio / light_pvio and its box in the glow lattice is 0). The glow lattice := pattern p of L3_GTAB (Hush_L3GTab: bit 0 centre = 2,
; 1 north, 2 south, 3 west, 4 east = 1, read from light_pvio), the same bytes Hush_L3Glow would write (~5 lines instead of ~35); marks
; carrier 8. Uses $00, $02, $0E, X, Y.
Hush_L3GSet:
    PHA
    AND.w #$00F0 : ASL A : STA.b $0E     ; 32cy
    LDA $01,S : AND.w #$000F : CLC : ADC.b $0E : TAX                     ; p0 - (8 * 32 + 8)
    SEP #$20
    LDA.l $7F0000+!L3_PVIO+(8*32+8)+1,X : ASL A : ASL A : ASL A : ASL A : STA.b $0E   ; east (0 / 1) << 4
    LDA.l $7F0000+!L3_PVIO+(8*32+8)-1,X : ASL A : ASL A : ASL A : TSB.b $0E           ; west << 3
    LDA.l $7F0000+!L3_PVIO+(8*32+8)+32,X : ASL A : ASL A : TSB.b $0E                 ; south << 2
    LDA.l $7F0000+!L3_PVIO+(8*32+8)-32,X : ASL A : TSB.b $0E                         ; north << 1
    LDA.l $7F0000+!L3_PVIO+(8*32+8),X : LSR A : ORA.b $0E                             ; centre 2 -> bit 0
    REP #$20
    AND.w #$001F : JSR Hush_L3GOff : TAY
    PLA : JSR Hush_L3GAdr
    PHB : PEA $7F7F : PLB : PLB
    LDA.w #$0007 : STA.b $0E
-   LDA.w !L3_GTAB,Y : STA.w $0000,X
    LDA.w !L3_GTAB+2,Y : STA.w $0002,X
    LDA.w !L3_GTAB+4,Y : STA.w $0004,X
    LDA.w !L3_GTAB+6,Y : STA.w $0006,X
    LDA.w !L3_GTAB+8,Y : STA.w $0008,X
    TYA : CLC : ADC.w #10 : TAY
    TXA : CLC : ADC.w #38 : TAX
    DEC.b $0E : BNE -
    PLB
    LDX.w #$0008 : JSR Hush_L3Mark
    SEP #$20
    RTS

; (D4: Hush_L3GChg is at the end of the code row.)

; (D4: Hush_L3Pick is now Hush_L3GPick in the bank $1B row; Hush_L3GlowC is inline in Hush_L3GRun.)

; (D3: Hush_L3ADirty removed; the commit calls Hush_LightAmb / Hush_LightMarkRow.)


; (D1a: Hush_L3ARow, Hush_L3AAdr and Hush_L3ACopy are at the end of the code row: the data row is full.)

; V counter -> A (M = 16 on return). The latch / flip-flop sequence of the vanilla scanline wait (bank_00.asm:15152).
; (Moved here from the code row in C2, unchanged; same bank $1F as its callers.)
Hush_LightV:
    SEP #$20
    LDA.l $002137
    LDA.l $00213F
    LDA.l $00213D : XBA
    LDA.l $00213D : AND.b #$01 : XBA
    REP #$20
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
    STA.w !L_DIRTY : STA.w !L_INKP : STA.w !L_JE
    DEC A : STA.w !L_LCELL
    SEP #$20
    LDA.b #$FF : STA.w !L_JOB
    STZ.w !L_RR
    LDA.b #$01 : STA.w !L_PALREQ : STA.w !L_ON
    REP #$30
    JSR Hush_LightGrids                  ; lattices / light_pvio := 0 (COMP / VIO are 0), no carrier has a lattice, L3 tables once
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
    LDA.b $10 : CMP.b #$07 : BNE .out0
    LDA.w !L_ON : BNE +
.out0
    JMP .out
+   LDA.w $C903 : BNE +                  ; hush_flash ($7EC903): the caught flash owns the colour-math registers (feedback.asm)
    LDA.b #$02 : STA.b $99               ; CGWSEL: the sub screen is the addend
    LDA.b #$22 : STA.b $9A               ; CGADSUB: add to BG2 and the backdrop
    LDA.b $1D : ORA.b #$01 : STA.b $1D   ; TS: BG1 (the light) on the sub screen
+   REP #$20
    LDA.w $C558 : CMP.l Hush_LightRamp+22 : SEP #$20 : BEQ +  ; row 2 colour 12 (the amber core)
    LDA.b #$01 : STA.w !L_PALREQ         ; the palette buffer was reloaded (room load, menu): light colours + soft shadow again
+   JSR Hush_L3Want                      ; L3: wanted displacement per carrier (~3 lines)
    STZ.w !L_RIDLE                       ; C2: the idle job scan may run again this frame
    JSR Hush_LightV : STA.w !L_V0
    CMP.w #!LIGHT_VMAX : BCS .exit       ; no spare time this frame: everything waits (the colour-math shadows above are set every frame)
    SEP #$20
    LDA.w !L_PALREQ : BEQ +
    REP #$20 : LDA.w !L_V0 : CMP.w #150 : SEP #$20 : BCS +   ; ~20 lines of work: only early in the frame
    JSR Hush_LightPal
+   JSR Hush_LightInk
    REP #$20 : LDA.w !L_V0 : CMP.w #(!LIGHT_VMAX-!L3_AGATE) : SEP #$20 : BCS +   ; the glow cell update (D4: one step, ring off + on + lattice) only with room left
    JSR Hush_LightAura
+   JSR Hush_L3GSlice                    ; D4: the glow region's guaranteed slice, before the guard jobs
    JSR Hush_LightV
    CMP.w #!LIGHT_VMAX : BCS .exit
    CLC : ADC.w #(!LIGHT_JOBQ-1)*!LIGHT_VMAX : LSR A : LSR A : STA.w !L_VJOB   ; D3: job units first until V >= (V + 3 VMAX) / 4
.unit
    SEP #$20
    JSR Hush_L3Unit : BCC .exit          ; B2d: guard job unit and region row alternately
    JSR Hush_LightV
    CMP.w !L_V0 : BCC .exit              ; wrapped into the next frame
    CMP.w #!LIGHT_VMAX : BCC .unit
.exit
    JSR Hush_L3Done                      ; light_done
.out
    PLB : PLP
    RTL

; (Hush_LightV moved to the data row in C2, after Hush_L3Done: the code row is full.)

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
    LDA.w !L_LCELL : BMI .on             ; D4: one step (L3 had two halves, with no glow lattice in between: the glow blinked off)
    STZ.b $08 : JSR .ring                ; old cells: no glow
    SEP #$20
    LDY.w !L_LCELL
    LDA.b #$00 : STA.w !L_VIO,Y
    JSR Hush_L3PVio
    REP #$20
    LDA.w !L_LCELL : JSR Hush_L3GZero    ; the old cell's glow lattice := 0
.on LDA.b $04 : STA.w !L_LCELL : BMI .none
    LDA.w #$0001 : STA.b $08
    LDA.b $04 : JSR .ring
    SEP #$20
    LDY.w !L_LCELL
    JSR Hush_LightFloor : BNE +
    LDA.b #$02 : STA.w !L_VIO,Y
    JSR Hush_L3PVio
+   REP #$20
    LDA.w !L_LCELL : JSR Hush_L3GSet     ; D4: glow lattice (carrier 8) from the pattern table (marks carrier 8); M = 8 on return
    LDA.w !L_LCELL : STA.l $7F0000+!L3_CELL+8                ; its lattice cell
    JMP Hush_L3Want                      ; D4: d against the new cell in this frame (RTS there)
.none
    SEP #$20
    LDA.b #$FF : STA.l $7F0000+!L3_CELL+8                    ; no glow
    LDX.w #$0008 : JSR Hush_L3Mark
.same
    SEP #$20
    RTS
.ring                                    ; A = centre i (M = 16), $08 = value: the 4 orthogonal neighbours inside the grid; the value is only set on
    STA.b $06                            ; floor cells (0 = clear: always). light_pvio follows (Hush_L3PVio)
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
    JSR Hush_L3PVio
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
; Hush_LightIdle: M = 8. No job running: light_job := $FF ($FE, "render pending", is not used since L3 B1: no tile renderer yet).
Hush_LightIdle:
    LDA.b #$FF
    STA.w !L_JOB
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
    ; idle: find the next slot whose light is out of date (round robin). C2 (src/dev/L3_REPORT.md): at most one "nothing found" scan per
    ; frame (L_RIDLE; the signatures cannot change later in the frame: sprites do not move during LightWork, SIGC only changes at a job's
    ; commit or in Hush_LightInk before the units); the time check once per scan (8 slots <= ~1300 cycles) instead of per slot; a slot
    ; with $0DD0 != 9 has signature 0 (Hush_LightSig .none), so it is current iff its committed SIGC is 0 / 0, tested before Hush_LightSig.
    LDA.w !L_RIDLE : BNE .none
    LDA.l $7F0000+!L3_ADB : INC A : BNE .none   ; D3: no new job while amber tiles are pending (a job's tiles reach VRAM before the next commit)
    JSR Hush_LightLate : BCS .ret        ; out of time: the round robin goes on from L_RR next frame
    LDA.b #$08 : STA.b $0A
    LDA.w !L_RR : AND.b #$07 : STA.b $0B
.pick
    REP #$20 : LDA.b $0B : AND.w #$0007 : TAX : ASL A : ASL A : TAY : SEP #$20   ; X = slot, Y = 4 * slot
    LDA.w $0DD0,X : CMP.b #$09 : BEQ .sig
    REP #$20 : LDA.w !L_SIGC,Y : ORA.w !L_SIGC+2,Y : BEQ .same                 ; no sprite, no committed light: current
.sig
    JSR Hush_LightSig                    ; keeps Y
    REP #$20
    LDA.w !L_TSIG : CMP.w !L_SIGC,Y : BNE .start
    LDA.w !L_TSIG+2 : CMP.w !L_SIGC+2,Y : BNE .start
.same
    SEP #$20
    INC.b $0B
    DEC.b $0A : BNE .pick
    INC.w !L_RIDLE                       ; every slot current: no new scan before the next frame
.none
    CLC
.ret
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
    JSR Hush_LightV                      ; D2 (B-010): 16 entries per unit (~7 lines) when it starts before LIGHT_VMAX - 10, else 8
    CMP.w #(!LIGHT_VMAX-10) : LDA.w #32 : BCC +
    LDA.w #16
+   STA.b $04
    LDA.w !L_JE : TAX : CLC : ADC.b $04
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
; frame's time is up -> GMAP[slot], COMP, D3: amber pair grids (Hush_LightAmb) + tile marks of the changed cells (Hush_LightMarkRow, at the
; end of every unit) (M = 8, X = 16). Only cells of the
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
    LDA.b #$FF : STA.b $06               ; D3: no changed cell yet (Hush_LightAmb / Hush_LightMarkRow)
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
+   CMP.w !L_COMP,Y : BNE .set
    JMP .next
.set
    STA.w !L_COMP,Y
    JSR Hush_LightAmb : BCS +            ; D3: the unit's changed span (pairs + marks at its end, Hush_LightMarkRow); C = 1: out of time
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
    JSR Hush_LightIdle                   ; the job ends here (D3: its tiles are marked, Hush_L3TPass derives them)
    SEC
    RTS

; -----------------------------------------------------------------------------
; L3 B2d: the region driver (design/lighting.md 4.5; src/dev/L3_REPORT.md B2d). State in L3_REG ($7FC7E0, defines !L3_R*).
; A region re-renders one carrier's part of the composite: rows jA .. jB x columns iA .. iB of the lattice, one row per unit (Hush_L3Compose
; of the carrier's kind, then Hush_L3Commit). Picked (Hush_L3Pick) for a carrier whose lattice changed (L3_RDM bit, Hush_L3Mark) or whose
; wanted d (WDX / WDY) != rendered d (RDX / RDY).

; (Hush_L3RegInit, Hush_L3Mark and Hush_L3Done are in the data row: the code row is full.)

; Hush_L3Unit: one unit of light work (JSR from Hush_LightWork; M = 8, X = 16, DB = $7E). C = 0: nothing to do. D3 (B-010): while the V
; counter is below L_VJOB (3/4 of the frame's unit lines) L2's order runs (src/dev/L3_REPORT.md "## D3": with a plain rotation a job got
; ~1 small unit per frame, since the amber pass and the glow region size their units to the rest of the frame): the running guard job,
; else the pending amber tiles (a finished job's tiles before the next job starts), else the next job. After that, D2's 3-way rotation by
; L3_RTURN (0, 1, 2 = guard job unit Hush_LightStep, amber unit Hush_L3TPass, glow region unit Hush_L3RegStep); when the one whose turn
; it is has nothing, the next ones run: none starves. (D4: the glow's guaranteed slice runs before the units, Hush_L3GSlice; the glow
; unit here is Hush_L3GStep = Hush_L3GRun for up to L3_GUNIT lines.)
Hush_L3Unit:
    JSR Hush_LightV : CMP.w !L_VJOB      ; M = 16
    SEP #$20 : BCS .rot
    LDA.w !L_JOB : BPL .jb               ; a job runs
    JSR Hush_L3TPass : BCS .y
.jb JSR Hush_LightStep : BCS .y
.rot
    LDA.l $7F0000+!L3_RTURN : INC A : CMP.b #3 : BCC +
    LDA.b #0
+   STA.l $7F0000+!L3_RTURN
    BEQ .j
    DEC A : BEQ .t
    JSR Hush_L3GStep : BCS .y
    JSR Hush_LightStep : BCS .y
    JMP Hush_L3TPass
.j  JSR Hush_LightStep : BCS .y
    JSR Hush_L3TPass : BCS .y
    JMP Hush_L3GStep
.t  JSR Hush_L3TPass : BCS .y
    JSR Hush_L3GStep : BCS .y
    JMP Hush_LightStep
.y  RTS

; (D4: Hush_L3RegStep removed: the glow region driver is Hush_L3GRun in the bank $1B row.)

; (D4: Hush_L3Pick / RegStep are Hush_L3GPick / GRun in the bank $1B row.)

; Hush_L3TPass (D2, B-010; D3: tiles from the pair grids via Hush_L3TRow): one unit of amber tile work (Hush_L3Unit; M = 8, X = 16, DB = $7E;
; returns M = 8, X = 16). C = 0: nothing pending (light_l3adb +0 = $FF) or too late for even one tile. Tile row ty = light_l3adb +0 (the first
; pending row): its pending span in light_tdirty (byte 4 ty = lo + 1, 4 ty + 1 = hi + 1; 0 = none) is derived by Hush_L3TRow. At most
; 2 tiles per scanline left before LIGHT_VMAX - 3 (a tile costs <= 61 cycles = 0.36 line; ~2 lines of set-up and return); the rest of the
; span stays pending. A finished row moves light_l3adb +0 on (empty: $FF / 0). Rows follow each other in one unit while they fit.
; DP: $06-$08 (Hush_L3TRow), $09 ty, $0A lo, $0B hi, $0C-$0D (Hush_L3TRow), $0E tiles that fit, $0F rows done.
Hush_L3TPass:
    STZ.b $0F
.top
    LDA.b $0F : CMP.b #(2*!L3_TROWS) : BCS .fin                          ; at most L3_TROWS rows per unit ($0F: 2 per row derived)
    LDA.l $7F0000+!L3_ADB : CMP.b #$FF : BEQ .fin
    STA.b $09
    LDA.w !L_JOB : BMI +                 ; D3: during a commit only the tile rows it can no longer mark (ty < 2 JROW - 1): the rest of
    LDA.w !L_JPH : CMP.b #$02 : BNE +    ; a job's tiles are derived while it commits, not all after it (and none twice)
    LDA.w !L_JROW : ASL A : DEC A : BMI .fin
    CMP.b $09 : BEQ .fin : BCC .fin
+   LDA.b $09
    REP #$20 : AND.w #$00FF : ASL A : ASL A : TAX : SEP #$20            ; X = 4 ty
    LDA.w !L_TD,X : BEQ .adv             ; nothing in this row
    DEC A : STA.b $0A                    ; lo
    JSR Hush_LightV                      ; M = 16, keeps X
    CMP.w !L_V0 : BCC .late              ; wrapped
    EOR.w #$FFFF : SEC : ADC.w #(!LIGHT_VMAX-3)                          ; VMAX - 3 - V
    BMI .late : BEQ .late
    ASL A : CMP.w #33 : BCC +
    LDA.w #32
+   STA.b $0E                            ; tiles that fit (1..32)
    SEP #$20
    LDA.w !L_TD+1,X : DEC A : STA.b $0B  ; hi
    SEC : SBC.b $0A : INC A              ; n
    CMP.b $0E : BCC .all : BEQ .all
    LDA.b $0A : CLC : ADC.b $0E : INC A : STA.w !L_TD,X                  ; the rest stays pending: lo' + 1 = lo + fit + 1
    DEC A : DEC A : STA.b $0B            ; hi = lo + fit - 1
    LDA.b #$00                           ; row not done
    BRA .go
.late
    SEP #$20
.fin
    LDA.b $0F : CMP.b #$01               ; C = 1: a row (part) was done
    RTS
.all
    STZ.w !L_TD,X : STZ.w !L_TD+1,X
    LDA.b #$01                           ; row done
.go
    PHA
    PHB
    PEA $7F7F : PLB : PLB
    REP #$30
    LDA.b $09 : JSL Hush_L3TRow          ; (masks ty itself)
    SEP #$20
    PLB : PLA
    INC.b $0F
    CMP.b #$01 : BNE .fin                ; row not done: it stays first, the unit ends
.adv
    INC.b $0F
    LDA.l $7F0000+!L3_ADB : INC A : CMP.l $7F0000+!L3_ADB+1 : BEQ + : BCS .empty
+   STA.l $7F0000+!L3_ADB
    JMP .top
.empty
    LDA.b #$FF : STA.l $7F0000+!L3_ADB
    LDA.b #$00 : STA.l $7F0000+!L3_ADB+1
    BRA .fin

; Hush_L3Done (D2: moved here from the data row): JSR from Hush_LightWork's exit (any M, X = 16, DB = $7E; returns M = 8). light_done
; ($7EE7F6) := 1 when no region runs, no amber tile row (light_l3adb) is pending, no carrier is marked (L3_RDM = 0) or has
; WDX / WDY != RDX / RDY (carrier 8), no guard job runs (L_JOB = $FF) and light_dirty = 0; else 0.
Hush_L3Done:
    SEP #$20
    STZ.w !L_RDONE
    LDA.l $7F0000+!L3_RC : BPL .no
    LDA.l $7F0000+!L3_ADB : INC A : BNE .no
    LDA.w !L_JOB : BPL .no
    REP #$20
    LDA.l $7F0000+!L3_RDM : ORA.w !L_DIRTY
    SEP #$20 : BNE .no
    LDA.l $7F0000+!L3_WDX+8 : CMP.l $7F0000+!L3_RDX+8 : BNE .no         ; D2: only the glow is displaced
    LDA.l $7F0000+!L3_WDY+8 : CMP.l $7F0000+!L3_RDY+8 : BNE .no
    INC.w !L_RDONE
.no
    RTS

; Hush_L3GChg (D4; code row: the bank $1B row and the data row are full): JSL from the RAM loops Hush_L3GF / PF (bank $7F) at a changed
; point: M = X = 8, DB = $7F, A = new V, X = i; DP as set by Hush_L3Commit ($03 CV row pointer, $05 cmin, $06 cmax, $07 IV offset of tile
; (0, j), $01 i1). CV(i, j) := V; the 4 tiles with that corner get the IV index delta (L3_D violet half: tile (i, j) corner a, (i - 1, j) b,
; (i, j - 1) c, (i - 1, j - 1) d; C4's commit code); the changed span [cmin, cmax] grows. Then the time: V >= LIGHT_VMAX - L3_GMARGIN or
; wrapped (< L_V0) -> $09 := i and X := i1 (the loop ends after this point). Returns X = i (or i1), M = X = 8. Uses A, Y, $0A, $0B. ~190 cycles.
Hush_L3GChg:
    TXY
    STA.b $0A
    SEC : SBC.b ($03),Y                  ; delta = new - old (-2..2)
    ASL A : ASL A : ASL A : CLC : ADC.b #104+48 : STA.b $0B               ; L3_D violet row of delta
    LDA.b $0A : STA.b ($03),Y
    STY.b $06                            ; cmax
    LDA.b $05 : BPL +
    STY.b $05                            ; cmin (first change)
+   REP #$30
    TYA : ASL A : CLC : ADC.b $07 : TAX
    LDA.b $0B : AND.w #$00FF : TAY
    LDA.w !L3_IV,X : CLC : ADC.w !L3_D,Y : STA.w !L3_IV,X                 ; tile (i, j): corner a
    LDA.w !L3_IV-2,X : CLC : ADC.w !L3_D+2,Y : STA.w !L3_IV-2,X           ; tile (i - 1, j): b
    LDA.w !L3_IV-68,X : CLC : ADC.w !L3_D+4,Y : STA.w !L3_IV-68,X         ; tile (i, j - 1): c
    LDA.w !L3_IV-70,X : CLC : ADC.w !L3_D+6,Y : STA.w !L3_IV-70,X         ; tile (i - 1, j - 1): d
    SEP #$30
    LDA.l $002137                        ; V counter (as Hush_LightV)
    LDA.l $00213F
    LDA.l $00213D : XBA
    LDA.l $00213D : AND.b #$01 : XBA
    REP #$20
    CMP.l $7E0000+!L_V0 : BCC .stop      ; wrapped into the next frame
    CMP.w #!LIGHT_VMAX-!L3_GMARGIN : BCS .stop   ; the hard limit only: a row started before GLIM ends (fewer split rows)
    SEP #$20
    LDX.b $06
    RTL
.stop
    SEP #$20
    LDX.b $06 : STX.b $09                ; the segment ends at i
    LDX.b $01                            ; X := i1: the loop's INX / CPX ends it
    RTL
Hush_Light_End:
assert pc() <= $1FC400                   ; src/FREESPACE.md row $1FB780-$1FC3FF

; =============================================================================
; D2 (B-010, src/dev/L3_REPORT.md "## D2 B-010"): src/FREESPACE.md row $1FC916-$1FC9FF, the unused tail of the Hush_LightTab row (build/rooms_gen.asm
; ends at Hush_LightData_End = $1FC916: tools/roomgen.py asserts its 1302 bytes; same vanilla room object data of rooms HUSH never loads).
org $1FC916
assert Hush_LightData_End <= $1FC916     ; the generated light tables must end before this block

; (D3: Hush_L3LRow removed; this row now holds Hush_L3TRow.)
; Hush_L3TRow (D3): JSL from Hush_L3TPass (amber) and Hush_L3Commit (glow region, bank $1B): M = X = 16, DB = $7F, A = tile row ty (0..27),
; DP $0A = first tile lo, $0B = last tile hi (bytes, lo <= hi <= 31). Derives tiles lo .. hi of row ty with the RAM loop Hush_L3Tile (row
; operands patched here: A98 row cy, A2 row cy -/+ 1, the quadrant flips, light_tiles row, IV row, end) and sets the light_dirty bit of
; cell row ty >> 1 if a word changed. Uses $06-$08 (LutV pointer), $0C-$0D (changed word), A, X, Y. Returns M = X = 16.
Hush_L3TRow:
    AND.w #$00FF : PHA                   ; ty
    XBA : LSR A : LSR A : CLC : ADC.w #!L_TILES                          ; light_tiles row ty (bank $7E)
    STA.w (Hush_L3Tile_C0+1)&$FFFF : STA.w (Hush_L3Tile_S0+1)&$FFFF
    STA.w (Hush_L3Tile_C1+1)&$FFFF : STA.w (Hush_L3Tile_S1+1)&$FFFF
    LDA $01,S : INC A : ASL A : ASL A : STA.b $0C                        ; 4 (ty + 1)
    ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0C : ADC.w #!L3_IV+2     ; IV of tile (0, ty): IV + 68 (ty + 1) + 2
    STA.w (Hush_L3Tile_V0+1)&$FFFF : STA.w (Hush_L3Tile_V1+1)&$FFFF
    LDA $01,S : AND.w #$00FE : XBA : LSR A : LSR A : CLC : ADC.w #!LP_A98+4+128   ; A98 + (cy + 1) * 128 + 4: tile (0, ty)
    STA.w (Hush_L3Tile_A0+1)&$FFFF : STA.w (Hush_L3Tile_A1+1)&$FFFF
    SEC : SBC.w #(!LP_A98-!LP_A2+128) : STA.b $0C                         ; A2 of padded row cy (= cell row cy - 1)
    LDA $01,S : LSR A : LDA.b $0C : BCC +
    ADC.w #255                           ; odd ty (C = 1): + 256 = padded row cy + 2 (cell row cy + 1)
+   STA.w (Hush_L3Tile_B0+1)&$FFFF : STA.w (Hush_L3Tile_B1+1)&$FFFF
    LDA $01,S : LSR A : LDA.w #$0000 : ROR A                              ; V flip for the south quadrants (odd ty)
    STA.w (Hush_L3Tile_F0+1)&$FFFF
    EOR.w #$4000 : STA.w (Hush_L3Tile_F1+1)&$FFFF                         ; + H flip for the east quadrants (odd tx)
    LDA.b $0B : AND.w #$00FF : INC A : ASL A                             ; end = 2 (hi + 1)
    STA.w (Hush_L3Tile_E0+1)&$FFFF : STA.w (Hush_L3Tile_E1+1)&$FFFF
    LDA.w #Hush_LightLutV : STA.b $06
    SEP #$20 : LDA.b #Hush_LightLutV>>16 : STA.b $08 : REP #$20
    STZ.b $0C                            ; changed
    LDA.b $0A : AND.w #$00FF : ASL A : TAX                               ; X = 2 lo
    AND.w #$0002 : BEQ +
    LDA.w #(Hush_L3Tile_1-1)&$FFFF : BRA ++                               ; odd lo: start with an east quadrant
+   LDA.w #(Hush_L3Tile-1)&$FFFF
++  PHK : PER .r-1                       ; RTL into bank $7F (= DB) at the loop; it RTLs back to .r
    PHB : PHA
    RTL
.r                                       ; M = X = 16
    PLA                                  ; ty
    LDX.b $0C : BEQ +
    AND.w #$00FE : TAX                   ; 2 (ty >> 1)
    LDA.l Hush_L3Bit,X : ORA.l $7E0000+!L_DIRTY : STA.l $7E0000+!L_DIRTY
+   RTL
Hush_L3TRow_End:
assert pc() <= $1FCA00                   ; src/FREESPACE.md row $1FC916-$1FC9FF

; =============================================================================
; C3 (src/dev/L3_REPORT.md "## C3"): the region renderer in bank $1B, src/FREESPACE.md row $1BB340-$1BB7FF (the unclaimed tail of
; NULL_1BB1E0, bank_1B.asm:6-209: all $FF in the vanilla ROM listing, no reference in vendor/usdasm; the M5 meter block ends before it).
; Called by JSL from bank $1F; everything they read in bank $1F (Hush_L3Bit, Hush_LightLutA / LutV) is read with long addressing.
org $1BB340

; (D4: Hush_L3List and Hush_L3Compose removed: one carrier, Hush_L3GPick sets the loop up, Hush_L3Commit runs it.)

; Hush_L3GRun (D4): JSL from Hush_L3GSlice / Hush_L3GStep (bank $1F), M = 8, X = 16, any DB (P, DB kept). Renders the glow while the V
; counter is below L3_GLIM at the start of a pick / row (or wrapped below L_V0): when no region runs and the glow needs one (L3_RDM bit 8:
; its lattice changed, or WDX / WDY != RDX / RDY; was Hush_L3GlowC) either the "same picture" skip (`.same`: the new d has the same e and
; t class as the rendered one in both axes, `.key`, so every displaced point is unchanged: RD := WD, no region) or a pick (Hush_L3GPick),
; else the region's next row (segment) by Hush_L3Commit (a row started before GLIM runs to its end; its loop stops after a changed point
; only at the hard limit LIGHT_VMAX - L3_GMARGIN, Hush_L3GChg: the segment then ends there). A region that ends lets the next pick follow
; in the same call. After row jB: row jB + 1 as a "tail" (tile row jB only) if it exists and has pending tiles (C4). Returns M = 8,
; X = 16 (as entered), C = 1: it did a pick or a row. Uses $00-$0F.
Hush_L3GRun:
    PHP
    PHB
    SEP #$20
    REP #$10
    PEA $7F7F : PLB : PLB
    STZ.w !L3_GDID
.top
    JSR .late : BCC +
.x  LDA.w !L3_GDID
    PLB
    PLP                                  ; M = 8 (entry)
    CMP.b #$01
    RTL
+   LDA.w !L3_RC : BPL .row
    LDA.w !L3_RDM+1 : LSR A : BCS .pk
    LDA.w !L3_WDX+8 : CMP.w !L3_RDX+8 : BNE +
    LDA.w !L3_WDY+8 : CMP.w !L3_RDY+8 : BEQ .x
+   LDA.w !L3_WDX+8 : JSR .key : STA.b $0F
    LDA.w !L3_RDX+8 : JSR .key : CMP.b $0F : BNE .pk
    LDA.w !L3_WDY+8 : JSR .key : STA.b $0F
    LDA.w !L3_RDY+8 : JSR .key : CMP.b $0F : BNE .pk
.same                                    ; same picture: the new d is "rendered" without a region
    LDA.w !L3_WDX+8 : STA.w !L3_RDX+8
    LDA.w !L3_WDY+8 : STA.w !L3_RDY+8
    BRA .x
.pk JSR Hush_L3GPick
    INC.w !L3_GDID
    JMP .top
.row
    INC.w !L3_GDID
    LDA.w !L3_RIC : STA.b $00
    LDA.w !L3_RI1 : STA.b $01
    LDA.w !L3_RJ : STA.b $02
    CMP.w !L3_RJB : BEQ + : BCS .tail
+   LDA.b #$01 : JSL Hush_L3Commit       ; compose + compare + tiles of segment i0 .. i1 ($01 lowered if the loop stopped)
    BRA .seg
.tail
    LDA.b #$81 : JSL Hush_L3Commit       ; no compare: the pending tiles of tile row jB
.seg
    LDA.b $01 : CMP.w !L3_RI1 : BCS +
    INC A : STA.w !L3_RIC                ; next segment of this row
    BRA .t2
+   LDA.w !L3_RI0 : STA.w !L3_RIC
    LDA.w !L3_RJ : INC A : STA.w !L3_RJ
    REP #$21                             ; D4: the next row's CV row pointer and IV offset (C = 0)
    LDA.w !L3_GCVR : ADC.w #38 : STA.w !L3_GCVR
    LDA.w !L3_GIVO : CLC : ADC.w #68 : STA.w !L3_GIVO
    SEP #$20
    LDA.w !L3_RJ
    DEC A : CMP.w !L3_RJB : BCC .t2
    BNE .end                             ; row jB + 1 done
    CMP.b #28 : BCS .end
    LDA.w !L3_RSA0 : CMP.w !L3_RSA1 : BEQ .t2 : BCC .t2
.end
    LDA.b #$FF : STA.w !L3_RC            ; the region ends
.t2 JMP .top
.late                                    ; M = 8 (kept): C = 1 when V >= GLIM or V < L_V0 (wrapped into the next frame)
    LDA.l $002137                        ; the V counter read of Hush_LightV (bank_00.asm:15152)
    LDA.l $00213F
    LDA.l $00213D : XBA
    LDA.l $00213D : AND.b #$01 : XBA
    REP #$20
    CMP.l $7E0000+!L_V0 : BCC +
    CMP.w !L3_GLIM
    SEP #$20
    RTS
+   SEP #$21
    RTS
.key                                     ; M = 8: A = d (signed, -16..16) -> A = (n & $F8) | class(n & 7), n = -d: the displaced glow
    EOR.b #$FF : INC A                   ; lattice depends on d only through e = n >> 3 and class(t) = 0 (t <= 3), 1 (t = 4), 2 (t >= 5):
    PHA                                  ; every glow pattern has |l(p) - l(q)| <= 1 for adjacent points (L3_REPORT.md "## D4"), so
    AND.b #$07 : CMP.b #$04              ; H = LERP_t[a, b] is a for t < 4 (b = a + 1) / t < 5 (b = a - 1), else b; the same for V
    BCC .k0 : BEQ .k1                    ; in s (adjacent H differ by <= 1 too). Uses $0E
    LDA.b #$02 : BRA .kc
.k0 LDA.b #$00 : BRA .kc
.k1 LDA.b #$01
.kc STA.b $0E
    PLA : AND.b #$F8 : ORA.b $0E
    RTS

; Hush_L3GPick (D4; was Hush_L3Pick + Hush_L3List): JSR from Hush_L3GRun, M = 8, X = 16, DB = $7F. L3_RDM bit 8 := 0; RDX / RDY := WDX /
; WDY (the snapshot the region renders); new box N = the exact support of the displaced glow lattice: Hush_L3Glow's non-zero points
; x0 = 2cx - 2 .. x1 = 2cx + 4 (cells cx - 1 .. cx + 1), displaced V(i) needs l(i0) or l(i0 + 1) non-zero with i0 = floor(i - dx / 8), so
; N = [x0 - 1 + ceil(dx / 8), x1 + ceil(dx / 8)] (8 columns; C3 used [x0 + floor(dx / 8) - 1, x1 + 1 + ceil(dx / 8) + 1], 10-11), same
; for y (rows 2cy - 2 .. 2cy + 4); CELL $FF: empty. Clipped to 0..32 x 0..28; region = drawn box U N; drawn := N. A non-empty region:
; RC := 8, tile spans RSA / RSB empty, and the loop constants (once per region; 4.5 item 3, n = -RD): t = n & 7, e = n >> 3 (x), s, f (y);
; L3_LIST +0 K = B - (CV + 78), B = glow lattice + 38 (f + 2) + e + 2; +4 LERP_s row (0: s = 0); the table operands of Hush_L3GF
; (LERP8_t, LERP_t, LERP_s) or Hush_L3PF (LERP_t). Empty: RC := $FF. Uses $04-$0F.
Hush_L3GPick:
    LDA.w !L3_RDM+1 : AND.b #$FE : STA.w !L3_RDM+1                       ; bit 8 := 0
    LDA.w !L3_WDX+8 : STA.w !L3_RDX+8 : STA.b $04                        ; snapshot
    LDA.w !L3_WDY+8 : STA.w !L3_RDY+8 : STA.b $05
    LDA.w !L3_CELL+8 : CMP.b #$FF : BNE +
    JMP .nempty                          ; no lattice
+   AND.b #$0F : ASL A : PHA
    SEC : SBC.b #3 : STA.b $06           ; x0 - 1 = 2cx - 3 (signed; clipped below)
    PLA : CLC : ADC.b #4 : STA.b $07     ; x1 = 2cx + 4
    LDA.w !L3_CELL+8 : AND.b #$F0 : LSR A : LSR A : LSR A : PHA
    SEC : SBC.b #3 : STA.b $08
    PLA : CLC : ADC.b #4 : STA.b $09
    LDA.b $04 : CLC : ADC.b #7 : JSR .asr3 : STA.b $0A                   ; ceil(dx / 8)
    CLC : ADC.b $06 : STA.b $06
    LDA.b $0A : CLC : ADC.b $07 : STA.b $07
    LDA.b $05 : CLC : ADC.b #7 : JSR .asr3 : STA.b $0A                   ; ceil(dy / 8)
    CLC : ADC.b $08 : STA.b $08
    LDA.b $0A : CLC : ADC.b $09 : STA.b $09
    LDA.b $06 : BPL +                    ; clip (signed bytes, all within -5..37)
    STZ.b $06
+   LDA.b $08 : BPL +
    STZ.b $08
+   LDA.b $07 : BMI .nempty
    CMP.b #33 : BCC +
    LDA.b #32 : STA.b $07
+   LDA.b $09 : BMI .nempty
    CMP.b #29 : BCC +
    LDA.b #28 : STA.b $09
+   LDA.b $06 : CMP.b $07 : BEQ + : BCS .nempty
+   LDA.b $08 : CMP.b $09 : BEQ .union : BCC .union
.nempty
    LDA.b #$01 : STA.b $08
    STZ.b $09 : STZ.b $06 : STZ.b $07
.union
    LDA.w !L3_DBY0+8 : CMP.w !L3_DBY1+8 : BEQ + : BCS .useN               ; drawn box empty: region = N
+   LDA.b $08 : CMP.b $09 : BEQ + : BCS .useD                             ; N empty: region = drawn box
+   LDA.w !L3_DBX0+8 : CMP.b $06 : BCC +
    LDA.b $06
+   STA.b $0A
    LDA.w !L3_DBX1+8 : CMP.b $07 : BCS +
    LDA.b $07
+   STA.b $0B
    LDA.w !L3_DBY0+8 : CMP.b $08 : BCC +
    LDA.b $08
+   STA.b $0C
    LDA.w !L3_DBY1+8 : CMP.b $09 : BCS +
    LDA.b $09
+   STA.b $0D
    BRA .set
.useD
    LDA.w !L3_DBX0+8 : STA.b $0A
    LDA.w !L3_DBX1+8 : STA.b $0B
    LDA.w !L3_DBY0+8 : STA.b $0C
    LDA.w !L3_DBY1+8 : STA.b $0D
    BRA .set
.useN
    LDA.b $06 : STA.b $0A
    LDA.b $07 : STA.b $0B
    LDA.b $08 : STA.b $0C
    LDA.b $09 : STA.b $0D
.set
    LDA.b $06 : STA.w !L3_DBX0+8         ; drawn := N
    LDA.b $07 : STA.w !L3_DBX1+8
    LDA.b $08 : STA.w !L3_DBY0+8
    LDA.b $09 : STA.w !L3_DBY1+8
    LDA.b $0A : STA.w !L3_RI0 : STA.w !L3_RIC
    LDA.b $0B : STA.w !L3_RI1
    LDA.b $0C : STA.w !L3_RJA : STA.w !L3_RJ
    LDA.b $0D : STA.w !L3_RJB
    LDA.b $0C : CMP.b $0D : BEQ + : BCC +
    JMP .empty
+   LDA.b #$08 : STA.w !L3_RC
    LDA.b #$FF : STA.w !L3_RSA0 : STA.w !L3_RSB0                         ; C4: no pending tiles (tile rows jA - 1, jA)
    STZ.w !L3_RSA1 : STZ.w !L3_RSB1
    REP #$20
    LDA.b $0C : AND.w #$00FF : INC A : ASL A : ASL A : STA.b $0A          ; 4 (jA + 1)
    ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0A : ADC.w #2 : STA.w !L3_GIVO   ; 68 (jA + 1) + 2
    LDA.b $0C : AND.w #$00FF : INC A : INC A : ASL A : STA.b $0A          ; 2 (jA + 2)
    ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0A : ADC.b $0A : ADC.b $0A : ADC.w #!L3_CV+2 : STA.w !L3_GCVR   ; CV + 38 (jA + 2) + 2
    LDA.w !L3_RDY+8 : JSR .neg           ; n = -dy
    PHA : AND.w #$0007 : BEQ +           ; s = 0: pS = 0 (the s = 0 loop)
    XBA : LSR A : LSR A : CLC : ADC.w #!L3_LERP
+   STA.w !L3_LIST+4                     ; pS = LERP + 64 s
    PLA : JSR .asr3w                     ; f (-2..2)
    INC A : INC A : ASL A : STA.b $0A    ; 2 (f + 2)
    ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0A : ADC.b $0A : ADC.b $0A : STA.b $0A   ; 38 (f + 2)
    LDA.w !L3_RDX+8 : JSR .neg           ; n = -dx
    PHA : AND.w #$0007 : XBA : LSR A : LSR A : CLC : ADC.w #!L3_LERP : STA.b $0C          ; pT = LERP + 64 t
    PLA : JSR .asr3w                     ; e (-2..2)
    CLC : ADC.b $0A : CLC : ADC.w #(!L3_LAT+(8*!L3_LATSZ)+2-!L3_CV-78)&$FFFF : STA.w !L3_LIST+0   ; K
    LDA.w !L3_LIST+4 : BEQ +
    STA.w (Hush_L3GF_LS+1)&$FFFF
    LDA.b $0C : STA.w (Hush_L3GF_LT+1)&$FFFF
    CLC : ADC.w #!L3_LERP8-!L3_LERP : STA.w (Hush_L3GF_L8+1)&$FFFF
    SEP #$20
    RTS
+   LDA.b $0C : STA.w (Hush_L3PF_LT+1)&$FFFF
    SEP #$20
    RTS
.empty
    LDA.b #$FF : STA.w !L3_RC
    RTS
.asr3                                    ; M = 8: A (signed byte) >> 3
    CMP.b #$80 : ROR A
    CMP.b #$80 : ROR A
    CMP.b #$80 : ROR A
    RTS
.neg                                     ; M = 16: A (low byte, signed) -> A = minus it (word); uses $0E
    AND.w #$00FF : EOR.w #$0080 : STA.b $0E
    LDA.w #$0080 : SEC : SBC.b $0E
    RTS
.asr3w                                   ; M = 16: A (signed word) >> 3
    CMP.w #$8000 : ROR A
    CMP.w #$8000 : ROR A
    CMP.w #$8000 : ROR A
    RTS

; (D4: Hush_L3GChg is in the data row, bank $1F: this row is full.)

; Hush_L3Commit (B2c; C3: moved here, JSL / RTL; C4: tile re-derive rewritten, fix 3 of the C1 profile; D4: compose + compare fused): JSL
; from Hush_L3GRun (DB = $7F there), any M / X (kept: PHP). A (low byte) = kind (bit 0 ignored, always violet -> L3_CV; bit 7: "tail" row jB + 1,
; no compare), DP $00 = i0, $01 = i1, $02 = lattice row j (0..28); $00 / $02 kept, $01 := the last point done when the loop stopped
; early (Hush_L3GChg: out of time). Uses $03-$0F, A, X, Y.
; (1) D4: the RAM loop Hush_L3GF / PF (constants from Hush_L3GPick; rows here: P0 = K + CV row j, P1 = P0 + 38, CV row, end = i1 + 1)
; computes the displaced glow V(i, j) for i = i0..i1 and compares it with CV(i, j); a change -> Hush_L3GChg (CV := V, IV deltas, span).
; The changed span [cmin, cmax] gives tiles [max(cmin - 1, 0), min(cmax, 31)], merged into the pending spans of tile rows j - 1 (L3_RSA)
; and j (L3_RSB).
; (2) Tiles: only tile row ty = j - 1 (its corner rows j - 1 and j are final now: row j - 1 was committed before, row j over columns <= i1),
; tiles tx in RSA and in the segment's window [max(i0 - 1, 0), i1 - 1] (last segment of the row, i1 = RI1: up to min(i1, 31); column i1 + 1
; is outside the region), by the RAM loop Hush_L3Tile (35-45 cycles per tile, + 14 changed); light_dirty bit ty >> 1 once if any changed.
; (3) Last segment of the row: RSA := RSB, RSB := empty. Each tile of a region is derived once, after its 4 corners are final.
; DP: $03 composite (CV) row pointer, $05 cmin, $06 cmax, $07 IV offset of tile (0, j), $09 stop point ($FF none), $0A / $0B temp / tile
; lo hi, $0F kind byte. D3: violet only (amber has no regions since D2); the tiles via Hush_L3TRow (the shared per-tile rule).
Hush_L3Commit:
    PHP
    SEP #$30
    STA.b $0F
    REP #$20
    LDA.w !L3_GCVR : STA.b $03           ; D4: kept per row by Hush_L3GPick / GRun (DB = $7F there)
    LDA.w !L3_GIVO : STA.b $07
    SEP #$30
    LDA.b #$FF : STA.b $05               ; cmin: none
    BIT.b $0F : BPL +                    ; tail row: no compare
    JMP .tiles
+   STA.b $09                            ; $FF: the loop did not stop
    REP #$20
    LDA.w !L3_LIST+4 : BEQ .p
    LDA.b $03 : CLC : ADC.w !L3_LIST+0 : STA.w (Hush_L3GF_P0+1)&$FFFF     ; P(e, j + f) at X = 0
    CLC : ADC.w #38 : STA.w (Hush_L3GF_P1+1)&$FFFF                        ; P(e, j + f + 1)
    LDA.b $03 : STA.w (Hush_L3GF_CV+1)&$FFFF
    SEP #$20 : LDA.b $01 : INC A : STA.w (Hush_L3GF_E+1)&$FFFF : REP #$20 ; CPX #end
    LDA.w #(Hush_L3GF-1)&$FFFF
    BRA .go
.p  LDA.b $03 : CLC : ADC.w !L3_LIST+0 : STA.w (Hush_L3PF_P0+1)&$FFFF
    LDA.b $03 : STA.w (Hush_L3PF_CV+1)&$FFFF
    SEP #$20 : LDA.b $01 : INC A : STA.w (Hush_L3PF_E+1)&$FFFF : REP #$20
    LDA.w #(Hush_L3PF-1)&$FFFF
.go                                      ; M = 16, A = RAM entry - 1: RTL into bank $7F (= DB) with X = i0, M = X = 8; it RTLs back to .r
    PHK : PER .r-1
    PHB : PHA
    SEP #$30
    LDX.b $00
    RTL
.r                                       ; M = X = 8
    LDA.b $09 : BMI .span
    STA.b $01                            ; stopped: the segment ends at point $09
.span                                    ; M = X = 8
    LDA.b $05 : BMI .tiles               ; nothing changed
    BEQ +
    DEC A
+   STA.b $0A                            ; lo = max(cmin - 1, 0)
    LDA.b $06 : CMP.b #32 : BCC +
    LDA.b #31
+   STA.b $0B                            ; hi = min(cmax, 31)
    LDA.b $0A : CMP.w !L3_RSA0 : BCS +
    STA.w !L3_RSA0
+   CMP.w !L3_RSB0 : BCS +
    STA.w !L3_RSB0
+   LDA.b $0B : CMP.w !L3_RSA1 : BCC +
    STA.w !L3_RSA1
+   CMP.w !L3_RSB1 : BCC .tiles
    STA.w !L3_RSB1
.tiles                                   ; M = X = 8: tile row j - 1, tiles RSA x window
    LDA.b $02 : BNE +
    JMP .roll                            ; no tile row -1
+   LDA.b $00 : BEQ +
    DEC A
+   CMP.w !L3_RSA0 : BCS +
    LDA.w !L3_RSA0
+   STA.b $0A                            ; lo = max(i0 - 1, 0, RSA lo)
    LDA.b $01 : CMP.w !L3_RI1 : BCC +
    CMP.b #32 : BCC ++                   ; last segment: up to min(i1, 31)
    LDA.b #31
    BRA ++
+   DEC A : BPL ++                       ; else up to i1 - 1
    JMP .roll
++  CMP.w !L3_RSA1 : BCC +
    LDA.w !L3_RSA1
+   STA.b $0B                            ; hi = min(window, RSA hi)
    CMP.b $0A : BCS .call
    JMP .roll                            ; nothing pending in the window
.call
    REP #$30
    LDA.b $02 : DEC A : JSL Hush_L3TRow  ; D3: tile row j - 1, tiles $0A .. $0B (sets the light_dirty bit itself)
.roll
    SEP #$30
    LDA.b $01 : CMP.w !L3_RI1 : BCC .out
    LDA.w !L3_RSB0 : STA.w !L3_RSA0      ; the row is done: tile row j's pending span moves up
    LDA.w !L3_RSB1 : STA.w !L3_RSA1
    LDA.b #$FF : STA.w !L3_RSB0
    STZ.w !L3_RSB1
.out
    PLP
    RTL
Hush_L3Bank1B_End:
assert pc() <= $1BB800                   ; src/FREESPACE.md row $1BB340-$1BB7FF
