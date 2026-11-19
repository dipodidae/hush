; =============================================================================
; HOOK: room_visuals  (distinct tiles for wall faces, pillars and exit markers; palette sets per floor / lighting)
;
; Collision is a property of the TILE IDS (`UnderworldTileTypes` + id, copied to $7EFE00 at room load; LoadBasicObjectAttributess,
; bank_01.asm:10661-10760), not of the object that drew them. The vanilla objects below are 2x2-tile objects that HUSH never uses
; (no vanilla room is ever loaded); roomgen (tools/roomgen.py OBJ_KINDS) emits them for the cells that need the new art. Tile word =
; `vhopppcc cccccccc` (v/h flip, o = BG priority, ppp = palette row, c = tile id); data order = TL, BL, TR, BR (RoomDraw_Rightwards2x2,
; bank_01.asm:4654-4668: `[$BF],Y [$CB],Y [$C2],Y [$CE],Y`). All ids keep the vanilla tile TYPE the cell needs (checked in the ROM):
; ids $24 $25 $2C $2D $3C $3D = type $01 (solid), ids $C0 $C1 $D0 $D1 = type $00 (floor) -> $7F2000 is identical to the plain-wall build.
;
; Site 1 - object $07 "wall face" (Rightwards2x2_1to16, data obj0388)
; Address:  $009EDA, 8 bytes
; Replaces: `dw $1C6A, $1C7A, $1C6A, $1C7A`   (6A 1C 7A 1C 6A 1C 7A 1C)  vendor/usdasm/bank_00.asm:4864-4865
; Does:     top row = the ceiling tile $015 (palette 7, priority 1) twice, bottom row = face tiles $024 (even column) / $025 (odd column),
;           palette 6, priority 1. Emitted for a `#` cell whose cell below is floor.
;           GFX_00 cells: ceiling (5,1), face A (4,2), face B (5,2).
;
; Site 2 - objects $B8 / $92 "pillar" (data obj1F52, shared by the rightwards and downwards 2x2 object)
; Address:  $00BAA4, 8 bytes
; Replaces: `dw $19D0, $19D2, $19D1, $19D3`   (D0 19 D2 19 D1 19 D3 19)  vendor/usdasm/bank_00.asm:6952-6953
; Does:     GFX_00 block (12,2) = tiles $02C $02D / $03C $03D, palette 5, priority 0 (Link and guards are drawn in FRONT of a pillar).
;
; Site 3 - objects $B9 / $93 "exit marker" (data obj1F5A)
; Address:  $00BAAC, 8 bytes
; Replaces: `dw $0DD4, $0DD6, $0DD5, $0DD7`   (D4 0D D6 0D D5 0D D7 0D)  vendor/usdasm/bank_00.asm:6957-6958
; Does:     GFX_06 block (0,0) = tiles $0C0 $0C1 / $0D0 $0D1, palette 4, priority 0, floor type $00 (walkable, never solid).
;
; Site 4 - UnderworldPaletteSets rows 1-5
; Address:  $0ED464, 20 bytes (row n = $0ED460 + 4n; byte 0 = BG palette id = 2 x pal_dungeon_NN, bytes 1-3 = sprite palettes)
; Replaces: `02 00 03 01 | 04 00 0A 01 | 06 00 01 07 | 0A 02 02 07 | 04 04 03 0A`   vendor/usdasm/bank_0E.asm:10412-10418 (rows 0x01-0x05)
; Does:     rows 0-5 all carry the sprite bytes `00 03 01` of row 0 (so the OBJ palettes are identical for every variant) and BG palette
;           ids 0, 2, 4, 6, 8, 10 = pal_dungeon_00..05. Room header byte 1 picks the row (roomgen: floor 1-3, dark = 0-2, lit = 3-5).
;           Row 0 is vanilla `00 00 03 01` and is not touched.
;
; Space:    src/FREESPACE.md hook rows $009EDA, $00BAA4 and $0ED464
; =============================================================================

org $009EDA
    dw $3C15, $3824, $3C15, $3825

org $00BAA4
    dw $142C, $143C, $142D, $143D            ; pillar
    dw $10C0, $10D0, $10C1, $10D1            ; exit marker

org $0ED464
    db $02, $00, $03, $01                    ; row 1: pal_dungeon_01 (dark, floor 2)
    db $04, $00, $03, $01                    ; row 2: pal_dungeon_02 (dark, floor 3)
    db $06, $00, $03, $01                    ; row 3: pal_dungeon_03 (lit, floor 1)
    db $08, $00, $03, $01                    ; row 4: pal_dungeon_04 (lit, floor 2)
    db $0A, $00, $03, $01                    ; row 5: pal_dungeon_05 (lit, floor 3)
