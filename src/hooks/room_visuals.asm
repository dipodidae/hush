; =============================================================================
; HOOK: room_visuals  (palette sets per floor / lighting)
;
; T0 (design/tiles.md): the wall-face / pillar / exit tile words (vanilla objects $07, $B8, $B9) and the E5 decoration-variant machinery (hijacked
; diagonal objects $09/$0A, Hush_DrawVariant, type1_routine / type1_data_offset rewrites, variant table at $009F72) are GONE: the window is now
; written by Hush_Blit from per-room cell data (src/hooks/roomload.asm), collision comes from the rewritten UnderworldTileTypes (build/rooms_gen.asm).
; Their ledger rows were removed; the vanilla bytes are untouched again.
;
; Site 4 - UnderworldPaletteSets rows 1-5
; Address:  $0ED464, 20 bytes (row n = $0ED460 + 4n; byte 0 = BG palette id = 2 x pal_dungeon_NN, bytes 1-3 = sprite palettes)
; Replaces: `02 00 03 01 | 04 00 0A 01 | 06 00 01 07 | 0A 02 02 07 | 04 04 03 0A`   vendor/usdasm/bank_0E.asm:10412-10418 (rows 0x01-0x05)
; Does:     rows 0-5 all carry the sprite bytes `00 03 01` of row 0 (so the OBJ palettes are identical for every variant) and BG palette
;           ids 0, 2, 4, 6, 8, 10 = pal_dungeon_00..05. Room header byte 1 picks the row (roomgen: floor 1-3, dark = 0-2, lit = 3-5).
;           Row 0 is vanilla `00 00 03 01` and is not touched.
;
; Space:    src/FREESPACE.md hook row $0ED464
; =============================================================================

org $0ED464
    db $02, $00, $03, $01                    ; row 1: pal_dungeon_01 (dark, floor 2)
    db $04, $00, $03, $01                    ; row 2: pal_dungeon_02 (dark, floor 3)
    db $06, $00, $03, $01                    ; row 3: pal_dungeon_03 (lit, floor 1)
    db $08, $00, $03, $01                    ; row 4: pal_dungeon_04 (lit, floor 2)
    db $0A, $00, $03, $01                    ; row 5: pal_dungeon_05 (lit, floor 3)
