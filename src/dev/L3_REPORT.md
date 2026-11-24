# L3 glued light: engine report (running)

Task: design/lighting.md rev 3, section 4.5 + section 5 contract, in `src/hooks/light.asm`.

## Status log
- step 0: spec + code read. Baseline `make build`: ok (Hush_Light_End $1FC3BC, Hush_LightGfx_End $1FFB67).
- step 1: design fixed (below). Next: code.
- A1: RAM layout defined (`!L3_*`, "Step A1 RAM map" below, ram_map rows); no code. `make build` ok.
- A2: `Hush_L3Tables` (data row, after Hush_LightGrids) builds LERP ($7FC200, t,a,b = 0..7) and PH/PL/PHV/PLV ($7FC400-$7FC5FF) once,
  guarded by L3_OK = $4C33, called from Hush_LightGrids after the LUTF check. Writes only $7FC200-$7FC5FF + L3_OK. `make build` ok.
- A3: `Hush_L3Want` (data row), JSR at the top of Hush_LightWork (before L_V0): WDX/WDY[c] = centre - (16cx+8, 16cy+8), clamp +-16,
  D = 1. Guards: origin + 8 (as Hush_LightSig), cell from L_SIGC p (class 0/$FF -> 0). Glow (c = 8): (x+8, y+16) (as Hush_LightAura),
  cell from L_LCELL ($FFFF -> 0). Not read by anything yet. Code row +3 B (JSR). FREESPACE row text updated.
  `make build`: `freespace: ... 315733 changed byte(s) diffed: ok` / `built build/hush.sfc`.
  `make test`: `PASS=39 FAIL=0 TIMEOUT=0 SKIP=2` (savestate skips), solutions 21/21, lagged frames 0, gfx 4/4, leakcheck CLEAN.
  Next: A4 (lattice build).
- B1 (in progress): L2 removed (pair grids, LUTF / LUTFV build, Hush_LightAmb / Vio / MarkRow / MarkBlock / Render, M98 / ColMask /
  multiplier tables, LP_* defines); light_tiles / NMI upload kept (B2), so BG1 shows no light. Hush_LightZeroGrids now takes A = address,
  X = length: room load zeroes the 9 lattices + light_pvio, CELL := $FF, bbox empty. Hush_L3Row (one lattice row, 33 points, from two
  padded source rows), Hush_L3Lat = job phase 3 (commit `.end` -> JPH 3, rows 2JBY0 .. 2JBY1 + 2, one per unit; then CELL / LB* / idle),
  box clear widened to cell rows JBY0 - 1 .. JBY1 + 1. Glow: Hush_L3PVio replaces the Hush_LightVio calls (light_pvio copy), Hush_L3Glow
  rebuilds rows 2cy - 2 .. 2cy + 4 of lattice 8 in both Aura halves (CELL[8] $FF in between). Hush_L3Want reads L3_CELL. Commit no longer
  stops mid-row (a changed cell is cheap now). `make build`: ok (314436 changed bytes diffed: ok).
  First `make test`: 7 solutions failed (r11 r14 r15 r17 r19 r20 final) from lag frames: a 33-point lattice row costs ~7 scanlines
  (~0.37 line per cell column) and the glow rebuilt 7 full rows (~45 lines). Fixes: Hush_L3Row takes a column range ($0B = k0 + 2,
  $0D = count): guards build only the job box columns, the glow only cx - 1 .. cx + 2; phase-3 rows start only before LIGHT_VMAX - 10;
  the glow half only before LIGHT_VMAX - 24 (was -14); the commit's mid-row time stop restored.
- B1 done. `make build`: `314518 changed byte(s) diffed: ok`, `built build/hush.sfc`. Space: code row ends `$1FC0F0` (784 B left, was 68),
  data row ends `$1FFAD9` (1319 B left, was 1176). `make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`; FAIL = smoke_lighting (expected: no
  renderer, BG1 empty); solutions 21/21, meter budget 21/21, must_not all pass, smoke_boot pass, smoke_hud pass (it failed once in the
  first run, passed in the final run). nmi_probe (room 20 walk): logic end max 218, 0 lag.
  Open: solutions `final` shows `lagged frames 1` (A3: 0). Not the glow (same with the glow gate at LIGHT_VMAX - 60) and identical with the
  phase-3 gate at -8 / -10; source not located yet. To check in B2 with a lag probe on the final replay.
  Not verified in-emulator yet: lattice contents (no test reads them; B2's renderer / qa's oracle will).
  Next: B2 (renderer from the lattices).
- B2a: `Hush_L3Compose` (data row, $1FFAD9-$1FFD27, 591 B; not called yet). A = kind (0 amber c 0-7, else violet c 8), DP $00 i0,
  $01 i1, $02 j; NEW[i0..i1] := max V_c (4.5 item 3). Uses WDX/WDY directly (no render snapshot yet; RDX/RDY left to the region step).
  Per carrier t, e, s, f are constant over the row (X = 8i - dx -> i + (-dx >> 3), t = -dx & 7): MVN of source rows j0 (and j0+1 if s > 0)
  into S, then (pT),Y / (pS),Y LERP lookups (B = 0 so TAY moves a*8+b). Columns clipped to the lattice bbox shifted by e; rows skipped
  unless j0 <= LBY1 and j0+1 >= LBY0. Glow has no LB*: bbox from CELL[8] = Hush_L3Glow's range. Fast paths s = 0, s = t = 0.
  Estimated (not measured) cycles/point incl. MVN: general ~103 (~0.6 scanline), s = 0 ~52, d = 0 ~33; set-up ~260 per carrier.
  `make build`: `315106 changed byte(s) diffed: ok`, `built build/hush.sfc`. Data row: 728 B left. `make test` not run (step rule).
- B2b: compose reworked to ~34 cycles/point (B2a ~103). (1) Lattices pair-coded in place: `P = 8 l(i) + l(i+1)` (l is read nowhere
  else). Hush_L3Row writes P(2k0 - 1) .. P(2(k0 + n) - 1) (the edge pairs recomputed from the source), DB = source bank, (dp),Y;
  93 cycles/column (was ~70), so the phase-3 gate moved LIGHT_VMAX - 10 -> -12 (row <= ~9.5 lines). (2) LERP8 = 8 LERP at $7FC800
  (512 B, built in Hush_L3Tables). (3) Loop = RAM code at $7FCA00 (90 B, copied from Hush_L3Code once): 8-bit A / X / Y, X = i,
  absolute operands patched per carrier row (source rows, table rows, end), x2 unrolled, odd n enters copy 2, max by CMP / BCC.
  No 8-bit-index layout without self-modifying code: three moving bases (source, tables, NEW) vs two index registers.
  `V = LERP_s[LERP8_t[P0] | LERP_t[P1]]` (`LDY P0,X / LDA L8,Y / LDY P1,X / ORA LT,Y / TAY / LDA LS,Y`; ORA = add since H1 <= 7, no CLC).
  Cycles/point (65816 table timings): general 31 (V < NEW) / 35 (store) + 2.5 loop = 33.5 / 37.5, +1 per page-crossing source row
  (max +2); s = 0: 17 / 21 + 2.5. t = s = 0 uses the s = 0 loop (LERP_0[P] = l; a plain copy no longer exists with P coding).
  Set-up ~330 cycles per carrier row. L3_S ($7FC640) freed. Data row ends `$1FFDB7` (584 B left).
  `make build`: `315252 changed byte(s) diffed: ok`, `built build/hush.sfc`. `make test` not run (step rule): the L3Row change is live
  (phase 3 + glow), so B2c's test run must check the lag / latency numbers.
- B2c: `Hush_L3Commit` (data row, $1FFD5E, 382 B + Hush_L3Bit 28 B; not called yet): NEW[i0..i1] -> CA / CV row j, span [cmin, cmax];
  tiles tx cmin-1..cmax (0..31) x ty j-1..j (0..27) from CA corners (LutA via PH + PL), else CV (LutV via PHV + PLV), else EMPTY; light_tiles
  written only on change + light_dirty bit ty >> 1. `make build`: `315658 changed byte(s) diffed: ok`, data row ends `$1FFF52` (174 B left). `make test` not run.
- B2d: region driver wired in. State in L3_REG (`!L3_R*`; ram_map `light_l3reg`), flag `light_done` $7EE7F6 (ram_map row). Hush_L3Mark sets
  L3_RDM bit c at the end of Hush_L3Lat (guards) and Hush_L3Glow (c 8). Hush_L3Pick: candidates = marked or WD != RD, max |ddx|+|ddy|,
  round robin on ties; snapshot RD := WD (Compose now reads RDX / RDY); N = bbox (glow: CELL[8] range) + [floor(d/8) - 1, ceil(d/8) + 1],
  clipped 0..32 x 0..28; region = drawn U N; drawn := N. Hush_L3Unit alternates job unit / region unit (L3_RTURN). Room load: CA / CV
  zeroed (DMA now `$7FB400-$7FC1DF`), Hush_L3RegInit. Hush_L3Done at LightWork's exit.
  Failed first: unit = one full row. `make test` 26/39: every solution failed from lag (game ~60% speed). Probe (src/dev/row_probe.lua,
  final room walk): compose up to 23 lines, commit up to ~40 (+ NMI wrap); cap 1 row/frame still 30 lag of 180 frames.
  Fix (deviation from "unit = one row", reported): unit = row segment of <= L3_RCOLS = 4 columns (L3_RIC cursor), started only
  before LIGHT_VMAX - L3_RGATE (36), at most L3_ROWCAP units per frame. Cap 6 / gate 24: final 5 lag; cap 3 / gate 36: final 3; cap 0
  (regions off): final 1 (= the B1 open lag, not regions); cap 1 / gate 36: final 1. Kept cap 1 / gate 36 / 4 columns.
  Space: code row ends `$1FC3F4` (11 B left; RegInit / Mark / Done moved to the data row), data row ends `$1FFFE0` (32 B left).
  `make build`: `316573 changed byte(s) diffed: ok`, `built build/hush.sfc`. `make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`;
  FAIL = smoke_lighting (41382 of 241920 tile words differ from its oracle; renderer throughput is 1 unit/frame, the test samples
  mid-render and its rule predates L3). Solutions 21/21, lag 0 in r01-r20, final 1 (pre-existing B1). meter budget 21/21, must_not pass.
  Open: (1) throughput: compose set-up per carrier dominates a 4-column unit (~2 lines/carrier); 1 unit/frame means a full re-render
  takes many frames. (2) final's 1 lag frame (B1). (3) light_done never seen 1 by a test yet.
- C1 (profile only; no `src/hooks` change): `src/dev/row_probe.lua` rewritten (exec callbacks at routine entries / exits / JSR return
  sites, `cpu.cycleCount` + `masterClock` deltas). Results under "## C1 profile". `make build`: ok (316573 changed bytes, unchanged);
  `make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2` (FAIL = smoke_lighting, as B2d; final lag 1, as B1).
- C2: fix 2 (idle scan once per frame, empty slots rejected early, one time check per scan). Results under "## C2".
- C3: new ROM row `$1BB340-$1BB7FF` (bank $1B); fix 1 (carrier list per region, time-sized units, pick gate). Results under "## C3".
- C4: fix 3 (tile re-derive: once per tile, RAM loop, per-tile index words), unit sizing from measured costs (RQ 16 -> 6, RSET 7 -> 6),
  probe: + down leg, tiles == LUT(composite) check, render intervals. Results under "## C4".
- C5 (measurement only; no `src/hooks` change): new probe `src/dev/c5_probe.lua`, all 21 rooms. Results under "## C5 all rooms".
- D1 (aborted session, found in the tree; built, `make test` 38 / 1 / 2 = C4): amber = the 4.1 lattice of light_comp computed per region row
  (Hush_L3ARow from light_pcomp), region = changed cells (L3_ADB), glow pre-empts amber (Hush_L3Preempt / park). No report section was written;
  the `src/` comments that cite "## D1 hybrid" mean this line and "## D1a".
- D1a: one stored amber lattice. Results under "## D1a".
- D2: B-010 (guard light catch-up). Amber lattice merged into the commit path, no amber regions. Results under "## D2 B-010".
- D3: director decision on B-010: L2's direct cell-to-tile amber renderer restored, L3 amber removed, scheduling fixed. Results under "## D3".
- D4: glow update rate (fast glow path, same-picture skip, pattern table, guaranteed glow slice). Results under "## D4".
- E rev5: design/lighting.md revision 5 on the SA-1 (guard carriers 0-7 displaced again, per-guard lattices, exact composite pass). Results
  under "## E rev5".

## Space before the change
- ROM: code row `$1FB780-$1FC3FF` ends `$1FC3BC` (68 B left); data row `$1FCA00-$1FFFFF` ends `$1FFB67` (1176 B left).
- RAM: `$7ECA00-$7EE7FF` full; bank $7F `$7F8000-$7FB3F1` used by the L2 pair grids / LUTF (freed by L3), `$7FB3F2-$7FDD7F` free
  (`$7F7667[0x6719]` "free ram", A `WRAM.asm:9269`, ram_map.md bank $7F note).

## Design decisions
1. Per-cell logic and jobs unchanged (rays, commit, GMAP, COMP, VIO). The L2 cell-pair renderer (pair grids, LUTF, tile marks,
   Hush_LightRender) is removed: L3 renders from per-carrier lattices.
2. Carriers 0-7 = guard slots (amber), 8 = the player glow (violet). Per carrier, bank $7F: lattice `l` (plain levels 0..6,
   padded grid G(i,j) = (j+2)*38 + (i+2), i = -2..35, j = -2..31, 1292 B; padding = 0 so displaced reads need no bounds checks),
   lattice bbox (conservative, from the non-zero cells), lattice cell, rendered dx/dy, wanted dx/dy, "drawn" box.
3. Lattice build (4.1 for N = 7: point = (sum of its 1/2/4 cells, each counted 4/2/1 times + 2) >> 2, one formula for centre,
   edge and corner) reads the padded job scratch `light_scr` (the job box clear now also clears one row above and below the box,
   so every cell the build reads is the new light or 0). Guards: new job phase 3 after the commit, one lattice row per unit.
   Glow: `light_pvio` (padded copy of VIO, bank $7F), built inline by Hush_LightAura.
4. Wanted d (4.5 item 2): guard centre = sprite origin + 8 (the point Hush_LightSig uses for the cell), Link = (x + 8, y + 16)
   (Hush_LightAura); minus (16cx + 8, 16cy + 8) of the lattice cell; clamp +-16; quantize toward zero by D.
5. Render = one region per carrier at a time: region = drawn box U new displaced box. Row by row: NEW := 0; for every carrier of
   the region's kind whose displaced box meets the row: copy its source row(s) (MVN) into scratch S, horizontal lerp in place
   (LERP_t), vertical lerp (LERP_s) and max into NEW; then NEW vs composite A (amber) / VL (violet): changed span; then the tile
   row above (corners rows j-1, j) only over the changed spans, through Hush_LightLutA / LutV (complete corner LUTs).
6. LERP[t][a][b] = floor(((8-t)a + tb + 4)/8), table of 8 x 64 bytes in WRAM (built by code once per power-on, no ROM table);
   pointer (dp),Y per carrier pass. Tile index tables PH/PL (amber 686a+98b / 14c+2d) and PHV/PLV (violet), also built once.
7. Budget: units start only before LIGHT_VMAX; long units (compose / tile segments) size themselves from the scanlines left
   before LIGHT_VEND (estimated cost per point), so no unit runs past it. Scheduler: a running region and a running job (phases
   0-2) alternate unit by unit; the lattice build (phase 3) never overlaps a region; idle: alternate "start job" / "start region",
   region = the carrier with the largest |wanted - rendered| (lattice change first), round robin on ties.
8. FastROM skipped: the header / memory-speed byte change cannot be verified against a ledger row and the human did not approve
   a header change (AGENTS.md: header changes need the director).

## Step A1 RAM map
All bank $7F, defines `!L3_*` in `src/hooks/light.asm`, rows in `docs/ram_map.md` (L3 table). 9 x 1292 = 11628 B does not fit the
free block `$7FB3F2-$7FDD7F` (10638 B), so the lattices take the L2 pair-grid / LUTF area (written only once L2 is removed);
everything else sits in the free block, so it can be built while L2 still runs.

| Address | Size | Meaning |
|---|---|---|
| `$7F8000-$7FAD6B` | 9 x 1292 | carrier lattices, c at `$8000 + 1292c` (0-7 guards, 8 glow), G(i,j) = (j+2)*38 + (i+2) |
| `$7FB400-$7FB90B` | 1292 | composite amber lattice (CA) |
| `$7FB910-$7FBE1B` | 1292 | composite violet lattice (CV) |
| `$7FBE20-$7FC1DF` | 960 | `light_pvio`, padded VIO copy (32 x 30) |
| `$7FC200-$7FC3FF` | 512 | LERP[t][a][b], `t*64 + a*8 + b` |
| `$7FC400-$7FC5FF` | 4 x 128 | PH / PL / PHV / PLV word tables `[x*8 + y]` |
| `$7FC600-$7FC63F` | 64 | NEW row scratch |
| `$7FC640-$7FC6BF` | 128 | S: two source rows of one carrier |
| `$7FC700-$7FC7CF` | 13 x 16 | per carrier: CELL, RDX, RDY, WDX, WDY, DBX0, DBX1, DBY0, DBY1, LBX0, LBX1, LBY0, LBY1 |
| `$7FC7D0` | 2 | L3_OK = `$4C33` tables built (intro clear zeroes `$7FC000+`, `bank_0C.asm:112`) |
| `$7FC7E0-$7FC7FF` | 32 | region / scheduler state (layout later) |

Free after: `$7FB3F2-$7FB3FF`, `$7FC800-$7FDD7F` (5504 B). `make build` (A1, defines only):
```
freespace: 91 region(s), 144 org(s) checked, 315371 changed byte(s) diffed: ok
ROM ok: headerless, 1 MiB, CRC32 777AAC2F
built build/hush.sfc
```

## C1 profile

Build = B2d (cap 1 region unit / frame, L3_RCOLS 4, L3_RGATE 36, LIGHT_VMAX 200). Probe: `src/dev/row_probe.lua` (rooms r01, r13,
final; 30 frames after entry, then walk left 60 / up 60 / right 60 frames). Time = Mesen `cpu.cycleCount` deltas (real CPU cycles);
`masterClock` / 1364 = scanlines. Check: a 3159-cycle unit took 18.0 lines (175 cyc/line, so the ~170 estimate holds). "Per point" =
per lattice column of the unit (median unit = 4 columns). Spare lines for all rooms: `src/dev/spare_probe.lua`.

### Frame level

| room | guards | LightWork entry line med / p90 / max | spare lines to VMAX med / min | light time used med / max (lines) | exit line med | region units / frame | job units / frame (cyc med) | LightV / LightLate calls per frame |
|---|---|---|---|---|---|---|---|---|
| r01 | 1 | 121 / 125 / 127 | 79 / 73 | 35.8 / 50.6 | 158 | 0.82 | 1.00 (1671: every one an idle scan) | 17.4 / 12.8 |
| r13 | 2 | 136 / 140 / 142 | 64 / 58 | 55.1 / 72.4 | 192 | 0.91 | 4.53 (1133) | 17.4 / 3.6 |
| final | 6 | 169 / 190 / 195 | 33 / 5 | 28.4 / 45.6 | 197 | **0.00** | 2.49 (727) | 8.2 / 0.6 |

Spare lines (200 - median entry line, spare_probe, all rooms): r01 79, r02 74, r03 77, r04 71, r05 78, r06 52, r07 77, r08 68, r09 75,
r10 74, r11 69, r12 62, r13 63, r14 47, r15 53, r16 56, r17 53, r18 59, r19 41, r20 43, final 30. A region unit may start only before
line 164 (VMAX - RGATE): the window is 164 - entry = 5 (r19), 7 (r20), -5 (final). **Final ran 0 region units in 180 frames.**
Fixed per-frame costs: pre-units (Want / Ink / Aura) 1306-1500 cyc med (~8 lines; Aura 94 when the cell is unchanged);
Hush_LightV 34 cyc per call (~590 cyc / frame in r01 / r13).

### Per region unit (medians; cycles)

| part | r01 | r01 / point | r13 | r13 / point | notes |
|---|---|---|---|---|---|
| unit total | 3159 (18 lines; p90 5275, max 33 lines) | 791 (p90 1319) | 2254 (13 lines; p90 3999, max 34 lines) | 619 (p90 1097) | n = 148 / 164 units, 3.6 / 3.5 columns mean |
| (a) Hush_L3Pick | 0 (1548 when it runs, ~1 in 40 units) | ~3 | 0 (1550) | ~3 | |
| (b) Compose without the loop | 764 | 191 | 1483 | 371 | |
| (b) . NEW clear | 116 | 29 | 118 | 30 | 16-bit index loop |
| (b) . set-up per overlapping carrier | 619 | | 619 | | estimate was ~330 |
| (b) . skipped carrier, CELL $FF | 48 each | | 48 each | | 7 of 8 slots in r01 |
| (b) . skipped carrier, lattice but row outside bbox | 492 | | 492 | | full t/s/e/f math before the reject |
| (b) carriers walked / with lattice / overlapping | 8 / 1 / 1 (mean 4.9 / 1.0 / 0.6) | | 8 / 2 / 1 (mean 6.4 / 1.8 / 1.4) | | |
| (c) RAM loop (incl. RTL in / out) | 105 | **26.6** | 109 | **27.0** | s = 0 loop only (335 / 744 points); the s > 0 loop never ran |
| (d) Commit compare | 181 | 45 | 179 | 45 | ~140 of it is the row-address set-up |
| (e) Commit tile part | 8 (no change); p90 2061, max 2811 | 0; ~590 per changed point | 8; p90 1697 | same | |
| (e) . cycles per tile | 236 | | 245 | | estimate was ~40 |
| (e) . tiles re-derived / changed per unit | mean 2.1 / 2.1, p90 10 / 10 | | mean 1.8 / 1.8, p90 8 / 8 | | every re-derived tile changed |
| (f) everything else in the unit | 1802 | **450** | 240 | 60 | r01: 1671 = an idle Hush_LightStep scan inside the unit (L3_RTURN = 0 path) |

Findings beside the costs:
- The loop itself is on target (26.6-27.0 cyc/point = the B2b estimate + ~12 cyc RTL in / out per call); 85-95 % of a unit is overhead.
- Each tile row is derived twice per region: Commit(j) writes tile rows j - 1 and j, Commit(j + 1) writes j and j + 1, plus the
  cmin - 1 overlap column: 2 (n + 1) / n = 2.5 tiles per changed point at n = 4. The first pass is a transient (row j + 1 is not
  composed yet), which is why re-derived = changed.
- Rendered dy stayed 0 for every carrier (the s > 0 loop never ran): the glow's WDY changes while walking up, but its region takes
  many frames at 1 unit / frame and the glow cell (CELL[8] $FF during rebuild) changes every 16 px, so a dy != 0 render never landed.

### Three biggest sinks and fixes

1. **Compose fixed cost per unit** (b): 191 (r01) / 371 (r13) cyc/point. ~620 per overlapping carrier, 492 per lattice carrier
   rejected by row, 48 per empty slot, 116 NEW clear, paid per 4-column unit (8 times per 32-column row).
   Fix: at Hush_L3Pick, build the region's carrier list (kind, CELL != $FF, bbox meets the region) with everything constant over the
   region precomputed (t, s, e, f, pT / pS / LERP8 operands, lattice base + e, valid row range y0 - f - 1 .. y1 - f). Per row and
   carrier only the row test (2 CMP), row address = base + 38 j from a 29-word table, 4 operand stores and the call (~110 cyc). First
   carrier's loop stores instead of max (no NEW clear). Size the unit by lines left (16-33 columns). Expected: 27 (s = 0) / 35 (s > 0)
   + 110 k / n; n = 16, k = 2 -> **~41 cyc/point** (from 191-371).
2. **Idle guard-job scan inside region units** (f): Hush_LightStep with no job = 8 x (Hush_LightSig + compare + Hush_LightLate ->
   Hush_LightV) = 1671 cyc (~10 lines), up to twice per frame (before the region unit when L3_RTURN = 0, and in the closing unit):
   450 cyc/point in r01, ~20 of its 36 used lines per frame.
   Fix: a per-frame "idle scan found nothing" flag (cleared at LightWork entry): the scan runs at most once per frame and L3Unit then
   goes straight to RegStep; in the scan, reject $0DD0 != 9 slots before Hush_LightSig and check Hush_LightLate once per scan, not per
   slot. Expected: **~0 cyc/point** in region units (one scan, <= ~600 cyc, per frame outside them).
3. **Tile re-derive** (e): 236-245 cyc per tile x 2.5 tiles per changed point = ~590 cyc per changed point.
   Fix: Commit(j) derives only tile row j - 1 (its corner rows j - 1 and j are final: committed earlier in the region or outside it),
   over the union of the changed spans of rows j - 1 and j (keep the previous row's span); the region's last row also derives row jB.
   Tile loop as RAM code like compose (8-bit index, right corners carried into the next tile's left, light_dirty OR once per tile row).
   Expected: ~1.1 tiles per changed point x ~90 cyc = **~100 cyc per changed point** (0 for unchanged points), no transient frames.

After 1-3: ~41 compose + ~12 compare (8-bit, set-up amortized) + ~10 RegStep / V per point = **~65 cyc per unchanged point,
~165 per changed one** (now 619-791 median, ~1300 p90). A unit then fits in ~4 lines, so L3_RGATE can drop from 36 to ~8, which
reopens the region window in final (entry med 169 -> 23 lines) and r19 / r20.

## C2

Fix 2 of the C1 profile (idle guard-job scan), `src/hooks/light.asm` `Hush_LightStep` idle path only; job semantics and light logic unchanged.
- `light_ridle` `$7EE7F7` (ram_map row; the free byte after `light_done`): set when a full 8-slot scan finds every signature current;
  cleared at `Hush_LightWork` entry. While set, the idle path returns C = 0 at once (L3Unit goes straight to RegStep). Safe: signatures
  cannot change later in the frame (sprites do not move during LightWork; SIGC changes only at a job commit, in Hush_LightInk before the
  units, and on room load), and no job can start without a scan.
- Slot with `$0DD0 != 9`: Hush_LightSig would give signature 0 / 0, so the slot is current iff SIGC = 0 / 0, tested before calling it.
- `Hush_LightLate` once per scan (at its start; late -> C = 1, RR unchanged) instead of after every slot.
- Space: the scan grew 15 B and the flag clear is 3 B; the code row had 11 B, so `Hush_LightV` (25 B, unchanged) moved to the data row.
  Code row ends `$1FC3EB` (20 B left), data row ends `$1FFFF9` (6 B left).

`make build`: `freespace: 91 region(s), 144 org(s) checked, 316583 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting (39057 of 234752 tile words differ from its oracle; B2d: 41382 of
241920; same cause: 1 region unit / frame, test samples mid-render). Solutions 21/21, lag 0 in r01-r20, final 1 (B1, unchanged);
meter budget 21/21, must_not 122 + 9 cases pass.

row_probe (`.venv/bin/python tools/run_test.py src/dev/row_probe.lua`, same walk as C1), before (C1) -> after (C2), medians unless noted:

| metric | r01 | r13 | final |
|---|---|---|---|
| light time used per frame (lines) | 35.8 -> **22.6** (max 50.6 -> 66.8) | 55.1 -> 54.9 | 28.4 -> 28.4 |
| LightWork exit line | 158 -> **145** | 192 -> 192 | 197 -> 197 |
| region unit total (cyc) | 3159 -> **2406** (p90 5275 -> 4522) | 2254 -> 2207 (p90 3999 -> 3999) | no region units (0 / frame, as C1) |
| region unit per column (cyc) | 791 -> **603** | 619 -> 570 | - |
| (f) other in unit (cyc) | 1802 -> **1049** | 240 -> 240 (p90 1246) | - |
| job-step units (cyc) | 1671 (every one a full idle scan) -> **118** (n 180) | 1133 -> 1057 (real jobs) | 727 -> 727 |
| LightV / LightLate calls per frame | 17.4 / 12.8 -> **5.7 / 1.0** | 17.4 / 3.6 -> 14.8 / 1.0 | 8.2 / 0.6 -> 8.2 / 0.6 |
| region units per frame | 0.82 -> 0.86 | 0.91 -> 0.91 | 0.00 -> 0.00 |
| lag in the 180-frame walk | 0 -> 0 | 0 -> 0 | 0 -> 0 |

Reading: the second idle scan per frame is gone (r01 job-step units 1671 -> 118 cyc). The first scan of the frame still runs inside the
first unit (r01 (f) 1049 cyc: 1 guard via Hush_LightSig + 7 fast-rejected slots + one LightLate), ~1.4 x the ~600 estimate; that is the
floor for this fix. Region throughput is unchanged (cap 1 unit / frame, RGATE 36), so smoke_lighting and final's empty region window are
not affected; those need fix 1 (compose set-up) and fix 3 (tile re-derive), then a lower L3_RGATE.

## C3

(a) ROM space. New row `$1BB340-$1BB7FF` (1216 B, `src/FREESPACE.md`): the unclaimed tail of `NULL_1BB1E0` ("FREE ROM: 0x0629 including
garbage", `vendor/usdasm/bank_1B.asm:6`; lines 58-209 = rows `$1BB340-$1BB7F8` all `db $FF`; next data `pool GetPitEntranceDestination`
at `$1BB800`, `bank_1B.asm:213-216`). Grep of `vendor/usdasm` for `$1BB3xx-$1BB7xx` operands and for `NULL_1BB1E0` finds only the label
(`bank_1B.asm:13`). The M5 meter block before it ends at `$1BB32C`. Moved there: `Hush_L3Compose` (rewritten), `Hush_L3Commit` (JSR/RTS ->
JSL/RTL, body unchanged), new `Hush_L3List`; ends `$1BB76E` (146 B left). `Hush_L3Pick` moved code row -> data row (same bank $1F, JMP from
RegStep). Space now: code row ends `$1FC1E9` (534 B left, was 20), data row ends `$1FFEA2` (349 B left, was 6).

(b) Fix 1.
- `Hush_L3List` (JSL at the end of a non-empty pick): per carrier of the region's kind with a lattice, everything constant over the region
  goes into `light_l3list` `$7FC640` (the old L3_S, free since B2b; ram_map row): B = base + 38 (f + 2) + e + 2, LERP_t / LERP_s rows,
  rows jlo..jhi and columns ilo..ihi already clipped to the region. Carriers that cannot touch the region are left out.
- `Hush_L3Compose`: 38 j once per call; per entry only row test, lo / hi clip, B + 38 j, source / end operands; table operands (LERP_t,
  LERP8_t, LERP_s) only when another entry used the loop since (`L3_RLP`); NEW clear with word stores.
- Unit sizing (`Hush_L3RegStep`): L = LIGHT_VMAX - V, k = entries; n = 4 (L - 7 - k) / (16 + k) columns (worst case of the C1 profile:
  every point changed, ~4 lines / column), capped at the rest of the row; n = 0 -> no unit. RGATE 36 and RCOLS 4 are gone; cap 1 -> 8
  units / frame. The pick (+ list) is now a unit of its own, gated at >= 20 lines left (`L3_PGATE`).
- Staleness: the list is built once per region; a carrier whose lattice / cell / bbox changes meanwhile is marked (Hush_L3Mark) and gets
  its own region; nothing non-zero is written outside the old N, which becomes the drawn box, so a stale list cannot leave light behind.

`make build`: `freespace: 92 region(s), 145 org(s) checked, 316786 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting: 16696 of 185472 tile words differ (C2: 39057 of 234752); the test
compares against the undisplaced lattice of COMP / VIO, which L3's glued light does not show by design (B2d note), so it cannot pass as
written. Solutions 21/21, lag 0 in r01-r20, final 1 (unchanged); meter budget 21/21, must_not 122 + 9 pass.

row_probe (same walk; the probe now follows the JSL / JMP layout, keys loop calls by list entry, and counts region start / end lines only
for units that rendered a segment), C2 -> C3, medians unless noted:

| metric | r01 | r13 | final |
|---|---|---|---|
| region units per frame (mean) | 0.86 -> **5.12** | 0.91 -> **3.73** | 0.00 -> **1.68** |
| columns per unit (mean / max) | 3.6 / 4 -> 4.9 / 12 | 3.5 / 4 -> 4.9 / 11 | - -> 2.2 / 4 |
| columns rendered per frame (mean) | ~3.1 -> **~25** | ~3.2 -> **~18** | 0 -> **~3.7** |
| compose set-up per overlapping carrier (cyc) | 619 -> **169** | 619 -> **184** | - -> 166 |
| skipped carrier (cyc) | 48 / 492 -> 40 (mean 53) | 48 / 492 -> 34 (mean 49) | - -> 71 |
| compose total per unit (cyc) | 764 + loop (C1) -> 379 incl. loop | 1483 + loop -> 548 incl. loop | - -> 317 |
| RAM loop cyc / point (s = 0 / s > 0) | 26.6 / - -> 26.4 / 40.7 | 27.0 / - -> 26.0 / 40.1 | - -> 29.5 / - |
| unit total (cyc; p90; lines max) | 2406; 4522 -> 1484; 4256; 40 | 2207; 3999 -> 1194; 3750; 37 | - -> 854; 2119; 21 |
| region unit end line (med / p90 / max) | - -> 175 / 190 / 199 | - -> 175 / 190 / 198 | - -> 187 / 192 / 198 |
| light time used per frame (lines) | 22.6 -> 71.0 | 54.9 -> 58.2 | 28.4 -> 26.5 |
| LightWork exit line | 145 -> 192 | 192 -> 195 | 197 -> 196 |
| lag in the 180-frame walk | 0 -> 0 | 0 -> 0 | 0 -> 0 |

Reading: compose overhead per carrier is down ~3.5x and a region now runs ~5 units per frame in r01 instead of < 1; the final room gets
region units (1.68 / frame) and still no lag. Units are not 16+ columns yet: the worst-case size (~4 lines per column) and the lines left
after the first units (start line median 162-182) give ~4-5 columns; many glow rows are only ~10-12 columns wide anyway (max 12). Every
rendered unit ended by line 199, so the worst-case model held in all three walks. What limits it now is fix 3: tiles cost 218-301 cyc each
and 2.5 per changed point (p90 tile part 2665 cyc in r01), and that worst case is what the sizing has to assume. Unit "other" is
387-447 cyc (RegStep sizing loop, two JSLs, LightV), up from 240 in r13.

## C4

Fix 3 of the C1 profile (tile re-derive) + unit sizing from the measured costs. `src/hooks/light.asm` only (+ ledger / RAM rows).
- **Once per tile.** `Hush_L3Commit(j)` derives only tile row j - 1 (its corner rows j - 1 and j are final then), only tiles that are
  pending: two spans in `light_l3reg` +15..+18 (RSA = tile row j - 1, RSB = tile row j), widened by each segment's changed columns
  [max(cmin - 1, 0), min(cmax, 31)], intersected with the segment's final window [i0 - 1, i1 - 1] (last segment: up to i1; column i1 + 1
  is outside the region); RSA := RSB at the row's last segment. After row jB, tile row jB runs as a "tail" row jB + 1 (Commit only,
  `kind | $80`) when RSA is not empty and jB < 28; the region margin row rarely changes, so 0 tail units ran in the three walks (path not
  exercised by the probe; the idle-frame check below would catch a missed tile).
- **Index words instead of LDA/ADC.** Deviation from the task's "premultiplied index tables, LDA/ADC": one word per BG1 tile holds the
  whole LUT byte index, `light_l3ia` `$7FCB00` (amber, `686a + 98b + 14c + 2d`) / `light_l3iv` `$7FD2F8` (violet), padded 34 x 30 so a
  composite change at (i, j) adds `delta * k` to the 4 tiles with that corner without bounds checks (`light_l3d` `$7FDAF0`, delta -6..6,
  built once in `Hush_L3Tables`). Per tile then only `LDA IA,X / BEQ / TAY / LDA [LutA],Y / CMP.l tiles,X / BNE`, violet (`LDA IV,X`,
  `[LutV],Y`, LutV[0] = the empty tile) only when the amber index is 0. A row-pair TOP/BOT layout would need 4 x 1.8 KB and an ADC.
  Cost moved to the change: ~180 cyc per changed point (compare + 4 deltas).
- **RAM loop** `Hush_L3Tile` (in `Hush_L3Code`, `light_l3code` 128 -> 256 B; 128 B used): IA / IV / light_tiles row bases and the end
  patched per call (like compose), DP pointers `[$03]` / `[$06]` to the LUTs; light_dirty bit once per call. 65816 timings: amber 35,
  violet 45, + 14 cyc when the word changes.
- **Sizing** (`Hush_L3RegStep`): L3_RQ 16 -> 6 (worst column = every point changed: ~180 compare / deltas + ~1.1 tiles x ~60 + ~41 per
  carrier = (6 + k) / 4 lines), L3_RSET 7 -> 6 (fixed part measured from RegStep's V read: 600-800 cyc + ~170 per carrier).
- Space: bank $1B row ends `$1BB7DF` (32 B left), code row `$1FC20F` (496 B left), data row `$1FFF19` (230 B left). RAM `$7FCA80-$7FDBBF`
  (docs/ram_map.md rows; free `$7FDBC0-$7FDD7F`). IA / IV zeroed by DMA on room load with CA / CV.

`make build`: `freespace: 92 region(s), 145 org(s) checked, 317049 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting, 12131 of 172928 tile words (C3: 16696 of 185472; same cause as
C3: it checks the undisplaced lattice). Solutions 21/21, lag 0 in r01-r20, final 1 (unchanged); meter budget 21/21, must_not 122 + 9 pass.

row_probe (`.venv/bin/python tools/run_test.py src/dev/row_probe.lua`). The walk is now left / up / right / **down** 60 frames each (240;
C3: 180 without down), so absolute counts differ. C3 -> C4 (RQ 6, RSET 6), medians unless noted:

| metric | r01 | r13 | final |
|---|---|---|---|
| tile part per derived tile (cyc; window / span set-up included) | 218-301 (C3) -> **141** | -> **128** | -> **183** |
| RAM tile loop per tile, incl. RTL in / out (cyc) | - -> **61.0** | -> **56.5** | -> **61.1** |
| tiles derived / changed per unit (mean) | 2.5 per changed point (C1) -> **2.2 / 2.1** | -> 2.3 / 2.2 | -> 1.2 / 1.1 |
| columns per unit (mean / max) | 4.9 / 12 -> **8.0** / 12 | 4.9 / 11 -> **8.7** / 26 | 2.2 / 4 -> **3.5** / 11 |
| region units per frame (mean) | 5.12 -> 4.76 | 3.73 -> 3.38 | 1.68 -> 1.58 |
| columns rendered per frame (mean) | ~25 -> **~38** | ~18 -> **~29** | ~3.7 -> **~5.5** |
| unit cost from RegStep (fit, cyc) | 796 + 113 n | 711 + 143 n | 598 + 171 n |
| actual / sizing model: med / p90 / max; overruns | 0.47 / 0.69 / 0.87; 0 | 0.46 / 0.69 / 0.90; 0 | 0.49 / 0.72 / 0.89; 0 |
| region unit end line (med / p90 / max) | 175 / 190 / 199 -> 175 / 194 / 199 | 175 / 190 / 198 -> 182 / 195 / 200 | 187 / 192 / 198 -> 193 / 196 / 199 |
| s > 0 loop: points (cyc / point) | 40.7 (C3) -> 1512 (39.6) | 884 (39.2) | 0 |
| carrier-frames with rendered dy != 0 / with s > 0 | 78 / 73 | 230 / 97 | 35 / 0 |
| frames between renders, glow (RD changes; med / p90 / max, n) | **3 / 4 / 17** (73) | 7 / 24 / 35 (11) | 54 / 74 / 74 (4) |
| frames between renders, guards | none moved d | 132 / 206 / 206 (3) | none moved d |
| frames with glow wanted d != rendered d | 131 of 240 | 139 of 240 | 204 of 240 |
| tiles == LUT(CA / CV corners) and IA / IV exact, at idle frames (RC = $FF) | 9 checks, **0 bad** | 1, 0 bad | 8, 0 bad |
| lag in the walk | 0 | 0 | 0 |

Intermediate step (RQ 6, RSET 7): ratio max 0.81-0.84, columns per unit 7.9 / 9.0 / 3.5; RSET 6 gains little but stayed at 0 overruns.

Reading: a tile is now derived once (derived = changed + ~5 %), at ~60 cyc in the loop; the per-tile cost that remains is the call set-up
(~100 cyc per commit, paid even for 1 tile). The s > 0 path runs: r01 renders the glow at dy -4..7 while walking up / down (1512 points
in the general loop), r13 at dy -5..7. Throughput is up ~1.5x (columns per frame), latency for the glow in r01 is 3 frames median. Still
slow: r13 guard lights (132 frames median between re-renders: a lit-room guard's region is most of the 33 x 29 lattice and 2 carriers) and
the final room's glow (54 frames: 30 spare lines, 1.6 units per frame). Both are now bound by lines per frame, not by tile cost: the next
lever is region size (a moved carrier re-renders drawn U new box, all rows) rather than per-point cost.

## C5 all rooms

Build = C4 (no ROM change; `make build`: `317049 changed byte(s) diffed: ok`, `built build/hush.sfc`). Probe: `src/dev/c5_probe.lua`
(`.venv/bin/python tools/run_test.py src/dev/c5_probe.lua`; 30.7 s, two runs gave identical numbers). Per room: jump, 30 frames, then
walk left / up / right / down 75 frames each (300 frames). Definitions:
- **wanted W** = carrier centre as Hush_L3Want sees it, unclamped (guard `x - $E2, y - $E8`; glow `$22 - $E2, $20 + 8 - $E8`).
  **rendered R** = `(16cx + RDX, 16cy + RDY)` snapshotted at Hush_L3List (the pick of a non-empty region) and counted as drawn when that
  region ends (RegStep `.end`, `LDA #$FF : STA.l L3_RC`, `$1FC207`). **lag px** = mean Euclidean |W - R| over frames x carriers that
  have a lattice and a drawn position.
- **re-render frames** = frames between two region ends of the same carrier, kept only when the carrier moved (W changed) in between;
  open intervals (walk start -> first end, last end -> walk end) are included when it moved, so 300 = never re-rendered in the walk.
- **guard-frames undrawn** = guard-frames with a lattice (CELL != $FF) but no region of it ended since the walk start and CELL was $FF
  at the start: its light is not on screen (or is stale); these frames are not in "guard lag px" (final's 0.0 = only the 1 static guard).
- **regions / s** = regions ended x 60 / 300. **region cyc** = pick unit (Hush_L3Pick -> unit end) + every row unit (RegStep `.row` ->
  unit end). **points** = (RI1 - RI0 + 1) x (RJB - RJA + 1). **spare** = 200 - LightWork entry line. **lag** = frames - LightWork exits.

| room | guards | regions / s | guard re-render frames med / p90 / max | guard lag px | guard-frames undrawn | glow re-render frames med / p90 / max | glow lag px | spare lines med / min | lag frames | region points med | region cyc med |
|---|---|---|---|---|---|---|---|---|---|---|---|
| r01 | 1 | 17.6 | - | 0.0 | 0 % | 3 / 4 / 31 | 4.0 | 78 / 73 | 0 | 99 | 22901 |
| r02 | 1 | 7.6 | 13 / 35 / 65 | 11.8 | 0 % | 3 / 33 / 118 | 21.3 | 75 / 67 | 0 | 208 | 46519 |
| r03 | 1 | 6.0 | - | 0.0 | 0 % | 3 / 4 / 151 | 2.2 | 76 / 45 | 0 | 99 | 21415 |
| r04 | 1 | 3.2 | 18 / 23 / 49 | 22.0 | 0 % | 199 / 199 / 199 | 12.6 | 72 / 44 | 0 | 616 | 104237 |
| r05 | 1 | 9.8 | 15 / 15 / 15 | 0.5 | 0 % | 3 / 5 / 77 | 2.6 | 78 / 53 | 0 | 99 | 23707 |
| r06 | 3 | 1.2 | 47 / 222 / 222 | 36.5 | 4 % | 300 / 300 / 300 | 11.2 | 55 / 41 | 0 | 638 | 184183 |
| r07 | 1 | 5.6 | - | 0.0 | 0 % | 3 / 8 / 76 | 3.7 | 77 / 41 | 0 | 90 | 23015 |
| r08 | 2 | 4.8 | 28 / 79 / 79 | 10.5 | 0 % | 5 / 95 / 98 | 39.0 | 68 / 38 | 0 | 108 | 33597 |
| r09 | 1 | 5.4 | 20 / 64 / 68 | 13.5 | 0 % | 3 / 71 / 187 | 32.0 | 73 / 67 | 0 | 108 | 28502 |
| r10 | 1 | 4.6 | 14 / 43 / 59 | 16.3 | 0 % | 3 / 203 / 203 | 15.7 | 74 / 45 | 0 | 480 | 82313 |
| r11 | 2 | 9.0 | - | 0.0 | 0 % | 4 / 6 / 77 | 4.6 | 69 / 62 | 0 | 100 | 26839 |
| r12 | 3 | 6.6 | 270 / 270 / 270 | 0.5 | 4 % | 6 / 13 / 78 | 10.1 | 62 / 32 | 0 | 108 | 29030 |
| r13 | 2 | 4.4 | 53 / 81 / 149 | 42.9 | 0 % | 7 / 56 / 89 | 9.1 | 62 / 53 | 0 | 126 | 37338 |
| r14 | 4 | 0.6 | 90 / 142 / 142 | 14.2 | 38 % | 300 / 300 / 300 | 29.8 | 50 / 21 | 0 | 640 | 239292 |
| r15 | 3 | 1.2 | 98 / 300 / 300 | 38.0 | 6 % | 174 / 174 / 174 | 54.3 | 54 / 25 | 0 | 624 | 187540 |
| r16 | 3 | 2.2 | 134 / 175 / 175 | 29.7 | 16 % | 9 / 135 / 135 | 14.4 | 47 / 23 | 0 | 126 | 36571 |
| r17 | 3 | 2.6 | 87 / 138 / 138 | 26.2 | 4 % | 10 / 158 / 158 | 28.3 | 56 / 38 | 0 | 120 | 37229 |
| r18 | 3 | 3.2 | 23 / 93 / 93 | 13.9 | 33 % | 11 / 108 / 108 | 33.1 | 59 / 35 | 0 | 252 | 73177 |
| r19 | 4 | 0.8 | 184 / 299 / 299 | 47.9 | 30 % | 268 / 268 / 268 | 51.2 | 40 / 32 | 0 | 442 | 168872 |
| r20 | 5 | 0.8 | 190 / 300 / 300 | 14.4 | 51 % | 51 / 218 / 218 | 37.5 | 41 / 11 | 0 | 580 | 185512 |
| final | 6 | 1.0 | 300 / 300 / 300 | 0.0 | 69 % | 49 / 100 / 100 | 66.7 | 28 / 6 | 0 | 143 | 51933 |

Reading: no lag frames anywhere, but the light falls far behind its carrier from r13 on: guard re-renders take 50-300 frames, the glow
lags 28-67 px in r14-final, and in r14 / r18-final 30-69 % of lit-guard frames show no (or stale) guard light at all. Cost per region is
~230-375 cyc per point at every size (99 points: ~23k cyc; 640 points: ~239k cyc = ~1370 lines, i.e. ~25+ frames at r14's 50 spare
lines), so the full-lattice regions (450-640 points: lit rooms r04 / r06 / r10 / r14 / r15 / r19 / r20) are what stall every carrier
behind them; per-point cost alone cannot close a 10x gap, region size (or doing the guard light differently) has to.

## D1a

Director: amber is ONE carrier (design/lighting.md rev 4: the 4.1 lattice of COMP, undisplaced). Built on the D1 tree (light_pcomp, L3_ADB,
amber / glow pick, pre-empt kept).
- `L3_AL` `$7F8000` (1292 B, plain levels) = the amber lattice. Job phase 3 (`Hush_L3Lat`) builds one row per unit from light_pcomp
  (`Hush_L3ARow` -> L3_NEW -> MVN), only before LIGHT_VMAX - 12. light_pcomp moved to `$7F850C`; **`$7F88CC-$7FA85F` (old lattices 1-7) freed**
  (ram_map). Glow (carrier 8, `$7FA860`) unchanged.
- Amber region row = `Hush_L3ACopy`: MVN of the L3_AL row into L3_NEW (7 cyc/point; no lerp), then Hush_L3Commit as before.
- **Deviation 1 (build box):** phase 3 builds over `L3_ALB` `$7FDBD1` (cells changed since the last build, grown in Hush_L3ADirty) instead of
  the job box. ALB is inside the job box, so rows with no change are skipped. It also covers a job aborted by an ink change after its commit
  (Hush_LightInk -> Hush_LightIdle): with the plain job box those cells would keep a stale lattice. Amber regions start only with ALB empty.
- **Deviation 2 (region):** amber region = L3_ADB (cells changed since the last amber region) in lattice points [2 x0, 2 x1 + 2] x [2 y0, 2 y1 + 2]
  (kept from D1), not the job box + 1. These are exactly the points a changed cell reaches (4.1). Amber d = 0, so no margin is needed.
- Space: code row ends `$1FC2CE` (305 B left; Hush_L3ARow moved there), data row ends `$1FFFD0` (47 B left).

`make build`: `freespace: 92 region(s), 145 org(s) checked, 317421 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting, 12356 of 268800 tile words (D1 tree: 20067 of 319872); first mismatches
are violet (glow displaced by design, rev 4 4.5). Solutions 21/21, lag 0 in all 21, meter budget 21/21, must_not 122 + 9 pass.

c5_probe (`.venv/bin/python tools/run_test.py src/dev/c5_probe.lua`, same walk as C5). **The guard columns are not valid under D1a.** The
probe tracks one region per guard carrier. Amber is now one region (RC 0) at a fixed position, so "re-render 300" and "lag px" for guards
measure nothing. The probe needs an amber-latency metric (frames from a COMP change to its tiles), for example from qa. C5 -> D1a:

| room | guards | regions / s | guard-frames undrawn | glow re-render frames med / p90 / max | glow lag px | spare lines med / min | lag frames | region points med | region cyc med |
|---|---|---|---|---|---|---|---|---|---|
| r01 | 1 | 17.6 -> 20.0 | 0 -> 0 % | 3/4/31 -> 2/4/31 | 4.0 -> 3.5 | 78 / 73 | 0 | 99 -> 99 | 22901 -> 21689 |
| r04 | 1 | 3.2 -> 2.8 | 0 -> 0 % | 199/199/199 -> 5/63/77 | 12.6 -> 1.4 | 72 / 44 | 0 | 616 -> 100 | 104237 -> 21683 |
| r06 | 3 | 1.2 -> 1.4 | 4 -> 0 % | 300/300/300 -> 10/135/135 | 11.2 -> 1.3 | 55 / 41 | 0 | 638 -> 100 | 184183 -> 25530 |
| r10 | 1 | 4.6 -> 5.2 | 0 -> 0 % | 3/203/203 -> 3/5/152 | 15.7 -> 3.1 | 74 / 45 | 0 | 480 -> 99 | 82313 -> 18664 |
| r13 | 2 | 4.4 -> 5.6 | 0 -> 0 % | 7/56/89 -> 6/21/77 | 9.1 -> 3.2 | 62 / 53 | 0 | 126 -> 99 | 37338 -> 25003 |
| r14 | 4 | 0.6 -> 4.0 | 38 -> 24 % | 300/300/300 -> 10/40/82 | 29.8 -> 12.6 | 50 / 21 | 0 | 640 -> 108 | 239292 -> 31154 |
| r15 | 3 | 1.2 -> 5.0 | 6 -> 0 % | 174/174/174 -> 6/9/78 | 54.3 -> 6.7 | 54 / 25 | 0 | 624 -> 99 | 187540 -> 23948 |
| r16 | 3 | 2.2 -> 3.8 | 16 -> 66 % | 9/135/135 -> 8/55/83 | 14.4 -> 5.1 | 47 / 23 | 0 | 126 -> 108 | 36571 -> 27633 |
| r19 | 4 | 0.8 -> 4.2 | 30 -> 25 % | 268/268/268 -> 11/15/44 | 51.2 -> 13.5 | 40 / 32 | 0 | 442 -> 110 | 168872 -> 30376 |
| r20 | 5 | 0.8 -> 2.6 | 51 -> 39 % | 51/218/218 -> 11/61/84 | 37.5 -> 16.3 | 41 / 11 | 0 | 580 -> 117 | 185512 -> 29751 |
| final | 6 | 1.0 -> 2.0 | 69 -> 59 % | 49/100/100 -> 26/54/54 | 66.7 -> 35.8 | 28 / 6 | 0 | 143 -> 117 | 51933 -> 39411 |

Other rooms (D1a): r02 11.4 / s, glow 3.3 px; r03 7.0, 2.0; r05 11.0, 2.2; r07 5.8, 3.2; r08 7.2, 11.0; r09 9.8, 4.0; r11 10.6, 3.5; r12 7.8,
7.5; r17 5.2, 5.2; r18 6.0, 9.2. Lag frames 0 in all 21 rooms. "Guard-frames undrawn" still reads per-guard CELL / region state; treat it
as indicative only (r16 66 %).

Reading: median regions are now ~100-117 points everywhere (C5: up to 640 in lit rooms), because the 450-640-point per-guard displaced
regions are gone. Glow latency in lit rooms dropped from 174-300 frames to 6-26 frames median, and glow lag from 30-67 px to 1-36 px.
final is still the worst case (28 spare lines). Open: (1) an amber latency metric in the probe; (2) smoke_lighting still checks
an undisplaced glow (test vs rev 4; qa).

## D2 B-010

Task: docs/bugs.md B-010 (light_done stays 0 for hundreds of frames with Link still). Probes (engine, `src/dev/`, not tests):
`d2_probe.lua` (r19 / final / r16 / r18, Link still 1200 frames, CPU cycles per unit kind, per job, per routine) and `d2_legs.lua` (replays
the exact input of tests/smoke/lighting.lua without its checks; per long wait: jobs, phases, awareness, a timeline). qa's probes:
`tests/dev/b010_light_done.lua`, `tests/dev/light_latency.lua` (the L2 metric of docs/engine_notes.md section 16).

### Profile before (D1a, r19, 1200 still frames, d2_probe)
| unit kind | share of light cycles | per unit (cyc) |
|---|---|---|
| amber region rows (ACopy + Commit) | 59 % | 1853 (7.9 points, 3.0 changed) |
| job phase 3 (lattice rows) | 16 % | 1137 |
| job phase 2 (commit) | 13 % | 714 |
| job phase 1 (wedges, 8 entries) | 7 % | 878 |
| job phase 0 / pick / glow / scan | 5 % | - |

~75k cycles per guard job (105 jobs, one every ~11 frames, 46 spare lines = ~7.8k cycles per frame): the light was saturated. Region units
were 8 points wide (worst-case sizing) with ~1.1k fixed cost each; phase 3 rebuilt the changed box row by row; amber regions could only
start with the phase-3 box empty; per changed point the commit spent ~200 cycles on 4 IA deltas.

### Changes (each `make build` ok; space: code row ends `$1FC3BC`, data row `$1FFF5C`, bank $1B `$1BB7E6`, new row `$1FC916-$1FC9FF` ends `$1FC9B2`)
1. Tried first, reverted: amber region rows sized "rest of the row" with a time check inside Hush_L3Commit: r19 longest run 336 -> 330.
2. No stored amber lattice, no phase 3, no amber regions (Pick / RegStep: glow only; Hush_L3Lat, AmbC, Preempt, ARow, AAdr, ACopy removed).
   A changed light_comp cell marks its 9 lattice points pending (`Hush_L3ADirty`, ~130 cyc: `light_l3lp` spans per lattice row + `light_l3lpr`).
3. `Hush_L3LRow` ($1FC916 row; head `Hush_L3LPass` in the data row): computes each pending point once from light_pcomp (4.1 formulas)
   straight into L3_CA, only when the running commit cannot change it any more (lattice row j < 2 JROW or > 2 JBY1 + 2, `Hush_L3LGate`);
   loops over rows within one unit on one V read (budget 1 point per line + 3 per row, <= ~110 cyc per point).
4. Amber pair words instead of IA deltas: `light_l3ia` now holds `2P = 16 l(i,j) + 2 l(i+1,j)` per lattice point (two byte merges per
   changed point instead of 4 word deltas); `Hush_L3Tile` takes the amber index as `PH[2P(top)] + PL[2P(bottom)]` (+20 cyc per tile).
5. Changed points mark their tiles (`Hush_L3TMark`: `light_tdirty` spans per tile row, rows in `light_l3adb`); `Hush_L3TPass` derives a tile
   row only when its two lattice rows are no longer pending (one span per row per job), several rows per unit, LUT pointers once per unit.
6. `Hush_L3Unit`: 3-way rotation job / amber (`Hush_L3Amb`: lattice rows, then the tile rows they finished) / glow region.
7. Wedge units: 16 entries when they start before LIGHT_VMAX - 10 (else 8; half the Hush_LightStale calls). L3Want no longer rewrites the
   guard WD every frame; L3Done checks only carrier 8's displacement (guards are never displaced).
8. Tried and reverted: (a) 9-point recompute per changed cell inside the commit (ADirty ~1.5-2.1k cyc per cell; the commit needed a
   LIGHT_VMAX - 13 pre-check): smoke 7-11 late waits; (b) marking only the changed points' tiles: -2 % tiles, +130 cyc per cell, net loss;
   (c) capping the amber unit (16 points, 2 tile rows): smoke 7 late waits (was 3-4), more per-unit overhead.

### Results (before = D1a, from docs/bugs.md B-010 and the runs above; after = final build)
| metric | before | after |
|---|---|---|
| b010_light_done r19: first done / done frames / longest done=0 run | 237 / 10 / 336 | **19 / 213 / 105** |
| d2_probe longest done=0 run, 1200 still frames: r19 / final / r16 / r18 | 336 / 298 / 223 / 40 | **106 / 77 / 25 / 11** |
| d2_probe jobs per 1200 frames, r19 (frames per job med / p90) | 104 (10 / 16) | 149 (5 / 8) |
| smoke_lighting max wait per room, r12 / r16 / r18 / r19 / r20 / final | 173 / 238 / 201 / 949 / 188 / 428 | **133 / 153 / 30 / 117 / 124 / 253** |
| smoke_lighting waits > 120 frames | 39 of 504 | **4 of 504** (r12 t=22 133, r16 t=17 153, r20 t=16 124, final t=5 253) |
| smoke_lighting tile words wrong | 0 | 0 (451584 words, 504 VRAM compares) |
| light_latency med / p90 / max: r13 | (L2 6 / 11 / 13) | 7 / 12 / 15 |
| light_latency med / p90 / max: r19 | (L2 11 / 19 / 61) | 14 / 20 / 21 |
| light_latency med / p90 / max: final | (L2 9 / 28 / 55) | 12 / 31 / 41 |
| lag frames (21 solution replays, b010 probe) | 0 | 0 |

Per guard job after (r19, d2_probe): job 0-2 ~17k cyc, lattice rows ~14.5k (10.8 rows, 72 points, 81 % of them changed), tile rows ~12k
(10 rows, 93 tiles). About half of the amber cost is per-row overhead (~600 cyc per lattice row and per tile row).

`make build`: `freespace: 93 region(s), 146 org(s) checked, 317702 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting liveness only: `4 of 504 waits for light_done exceeded 120 frames
(max 253 in final)`; tiles 0 wrong, glow d 504 checks. Solutions 21/21 with lagged frames 0, meter budget 21/21, must_not 122 + 9 pass.

### Open (why the last 4 waits are long; d2_legs)
- final t=5 (253): guard 4 is Alert (all-around light) for ~90 frames, then three patrolling guards keep the pipeline busy (jobs back to
  back: 18 jobs in 237 frames, ~36 spare lines per frame). Throughput-bound: ~55k cyc per job in final vs ~6.1k per frame.
- r16 t=17, r12 t=22, r20 t=16: one Suspicious / Alert guard (class 2 / 3, all-around jobs) plus patrols; same pattern.
- Remaining cost is the amber pipeline's per-row overhead and the wedges of all-around jobs. The next lever with a large effect is the L2
  amber path (tile word straight from the 2 x 2 cells C, H, V, D per quadrant via a pre-multiplied cell grid + one LUT; mathematically the
  same tiles as the rev 4 amber lattice, header of light.asm): no lattice points at all, ~30 cyc per tile. Needs ~10 KB of bank $7F
  (free: `$7F88CC-$7FA85F`, `$7F8000-$7F850B`, CA / IA once amber stops using them) and a director decision (it reverses D1a's
  "amber = one stored lattice" structure).

## D3

Director decision (B-010, design/lighting.md section 5 "Catch-up": per room median <= 15, p90 <= 40, max <= 90 frames per stale episode):
L2's direct cell-to-tile amber renderer back, L3 glow (carrier 8, displaced violet lattice, region driver) kept, dead L3 amber removed,
and find / fix why change -> commit is slow. Probe: `src/dev/d3_episodes.lua` (replays smoke_lighting's exact input with its catch-up
tracker; per long episode the jobs and a per-frame timeline of the slot and of the pipeline).

### Changes (each `make build` ok)
1. **Amber = L2 again.** Pair grids `light_pgrid` `$7F8000` (A98 / A2, W and E pairs interleaved: G = (cy + 1) 128 + (cx + 1) 4, so one
   index X = 2 tx serves the grids, light_tiles and IV), `light_lutf` `$7F9000` (2401 words, built once per power-on with the L3 tables,
   `light_l3ok` = `$4C34`; 0 where every amber corner is 0: LutA gives the empty tile exactly then, tools/autotile.py `light_lut`).
   Removed: Hush_L3ADirty / Amb / LPass / LGate / LSpan / LPtr / LMark / LRow, light_pcomp, CA, IA, PH / PL / PHV / PLV, light_l3lp.
   `light_l3lpr` stays `$FF` (no lattice; the test reads it). Job box clear back to the box rows.
2. **One per-tile rule for both renderers** (`Hush_L3Tile` RAM loop, driven by `Hush_L3TRow` from the amber pass and the glow commit):
   LUTF[A98 + A2] EOR quadrant flip if non-zero, else LutV[IV] (violet composite of the glow, LutV[0] = empty). smoke_lighting: 0 of
   451584 tile words wrong in every run below.
3. **Marks:** each commit unit marks the 4 x 4 tile block of its changed cells once (`Hush_LightMarkRow` -> light_tdirty spans + L3_ADB);
   the pairs are rewritten once per unit over the changed span (`Hush_LightAmbRow`, 2 pairs per cell; L2 wrote 4 per changed cell).
   The commit's time check is skipped for the rest of a row when its first change comes before LIGHT_VMAX - 56, else it stops at
   LIGHT_VMAX - 16 (`Hush_LightLateC`: the deferred pairs + marks still follow, <= ~15 lines).
4. **Scheduling** (the cause, below): until `light_vjob` = 3/4 of the frame's unit lines, L2's order (running job, else pending amber
   tiles, else next job); then D2's rotation. **No new job is picked while amber tiles are pending.** The amber pass renders, during a
   commit, only tile rows the commit can no longer mark (ty < 2 JROW - 1). The glow goes first once it has waited 4 light frames
   (`light_l3reg` +19; its pick needs 20 lines, more than the rotation leaves in final).
5. Tried and reverted: no mid-wedge restart for all-around jobs (r15 max 87 -> 91, final 119 -> 132: stale commits).

### Why change -> commit took up to 229 frames (d3_episodes, step 1 build = L2 amber + D2 scheduling)
- **Starvation by the rotation:** job / amber / glow alternated per unit, but the amber pass and the glow region size their units to the
  rest of the frame, so a job got ~1 unit (16 wedge entries or 1 commit row) per frame. An Alert / Suspicious job (4 wedges x 99 entries
  lit) needed 21-25 frames of wedges + 12-15 of commit; final jobs med 9 / max 37 frames, r12 med 15. With step 4: final med 5-6, r12 9-10.
- **The pipeline never emptied:** a new job could start while the previous job's tiles were pending (`.late` path and the rotation both
  reach the pick), so amber was pending on nearly every frame and "shown" (global) almost never held. With the no-pick rule each job's
  tiles reach VRAM during the next job's clear / wedges.
- **Remaining (not fixed):** an Alert guard charging in a lit room changes cell every ~14 frames; its all-around job (~12 frames in r12)
  plus its render and upload (~7-10) is longer, so its episode (and the other slots' episodes that overlap it) closes only after it calms
  down. r12's slot 1 episode (L at 0, 14, 29, 44, Unaware from ~44, closed ~75-84) and final's slot 4 (Alert ~110 frames) are exactly these.

### Catch-up per room (smoke_lighting, median / p90 / max frames (episodes); final build = last `make test`)
| room | D2 (B-010 update) | D3 step 1 (L2 amber only) | D3 final |
|---|---|---|---|
| r02 / r04 / r06 | 8/13/14 / 4/13/14 / 9/14/24 | 5/11/12 / 3/10/12 / 6/9/17 | 5/8/10 (15) / 3/8/12 (14) / 5/10/10 (24) |
| r08 / r09 / r10 | 7/27/38 / 8/21/26 / 4/9/12 | 7/16/51 / 8/16/21 / 3/8/9 | 5/16/18 (13) / 6/12/17 (11) / 3/8/11 (11) |
| r12 | **24/135/135** | **33/84/84** | **14/75/75 (7)** |
| r13 / r14 / r15 | 12/16/23 / **12/53/55** / 12/31/60 | 8/13/14 / 10/33/47 / 10/17/70 | 8/12/15 (30) / 8/18/21 (20) / 10/16/57 (40) |
| r16 / r17 / r18 | **13/155/156** / **10/39/100** / 15/33/35 | 9/33/59 / 8/25/40 / 12/21/28 | 10/34/68 (20) / 9/17/38 (37) / 9/20/23 (18) |
| r19 / r20 | **19/106/124** / **12/130/130** | 13/26/52 / 8/28/30 | 15/19/40 (99) / 9/29/36 (22) |
| final | **33/94/252** | **14/61/142** | **11/37/174 (54)** |
| max to commit (final) | 229 | 139 | 170 (one Alert episode; other episodes <= 64) |
Runs vary by a few frames (the walk waits for light_done, so guards are elsewhere); final's max was 119-183 over the last 5 runs, r12's 75-84.

### Glow and lag (c5_probe, same walk as C5; glow re-render frames med / p90 / max, glow lag px)
| room | D1a | D3 final |
|---|---|---|
| r01 / r04 / r10 | 2/4/31, 3.5 / 5/63/77, 1.4 / 3/5/152, 3.1 | 3/4/31, 3.9 / 9/77/77, 1.4 / 3/10/153, 4.8 |
| r14 / r16 / r19 | 10/40/82, 12.6 / 8/55/83, 5.1 / 11/15/44, 13.5 | 15/46/82, 23.1 / 11/59/79, 11.5 / 28/75/75, 41.1 |
| r20 / final | 11/61/84, 16.3 / 26/54/54, 35.8 | 42/91/91, 29.6 / **94/119/119, 68.4** |
Without the glow wait (step 4, last part) final was 224 frames (once in the walk). Lag frames: 0 in all 21 c5 walks and all 21 solution
replays (`lagged frames 0`).

### Space / RAM
Code row ends `$1FC371` (142 B left), data row `$1FFFDF` (32 B left), `$1FC916` row `$1FC9C9` (Hush_L3TRow), bank $1B `$1BB747` (184 B left).
RAM: `light_pgrid` `$7F8000-$7F8FFF`, `light_lutf` `$7F9000-$7FA2C1`, `light_vjob` `$7EE7FD`, glow wait `$7FC7F3`; freed: CA, IA, PH-PLV,
light_l3lp (docs/ram_map.md rows).

`make build`: `freespace: 93 region(s), 146 org(s) checked, 317624 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting catch-up only: `r12 median 14 (<= 15) p90 75 (<= 40) max 75 (<= 90);
final median 11 (<= 15) p90 37 (<= 40) max 174 (<= 90)`; tiles 0 wrong. Solutions 21/21 with lagged frames 0, meter budget 21/21,
must_not 122 + 9 pass.

### Open
1. Alert-guard episodes (r12, final): needs either a ~2x cheaper all-around job + render, or a spec decision (designer / director) on
   episodes of a guard whose cell changes faster than its light can be rebuilt.
2. Glow latency in r19 / r20 / final is worse than D1a (glow gets <= 1 frame in 5 under load).

## D4

Task: glow update rate (D3 final re-render median ~94 frames) without breaking guard catch-up. Probes (engine, `src/dev/`): `d4_probe.lua`
(c5's walk, 300 frames per room; glow re-render = frames between glow region ends or same-picture skips while Link moved), `d4_lag.lua`
(the 21 solution replays; lag frames, main-loop end line `$00805D`, per lag frame a unit trace).

### Changes (`src/hooks/light.asm`; each `make build` ok)
1. **One carrier, fused loop.** Hush_L3List / Compose / Pick / GlowC / RegStep removed. `Hush_L3GPick` (bank $1B) snapshots RD := WD, sets
   the region and patches the table operands of the RAM loop once per region. RAM loops `Hush_L3GF` (s > 0) / `Hush_L3PF` (s = 0) compute
   the displaced glow value and compare it with CV directly (no NEW row, no carrier list); a change calls `Hush_L3GChg` (CV, IV deltas,
   span, time). `Hush_L3Commit` per row: CV row / IV offset kept in `light_l3reg` +24 / +26 (no multiplications), no PHB.
2. **Exact glow region.** N = [2cx - 3 + ceil(dx/8), 2cx + 4 + ceil(dx/8)] (same for y): 8 x 8 points (C3: 10-11 x 9-10).
3. **Same-picture skip.** Every glow pattern has |l(p) - l(q)| <= 1 for adjacent points (centre 2 only next to edges >= 1), so H =
   LERP_t[a, b] is a for t <= 3, max(a, b) at t = 4, b for t >= 5; the same for V. The picture depends on d only through
   (e, class(t), f, class(s)); `Hush_L3GRun .key` compares them and sets RD := WD without a region when equal (r01: 19 skips/s vs 26 regions/s).
   D = 2 would not help: class changes still come at 3 of 8 px per axis. **D stays 1.**
4. **Glow cell change in one step** (D3: two halves with no glow lattice in between, the glow blinked off at each cell crossing; ~42 lines):
   `Hush_L3GTab` builds the 32 glow lattice patterns (5 floor flags) once per power-on into `light_l3gtab` `$7FAE00` (2240 B, ram_map row);
   `Hush_LightAura` = old ring off + `Hush_L3GZero` + new ring on + `Hush_L3GSet` (copy, ~5 lines) + Hush_L3Want: **19-20 lines**, gate
   `L3_AGATE` = 24 (D3: 24 per half). `light_l3ok` = `$4C35`.
5. **Scheduling.** `Hush_L3GSlice`: the glow runs first in every light frame until min(V + 12, LIGHT_VMAX - 8) (`L3_GSLICE`); in the
   rotation the glow unit is 8 lines (`L3_GUNIT`). A row started in the slice runs to its end; `Hush_L3GChg` stops a row only at the hard
   limit LIGHT_VMAX - 8 (stopping at the slice end split rows: +40 % cycles per region). GWAIT / GFIRST removed.
6. **Lag fix.** `d4_lag` found one lag frame (r20 replay, frame 173): the rotation's glow unit returned "nothing" at line 200 and
   Hush_L3Unit fell through to a job commit that started at line 201 and ended at 216. `Hush_L3GStep` now returns C = 1 when nothing was
   done and the frame is over (Hush_LightLate). Tried and reverted: a late check at the start of every job unit (lag 0, but final catch-up
   19 / 53 / 68).
7. Tried: slices 16 + glow unit to the frame end (glow fine, r19 catch-up median 16), 8 / 8 (final glow 10-12), 4 / 8 (final glow 38: small
   slices split rows; 31k cycles per region).

### Glow (d4_probe, final build; re-render frames med / p90 / max; D3 from "## D3")
| room | D3 | D4 | glow lag px | regions + skips / s | region cyc med (points, changed points) |
|---|---|---|---|---|---|
| r01 / r02 / r03 | 3/4/31 / - / - | 1/2/33 / 1/2/34 / 1/2/76 | 0.5 / 0.8 / 1.2 | 26.4+19.2 / 18.8+10.2 / 8.0+5.6 | 11505 (64, 7) / 11815 / 9274 |
| r04 / r05 / r06 | 9/77/77 / - / - | 2/5/65 / 1/2/55 / 3/6/138 | 0.8 / 0.5 / 0.6 | 3.8+2.4 / 15.2+10.6 / 2.2+0.6 | 10252 / 11614 / 14172 |
| r07 / r08 / r09 | - | 1/2/74 / 2/5/14 / 1/3/6 | 3.0 / 8.4 / 1.6 | 8.2+6.6 / 13.4+4.4 / 14.6+7.8 | 9839 / 12247 / 11901 |
| r10 / r11 / r12 / r13 | 3/10/153 / - / - / - | 1/2/152 / 2/3/33 / 2/5/8 / 2/4/42 | 2.3 / 1.0 / 3.9 / 1.6 | 7.8+5.0 / 18.2+8.4 / 15.2+3.4 / 10.4+2.6 | 8939 / 11813 / 12493 / 13225 |
| r14 / r15 / r16 | 15/46/82 / - / 11/59/79 | 5/8/43 / 2/5/76 / 4/7/64 | 8.2 / 4.4 / 3.1 | 6.8+0.8 / 10.4+2.8 / 6.4+1.0 | 16594 (64, 16) / 11087 / 15733 |
| r17 / r18 / r19 | - / - / 28/75/75 | 3/5/53 / 3/6/24 / 5/7/8 | 2.6 / 5.1 / 7.1 | 10.0+1.8 / 12.8+1.8 / 7.4+0.8 | 14091 / 13044 / 15215 (72, 16) |
| r20 / final | 42/91/91 / **94/119/119** | 5/9/62 / **7/61/69** | 7.5 / 12.3 (D3 68.4) | 5.6+0.6 / 3.6+0.4 | 14056 / 17662 (72, 20) |
Targets: median <= 4 in r01-r13 (max 2), <= 8 in r14-final (max 7). p90 / max outliers are walk starts / cell changes under load (final
p90 61: frames where Aura waits for its gate). Glow at the 16 px clamp: 0 % (r14 1 %, final 4 %; D3 final ~40 % with the 2-step Aura).
Lag frames 0 in all 21 walks. Max line: LightWork exit 201-212, GRun exit <= 208, Aura end <= 194.

### Guard catch-up (smoke_lighting, final build; median / p90 / max (episodes))
| room | D4 | glow-starved build (same code, slice 0, glow unit 2 lines) |
|---|---|---|
| r02 / r04 / r06 / r08 | 5/9/10 (13) / 3/10/11 (15) / 6/9/15 (23) / 9/20/21 (14) | 6/14/15 / 3/13/15 / 6/11/20 / 7/14/17 |
| r09 / r10 / r13 | 7/10/16 (11) / 3/7/7 (12) / 7/11/12 (27) | 6/13/18 / 3/6/10 / 8/16/24 |
| **r12** | **24/39/53 (12)** | **26/44/58** |
| r14 / r15 / r16 / r17 | 8/23/25 (16) / 10/23/59 (44) / 15/29/49 (32) / 10/27/58 (38) | 10/18/20 / 10/24/45 / 11/31/37 / 10/16/44 |
| r18 / r19 / r20 | 9/17/20 (17) / 14/33/45 (74) / 10/24/29 (24) | 10/23/34 / 12/20/32 / 10/21/40 |
| **final** | **18/43/58 (63)** | **13/43/57** |
r12 and final fail the section 5 limits also with the glow starved (r12 median 26, final p90 43): their bound is guard-job throughput
("max to commit" r12 29, final 50 frames; D3 open item 1), not the glow. The glow costs final ~+5 on the median. Runs move by a few frames
(the walk waits for light_done); r15 / r16 / r19 crossed a limit in single runs of other configs (r15 max 102 at slice 4, r19 median 16-17
at 16 / hog and with the job-unit late check).

### Space / RAM
Bank $1B row ends `$1BB7AC` (83 B left), code row `$1FC2EB` (276 B left), data row `$1FFF87` (120 B left). RAM code 139 of 256 B.
RAM: `light_l3gtab` `$7FAE00-$7FB6BF` (new row), `light_l3list` / `light_l3reg` / `light_l3code` / `light_l3ok` rows updated; `light_l3new`
unused.

`make build`: `freespace: 93 region(s), 146 org(s) checked, 317515 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting catch-up only: `r12 median 24 (<= 15) p90 39 (<= 40) max 53 (<= 90);
final median 18 (<= 15) p90 43 (<= 40) max 58 (<= 90)`; 0 tile mismatches in 504 checks. Solutions 21/21 with lagged frames 0, meter
budget 21/21, must_not 122 + 9 pass.

### Open
1. r12 / final catch-up: guard-job throughput (D3 open item 1), fails with the glow starved too. Needs a cheaper all-around job or a
   director / designer decision.
2. Final glow p90 61: the Aura gate (V0 < 176) is often missed in final (spare 28 lines); a cheaper ring update (~8 of the 20 lines) would help.

## E rev5

Task: design/lighting.md revision 5 (SA-1 cartridge): 4.5 for every carrier again. Guard g: its own lattice l_g (4.1 of its committed map
alone), its own d from its centre pixel (sprite origin + (8, 8), as Hush_LightSig), clamp +-16, **D = 1**; amber = max over guards of V_g;
tiles via the complete LUTs (substitutes incl.); glow unchanged. Step 0 first: `!LIGHT_WIN0` = 1 (BG1 light window at tilemap tiles
0..31 x 0..27, one DMA per row span): `make build` ok, `make test` **PASS=39 FAIL=0 SKIP=2**.

### Design (simplest exact on the SA-1)
1. **Lattice per guard** (`light_l3glat` `$41:0000`, 8 x 1292 B, pair-coded like the glow): at each job end (`Hush_LightCommit .end` ->
   `Hush_L3GLat`, bank $03) lattice rows `2 JBY0 - 1 .. 2 JBY1 + 3`, cell columns `JBX0 .. JBX1 + 1` are rebuilt by the existing
   `Hush_L3Row` from `light_scr` (the job-box clear now covers box rows +-1, so every cell read is the new light or 0). Then its bbox (non-zero
   cells of GMAP[g] -> points `2cx .. 2cx + 2`), cell (the committed signature's, `$FF` class 0) and its RDM bit. A pass reads a lattice
   only within bbox +-1, which the rebuild always covers; the whole amber RAM is zeroed by the SA-1 once per room load (`Hush_L3AZero`).
2. **Pass** (`Hush_L3AStep`, a unit of `Hush_L3Unit` after a running job, before the tile pass): pick = WD refreshed (`Hush_L3Want`, now
   all 9 carriers), every guard marked or with WD != RD takes RD := WD; its old drawn box and its new box N (exact support of V_g:
   `[LB0 - 1 + ceil(d / 8), LB1 + ceil(d / 8)]` per axis) add their rows to per-row spans; drawn := N. Rows (one per unit): NEW := max over
   all guards whose drawn box meets the row (RAM loops `Hush_L3GA` s > 0 / `Hush_L3PA` s = 0, the B2b LERP8 / LERP formula), then CA
   compare; changed points rewrite the index words QH / QL (`98 (7a + b)`, `2 (7c + d)`) and mark their tiles (`light_tdirty`). Exact:
   every point a dirty guard's old or new light touches is recomputed from all guards.
3. **Tiles**: one tile loop for both kinds (`Hush_L3Tile`, single quadrant now): amber index `QH(tx, ty) + QL(tx, ty + 1)` (0 = no amber
   corner -> violet word), word = `light_l3luta` (BW-RAM copy of Hush_LightLutA, the complete LUT incl. substitutes). L2 pair grids, LUTF,
   Hush_LightBuild / Amb / AmbRow / MarkRow / LateC removed; the commit only keeps GMAP / COMP (logic) current.
4. `light_done` also needs no pass running and WD = RD for all 9 carriers.

Bugs found on the way (both fixed, both caught in the emulator): asar emits `MVN a,b` as `54 a b` (a = destination; the first LutA copy
went to ROM, every amber tile word was 0); a 16-bit `STA $0E` in the pick overwrote its "span added" flag at `$0F` (passes never started).

### Results (`src/dev/e5_probe.lua`, all 21 rooms: jump, 30 frames, walk left / up / right / down 75 frames each, then 24 x (10 frames of
walking, wait for light_done <= 400 frames, full BG1 compare with the rev 5 oracle); 136 s)
- **Rev 5 oracle** (amber = max over guards of V_g from GMAP[g] + rendered d, violet = displaced glow, LUT words, rendered d vs 4.5 item 2
  for every carrier): **503 checks, 450688 tile words, 0 mismatches**.
- "render frames" = frames from a carrier's first move after its last render to the next render (= frames between renders while it keeps
  moving); "lag px" = mean |wanted centre - rendered centre| over frames x carriers with light; clamp = carrier-frames with |RD| = 16.
  Catch-up = section 5 episodes with "drawn in VRAM" tracked per guard through pass end -> tiles derived -> published -> retired (uploaded).

| room | guard render frames med/p90/max (n) | guard lag px | glow render med/p90/max | at clamp | lag frames | catch-up med/p90/max (n) |
|---|---|---|---|---|---|---|
| r01 / r03 / r07 / r11 | no moving lit guard | 0.0 | 1/1/33 .. 1/1/76 | 0 % | 0 | r03 2/3/3, r07 2/4/4 |
| r02 / r04 / r05 / r06 | 0/1/60 (167) / 0/1/2 (175) / 0/0/0 (12) / 0/1/61 (272) | 0.0 / 0.7 / 0.0 / 0.0 | 1/1/32 / 1/60/64 / 1/1/54 / 1/1/139 | <= 0.2 % | 0 | 2/4/4 / 2/3/4 / 4/10/10 / 3/4/6 |
| r08 / r09 / r10 | 0/1/60 (142) / 0/1/60 (128) / 0/1/56 (111) | 0.3 / 0.1 / 0.5 | 1/1/64 / 1/1/32 / 1/1/76 | <= 0.2 % | 0 | 3/4/6 / 3/5/7 / 1/2/3 |
| r12 / r13 / r14 | 0/1/3 (18) / 0/1/60 (322) / 0/0/2 (143) | 0.0 / 0.0 / 0.2 | 1/1/22 / 1/1/43 / 1/1/43 | <= 0.2 % | 0 | 13/25/34 / 3/4/5 / 3/5/8 |
| r15 / r16 / r17 | 0/1/137 (298) / 0/1/61 (200) / 0/1/2 (231) | 1.2 / 0.2 / 0.0 | 1/1/70 / 1/1/64 / 1/1/55 | 0.8 / 1.2 / 0 % | 0 | 3/5/7 / 4/23/39 / 3/5/9 |
| r18 / r19 / r20 / final | 0/1/60 (119) / 0/0/2 (524) / 0/1/61 (169) / 0/0/5 (315) | 0.0 / 0.0 / 0.4 / 0.5 | 1/1/22 / 1/1/55 / 1/1/64 / 1/1/77 | 0 / 0 / 0.2 / 1.0 % | 0 | 4/20/28 / 3/7/33 / 3/5/9 / 3/6/25 |

Reading: every carrier, in every room, is re-rendered with its current displacement in the frame after it moves (median 0-1, p90 <= 1
frame, so ~0.75 px per update at patrol speed); maxes are single events (room start / a job running first). Catch-up per guard is within
15 / 40 / 90 in all rooms. 0 lag frames (21 walks; solution replays below). SA-1 busy (job entry -> exit, lines per frame, mean / max):
r19 176 / 544, final 164 / 528, r13 112 / 318 (runs over a frame are cut by the next post; no post was skipped). `src/dev/e5_nmi.lua`
(sa1_probe on r13 / r15 / r19 / r20 / final): NMI end max line 255-257 (vblank ends 261, `LIGHT_NMIEND` 258 caps the rows: 8-10 tile rows
per uploading NMI median, max 26), logic end max 207, lag 0, skip 0.

### make test
`make build`: `freespace: 106 region(s), 158 org(s) checked, 318809 changed byte(s) diffed: ok`, `built build/hush.sfc`.
`make test`: `PASS=38 FAIL=1 TIMEOUT=0 SKIP=2`. FAIL = smoke_lighting, **expected**: its amber oracle is still rev 4 (undisplaced composite
lattice); `22879 of 451584 tile words differ` (first: r02 t=2, amber shifted by the guard's d). Everything else in it passes on this build
(GMAP vs rules, composite, glow cell / d, VRAM = light_tiles). Solutions 21/21 with lagged frames 0, meter budget 21/21, must_not 122 + 9.
**For qa (catch-up rule):** the test's "shown" proxy is global (no tile row pending and `light_dirty` = 0). With every guard light moving
every frame the pipeline is legitimately never idle in r19 / r12, so that proxy reports r19 20/68/134 and r12 12/53/67 although the
per-guard measurement above (r19 3/7/33, r12 13/25/34) is within the limits. A per-guard "drawn" signal is needed in the test; the probe's
definition (Hush_L3ARow_end / Hush_LightPub_publish / _retire, labels added for it) is one option.

### Space / RAM
New ROM row `$03EBA0-$03F370` (vanilla room object data of rooms $0100-$010C, rooms.asm:908-924; ends `$03F0A3`, 717 B left). Code row ends
`$1FC32F` (208 B left), data row `$1FFE62` (413 B left), TRow row `$1FC999` (102 B left), RAM code 143 / 256 B. RAM (docs/ram_map.md):
`light_l3glat` `$41:0000`, `light_l3ca` `$41:2860`, `light_l3qh` / `ql` `$41:2E00` / `$41:3540`, `light_l3ast` `$41:3D00`,
`light_l3aspan` `$41:3D40`, `light_l3aconst` `$41:3D80`, `light_l3luta` `$41:9000` (was `light_lutf`), `light_l3new` used again;
`$41:8000-$41:8FFF` (pair grids) free. Room load: the SNES no longer zeroes the 4 KB pair grids; the SA-1 zeroes 15.5 KB of amber RAM in
its first light frame of the room.

### Probes (src/dev)
`e5_probe.lua` (all rooms, the numbers above), `e5_quick.lua` (5 rooms), `e5_out.lua` (render outliers), `e5_nmi.lua` (sa1_probe subset),
`e5_prof.lua` (SA-1 lines per unit kind: r19 rows 85, pick 20, publish 22, tiles 18, glow 10, jobs 6, lattices 8 lines per frame),
`e5_dbg.lua` (debug dump of the pass state).

### Open
1. smoke_lighting: amber rule rev 4 -> rev 5 and a per-guard catch-up signal (qa).
2. If more SA-1 headroom is wanted: run the RAM loops from I-RAM (`$00:3540-$36FF` is free) instead of BW-RAM.
