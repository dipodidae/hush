; =============================================================================
; HOOKS: roomload  (E6: only the visible window is uploaded / turned into collision; the vanilla loops did all four quadrants)
;
; Measured (tests/dev/room_load_profile.lua) after transition.asm had skipped the graphics: LoadAndDrawRoom 12 frames, LoadEveryObjectAttributeSet 15 of the remaining 32.
; A HUSH room is the visible 32 x 28 tile window (tiles x 16..47, y 18..45 of the 64 x 64 tile room, docs/engine_notes.md section 1); the scroll never changes, so nothing else is ever seen.
;
; Hook 1  $02C583 (4 bytes, LoadAndDrawRoom)  `JSL LoadAndBuildRoom` (22 3A 87 01, bank_02.asm:12700-12705)
;         -> JML Hush_BuildRoom. LoadAndBuildRoom runs as before (object drawing into the tile buffers $7E2000 = BG2 layer, $7E4000 = BG1 layer). Then, instead of the four
;         rounds of {TilemapPrep_NotWaterOnTag, NMI_UploadTilemap_long, BuildBG2QuadrantForUpload, NMI_UploadTilemap_long} (bank_02.asm:12710-12719; each round copies a 2 KB
;         quadrant through $7E1000), the window rows are DMA'd straight from the buffers to the BG1 / BG2 tilemaps in VRAM (forced blank): 28 rows x 2 screens x 2 layers = 112
;         DMAs of 16 words. VRAM layout (UnderworldTilemapQuadrantVRAMIndex + TilemapUpload_HighBytes, bank_00.asm:2944-3105, 4107-4130): BG2 tilemap at word $0000, BG1 at $1000 (TilemapUpload_HighBytes[$11] = $10 = VMADDH: the "VRAM $2000" comments of the table are byte addresses),
;         each a 2 x 2 arrangement of 32 x 32 word screens (+$0000 TL, +$0400 TR, +$0800 BL, +$0C00 BR). Ends like the vanilla loop (jump to $02C5A7: restore $9B ...), with
;         $0418 = 0 and $045C = $10 as the loop leaves them. VRAM outside the window keeps the previous room's (never visible) tiles.
; Hook 2  $02827D (4 bytes, Module06_UnderworldLoad)  `JSL LoadEveryObjectAttributeSet` (22 BF B8 01, bank_02.asm:421)
;         -> JSL Hush_AttrSet: the collision map $7F2000 (one byte per 8x8 tile = UnderworldTileTypes[tile id], LoadBasicObjectAttributess_full, bank_01.asm:10679-10776, with its
;         "types $10-$1B take the flip bits" rule) is computed for the 896 window tiles only (vanilla: 4096 iterations over both layers, $7F3000 stays 0: the BG1 layer is floor only).
;         Outside the window $7F2000 keeps its power-on / intro value 0 (walkable but unreachable behind the solid rim). Then the vanilla LoadComplexObjectAttributes and
;         LoadDoorObjectAttributes run (via Hush_AttrTail in bank 01: they are JSR-only; HUSH rooms have no stairs / doors so they only clear the counters), the crystal-peg flip
;         and `STZ $0200` as at the end of LoadEveryObjectAttributeSet (bank_01.asm:10640-10655).
; Hook 3  free block NULL_01B53C (bank_01.asm:9965): Hush_AttrTail = JSR $B967 : JSR $BE17 : RTL (7 bytes after Hush_DrawVariant).
;
; Space: src/FREESPACE.md rows $02C583, $02827D, $01B53C (extended), $0FFE72 (NULL_0FFE72 "FREE ROM: 0x018E", bank_0F.asm:5337; all $FF, no references).
; =============================================================================

org $02C583
    JML Hush_BuildRoom

org $02827D
    JSL Hush_AttrSet

org $01B54F
Hush_AttrTail:
    JSR.w $B967                          ; LoadComplexObjectAttributes
    JSR.w $BE17                          ; LoadDoorObjectAttributes
    RTL
assert pc() <= $01B560                   ; the free block NULL_01B53C ends at $01B55F

org $0FFE72
Hush_BuildRoom:                          ; M = X = 8 bit, in LoadAndDrawRoom
    JSL $01873A                          ; LoadAndBuildRoom
    SEP #$20
    LDA.b #$80 : STA.w $2115             ; VMAIN: word writes, increment after the high byte
    LDA.b #$7E : STA.w $4304             ; DMA0 source bank
    REP #$30
    LDA.w #$1801 : STA.w $4300           ; DMA0: mode 1 (two registers), B-bus $18 = VMDATA
    LDA.w #$2000 : STA.b $08             ; layer 0: BG2 buffer -> VRAM word $0000
    LDA.w #$0000 : STA.b $06
    JSR .layer
    LDA.w #$4000 : STA.b $08             ; layer 1: BG1 buffer -> VRAM word $1000
    LDA.w #$1000 : STA.b $06
    JSR .layer
    SEP #$30
    STZ.w $0418
    LDA.b #$10 : STA.w $045C
    STZ.w $0200
    JML $02C5A7                          ; PLA : STA $9B : STZ $17 : STZ $0200 : STZ $B0 : RTS (the end of LoadAndDrawRoom)

.layer                                   ; $08 = buffer, $06 = VRAM base word; M = X = 16 bit
    LDA.b $08 : CLC : ADC.w #(18*128+32) : STA.b $00      ; source of (tx 16, ty 18)
    LDA.b $06 : CLC : ADC.w #(18*32+16)  : STA.b $02      ; VRAM word of (tx 16, ty 18) in the left screen
    LDX.w #28
.row
    LDA.b $02 : STA.w $2116              ; tiles 16..31: left screen
    LDA.b $00 : STA.w $4302
    LDA.w #32 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    LDA.b $02 : CLC : ADC.w #($0400-16) : STA.w $2116     ; tiles 32..47: the right screen, column 0
    LDA.b $00 : CLC : ADC.w #32 : STA.w $4302
    LDA.w #32 : STA.w $4305
    SEP #$20 : LDA.b #$01 : STA.w $420B : REP #$20
    LDA.b $00 : CLC : ADC.w #128 : STA.b $00
    LDA.b $02 : CLC : ADC.w #32  : STA.b $02
    DEX
    CPX.w #14 : BNE +
    LDA.b $02 : CLC : ADC.w #$0400 : STA.b $02            ; row 32: bottom screens (skip the right screen of the top pair)
+   CPX.w #0 : BNE .row
    RTS

Hush_AttrSet:                            ; M = X = 8 bit
    REP #$30
    LDA.w #$2000 : STA.b $00             ; [$00] = $7E2000, the BG2 tile buffer
    LDA.w #$007E : STA.b $02
    LDY.w #(18*128+32)                   ; byte offset of (tx 16, ty 18)
    LDA.w #(18*64+16) : STA.b $0A        ; collision map index of the same tile
    LDA.w #28 : STA.b $0C                ; rows
.arow
    LDA.w #32 : STA.b $0E                ; columns
.acol
    LDA.b [$00],Y : STA.b $04            ; tile word
    AND.w #$03FF : TAX
    SEP #$20
    LDA.l $7EFE00,X                      ; tile type
    CMP.b #$10 : BCC .store
    CMP.b #$1C : BCS .store
    STA.b $06
    LDA.b $05                            ; types $10-$1B: the flip bits of the tile select the variant
    ASL A : ROL A : ROL A : AND.b #$03
    ORA.b $06
.store
    LDX.b $0A
    STA.l $7F2000,X
    REP #$20
    INC.b $0A
    INY : INY
    DEC.b $0E : BNE .acol
    TYA : CLC : ADC.w #64 : TAY          ; the 32 tiles right of the window
    LDA.b $0A : CLC : ADC.w #32 : STA.b $0A
    DEC.b $0C : BNE .arow
    SEP #$30
    JSL Hush_AttrTail
    SEP #$30
    LDA.l $7EC172
    BEQ .nopegs
    JSL $01C22A                          ; FlipCrystalPegAttributes
    SEP #$30
.nopegs
    STZ.w $0200
    RTL
Hush_RoomLoad_End:
assert pc() <= $0FFFA0                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
