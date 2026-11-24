; =============================================================================
; light.asm  (L1: lantern light = guard sight, design/lighting.md; docs/engine_notes.md section 16)
;
; Not a hook file of its own: three existing HUSH routines call in (no new vanilla bytes are replaced):
;   roomload.asm  Hush_AttrSet   end `STZ.w $0200 : RTL` -> `JML Hush_LightInit` (which does the STZ and the RTL): after the collision map is built,
;                                in the forced blank of Module06 -> light state reset, cell solidity from $7F2000, BG1 window := no light (VRAM upload)
;   meter.asm     Hush_MeterFrame `.out` -> `JSL Hush_LightWork` (end of every Module07 frame, after the guards and Link ran)
;   sa1.asm       Hush_Sa1Entry idle loop -> `JSL Hush_LightJob` (SA-1 step 4: the worker runs on the SA-1, see "SA-1 light worker" below)
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
;   E rev5 (design/lighting.md revision 5, src/dev/L3_REPORT.md "## E rev5"; supersedes the D3 amber above): every guard slot g has its own
;   pair-coded lattice l_g (light_l3glat, built at its job end, Hush_L3GLat) and is displaced by its own d (light_l3car, D = 1). The SA-1
;   amber pass (Hush_L3AStep, bank $03 row) re-composites A = max over guards of V_g over the rows a dirty guard's old / new box touch, then
;   QH / QL index words and tile marks; the tile loop takes amber from LutA[QH + QL] (BW-RAM copy), else violet. The pair grids / LUTF are gone.
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
;   SA-1 light worker (bring-up step 4): Hush_LightWork (SNES, end of frame) keeps the colour math, the palette check and Hush_LightPal (WRAM),
;   then Hush_LightPost stages the inputs (sprite arrays, room, ink, Link / scroll; docs/ram_map.md sa1_stage) in I-RAM and posts the frame
;   (sa1_cmd := $FF). The SA-1 (Hush_LightJob) copies them, clears sa1_cmd and runs the worker (Hush_LightRun, D = $3100). No V counter on
;   the SA-1: Hush_LightV = sa1_cmd, so the units run until the work is done or the next frame is posted. The NMI time-gates its rows by the
;   PPU V counter (LIGHT_NMIEND) and never reads a cell row the SA-1 is writing (Hush_L3Lock / Unlock, sa1_trow / sa1_nmiup).
;   light_job ($7EE770): slot 0-7 = a guard job runs, $FF = idle ($FE is no longer used).
;   light_dirty ($7EE742): bits 0-13 = cell rows to upload (none are set until B2); 0 = the BG1 VRAM window equals light_tiles.
;
; Space:    src/FREESPACE.md rows $1FB780-$1FC3FF (this code), $1FC400-$1FC9FF (build/rooms_gen.asm: Hush_LightTab, Hush_LightWords - the
;           old per-cell words, no longer read) and $1FCA00-$1FFFFF (build/light_gen.asm, the L3 tables and the code that did not fit the
;           code row: Hush_LightGrids / ZeroGrids / L3*; all bank $1F, so JSR works): vanilla room object data of rooms HUSH never
;           loads (rooms.asm:750-870) + the $FF tail NULL_1FFF4E, same evidence as the E1 room-data rows. C3: $1BB340-$1BB7FF (D4: Hush_L3GRun,
;           Hush_L3GPick, Hush_L3GChg, Hush_L3Commit; JSL from bank $1F; the unclaimed tail of NULL_1BB1E0, bank_1B.asm:6-209). SA-1 step 4:
;           $03EB05-$03EB7F (Hush_LightPost; head of NULL_03EB05, bank_03.asm:4559-4581).
; RAM:      SA-1 step 3: BW-RAM $40:CA00-$40:E7FF (light vars, was $7ECA00-$7EE7FF) and $41:8000-$41:DD7F (L3 caches, was $7F8000-$7FDD7F),
;           same low 16 bits as before (docs/ram_map.md "HUSH lighting" / L3); the same long addresses for the SNES ($40-$4F, Sa1.cpp:68) and
;           the SA-1 ($40-$5F, Sa1.cpp:69). SA-1 step 4: the worker runs on the SA-1, which cannot read WRAM: the sprite arrays, hush_room and
;           the ink are read from the staged copy in I-RAM (!SA1_IN_*), Link / scroll from its direct page ($3100); the SNES-only parts
;           (Hush_LightInit / Pal / Wipe / Nmi / Work) still read WRAM long ($7Exxxx).
;           Direct page $00-$0F scratch (end of frame / Module06 only, never in the NMI; SA-1: its own page $3100). Vanilla $7E0134 (animated
;           tile VRAM word, see above). I-RAM $3004-$3009, $3100-$353F (docs/ram_map.md "SA-1 memory"). DMA channel 5 + WMADD / WMDATA
;           (Hush_LightPost; unused by vanilla).
;           SNES access time is unchanged: banks $40-$7F are all 8 master clocks per access (MesenCE SnesMemoryManager.cpp:92-94).
; =============================================================================

!L_BANK   = $40                  ; light vars (L_*): BW-RAM bank $40 (SA-1 step 3; was WRAM $7E)
!L3_BANK  = $41                  ; L3 caches (L3_* / LP_*): BW-RAM bank $41 (was WRAM $7F)
!LB       = $400000              ; long base of L_* (was $7E0000)
!L3B      = $410000              ; long base of L3_* / LP_* (was $7F0000)
!L_DBW    = $4040                ; PEA operand: DB := !L_BANK
!L3_DBW   = $4141                ; PEA operand: DB := !L3_BANK

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
                         ;    step 5a: = L_WD | the published rows not yet retired (SA-1 writes only; the NMI never writes it)
!L_WD     = $E744        ; 2  step 5a: cell rows of light_tiles changed since their last copy to light_pub (SA-1 only)
!L_PUBM   = $E746        ; 2  step 5a: rows of the last publication (non-zero: retire it once SA1_PUBF is 0 again; SA-1 only)
!L_PUB    = $2000        ; 1792 step 5a: light_pub, the published copy of light_tiles (same layout); the NMI uploads only from here
!LIGHT_WIN0 = 1          ; step 5a: 1 = the BG1 light window is tilemap tiles 0..31 x 0..27 of screen 0 (one DMA per row span, bg1_window.asm);
                         ;    0 = tiles 16..47 x 18..45 as before (2 DMAs per cell row). tests/smoke/lighting.lua is layout-agnostic (qa)
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

; L3 glued light (design/lighting.md 4.5; src/dev/L3_REPORT.md "Step A1 RAM map"; docs/ram_map.md light_l3*), bank !L3_BANK, DB = !L3_BANK.
; (Comments below that say "bank $7F" / "DB = $7F" / "$7Fxxxx" mean bank !L3_BANK = $41 since SA-1 step 3; "bank $7E" / "DB = $7E" for the
; L_* variables mean !L_BANK = $40.)
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
!L3_OK    = $C7D0                ; 2  $4C35 (D4; D3 $4C34) = LERP / LERP8 / L3_D tables, the RAM code, (D3) LUTF and (D4) L3_GTAB built (SA-1 step 3:
                                 ;    zeroed at every power-on / reset by Hush_Sa1Entry, sa1.asm; was the intro WRAM clear, bank_0C.asm:88-113)
assert !L3B+!L3_OK == !SA1_L3OK
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
; E rev5 (design/lighting.md revision 5: guard carriers 0-7 displaced too; src/dev/L3_REPORT.md "## E rev5"; docs/ram_map.md rows), bank $41:
!L3_GLAT  = $0000                ; 8 x 1292 guard lattices l_g, g at $0000 + 1292 g, pair-coded P(i, j) = 8 l(i, j) + l(i + 1, j) at
                                 ;    G(i, j) = (j + 2) * 38 + (i + 2) (same layout as the glow lattice); built at the end of each guard job
                                 ;    (Hush_L3GLat) from light_scr; padding / outside the light 0
!L3_CA    = $2860                ; 1292 composite amber lattice A(i, j) = max over guards of V_g (plain levels 0..6), same G
!L3_QH    = $2E00                ; 1856 [64 j + 2 i] word = 98 (7 A(i, j) + A(i + 1, j)), j 0..28, i 0..31 (tile top corners: 686a + 98b)
!L3_QL    = $3540                ; 1856 [64 j + 2 i] word = 2 (7 A(i, j) + A(i + 1, j)) (tile bottom corners: 14c + 2d)
!L3_AZEND = $3C80                ; Hush_L3AZero zeroes $41:0000 .. AZEND - 1 (lattices, CA, QH, QL)
!L3_AST   = $3D00                ; amber pass state: +0 1 = a pass runs, +1 next row j, +2 1 = zero the amber RAM at the next SA-1 run
!L3_APASS = !L3_AST+0
!L3_AJ    = !L3_AST+1
!L3_AFRESH = !L3_AST+2           ;    (set by Hush_LightInit on every room load)
!L3_ASLO  = $3D40                ; 29  per lattice row j: first point of the pass's span ($FF: none)
!L3_ASHI  = $3D60                ; 29  last point
!L3_ABASE = $3D80                ; 16  per guard g (word): G base of P(i + e, j + f) at i = j = 0 = 1292 g + 38 (f + 2) + e + 2 (rendered d)
!L3_AT    = $3DA0                ; 8   per guard: t = (-RDX) & 7
!L3_AS    = $3DA8                ; 8   per guard: s = (-RDY) & 7
!L3_LUTA  = $9000                ; 4802 BW-RAM copy of Hush_LightLutA (Hush_L3Tables, once per power-on; was D3 light_lutf)
!L3_NEW   = $C600                ; 64  new composite amber row of the pass (index i 0..32; was light_l3new)

!LIGHT_VMAX = 200        ; no new unit at or after this scanline; long units also stop at it (Hush_LightLate). After LightWork the frame still
                         ; runs HandleFloorIndicator + PrepareOAMForTransfer (bank_02.asm:1509, bank_00.asm:76). Measured (tests/dev/nmi_probe.lua,
                         ; final room): end of logic max 219 of 225, 0 lag frames (204: max 223, too close; 196: r19 light latency too long)
!LIGHT_NMIROWS = 14      ; cell rows uploaded per NMI at most (SA-1 step 4: all 14; the real cap is LIGHT_NMIEND. Was 6: 768 bytes in 12 DMAs,
                         ; ~7 lines from line ~250, with the vanilla animated-tile upload still in every NMI)
!LIGHT_NMIEND = 258      ; SA-1 step 4: Hush_LightNmi starts a row (2 DMAs of 48 words, ~1 line) only below this PPU line (vblank ends at 261;
                         ; src/dev/sa1_probe.lua "NMI end" = the NMI's INIDISP restore)
!LIGHT_JOBQ = 4          ; D3 (B-010): guard job units run first until 3/4 of the frame's unit lines are used (L_VJOB), then the rotation
assert !LIGHT_JOBQ == 4  ; Hush_LightWork divides by 4 with two LSR
!L_VJOB   = $E7FD        ; 2  D3: V counter up to which Hush_L3Unit runs the guard job first (set by Hush_LightWork every light frame)

; -----------------------------------------------------------------------------
; Data: build/light_gen.asm (tools/roomgen.py from tools/autotile.py; data only, defines !HUSH_LIGHT_*) + the render tables.
; First in the file: the !HUSH_LIGHT_* defines are used by the code below.
org $1FCA00
Hush_LightGfx:
incsrc "!HUSH_LIGHT_GEN"
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
    LDA.w #!L3_LAT+(8*!L3_LATSZ) : LDX.w #!L3_LATSZ : JSR Hush_LightZeroGrids   ; the glow lattice (E rev5: the guard lattices, CA, QH / QL
                                                                                ; are zeroed by the SA-1, Hush_L3AZero, light_l3afresh)
    LDA.w #!L3_CV : LDX.w #(!L3_PVIO+960-!L3_CV) : JSR Hush_LightZeroGrids   ; CV (B2d: light_tiles is reset to empty) + light_pvio
    LDA.w #!L3_IV : LDX.w #2040 : JSR Hush_LightZeroGrids                   ; C4: violet tile indexes (= CV all 0)
    PEA !L3_DBW : PLB : PLB
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
    LSR A : LSR A : ORA.b $02 : STA.l !L3B-1,X               ; P(2k - 1) = 8 O(k-1) + E(k)
    LDA.b $06 : AND.b #$FC : ASL A : STA.b $06               ; 8 E(k)
    LDA.b $07 : INC A : LSR A : ORA.b $06 : STA.l !L3B,X     ; P(2k) = 8 E(k) + O(k)
    AND.b #$07 : ASL A : ASL A : ASL A : STA.b $02           ; 8 O(k)
    LDA.b $07 : STA.b $06
    INX : INX : INY
    DEC.b $0D : BNE .k
    LDA.b ($00),Y : CLC : ADC.b ($03),Y : ADC.b $06 : ADC.b #2 : LSR A : LSR A   ; E(k0 + n)
    ORA.b $02 : STA.l !L3B-1,X           ; P(2(k0 + n) - 1)
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
    LDA.b #!L3_BANK : STA.b $0A          ; light_pvio's bank
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

; Hush_LightZeroGrids: JSR, M = X = 16 (P, DB kept), A = bank !L3_BANK address, X = byte count (>= 2): := 0. SA-1 step 3: a CPU fill
; (the old DMA channel 5 -> WMDATA fill only reaches WRAM, and A-bus -> A-bus DMA does not exist): the first byte := 0, then MVN copies it
; forward over the next n - 1 bytes (source = dest - 1, 7 cycles per byte; ~9.7 KB per room load, forced blank).
Hush_LightZeroGrids:
    PHP : PHB
    REP #$30
    PHA                                  ; start
    PEA !L3_DBW : PLB : PLB
    TAY : INY                            ; Y = destination = start + 1
    DEX : DEX : TXA                      ; A = n - 2: MVN moves A + 1 = n - 1 bytes
    PLX                                  ; X = source = start
    SEP #$20 : STZ.w $0000,X : REP #$20  ; the first byte
    MVN !L3_BANK,!L3_BANK                ; (DB := the destination bank, restored below)
    PLB : PLP
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
    PHB                                  ; E rev5: LutA -> L3_LUTA (BW-RAM; the tile loop reads it with abs,Y; was D3's LUTF build)
    LDA.w #(2*2401)-1 : LDX.w #Hush_LightLutA : LDY.w #!L3_LUTA
    MVN !L3_BANK,Hush_LightLutA>>16      ; (asar emits the operands as written: 54 dest src; checked in the built ROM)
    PLB
    RTS
assert Hush_LightLutV-Hush_LightLutA == 2*2401
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

; (E rev5: Hush_LightBuild, Hush_LightAmb, Hush_LightAmbRow and Hush_LightMarkRow removed: amber is the composite of the displaced guard
; lattices, Hush_L3ARow in the bank $03 row; the commit no longer marks tiles.)

; Hush_L3RowL / Hush_L3WantL (E rev5): JSL wrappers of Hush_L3Row / Hush_L3Want for the bank $03 row (same entry / exit state).
Hush_L3RowL:
    JSR Hush_L3Row
    RTL
Hush_L3WantL:
    JSR Hush_L3Want
    RTL

; Hush_L3PVio: Y = cell i (M = 8, X = 16, DB = $7E): light_pvio[p] := light_vio[i] (the padded copy the glow lattice reads). Keeps X, Y; uses $0E.
Hush_L3PVio:
    PHX
    REP #$20
    TYA : AND.w #$00F0 : ASL A : STA.b $0E
    TYA : AND.w #$000F : CLC : ADC.b $0E : TAX
    SEP #$20
    LDA.w !L_VIO,Y : STA.l !L3B+!L3_PVIO+(8*32+8),X
    PLX
    RTS

; Hush_L3TMark (D2; D3: inputs in $08 / $09; E rev5: JSL from Hush_L3ACommit, bank $03) (M = 8, X = 16, any DB), A = tile row ty (0..27),
; $08 = lo + 1, $09 = hi + 1 (tile columns): light_tdirty span of row ty grows to cover them, light_l3adb (pending tile rows) grows to cover
; ty. Uses X.
Hush_L3TMark:
    CMP.l !L3B+!L3_ADB : BCS +
    STA.l !L3B+!L3_ADB
+   CMP.l !L3B+!L3_ADB+1 : BCC +
    STA.l !L3B+!L3_ADB+1
+   REP #$20 : AND.w #$00FF : ASL A : ASL A : TAX : SEP #$20
    LDA.l !LB+!L_TD,X : BEQ + : CMP.b $08 : BCC ++
+   LDA.b $08 : STA.l !LB+!L_TD,X
++  LDA.l !LB+!L_TD+1,X : CMP.b $09 : BCS +
    LDA.b $09 : STA.l !LB+!L_TD+1,X
+   RTL

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
    LDA.l !SA1_IN_ROOM : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX     ; hush_room (staged, SA-1 step 4)
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
    LDA.w !L_JBY0 : CLC : ADC.b #7 : STA.b $08                ; padded row cy + 8 of cy = JBY0 - 1 .. (E rev5: one row above and below the
    LDA.w !L_JBY1 : CLC : ADC.b #9 : STA.b $09                ; box too, so Hush_L3GLat's lattice rows 2 JBY0 - 1 .. 2 JBY1 + 3 read only
                                                              ; the new light or 0; rows -1 / 14 are padding, always 0)
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

; (E rev5: Hush_LightLateC removed with Hush_LightAmb.)

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
; E rev5 (design/lighting.md revision 5, 4.5 item 2): guard carriers 0-7 are displaced again: centre = sprite origin + (8, 8) (the staged
; sprite arrays, as Hush_LightSig): dx = x + 8 - $E2 - (16cx + 8) = x - $E2 - 16cx, dy = y - $E8 - 16cy, clamped; D = 1. Also JSL (Hush_L3WantL)
; from the amber pass pick, so a lattice committed earlier in the same light frame gets its d before the snapshot.
Hush_L3Want:
    REP #$20
    LDX.w #$0008
    JSR .cell : BCS .lz                  ; X = 8: the glow
    LDA.b $22 : SEC : SBC.b $E2 : SEC : SBC.b $00 : JSR .clamp : STA.b $04
    LDA.b $20 : CLC : ADC.w #8 : SEC : SBC.b $E8 : SEC : SBC.b $02 : JSR .clamp
    BRA .ls
.g  JSR .cell : BCS .lz                  ; X = 0..7: guard slot
    SEP #$20
    LDA.l !SA1_IN_SPR+$0D30,X : XBA : LDA.l !SA1_IN_SPR+$0D10,X
    REP #$20
    SEC : SBC.b $E2 : SEC : SBC.b $00 : JSR .clamp : STA.b $04
    SEP #$20
    LDA.l !SA1_IN_SPR+$0D20,X : XBA : LDA.l !SA1_IN_SPR+$0D00,X
    REP #$20
    SEC : SBC.b $E8 : SEC : SBC.b $02 : JSR .clamp
    BRA .ls
.lz LDA.w #$0000 : STA.b $04
.ls JSR .store
    DEX : BPL .g
    SEP #$20
    RTS
.cell                                    ; M = 16, X = carrier: C = 1 no lattice; else $00 = 16cx, $02 = 16cy
    LDA.l !L3B+!L3_CELL,X : AND.w #$00FF : CMP.w #$00FF : BCS +
    PHA : AND.w #$000F : ASL A : ASL A : ASL A : ASL A : STA.b $00
    PLA : AND.w #$00F0 : STA.b $02
    CLC
+   RTS
.store                                   ; M = 16: A = dy, $04 = dx, X = carrier -> bank $7F bytes; M = 16 on return
    SEP #$20
    STA.l !L3B+!L3_WDY,X
    LDA.b $04 : STA.l !L3B+!L3_WDX,X
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
    STA.l !L3B+!L3_GLIM
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
base !L3B+!L3_CODE
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
; E rev5: Hush_L3Tile, entered by RTL from Hush_L3TRow (operands patched there): M = X = 16, DB = $41, X = 2 tx of the first tile. Per tile:
; amber index = QH(tx, ty) (_A) + QL(tx, ty + 1) (_B) = 686a + 98b + 14c + 2d of the composite amber corners (light_l3ca, design/lighting.md
; 4.5 item 4: max over the guards of V_g); 0 = no amber corner > 0: then the violet word LutV[IV(tx, ty)] via [$06] (LutV[0] = the empty
; tile; 4.3 "amber wins"); else LutA[index] from its BW-RAM copy (L3_LUTA). light_tiles row (_C / _S, bank $40) written only on change,
; then $0C := the word (non-zero: every LUT word has a tile id >= $100). _E = end = 2 (hi + 1). Returns by RTL.
Hush_L3Tile:
Hush_L3Tile_A:
    LDA.w $0000,X                        ; QH row ty
    CLC
Hush_L3Tile_B:
    ADC.w $0000,X                        ; + QL row ty + 1
    BEQ Hush_L3Tile_V
    TAY
    LDA.w !L3_LUTA,Y
Hush_L3Tile_C:
    CMP.l !LB,X                          ; light_tiles
    BEQ Hush_L3Tile_N
Hush_L3Tile_S:
    STA.l !LB,X
    STA.b $0C                            ; changed
Hush_L3Tile_N:
    INX : INX
Hush_L3Tile_E:
    CPX.w #$0000 : BCC Hush_L3Tile
    RTL
Hush_L3Tile_V:
Hush_L3Tile_IV:
    LDA.w $0000,X                        ; IV row ty
    TAY
    LDA.b [$06],Y                        ; LutV
    BRA Hush_L3Tile_C
; E rev5: the amber compose loops, entered by RTL from Hush_L3ARow (bank $03; operands patched there per guard and row): M = X = 8,
; DB = $41, X = first point i. NEW[i] := max(NEW[i], V_g(i, j)) (4.5 item 3, one guard: P0 = P(i + e, j + f) of its pair-coded lattice,
; P1 = the row below; Hush_L3GA: s > 0, Hush_L3PA: s = 0). Returns by RTL.
Hush_L3GA:
Hush_L3GA_P0:
    LDY.w $0000,X
Hush_L3GA_L8:
    LDA.w $0000,Y                        ; 8 H0
Hush_L3GA_P1:
    LDY.w $0000,X
Hush_L3GA_LT:
    ORA.w $0000,Y                        ; + H1
    TAY
Hush_L3GA_LS:
    LDA.w $0000,Y                        ; V
    CMP.w !L3_NEW,X
    BCC +
    STA.w !L3_NEW,X
+   INX
Hush_L3GA_E:
    CPX.b #$00 : BCC Hush_L3GA
    RTL
Hush_L3PA:
Hush_L3PA_P0:
    LDY.w $0000,X
Hush_L3PA_LT:
    LDA.w $0000,Y                        ; V = H0
    CMP.w !L3_NEW,X
    BCC +
    STA.w !L3_NEW,X
+   INX
Hush_L3PA_E:
    CPX.b #$00 : BCC Hush_L3PA
    RTL
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
    LDA.w #$0000 : STA.l !LB+!L_RDONE  ; + the free byte after it
    RTS

; Hush_L3Mark: JSR (bank $1F), any M / X (P, X kept), X = carrier 0..8: L3_RDM |= 1 << c (its lattice changed).
Hush_L3Mark:
    PHP
    REP #$30
    PHX
    TXA : AND.w #$000F : ASL A : TAX
    LDA.l Hush_L3Bit,X : ORA.l !L3B+!L3_RDM : STA.l !L3B+!L3_RDM
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
    STA.l !L3B,X : STA.l !L3B+2,X : STA.l !L3B+4,X : STA.l !L3B+6,X : STA.l !L3B+8,X
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
    LDA.l !L3B+!L3_PVIO+(8*32+8)+1,X : ASL A : ASL A : ASL A : ASL A : STA.b $0E   ; east (0 / 1) << 4
    LDA.l !L3B+!L3_PVIO+(8*32+8)-1,X : ASL A : ASL A : ASL A : TSB.b $0E           ; west << 3
    LDA.l !L3B+!L3_PVIO+(8*32+8)+32,X : ASL A : ASL A : TSB.b $0E                 ; south << 2
    LDA.l !L3B+!L3_PVIO+(8*32+8)-32,X : ASL A : TSB.b $0E                         ; north << 1
    LDA.l !L3B+!L3_PVIO+(8*32+8),X : LSR A : ORA.b $0E                             ; centre 2 -> bit 0
    REP #$20
    AND.w #$001F : JSR Hush_L3GOff : TAY
    PLA : JSR Hush_L3GAdr
    PHB : PEA !L3_DBW : PLB : PLB
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

; Hush_LightPpuV: PPU V counter -> A (M = 16 on return). The latch / flip-flop sequence of the vanilla scanline wait (bank_00.asm:15152).
; SNES only (SA-1 step 4: Hush_LightWork's palette gate; was Hush_LightV, the worker's time base).
Hush_LightPpuV:
    SEP #$20
    LDA.l $002137
    LDA.l $00213F
    LDA.l $00213D : XBA
    LDA.l $00213D : AND.b #$01 : XBA
    REP #$20
    RTS

; Hush_LightV (SA-1 step 4: the worker runs on the SA-1, which cannot read the PPU, and MesenCE's SA-1 H/V counter read registers
; $2302-$2305 return nothing, Sa1.cpp:430-434): the worker's "time" -> A (M = 16 on return) = the mailbox command byte: 0 while no new
; frame is posted ("early": every LIGHT_VMAX / GLIM / VJOB gate passes; L_V0 = 0), $FF (>= LIGHT_VMAX) once the SNES posted the next
; frame (Hush_LightPost): every unit stops as it did at LIGHT_VMAX, the worker returns, the SA-1 takes the new inputs.
Hush_LightV:
    REP #$20
    LDA.l !SA1_CMDL : AND.w #$00FF
    RTS

; Hush_LightPub (SA-1 step 5a, double buffer; replaces the step 4 row lock Hush_L3Lock / Unlock): JSR from Hush_LightRun (SA-1) at its start,
; after every unit and at its exit; any M, X = 16, any DB (kept); returns M = 8, X = 16. Uses A, X, Y, stack only (no DP).
; The SA-1 renders into light_tiles (L_WD: rows changed since their copy); the NMI uploads only light_pub. While SA1_PUBF = 1 the NMI owns
; light_pub and SA1_PUBT, and this does nothing. Else: (1) retire: the last publication is in VRAM -> light_dirty := L_WD (the rows that
; changed since); (2) publish: L_WD != 0 -> its span of cell rows lo .. hi is copied light_tiles -> light_pub (MVN, 128 B per cell row),
; SA1_PUBT := t0 = 2 lo, n = 2 (hi - lo + 1) tile rows, L_PUBM := L_WD, L_WD := 0, then SA1_PUBF := 1 (last). light_dirty keeps the
; published rows until they are retired, so light_dirty = 0 still means "the BG1 VRAM window equals light_tiles".
Hush_LightPub:
    PHB
    PEA !L_DBW : PLB : PLB
    SEP #$20
    LDA.l !SA1_PUBF : BNE .out
    REP #$20
    LDA.w !L_PUBM : BEQ +
.retire                                  ; (labels for src/dev/e5_probe.lua)
    STZ.w !L_PUBM                        ; retire
    LDA.w !L_WD : STA.w !L_DIRTY
+   LDA.w !L_WD : BEQ .out
.publish
    STA.w !L_PUBM
    STZ.w !L_WD
    LDX.w #$FFFF
-   INX : LSR A : BCC -                  ; X = lo (the lowest set bit)
    TXY
-   AND.w #$3FFF : BEQ +                 ; (sets Z from A: TXY set it from Y)
    INY : LSR A : BRA -                  ; Y = hi (the highest set bit)
+   TXA : ASL A : PHA                    ; 1,S = t0
    TYA : INC A : ASL A : SEC : SBC $01,S                     ; n = 2 (hi + 1) - t0
    XBA : ORA $01,S : STA.l !SA1_PUBT    ; t0, n
    AND.w #$FF00 : LSR A : LSR A : DEC A : PHA                ; 64 n - 1 (MVN count); 3,S = t0
    LDA $03,S : XBA : LSR A : LSR A      ; 64 t0
    PHA : CLC : ADC.w #!L_TILES : TAX
    PLA : CLC : ADC.w #!L_PUB : TAY
    PLA
    MVN !L_BANK,!L_BANK                  ; light_tiles rows t0 .. t0 + n - 1 -> light_pub (DB := !L_BANK)
    PLA
    SEP #$20
    LDA.b #$01 : STA.l !SA1_PUBF         ; published: the NMI owns light_pub now
.out
    SEP #$20
    PLB
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
-   LDA.l !SA1_CMDL : BNE -              ; SA-1 step 4: no light frame posted or running (nothing posts one before this returns: only
    LDA.l !SA1_STATL : CMP.b #$02 : BEQ - ; Hush_LightWork in module 7 does), so the SA-1 does not touch the light state reset below
    LDA.b #$00 : STA.l !SA1_PUBF         ; step 5a: nothing published (the NMI uploads nothing outside module 7 anyway)
    PHB : PHP
    REP #$30
    PEA !L_DBW : PLB : PLB
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
-   STA.w !L_TILES,X : STA.w !L_PUB,X : INX : INX : CPX.w #1792 : BCC -    ; light_tiles and light_pub (step 5a)
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
    STA.w !L_DIRTY : STA.w !L_INKP : STA.w !L_JE : STA.w !L_WD : STA.w !L_PUBM
    DEC A : STA.w !L_LCELL
    SEP #$20
    LDA.b #$FF : STA.w !L_JOB
    STZ.w !L_RR
    LDA.b #$01 : STA.w !L_PALREQ : STA.w !L_ON
    STA.l !L3B+!L3_AFRESH                ; E rev5: the SA-1 zeroes the amber RAM (guard lattices, CA, QH / QL) before its next light frame
    REP #$30
    JSR Hush_LightGrids                  ; lattices / light_pvio := 0 (COMP / VIO are 0), no carrier has a lattice, L3 tables once
    SEP #$20
    JSL Hush_LightChrUp                  ; the light tiles (slots 4-6) + the animated tiles moved to slot 7
    ; BG1 window := no light (28 tile rows, forced blank; from light_pub, step 5a)
    PEA $0000 : PLB : PLB
    REP #$30
    JSR Hush_LightDmaSetup
if !LIGHT_WIN0
    LDA.w #!L_PUB : STA.w $4302          ; step 5a: the window is one contiguous block at VRAM word $1000: one DMA
    LDA.w #$1000 : STA.w $2116
    LDA.w #1792 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B
else
    LDA.w #$0000
-   PHA
    JSR Hush_LightUpRow
    PLA : INC A : CMP.w #14 : BCC -      ; 14 cell rows = 28 tile rows
endif
    PLP : PLB
    RTL

; -----------------------------------------------------------------------------
; Hush_LightDmaSetup: DB = $00, M = X = 16 (returns M = 16): DMA0 = mode 1 to VMDATA from bank !L_BANK, VMAIN = $80.
; Hush_LightUpRow (!LIGHT_WIN0 = 0 only): A = cell row 0..13 = tile rows t = 2A, 2A + 1 of light_pub (step 5a; was light_tiles)
; (window rows; tilemap rows 18 + t; BG1 tilemap at VRAM word $1000, 2 x 2 screens of 32 x 32, as
; Hush_BuildRoom .layer). 2 DMAs of 48 words instead of 4 of 16: left screen from (row 18 + t, column 16): light_tiles row t left half ->
; columns 16-31, its right half -> row 19 + t columns 0-15 (left of the window: never shown, the camera is fixed at tilemap x 16..47,
; docs/gfx/art_map.md), row t + 1 left half -> columns 16-31; right screen from (row 18 + t, column 0): row t right half, row t + 1 left
; half -> columns 16-31 (right of the window), row t + 1 right half. Tile rows 2A and 2A + 1 are always on the same screen row (18 + 2A
; is even, the top / bottom screens split at tilemap row 32 = window row 14).
Hush_LightDmaSetup:
    SEP #$20
    LDA.b #$80 : STA.w $2115             ; VMAIN: increment after the high byte
    LDA.b #!L_BANK : STA.w $4304         ; DMA0 source bank: light_pub (BW-RAM)
    REP #$20
    LDA.w #$1801 : STA.w $4300           ; DMA0: mode 1 to VMDATA
    RTS

if !LIGHT_WIN0 == 0
Hush_LightUpRow:
    ASL A : PHA                          ; t = 2A
    XBA : LSR A : LSR A                  ; 64 t (bytes per light_pub row)
    CLC : ADC.w #!L_PUB : STA.w $4302
    PLA : CLC : ADC.w #18                ; tilemap row
    CMP.w #32 : BCC +
    ADC.w #31                            ; C = 1: + 32 (the bottom screens start at $1800 = $1000 + 64 rows)
+   ASL A : ASL A : ASL A : ASL A : ASL A
    CLC : ADC.w #($1000+16) : STA.w $2116
    PHA
    LDA.w #96 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    PLA : CLC : ADC.w #($0400-16) : STA.w $2116                  ; the right screen, column 0
    LDA.w $4302 : SEC : SBC.w #64 : STA.w $4302                  ; the source advanced by 96: back to the row's right half (+32)
    LDA.w #96 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    RTS
endif

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
;   module 7 (step 5a): the published light_pub rows (SA1_PUBF = 1: tile rows t0 .. t0 + n - 1, SA1_PUBT) go to VRAM while they fit before
;   PPU line LIGHT_NMIEND; the rest stays published (t0 / n advanced) for the next NMI; all done -> SA1_PUBF := 0 (the SA-1 retires them and
;   may publish again, Hush_LightPub). No lock: the SA-1 never writes light_pub / SA1_PUBT while SA1_PUBF = 1, and light_tiles is never read
;   here. Item menu (module $0E, submodule 1): $1D := 0 for this frame (no light behind the menu; Hush_LightWork sets bit 0 again in the
;   next gameplay frame).
Hush_LightNmi:
    PHP : PHB
    SEP #$20
    LDA.l !LB+!L_ON : BEQ .out
    LDA.b $10 : CMP.b #$07 : BEQ .room
    CMP.b #$0E : BNE .out
    LDA.b $11 : CMP.b #$01 : BNE .out
    STZ.b $1D
.out
    PLB : PLP
    RTL
.room
    LDA.l !SA1_PUBF : BEQ .out           ; nothing published
    REP #$30
    PHX : PHY
    PEA $0000 : PLB : PLB                ; DB = $00 (PPU / DMA registers; I-RAM is read long)
    JSR Hush_LightDmaSetup               ; M = 16
if !LIGHT_WIN0
    ; one DMA: tile rows t0 .. t0 + k - 1 of light_pub -> VRAM word $1000 + 32 t0 (the window is contiguous, bg1_window.asm)
    JSR Hush_LightPpuV                   ; M = 16
    CMP.w #225 : BCC .done               ; not in vblank any more
    EOR.w #$FFFF : SEC : ADC.w #!LIGHT_NMIEND                     ; lines left = LIGHT_NMIEND - V
    BMI .done : BEQ .done
    ASL A : PHA                          ; tile rows that fit: 2 per line (128 B; DMA moves ~170 B per line)
    LDA.l !SA1_PUBT : XBA : AND.w #$00FF                          ; n
    CMP $01,S : BCC +
    LDA $01,S
+   STA $01,S                            ; 1,S = k = min(n, fit)
    LDA.l !SA1_PUBT : AND.w #$00FF                                ; t0
    ASL A : ASL A : ASL A : ASL A : ASL A : ADC.w #$1000 : STA.w $2116   ; (C = 0: t0 <= 27)
    ASL A : CLC : ADC.w #(!L_PUB-$2000) : STA.w $4302                     ; 2 (32 t0 + $1000) - $2000 + L_PUB = L_PUB + 64 t0
    LDA $01,S : XBA : LSR A : LSR A : STA.w $4305                         ; 64 k bytes
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    LDA $01,S : XBA : EOR.w #$FFFF : SEC : ADC $01,S              ; k - 256 k: t0 += k, n -= k
    CLC : ADC.l !SA1_PUBT : STA.l !SA1_PUBT
    PLX
    AND.w #$FF00 : BNE .done             ; rows left: the next NMI
else
-   LDA.l !SA1_PUBT : AND.w #$FF00 : BEQ .fin
    JSR .vlate : BCS .done               ; a cell row (2 DMAs, ~1 line) only while it ends inside vblank
    LDA.l !SA1_PUBT : AND.w #$00FF : LSR A : JSR Hush_LightUpRow  ; cell row t0 / 2 (t0, n are even here)
    LDA.l !SA1_PUBT : CLC : ADC.w #$FE02 : STA.l !SA1_PUBT       ; t0 += 2, n -= 2
    BRA -
endif
.fin
    SEP #$20
    LDA.b #$00 : STA.l !SA1_PUBF         ; all uploaded: the SA-1 retires them
.done
    REP #$30
    PLY : PLX
    PLB : PLP
    RTL
if !LIGHT_WIN0 == 0
.vlate                                   ; M = 16 on return: C = 1 when the PPU is at / past line LIGHT_NMIEND or already in the next frame
    JSR Hush_LightPpuV
    CMP.w #225 : BCC +
    CMP.w #!LIGHT_NMIEND
    RTS
+   SEC
    RTS
endif

; -----------------------------------------------------------------------------
; Hush_LightWipe: JSL from the submodule $0F hook ($02931D, transition.asm; it called Hush_Wipe directly before L1). Runs Hush_Wipe, then, once per
; room load, the light palette (Hush_LightPal) so the first fade-in frame already shows the soft shadow. Keeps A, X, Y, P as Hush_Wipe left them.
Hush_LightWipe:
    JSL Hush_Wipe
    PHP
    REP #$30
    PHA : PHX : PHY
    PHB
    PEA !L_DBW : PLB : PLB
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
; Hush_LightWork: JSL from Hush_MeterFrame (end of the Module07 frame), any M/X, keeps P. SA-1 step 4: the SNES part only: the colour-math
; shadows, the palette check / Hush_LightPal (WRAM: the SA-1 cannot write it), then Hush_LightPost stages the worker's inputs and posts
; the frame to the SA-1 (Hush_LightJob / Hush_LightRun run the worker there) and returns at once.
Hush_LightWork:
    PHP : PHB
    SEP #$20 : REP #$10
    PEA !L_DBW : PLB : PLB
    LDA.b $10 : CMP.b #$07 : BNE .out
    LDA.w !L_ON : BEQ .out
    LDA.l $7EC903 : BNE +                ; hush_flash ($7EC903): the caught flash owns the colour-math registers (feedback.asm)
    LDA.b #$02 : STA.b $99               ; CGWSEL: the sub screen is the addend
    LDA.b #$22 : STA.b $9A               ; CGADSUB: add to BG2 and the backdrop
    LDA.b $1D : ORA.b #$01 : STA.b $1D   ; TS: BG1 (the light) on the sub screen
+   REP #$20
    LDA.l $7EC558 : CMP.l Hush_LightRamp+22 : SEP #$20 : BEQ +  ; row 2 colour 12 (the amber core)
    LDA.b #$01 : STA.w !L_PALREQ         ; the palette buffer was reloaded (room load, menu): light colours + soft shadow again
+   LDA.w !L_PALREQ : BEQ +
    JSR Hush_LightPpuV : CMP.w #150 : SEP #$20 : BCS +       ; ~20 lines of work: only early in the frame
    JSR Hush_LightPal
+   JSL Hush_LightPost                   ; bank $03 (M = 8, X = 16; DB kept)
.out
    PLB : PLP
    RTL

; Hush_LightJob (SA-1 step 4): JSL from the SA-1 idle loop (Hush_Sa1Entry, sa1.asm) when the command byte is non-zero: M = X = 16,
; D = $3000, DB = $00; returns the same (P, D, DB kept). Status := 2, the staged inputs (SA1_STAGE, written by Hush_LightPost) -> SA1_IN
; (MVN), the DP inputs -> the worker's direct page SA1_DP ($20-$23 Link y / x, $E2 / $E8 BG2 scroll: Hush_L3Want / Aura / Ink / Sig
; read them as `.b`), command := 0 (the SNES may stage the next frame), D := SA1_DP, one worker frame (Hush_LightRun), status := 1.
Hush_LightJob:
    PHP : PHD : PHB
    PEA $0000 : PLB : PLB                ; DB = $00 (I-RAM)
    SEP #$20
    LDA.b #$02 : STA.w !SA1_STATL&$FFFF
    REP #$30
    LDA.w #!SA1_INLEN-1 : LDX.w #!SA1_STAGE : LDY.w #!SA1_IN
    MVN $00,$00                          ; DB := $00 (already)
    LDA.w !SA1_IN_DP+0 : STA.w !SA1_DP+$20
    LDA.w !SA1_IN_DP+2 : STA.w !SA1_DP+$22
    LDA.w !SA1_IN_DP+4 : STA.w !SA1_DP+$E2
    LDA.w !SA1_IN_DP+6 : STA.w !SA1_DP+$E8
    INC.w !SA1_RUNS
    SEP #$20
    STZ.w !SA1_CMDL&$FFFF                ; taken
    REP #$20
    LDA.w #!SA1_DP : TCD
    SEP #$20
    JSR Hush_LightRun
.done
    SEP #$20
    LDA.b #$01 : STA.l !SA1_STATL
    PLB : PLD : PLP
    RTL

; Hush_LightRun (SA-1 step 4; the worker part of the old Hush_LightWork): JSR from Hush_LightJob, M = 8, X = 16, D = SA1_DP; sets DB.
; No PPU V counter on the SA-1: Hush_LightV is the mailbox (0 until the SNES posts the next frame, then $FF), so the units run until the
; work is done or the next frame is posted; L_V0 = 0. light_done := 0 first, so it never stays 1 from the last run while this one
; changes the light (it is 1 only between a complete run and the next).
Hush_LightRun:
    PEA !L_DBW : PLB : PLB
    STZ.w !L_RDONE
    LDA.w !L_ON : BEQ .out
    LDA.l !L3B+!L3_OK : CMP.b #$35 : BNE .out                  ; no room loaded since this power-on (BW-RAM keeps a stale light_on; the
                                                                ; SA-1 zeroes light_l3ok at its start, Hush_LightInit sets it, $4C35)
    LDA.l !L3B+!L3_AFRESH : BEQ +        ; E rev5: first light frame after a room load: amber RAM := 0, no amber pass
    JSL Hush_L3AZero
+   JSR Hush_LightPub                    ; step 5a: retire / publish (the NMI may have taken the last publication)
    JSR Hush_L3Want                      ; L3: wanted displacement per carrier
    STZ.w !L_RIDLE                       ; C2: the idle job scan may run again this frame
    JSR Hush_LightV : STA.w !L_V0
    CMP.w #!LIGHT_VMAX : BCS .exit       ; already posted again: everything waits
    SEP #$20
    JSR Hush_LightInk
    REP #$20 : LDA.w !L_V0 : CMP.w #(!LIGHT_VMAX-!L3_AGATE) : SEP #$20 : BCS +   ; the glow cell update (D4: one step, ring off + on + lattice)
    JSR Hush_LightAura
+   JSR Hush_L3GSlice                    ; D4: the glow region (step 4: to its end unless the next frame is posted), before the guard jobs
    JSR Hush_LightV
    CMP.w #!LIGHT_VMAX : BCS .exit
    CLC : ADC.w #(!LIGHT_JOBQ-1)*!LIGHT_VMAX : LSR A : LSR A : STA.w !L_VJOB   ; D3: job units first until V >= (V + 3 VMAX) / 4 (step 4: always)
.unit
    SEP #$20
    JSR Hush_L3Unit : BCC .exit          ; B2d: guard job unit and region row alternately
    JSR Hush_LightPub                    ; step 5a: new rows go out as soon as the NMI has taken the last ones
    JSR Hush_LightV
    CMP.w !L_V0 : BCC .exit              ; wrapped into the next frame
    CMP.w #!LIGHT_VMAX : BCC .unit
.exit
    JSR Hush_LightPub                    ; step 5a (M = 8 on return)
    JSR Hush_L3Done                      ; light_done
.out
    RTS

; (Hush_LightV moved to the data row in C2, after Hush_L3Done: the code row is full.)

Hush_LightPal:                           ; M = 8, X = 16. Light colours (BG row 2, colours 1-15: Hush_LightRamp) + the soft shadow: room rows 3-7 dimmed
    STZ.w !L_PALREQ
    REP #$20
    LDX.w #$0000
-   LDA.l Hush_LightRamp,X
    STA.l $7EC542,X : STA.l $7EC342,X    ; $7EC500 / $7EC300 + row 2 * 32 + colour 1 * 2
    INX : INX : CPX.w #30 : BCC -
    LDA.l $7EC900 : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX
    LDA.l Hush_RoomTable+19,X : LSR A    ; bit 0: lit room
    LDA.w #Hush_DimDark : BCC +
    LDA.w #Hush_DimLit
+   STA.b $04
    LDA.w #(Hush_DimDark>>16) : STA.b $06
    LDX.w #(3*32+2)                      ; rows 3..7, colours 1..15 (the room tiles; rows 0-1 are the HUD, row 2 the light)
.col
    LDA.l $7EC500,X : STA.b $00
    AND.w #$001F : TAY
    LDA.b [$04],Y : AND.w #$001F : STA.b $02
    LDA.b $00 : LSR A : LSR A : LSR A : LSR A : LSR A : AND.w #$001F : TAY
    LDA.b [$04],Y : AND.w #$001F : ASL A : ASL A : ASL A : ASL A : ASL A : TSB.b $02
    LDA.b $00 : XBA : LSR A : LSR A : AND.w #$001F : TAY
    LDA.b [$04],Y : AND.w #$001F : XBA : ASL A : ASL A : TSB.b $02
    LDA.b $02 : STA.l $7EC500,X : STA.l $7EC300,X
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
    LDA.l !SA1_IN_INK+4 : BEQ .have      ; hush_ink_t (SA-1 step 4: the staged copy of $7EC90C / $7EC908 / $7EC90A)
    LDA.l !SA1_IN_INK : SEC : SBC.b $E2 : CMP.w #$0100 : BCS .have
    LSR A : LSR A : LSR A : LSR A : STA.b $00
    LDA.l !SA1_IN_INK+2 : SEC : SBC.b $E8 : CMP.w #$00E0 : BCS .have
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
    LDA.w !L_LCELL : STA.l !L3B+!L3_CELL+8                ; its lattice cell
    JMP Hush_L3Want                      ; D4: d against the new cell in this frame (RTS there)
.none
    SEP #$20
    LDA.b #$FF : STA.l !L3B+!L3_CELL+8                    ; no glow
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
    LDA.l !SA1_IN_SPR+$0DD0,X : CMP.b #$09 : BNE .none     ; SA-1 step 4: the sprite arrays are the staged copy (I-RAM, !SA1_IN_SPR)
    LDA.l !SA1_IN_SPR+$0E20,X : CMP.b #$41 : BNE .none
    LDA.l !SA1_IN_SPR+$0D80,X : CMP.b #$03 : BCS .none     ; asleep (3) or anything else: no light
    INC A : STA.b $08
    LDA.l !SA1_IN_SPR+$0D30,X : XBA : LDA.l !SA1_IN_SPR+$0D10,X
    REP #$20
    CLC : ADC.w #8 : SEC : SBC.b $E2 : CMP.w #$0100 : BCS .none16
    LSR A : LSR A : LSR A : LSR A : STA.b $00
    SEP #$20
    LDA.l !SA1_IN_SPR+$0D20,X : XBA : LDA.l !SA1_IN_SPR+$0D00,X
    REP #$20
    CLC : ADC.w #8 : SEC : SBC.b $E8 : CMP.w #$00E0 : BCS .none16
    AND.w #$00F0 : ASL A : CLC : ADC.b $00 : CLC : ADC.w #(8*32+8) : STA.w !L_TSIG+2
    SEP #$20
    LDA.b $08 : STA.w !L_TSIG
    CMP.b #$01 : BNE .none
    LDA.l !SA1_IN_SPR+$0DE0,X : AND.b #$03 : STA.w !L_TSIG+1
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
    LDA.l !L3B+!L3_ADB : INC A : BNE .none   ; D3: no new job while amber tiles are pending (a job's tiles reach VRAM before the next commit)
    JSR Hush_LightLate : BCS .ret        ; out of time: the round robin goes on from L_RR next frame
    LDA.b #$08 : STA.b $0A
    LDA.w !L_RR : AND.b #$07 : STA.b $0B
.pick
    REP #$20 : LDA.b $0B : AND.w #$0007 : TAX : ASL A : ASL A : TAY : SEP #$20   ; X = slot, Y = 4 * slot
    LDA.l !SA1_IN_SPR+$0DD0,X : CMP.b #$09 : BEQ .sig
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
    LDA.l !SA1_IN_ROOM : AND.w #$00FF : ASL A : ASL A : ASL A : ASL A : ASL A : TAX   ; hush_room (staged, SA-1 step 4) -> ROOM TABLE record (not hush_range: Hush_Tick
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
    LDA.b #$00 : XBA                     ; B := 0 for the TAY below (X = 16). SA-1 step 4: was TDC (D = $0000 on the SNES; the SA-1's
                                         ; worker D is $3100)
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
.cell
    LDA.w !L_SCR,X : CMP.b ($0C),Y : BNE .chg
.next
    INX : INY
    DEC.b $02 : BNE .cell
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
    STA.w !L_COMP,Y                      ; (E rev5: the logic map only; amber is drawn from the guard lattices, Hush_L3GLat at .end)
    BRA .next
.end
    REP #$20
    LDA.w !L_JOB : AND.w #$0007 : ASL A : ASL A : TAX
    LDA.w !L_JSIG : STA.w !L_SIGC,X
    LDA.w !L_JSIG+2 : STA.w !L_SIGC+2,X
    SEP #$20
    JSL Hush_L3GLat                      ; E rev5: the slot's lattice l_g from the new map, its bbox / cell, carrier marked (bank $03)
    JSR Hush_LightIdle                   ; the job ends here
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
    JSL Hush_L3AStep : BCS .y            ; E rev5: the amber pass (guard lattices displaced, composited), one row per unit
    JSR Hush_L3TPass : BCS .y
.jb JSR Hush_LightStep : BCS .y
.rot
    LDA.l !L3B+!L3_RTURN : INC A : CMP.b #3 : BCC +
    LDA.b #0
+   STA.l !L3B+!L3_RTURN
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
    LDA.l !L3B+!L3_ADB : CMP.b #$FF : BEQ .fin
    STA.b $09
    LDA.b $09
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
    PEA !L3_DBW : PLB : PLB
    REP #$30
    LDA.b $09 : JSL Hush_L3TRow          ; (masks ty itself)
    SEP #$20
    PLB : PLA
    INC.b $0F
    CMP.b #$01 : BNE .fin                ; row not done: it stays first, the unit ends
.adv
    INC.b $0F
    LDA.l !L3B+!L3_ADB : INC A : CMP.l !L3B+!L3_ADB+1 : BEQ + : BCS .empty
+   STA.l !L3B+!L3_ADB
    JMP .top
.empty
    LDA.b #$FF : STA.l !L3B+!L3_ADB
    LDA.b #$00 : STA.l !L3B+!L3_ADB+1
    BRA .fin

; Hush_L3Done (D2: moved here from the data row): JSR from Hush_LightWork's exit (any M, X = 16, DB = $7E; returns M = 8). light_done
; ($7EE7F6) := 1 when no region runs, no amber tile row (light_l3adb) is pending, no carrier is marked (L3_RDM = 0) or has
; WDX / WDY != RDX / RDY (E rev5: all 9 carriers), no amber pass runs (light_l3ast +0 = 0), no guard job runs (L_JOB = $FF) and
; light_dirty = 0; else 0.
Hush_L3Done:
    SEP #$20
    STZ.w !L_RDONE
    LDA.l !L3B+!L3_RC : BPL .no
    LDA.l !L3B+!L3_ADB : INC A : BNE .no
    LDA.l !L3B+!L3_APASS : BNE .no
    LDA.w !L_JOB : BPL .no
    REP #$20
    LDA.l !L3B+!L3_RDM : ORA.w !L_DIRTY
    SEP #$20 : BNE .no
    LDX.w #$0008
-   LDA.l !L3B+!L3_WDX,X : CMP.l !L3B+!L3_RDX,X : BNE .no
    LDA.l !L3B+!L3_WDY,X : CMP.l !L3B+!L3_RDY,X : BNE .no
    DEX : BPL -
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
    SEP #$10                             ; X = 8 (M = 16 for the time compare)
    LDA.l !SA1_CMDL : AND.w #$00FF       ; the worker's time (SA-1 step 4, as Hush_LightV; was the PPU V counter)
    CMP.l !LB+!L_V0 : BCC .stop      ; wrapped into the next frame
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
    AND.w #$00FF
    PHA                                  ; ty
    XBA : LSR A : LSR A                  ; 64 ty
    PHA
    CLC : ADC.w #!L_TILES                ; light_tiles row ty (bank $40)
    STA.w (Hush_L3Tile_C+1)&$FFFF : STA.w (Hush_L3Tile_S+1)&$FFFF
    LDA $01,S : CLC : ADC.w #!L3_QH : STA.w (Hush_L3Tile_A+1)&$FFFF       ; E rev5: QH row ty
    PLA : CLC : ADC.w #!L3_QL+64 : STA.w (Hush_L3Tile_B+1)&$FFFF          ; QL row ty + 1
    LDA $01,S : INC A : ASL A : ASL A : STA.b $0C                        ; 4 (ty + 1)
    ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0C : ADC.w #!L3_IV+2     ; IV of tile (0, ty): IV + 68 (ty + 1) + 2
    STA.w (Hush_L3Tile_IV+1)&$FFFF
    LDA.b $0B : AND.w #$00FF : INC A : ASL A                             ; end = 2 (hi + 1)
    STA.w (Hush_L3Tile_E+1)&$FFFF
    LDA.w #Hush_LightLutV : STA.b $06
    SEP #$20 : LDA.b #Hush_LightLutV>>16 : STA.b $08 : REP #$20
    STZ.b $0C                            ; changed
    LDA.b $0A : AND.w #$00FF : ASL A : TAX                               ; X = 2 lo
    LDA.w #(Hush_L3Tile-1)&$FFFF
    PHK : PER .r-1                       ; RTL into bank $41 (= DB) at the loop; it RTLs back to .r
    PHB : PHA
    RTL
.r                                       ; M = X = 16
    PLA                                  ; ty
    LDX.b $0C : BEQ +
    AND.w #$00FE : TAX                   ; 2 (ty >> 1)
    LDA.l Hush_L3Bit,X : ORA.l !LB+!L_DIRTY : STA.l !LB+!L_DIRTY
    LDA.l Hush_L3Bit,X : ORA.l !LB+!L_WD : STA.l !LB+!L_WD          ; step 5a: changed since its copy to light_pub (Hush_LightPub)
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
    PEA !L3_DBW : PLB : PLB
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
    REP #$20
    LDA.l !SA1_CMDL : AND.w #$00FF       ; the worker's time (SA-1 step 4, as Hush_LightV; was the PPU V counter, bank_00.asm:15152)
    CMP.l !LB+!L_V0 : BCC +
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

; =============================================================================
; SA-1 step 4: src/FREESPACE.md row $03EB05-$03EB7F (head of NULL_03EB05, bank_03.asm:4559-4581: all $FF in the vanilla listing, no
; reference in vendor/usdasm; the code / data rows of bank $1F are full).
org $03EB05
; Hush_LightPost: JSL from Hush_LightWork (SNES, end of the Module07 frame), M = 8, X = 16, any DB (kept; P kept). Stages the inputs the
; SA-1 worker reads (it cannot read WRAM) and posts the frame: only when the command byte is 0 (the SA-1 has taken the previous frame;
; else the staged inputs stay and SA1_SKIP counts the frame). SA1_STAGE (I-RAM, docs/ram_map.md "SA-1 memory"): +$000 = WRAM
; $7E0D00-$7E0E2F (the sprite arrays Hush_LightSig / Step read for slots 0-7: $0D00 / $0D10 / $0D20 / $0D30 y / x, $0D80 awareness, $0DD0
; state, $0DE0 facing, $0E20 type; 304 B by DMA channel 5 B -> A from WMDATA, ~2 lines), +$130 hush_room ($7EC900), +$132 ink x / y /
; timer ($7EC908-$7EC90D), +$138 DP $20 / $22 (Link y / x), $E2 / $E8 (BG2 scroll). Then command := $FF. DMA channel 5 and WMADD /
; WMDATA are used nowhere in vanilla (grep of vendor/usdasm: no DMA5 / $435x / WMADD / WMDATA / $2180-$2183 operand) nor elsewhere in src/.
Hush_LightPost:
    PHB : PHP
    PEA $0000 : PLB : PLB                ; DB = $00: I-RAM, DMA / WRAM registers
    SEP #$20 : REP #$10
    LDA.w !SA1_CMDL&$FFFF : BEQ .stage
    REP #$20
    INC.w !SA1_SKIP
    BRA .out
.stage
    REP #$20
    LDA.w #$0D00 : STA.w $2181           ; WMADDL / WMADDM ($2183 below: bank $7E)
    LDA.w #$8080 : STA.w $4350           ; DMAP5 $80: B -> A, one register, A address increments; BBAD5 $80: WMDATA
    LDA.w #!SA1_STAGE : STA.w $4352
    LDA.w #$0130 : STA.w $4355
    LDA.l $7EC900 : STA.w !SA1_STAGE+$130
    LDA.l $7EC908 : STA.w !SA1_STAGE+$132
    LDA.l $7EC90A : STA.w !SA1_STAGE+$134
    LDA.l $7EC90C : STA.w !SA1_STAGE+$136
    LDA.b $20 : STA.w !SA1_STAGE+$138
    LDA.b $22 : STA.w !SA1_STAGE+$13A
    LDA.b $E2 : STA.w !SA1_STAGE+$13C
    LDA.b $E8 : STA.w !SA1_STAGE+$13E
    SEP #$20
    STZ.w $2183                          ; WMADDH: bank $7E
    STZ.w $4354                          ; A bus bank $00
    LDA.b #$20 : STA.w $420B             ; MDMAEN: channel 5
    LDA.b #$FF : STA.w !SA1_CMDL&$FFFF   ; post: the SA-1 stops its units (Hush_LightV), then takes these inputs
.out
    PLP : PLB
    RTL
Hush_LightPost_End:
assert pc() <= $03EB80                   ; src/FREESPACE.md row $03EB05-$03EB7F
assert !SA1_STAGE+!SA1_INLEN <= !SA1_IN
assert !SA1_IN_DP+8 == !SA1_IN+!SA1_INLEN

; =============================================================================
; E rev5 (design/lighting.md revision 5, 4.5 for every carrier; src/dev/L3_REPORT.md "## E rev5"): the amber pass. src/FREESPACE.md row
; $03EBA0-$03F370: vanilla room object data of rooms $0100-$010C (RoomDataTiles_0100 .. _010C, rooms.asm:913-924), read only through
; RoomData_ObjectDataPointers / door pointers of those rooms (rooms.asm:262-274, 586-598); HUSH never loads a vanilla room (FREESPACE.md
; "E1 notes"). Runs on the SA-1 only (JSL from bank $1F).
; Model: each guard slot g has a lattice l_g (L3_GLAT, pair-coded, 4.1 of its committed map alone, Hush_L3GLat at the end of its job), its
; lattice bbox (light_l3car LB*), cell (light_l3car +0) and rendered d (RDX / RDY, the snapshot of WDX / WDY at the last pass that
; included it). A pass: every guard that is marked (its lattice changed) or has WD != RD takes RD := WD; its old drawn box and its new
; displaced box N (the exact support of V_g) add their rows to per-row spans; drawn := N. Then row by row (one row per unit): NEW := max over
; the guards whose drawn box meets the row of V_g (RAM loops Hush_L3GA / PA), compared with the composite amber lattice CA; changed points
; update QH / QL (the tile loop's index words) and mark their tiles (light_tdirty, Hush_L3TPass derives them). Exact: every point of
; every row a dirty guard touched is recomputed from all guards, so CA = max over g of V_g(RD_g) once the pass and its tiles are done.
org $03EBA0

; Hush_L3AZero: JSL from Hush_LightRun (SA-1; any M, X = 16, any DB; returns M = 8, X = 16, DB kept). $41:0000 .. AZEND - 1 (guard
; lattices, CA, QH, QL) := 0 (MVN forward fill), no pass, light_l3afresh := 0. ~16k bytes, ~0.4 frame of SA-1 time, once per room load.
Hush_L3AZero:
    PHB
    REP #$30
    LDA.w #$0000 : STA.l !L3B+!L3_GLAT
    LDA.w #!L3_AZEND-3 : LDX.w #!L3_GLAT : LDY.w #!L3_GLAT+2
    MVN !L3_BANK,!L3_BANK
    SEP #$20
    LDA.b #$00 : STA.l !L3B+!L3_APASS : STA.l !L3B+!L3_AFRESH
    PLB
    RTL

; Hush_L3AStep: JSL from Hush_L3Unit (M = 8, X = 16, any DB; returns M = 8, X = 16, DB kept). C = 1: it did work (a pick or a row).
Hush_L3AStep:
    PHB
    PEA !L3_DBW : PLB : PLB
    LDA.w !L3_APASS : BNE .row
    JSR Hush_L3APick
    BRA .out
.row
    JSR Hush_L3ARow
    SEC
.out
    PLB
    RTL

; Hush_L3APick: JSR from Hush_L3AStep (M = 8, X = 16, DB = $41). WD fresh (Hush_L3WantL); spans := empty; per dirty guard (above): RD := WD,
; drawn box + N -> spans, drawn := N = [LBX0 - 1 + ceil(dx / 8), LBX1 + ceil(dx / 8)] x (same for y), clipped to 0..32 x 0..28 (empty
; without a cell or bbox); loop constants: t = n & 7, e = n >> 3 of n = -dx, s / f of -dy, ABASE = GLAT + 1292 g + 38 (f + 2) + e + 2.
; C = 1: a pass starts (APASS := 1, AJ := 0). Uses $04-$0F, A, X, Y.
Hush_L3APick:
    JSL Hush_L3WantL
    LDX.w #28
-   LDA.b #$FF : STA.w !L3_ASLO,X
    STZ.w !L3_ASHI,X
    DEX : BPL -
    STZ.b $03                            ; a span was added (byte; $0E / $0F take word stores below)
    LDX.w #$0007
.g  LDA.w !L3_RDM : AND.l Hush_L3ABit,X : BNE .d
    LDA.w !L3_WDX,X : CMP.w !L3_RDX,X : BNE .d
    LDA.w !L3_WDY,X : CMP.w !L3_RDY,X : BNE .d
    JMP .next
.d  LDA.l Hush_L3ABit,X : TRB.w !L3_RDM
    LDA.w !L3_WDX,X : STA.w !L3_RDX,X : STA.b $04
    LDA.w !L3_WDY,X : STA.w !L3_RDY,X : STA.b $05
    LDA.w !L3_DBX0,X : STA.b $06 : LDA.w !L3_DBX1,X : STA.b $07   ; the old drawn box
    LDA.w !L3_DBY0,X : STA.b $08 : LDA.w !L3_DBY1,X : STA.b $09
    JSR .span
    LDA.w !L3_CELL,X : CMP.b #$FF : BEQ .ne
    LDA.w !L3_LBY0,X : CMP.w !L3_LBY1,X : BEQ + : BCS .ne
+   LDA.b $04 : CLC : ADC.b #7 : JSR .asr3 : STA.b $0A            ; ceil(dx / 8)
    CLC : ADC.w !L3_LBX1,X : STA.b $07
    LDA.w !L3_LBX0,X : DEC A : CLC : ADC.b $0A : STA.b $06
    LDA.b $05 : CLC : ADC.b #7 : JSR .asr3 : STA.b $0A            ; ceil(dy / 8)
    CLC : ADC.w !L3_LBY1,X : STA.b $09
    LDA.w !L3_LBY0,X : DEC A : CLC : ADC.b $0A : STA.b $08
    LDA.b $06 : BPL +                    ; clip (signed bytes, all within -3..37)
    STZ.b $06
+   LDA.b $08 : BPL +
    STZ.b $08
+   LDA.b $07 : BMI .ne
    CMP.b #33 : BCC +
    LDA.b #32 : STA.b $07
+   LDA.b $09 : BMI .ne
    CMP.b #29 : BCC +
    LDA.b #28 : STA.b $09
+   LDA.b $06 : CMP.b $07 : BEQ + : BCS .ne
+   LDA.b $08 : CMP.b $09 : BEQ .nok : BCC .nok
.ne LDA.b #$01 : STA.b $08
    STZ.b $09 : STZ.b $06 : STZ.b $07
.nok
    LDA.b $06 : STA.w !L3_DBX0,X : LDA.b $07 : STA.w !L3_DBX1,X   ; drawn := N
    LDA.b $08 : STA.w !L3_DBY0,X : LDA.b $09 : STA.w !L3_DBY1,X
    JSR .span
    LDA.b $04 : EOR.b #$FF : INC A : PHA : AND.b #$07 : STA.w !L3_AT,X   ; n = -dx: t
    PLA : JSR .asr3 : STA.b $0A                                       ; e
    LDA.b $05 : EOR.b #$FF : INC A : PHA : AND.b #$07 : STA.w !L3_AS,X   ; n = -dy: s
    PLA : JSR .asr3                                                   ; f
    REP #$20
    JSR .sx : INC A : INC A : STA.b $0C                               ; m = f + 2
    ASL A : STA.b $0E : ASL A : CLC : ADC.b $0E : STA.b $0E           ; 6m
    LDA.b $0C : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0E : STA.b $0E   ; 38m
    LDA.b $0A : JSR .sx : CLC : ADC.b $0E : STA.b $0E                 ; + e
    PHX
    TXA : ASL A : TAX
    LDA.l Hush_L3AOff,X : CLC : ADC.b $0E : ADC.w #2 : STA.w !L3_ABASE,X   ; + GLAT + 1292 g + 2
    PLX
    SEP #$20
.next
    DEX : BMI +
    JMP .g
+   LDA.b $03 : BEQ +
    LDA.b #$01 : STA.w !L3_APASS
    STZ.w !L3_AJ
    SEC
    RTS
+   CLC
    RTS
.span                                    ; rect $06 x0, $07 x1, $08 y0, $09 y1 (y0 > y1: empty) -> per-row spans; $03 := non-zero. Keeps X.
    LDA.b $08 : CMP.b $09 : BEQ + : BCC +
    RTS
+   PHX
    REP #$20 : LDA.b $08 : AND.w #$00FF : TAX : SEP #$20
-   LDA.b $06 : CMP.w !L3_ASLO,X : BCS +
    STA.w !L3_ASLO,X
+   LDA.b $07 : CMP.w !L3_ASHI,X : BCC +
    STA.w !L3_ASHI,X
+   INX : TXA : CMP.b $09 : BEQ - : BCC -
    PLX
    INC.b $03
    RTS
.asr3                                    ; M = 8: A (signed byte) >> 3
    CMP.b #$80 : ROR A
    CMP.b #$80 : ROR A
    CMP.b #$80 : ROR A
    RTS
.sx                                      ; M = 16: A (low byte, signed) -> sign-extended word
    AND.w #$00FF : EOR.w #$0080 : SEC : SBC.w #$0080
    RTS

; Hush_L3ARow: JSR from Hush_L3AStep (M = 8, X = 16, DB = $41). The next row j >= AJ with a span [lo, hi] (none: the pass ends, APASS := 0):
; NEW[lo..hi] := 0; for every guard whose drawn box meets row j and [lo, hi]: NEW := max(NEW, V_g) over the overlap (RAM loop, operands
; from ABASE / AT / AS and the row); then Hush_L3ACommit. DP $00 lo, $01 hi, $02-$03 j, $04 / $05 overlap i0 / i1, $08 LERP_t row,
; $0A / $0B t / s, $0C 38 j, $0E P0 operand.
Hush_L3ARow:
    LDA.w !L3_AJ
-   CMP.b #29 : BCS .end
    REP #$20 : AND.w #$00FF : TAX : SEP #$20
    LDA.w !L3_ASLO,X : CMP.w !L3_ASHI,X : BEQ .go : BCC .go
    INX : TXA : BRA -
.end
    STZ.w !L3_APASS
    RTS
.go
    STX.b $02                            ; j (word)
    STA.b $00                            ; lo
    LDA.w !L3_ASHI,X : STA.b $01         ; hi
    LDA.b #$FF : STA.w !L3_ASLO,X        ; consumed
    STZ.w !L3_ASHI,X
    TXA : INC A : STA.w !L3_AJ
    REP #$20 : LDA.b $00 : AND.w #$00FF : TAX : SEP #$20
-   STZ.w !L3_NEW,X
    INX : TXA : CMP.b $01 : BEQ - : BCC -
    REP #$20
    LDA.b $02 : ASL A : STA.b $0C : ASL A : CLC : ADC.b $0C : STA.b $0C   ; 6j
    LDA.b $02 : ASL A : ASL A : ASL A : ASL A : ASL A : CLC : ADC.b $0C : STA.b $0C   ; 38j
    SEP #$20
    LDX.w #$0007
.g  LDA.w !L3_DBY0,X : CMP.b $02 : BEQ + : BCS .gn                 ; box below the row (or empty: DBY0 = 1 > DBY1 = 0)
+   LDA.w !L3_DBY1,X : CMP.b $02 : BCC .gn                        ; above
    LDA.w !L3_DBX0,X : CMP.b $00 : BCS +
    LDA.b $00
+   STA.b $04                            ; i0 = max(lo, x0)
    LDA.w !L3_DBX1,X : CMP.b $01 : BCC +
    LDA.b $01
+   STA.b $05                            ; i1 = min(hi, x1)
    CMP.b $04 : BCC .gn
    JSR .call
.gn DEX : BPL .g
    JMP Hush_L3ACommit
.call                                    ; X = guard g: the RAM loop over i0 .. i1 of row j
    PHX
    REP #$20
    TXA : ASL A : TAY
    LDA.w !L3_ABASE,Y : CLC : ADC.b $0C : STA.b $0E                ; P0 = P(i0 + e, j + f) - i0
    SEP #$20
    LDA.w !L3_AT,X : STA.b $0A
    LDA.w !L3_AS,X : STA.b $0B
    REP #$20
    LDA.b $0A : AND.w #$0007 : XBA : LSR A : LSR A : CLC : ADC.w #!L3_LERP : STA.b $08   ; LERP_t row
    LDA.b $0B : AND.w #$0007 : BEQ .p
    XBA : LSR A : LSR A : CLC : ADC.w #!L3_LERP : STA.w (Hush_L3GA_LS+1)&$FFFF         ; LERP_s row
    LDA.b $08 : STA.w (Hush_L3GA_LT+1)&$FFFF
    CLC : ADC.w #!L3_LERP8-!L3_LERP : STA.w (Hush_L3GA_L8+1)&$FFFF
    LDA.b $0E : STA.w (Hush_L3GA_P0+1)&$FFFF
    CLC : ADC.w #38 : STA.w (Hush_L3GA_P1+1)&$FFFF
    SEP #$20 : LDA.b $05 : INC A : STA.w (Hush_L3GA_E+1)&$FFFF : REP #$20
    LDA.w #(Hush_L3GA-1)&$FFFF
    BRA .jmp
.p  LDA.b $08 : STA.w (Hush_L3PA_LT+1)&$FFFF
    LDA.b $0E : STA.w (Hush_L3PA_P0+1)&$FFFF
    SEP #$20 : LDA.b $05 : INC A : STA.w (Hush_L3PA_E+1)&$FFFF : REP #$20
    LDA.w #(Hush_L3PA-1)&$FFFF
.jmp                                     ; M = 16: RTL into bank $41 (= DB) at the loop with X = i0, M = X = 8; it RTLs back to .r
    PHK : PER .r-1
    PHB : PHA
    SEP #$30
    LDX.b $04
    RTL
.r  REP #$10
    PLX
    RTS

; Hush_L3ACommit: JMP from Hush_L3ARow (M = 8, X = 16, DB = $41; $00 lo, $01 hi, $02 j, $0C 38 j). CA(lo..hi, j) := NEW where it differs;
; changed span [cmin, cmax] -> QH / QL (i = max(cmin - 1, 0) .. min(cmax, 31)) and tile marks (same columns, tile rows j - 1, j within
; 0..27; Hush_L3TMark). Uses $06-$0F, A, X, Y.
Hush_L3ACommit:
    REP #$20
    LDA.b $0C : CLC : ADC.w #!L3_CA+78 : STA.b $06                 ; CA(0, j) = CA + 38 (j + 2) + 2
    LDA.b $00 : AND.w #$00FF : TAY
    SEP #$20
    LDA.b #$FF : STA.b $08               ; cmin: none
.c  LDA.w !L3_NEW,Y : CMP.b ($06),Y : BEQ .cn
    STA.b ($06),Y
    TYA : STA.b $09                      ; cmax
    LDA.b $08 : BPL .cn
    TYA : STA.b $08                      ; cmin
.cn INY : TYA : CMP.b $01 : BEQ .c : BCC .c
    LDA.b $08 : BPL +
    RTS                                  ; nothing changed
+   BEQ +
    DEC A
+   STA.b $0A                            ; first column max(cmin - 1, 0)
    LDA.b $09 : CMP.b #32 : BCC +
    LDA.b #31
+   STA.b $0B                            ; last column min(cmax, 31)
    REP #$20
    LDA.b $02 : AND.w #$00FF : XBA : LSR A : LSR A : STA.b $0E      ; 64 j
    LDA.b $0A : AND.w #$00FF : TAY
    SEP #$20
.q  LDA.b ($06),Y : STA.b $0D
    ASL A : ASL A : ASL A : SEC : SBC.b $0D                        ; 7 A(i, j)
    INY : CLC : ADC.b ($06),Y : DEY                                 ; + A(i + 1, j)
    REP #$20
    AND.w #$00FF : ASL A : STA.b $0C                                ; 2q
    TYA : ASL A : CLC : ADC.b $0E : TAX                             ; 64 j + 2 i
    LDA.b $0C : STA.w !L3_QL,X
    PHX : TAX : LDA.l Hush_LightM98,X : PLX : STA.w !L3_QH,X        ; 98 q
    SEP #$20
    INY : TYA : CMP.b $0B : BEQ .q : BCC .q
    LDA.b $0A : INC A : STA.b $08        ; tiles lo + 1, hi + 1 (Hush_L3TMark)
    LDA.b $0B : INC A : STA.b $09
    LDA.b $02 : BEQ +
    DEC A : JSL Hush_L3TMark             ; tile row j - 1
+   LDA.b $02 : CMP.b #28 : BCS +
    JSL Hush_L3TMark                     ; tile row j
+   RTS

; Hush_L3GLat: JSL from Hush_LightCommit .end (job end; M = 8, X = 16, any DB; returns M = 8, X = 16, DB kept). Slot g = light_job.
; (1) Lattice rows j = 2 JBY0 - 1 .. 2 JBY1 + 3 of l_g, cell columns JBX0 .. JBX1 + 1 (points P(2 JBX0 - 1) .. P(2 JBX1 + 3)) by Hush_L3Row
; from light_scr (= the new light in box rows JBY0 - 1 .. JBY1 + 1, Hush_LightBox; 0 outside the box): every point the old or the new
; light reaches, + 1 point around (the displaced reads of a pass stay within LB +- 1). (2) LB := the bbox of the non-zero cells of
; GMAP[g] (points 2cx .. 2cx + 2), empty if none. (3) CELL := the job's cell (class 0: $FF). (4) RDM bit g := 1. Uses $00-$0F.
Hush_L3GLat:
    PHB
    PEA !L3_DBW : PLB : PLB
    LDA.l !LB+!L_JBY0 : CMP.l !LB+!L_JBY1 : BEQ + : BCS .box      ; empty box: neither light exists
+   REP #$20
    LDA.l !LB+!L_JOB : AND.w #$0007 : ASL A : TAX
    LDA.l Hush_L3AOff,X : STA.b $0E      ; lattice base
    LDA.w #!L_SCR : STA.b $08
    SEP #$20
    LDA.b #!L_BANK : STA.b $0A
    LDA.l !LB+!L_JBX0 : INC A : INC A : STA.b $0B                  ; k0 + 2
    LDA.l !LB+!L_JBY1 : ASL A : CLC : ADC.b #5 : STA.b $0C         ; last c = 2 JBY1 + 5 (c = j + 2)
    LDA.l !LB+!L_JBY0 : ASL A : INC A                              ; first c = 2 JBY0 + 1
.r  PHA
    LDA.l !LB+!L_JBX1 : SEC : SBC.l !LB+!L_JBX0 : INC A : INC A : STA.b $0D   ; n
    LDA $01,S
    REP #$30
    AND.w #$00FF : DEC A : DEC A         ; j
    LDX.b $0E
    JSL Hush_L3RowL                      ; M = 8 on return (X = 16)
    PLA : INC A : CMP.b $0C : BEQ .r : BCC .r
.box
    REP #$20
    LDA.l !LB+!L_JOB : AND.w #$0007 : STA.b $04
    ASL A : ASL A : ASL A : ASL A : ASL A : STA.b $06
    LDA.b $04 : XBA : SEC : SBC.b $06 : TAX                        ; 224 g
    SEP #$20
    LDA.b #$FF : STA.b $00 : STA.b $02   ; min cx, min cy
    STZ.b $01 : STZ.b $03 : STZ.b $05    ; max cx, max cy, found
    LDY.w #$0000
.s  LDA.l !LB+!L_GMAP,X : BEQ .sn
    INC.b $05
    TYA : AND.b #$0F : CMP.b $00 : BCS +
    STA.b $00
+   CMP.b $01 : BCC +
    STA.b $01
+   TYA : LSR A : LSR A : LSR A : LSR A : CMP.b $02 : BCS +
    STA.b $02
+   CMP.b $03 : BCC .sn
    STA.b $03
.sn INX : INY : CPY.w #224 : BCC .s
    REP #$20 : LDA.l !LB+!L_JOB : AND.w #$0007 : TAX : SEP #$20
    LDA.b $05 : BEQ .em
    LDA.b $00 : ASL A : STA.w !L3_LBX0,X
    LDA.b $01 : ASL A : INC A : INC A : STA.w !L3_LBX1,X
    LDA.b $02 : ASL A : STA.w !L3_LBY0,X
    LDA.b $03 : ASL A : INC A : INC A : STA.w !L3_LBY1,X
    BRA .cl
.em LDA.b #$01 : STA.w !L3_LBY0,X    ; empty: LBY0 = 1 > LBY1 = 0
    STZ.w !L3_LBY1,X
.cl LDA.l !LB+!L_JSIG : BEQ .nc      ; class 0: no light, no lattice cell
    REP #$20
    LDA.l !LB+!L_JSIG+2 : SEC : SBC.w #(8*32+8) : STA.b $06        ; 32 cy + cx
    AND.w #$001F : STA.b $04
    LDA.b $06 : LSR A : AND.w #$00F0 : ORA.b $04                    ; i = 16 cy + cx
    SEP #$20
    BRA .sc
.nc LDA.b #$FF
.sc STA.w !L3_CELL,X
    LDA.l Hush_L3ABit,X : TSB.w !L3_RDM
    PLB
    RTL

Hush_L3AOff:                             ; [2g] guard lattice base
    dw !L3_GLAT+(0*!L3_LATSZ), !L3_GLAT+(1*!L3_LATSZ), !L3_GLAT+(2*!L3_LATSZ), !L3_GLAT+(3*!L3_LATSZ)
    dw !L3_GLAT+(4*!L3_LATSZ), !L3_GLAT+(5*!L3_LATSZ), !L3_GLAT+(6*!L3_LATSZ), !L3_GLAT+(7*!L3_LATSZ)
Hush_L3ABit:                             ; [g] 1 << g
    db $01, $02, $04, $08, $10, $20, $40, $80
Hush_L3Amber_End:
assert pc() <= $03F371                   ; src/FREESPACE.md row $03EBA0-$03F370
assert !L3_GLAT+(8*!L3_LATSZ) <= !L3_CA
assert !L3_CA+!L3_LATSZ <= !L3_QH
assert !L3_QL+(29*64) <= !L3_AZEND
assert !L3_AZEND <= !L3_AST
