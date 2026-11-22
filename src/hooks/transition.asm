; =============================================================================
; HOOKS: transition  (E6: fast room load + short fade-out / fade-in instead of the 160-frame vanilla load and iris)
;
; The vanilla room load (Module05 -> Module06 -> submodule $0F iris) took ~160 frames (docs/engine_notes.md section 7). Measured split
; (tests/dev/room_load_profile.lua, frames of forced blank): LoadDefaultGraphics 17, DecompressSword/Shield/FollowerGraphics 15,
; DecompressAnimatedUnderworldTiles 6, InitializeTilesets 42, LoadEveryObjectAttributeSet 15, LoadAndDrawRoom 12, then the iris 44.
; All HUSH rooms use the same blockset ($00) and sprite set ($04), so after the first (full) load the graphics in VRAM and their WRAM
; buffers are already right. hush_gfx = 1 says so; while it is set a room load skips the graphics work and runs only what is room
; specific (tilemaps, collision, palettes, sprites, Link).
;
; Hook 1  $028158 (4 bytes, Module05_LoadFile)  `JSL LoadDefaultGraphics` (22 D0 E2 00, bank_02.asm:~0281:58)
;         -> JML Hush_M05Gfx. It runs the original 7 JSLs of Module05 (LoadDefaultGraphics, Sprite_LoadGraphicsProperties,
;         LoadDefaultTileTypes, DecompressSwordGraphics, DecompressShieldGraphics, InitializeLink, LoadFollowerGraphics) or, with
;         hush_gfx set, only the three cheap room-independent ones, then JML $028174 (the instruction after them).
; Hook 2  $028279 (4 bytes, Module06_UnderworldLoad)  `JSL DecompressAnimatedUnderworldTiles` (22 37 D3 00) -> JSL Hush_DecompAnim (skipped with hush_gfx)
; Hook 3  $028286 (4 bytes, Module06_UnderworldLoad)  `JSL InitializeTilesets` (22 9B E1 00) -> JSL Hush_InitTilesets (skipped with hush_gfx;
;         a real run sets hush_gfx := 1)
; Hook 4  $02931D (7 bytes, Module07_0F_LandingWipe, the front half of the submodule)  `LDA.b $B0 : ASL A : TAX : JSR (.vectors,X)`
;         (A5 B0 0A AA FC 19 93, bank_02.asm:3634-3639) -> JSL Hush_Wipe + 3 NOPs. Submodule $0F used to be the 44-frame iris spotlight
;         (IrisSpotlight_open / _ConfigureTable); Hush_Wipe replaces it with a 6-pass brightness fade (in after a load, out before an advance). The
;         rest of the submodule (HandleLinkAnimation, DrawLink) still runs after it.
;
; Hook 5  $028856 (4 bytes, the tail of the player-control submodule: DrawLink, then HandleItemRefills, then HandleFloorIndicator, bank_02.asm:1503-1506)
;         `JSL HandleItemRefills` (22 75 DB 0D) -> JSL Hush_Refills = the same call, then Hush_HudClean. HandleItemRefills (RefillLogic, bank_0D.asm:12727+) rewrites the
;         HUD digits every frame, so the HUD cells HUSH does not use have to be blanked after it (it runs after Hush_FrameHook in the same pass).
;
; Hook 6  $018A1F (5 bytes, RoomDraw_FloorChunks, bank_01.asm:1498) `LDY.b $0C : LDA.w RoomQuadrantDataOffset,Y` (A4 0C B9 02 9B) -> `JML Hush_FloorChunks` + NOP. RoomDraw_DrawFloors calls
;         it twice (the first call by JSR for the lower layer = BG1 buffer $7E4000, the second by falling through for the upper layer = BG2 buffer $7E2000; 4.8 frames together, the biggest
;         part of what is left after the graphics skip). All HUSH rooms have floor byte $22 (tools/roomgen.py FLOOR_BYTE): both layers get floor $20 (RoomDraw_DrawFloors stores
;         `$0490` = the lower layer's floor, `$046A` = the upper one's, both x 16). While hush_gfx is set (a room was fully loaded before):
;           * lower call, `$0490` = $20: skipped. The BG1 buffer is never drawn on by HUSH objects, so it still holds the floor;
;           * upper call, `$046A` = $20 (and `$0490` = $20): the BG2 floor equals the BG1 floor, so the 28 window rows (tiles x 16..47, y 18..45; 64 bytes each, MVN) are copied from the BG1
;             buffer; the BG2 buffer outside the window keeps the previous room's tiles (never visible, never read: Hush_BuildRoom / Hush_AttrSet use the window only);
;         both end with JML $018A43 (the RTS of RoomDraw_FloorChunks) after `$0C := 8` (what the vanilla loop leaves). Anything else runs the replaced instructions and continues at $018A24.
;
; Flow of an advance (exit cell touched): Hush_FrameHook -> Hush_StartAdvance(next): hush_trans := 1 (fade out), $11 := $0F (submodule
;   $0F freezes the guards and Link, like the iris did: the AI returns early while $11 != 0) -> N_OUT passes of Hush_Wipe lower the brightness
;   $13 -> Hush_LoadRoom(next) (Module05 -> fast Module06, one long pass of forced blank) -> Module06 ends with $11 = $0F -> hush_trans = 2:
;   N_IN passes of fade-in -> $11 := 0, the room plays. The last room starts Hush_Ending's module instead (ending.asm).
; Frozen while fading: guards are still drawn (HandleAllSprites runs in Hush_Wipe as it did in the iris), their AI does not run.
;
; RAM: docs/ram_map.md (hush_gfx, hush_trans, hush_tcnt, hush_next).
; Space: src/FREESPACE.md rows (hooks above; free block $0EF220).
; =============================================================================

!hush_room  = $7EC900
!hush_gfx   = $7EC90E
!hush_trans = $7EC90F
!hush_tcnt  = $7EC910
!hush_etimer = $7EC917
!hush_next  = $7EC911

!N_OUT = 6                               ; fade-out passes (brightness 12, 9, 6, 3, 0, then the load)
!N_IN  = 6                               ; fade-in passes (brightness 2, 5, 8, 11, 14, then 15 and the room plays).
                                         ; N_IN + 2 must stay a multiple of 4: the guards look at ((slot xor $1A) & 1 or 3); with the 20 main-loop passes of the old
                                         ; iris flow and the 8 of this one a room starts on the same $1A phase, which keeps the recorded solution replays valid (tests/dev/phase_probe.lua)

org $028158
    JML Hush_M05Gfx

org $028279
    JSL Hush_DecompAnim

org $028286
    JSL Hush_InitTilesets

org $02931D
    JSL Hush_LightWipe                   ; L1 (light.asm): Hush_Wipe, then the light colours + soft shadow palette before the first fade-in frame
    NOP : NOP : NOP

org $028856
    JSL Hush_Refills

org $018A1F                              ; RoomDraw_FloorChunks, first two instructions: `LDY.b $0C : LDA.w RoomQuadrantDataOffset,Y` (A4 0C B9 02 9B, bank_01.asm:1498-1500)
    JML Hush_FloorChunks
    NOP

; -----------------------------------------------------------------------------
org $0EF220
Hush_M05Gfx:                             ; M = X = 8 bit
    LDA.l !hush_gfx
    BNE .fast
    JSL $00E2D0                          ; LoadDefaultGraphics
    SEP #$30
    JSL $00FC41                          ; Sprite_LoadGraphicsProperties
    SEP #$30
    JSL $0E97D9                          ; LoadDefaultTileTypes
    SEP #$30
    JSL $00D2C8                          ; DecompressSwordGraphics
    SEP #$30
    JSL $00D308                          ; DecompressShieldGraphics
    SEP #$30
    JSL $07F13C                          ; InitializeLink
    SEP #$30
    JSL $00D423                          ; LoadFollowerGraphics
    SEP #$30
    JML $028174
.fast
    JSL $00FC41                          ; Sprite_LoadGraphicsProperties (cheap, 0.05 frame)
    SEP #$30
    JSL $0E97D9                          ; LoadDefaultTileTypes
    SEP #$30
    JSL $07F13C                          ; InitializeLink
    SEP #$30
    JML $028174

Hush_DecompAnim:                         ; Y = animated sheet id, set by the caller
    PHA
    LDA.l !hush_gfx
    BNE .skip
    PLA
    JML $00D337                          ; DecompressAnimatedUnderworldTiles (its RTL returns to Module06)
.skip
    PLA
    RTL

Hush_InitTilesets:
    LDA.l !hush_gfx
    BNE .skip
    JSL $00E19B                          ; InitializeTilesets
    SEP #$30
    LDA.b #$01
    STA.l !hush_gfx                      ; the HUSH room graphics are in VRAM now
.skip
    RTL

; -----------------------------------------------------------------------------
; Hush_StartAdvance: A = next room index ($FF = the ending). Called from Hush_FrameHook (M = X = 8, module 7, submodule 0).
Hush_StartAdvance:
    STA.l !hush_next
    LDA.b #$01
    STA.l !hush_trans                    ; fading out
    LDA.b #$00
    STA.l !hush_tcnt
    LDA.b #$0F
    STA.b $11                            ; submodule $0F: guards and Link frozen, Hush_Wipe runs
    STZ.b $B0
    LDA.b #$1B                           ; SFX3.1B (the secret chime of RoomTag_OperateKillDoor, bank_01.asm:12737): room cleared
    STA.w $012F
    RTL

; -----------------------------------------------------------------------------
; Hush_Wipe: submodule $0F (JSL from $02931D). M = X = 8 bit.
Hush_Wipe:
    SEP #$30
    JSL Hush_HudClean                    ; the HUD buffer the NMI uploads while fading is already clean
    SEP #$30
    JSL $068328                          ; HandleAllSprites (draws the frozen guards; the vanilla iris did this too)
    LDA.l !hush_trans
    CMP.b #$01
    BEQ .out
    LDA.l !hush_tcnt                     ; ---- fade in
    INC A
    STA.l !hush_tcnt
    CMP.b #!N_IN
    BCS .in_done
    STA.b $0F
    ASL A : CLC : ADC.b $0F              ; 3t
    DEC A
    STA.b $13                            ; 2, 5, 8, 11, 14
    RTL
.in_done
    LDA.b #$0F
    STA.b $13
    STZ.b $11                            ; the room plays from the next pass
    STZ.b $B0
    LDA.b #$00
    STA.l !hush_trans
    STA.l !hush_tcnt
    JSL Hush_RoomMusic                   ; feedback.asm: start the room's song (entrance row song byte; $FF = keep playing)
    RTL
.out                                     ; ---- fade out
    LDA.l !hush_tcnt
    INC A
    STA.l !hush_tcnt
    CMP.b #!N_OUT
    BCS .out_done
    STA.b $0F
    ASL A : CLC : ADC.b $0F              ; 3t
    EOR.b #$FF : INC A                   ; -3t
    CLC : ADC.b #$0F                     ; 12, 9, 6, 3, 0
    STA.b $13
    RTL
.out_done
    LDA.l !hush_next
    CMP.b #$FF
    BEQ .ending
    JSL Hush_LoadRoom                    ; Module05 next pass; hush_trans := 2 (fade-in after the load)
    LDA.b #$0F
    STA.b $11                            ; keep the rest of this Module07 pass out of Hush_FrameHook (Link still stands on the exit)
    RTL
.ending
    JSL Hush_BeginEnding                 ; ending.asm: module change; Hush_FrameHook ignores the rest of this pass ($10 != 7)
    RTL

; -----------------------------------------------------------------------------
; Hush_HudClean: JSL (any M/X, preserves P). Blanks the HUD cells HUSH does not use, in the HUD buffer $7EC700 that the NMI uploads every frame
; ($16 stays non-zero after RebuildHUD; the vanilla HUD code re-writes digits whenever a count changes, so this runs every gameplay frame after
; the player module, i.e. from Hush_FrameHook, and every fade pass from Hush_Wipe). Cells (docs/gfx/hud_map.md sections 2-3: buffer row 0 = tilemap row 2
; (icons), row 1 = row 3 (digits), 32 words per row, blank = $207F):
;   gem counter (always): icon col 9 = $7EC712, digits cols 8-10 = $7EC750-$7EC754
;   ink pot counter (until the room's cumulative tool mask has bit 2): icon cols 12-13 = $7EC718/1A, digits $7EC758/5A
;   dart counter    (until bit 1): icon cols 15-16 = $7EC71E/20, digits cols 15-16 = $7EC75E/60
Hush_HudClean:
    PHP
    REP #$30
    LDA.w #$207F
    STA.l $7EC712
    STA.l $7EC750 : STA.l $7EC752 : STA.l $7EC754
    LDA.l !hush_room : AND.w #$00FF
    ASL A : ASL A : ASL A : ASL A : ASL A
    TAX
    SEP #$20
    LDA.l Hush_RoomTable+18,X
    STA.b $00
    REP #$20
    LDA.b $00 : AND.w #$0004
    BNE .ink_given
    LDA.w #$207F
    STA.l $7EC718 : STA.l $7EC71A : STA.l $7EC758 : STA.l $7EC75A
.ink_given
    LDA.b $00 : AND.w #$0002
    BNE .darts_given
    LDA.w #$207F
    STA.l $7EC71E : STA.l $7EC720 : STA.l $7EC75E : STA.l $7EC760
.darts_given
    PLP
    RTL

Hush_Refills:                            ; JSL from $028856 (M = X = 8)
    JSL $0DDB75                          ; HandleItemRefills
    SEP #$30
    JSL Hush_HudClean
    SEP #$30
    JSL Hush_MeterFrame                  ; M5 (meter.asm): Hush_SaveLink (E7, feedback.asm: Link's position for Hush_Solid next frame), then the stealth meter + its HUD cells
    RTL

Hush_FloorChunks:                        ; JML from $018A1F; M = X = 16 bit, DB = $01
    SEP #$20
    LDA.l !hush_gfx
    REP #$20
    BEQ .vanilla
    LDA.w $0490
    CMP.w #$0020
    BNE .vanilla                         ; not the HUSH floor
    LDA.b $C0
    AND.w #$00FF
    CMP.w #$0040
    BNE .upper                           ; $C0 = high byte of the first row pointer: $40 = $7E4000 (lower layer), $20 = $7E2000 (upper)
    BRA .done                            ; lower layer: the BG1 buffer still holds the floor
.upper
    LDA.w $046A
    CMP.w #$0020
    BNE .vanilla
    PHB
    LDX.w #$4000+(18*128)+32             ; the window rows (tx 16..47) of rows 18..45: BG1 buffer -> BG2 buffer
    LDY.w #$2000+(18*128)+32
    LDA.w #28 : STA.b $08
-   LDA.w #63
    MVN $7E,$7E
    TXA : CLC : ADC.w #64 : TAX
    TYA : CLC : ADC.w #64 : TAY
    DEC.b $08
    BNE -
    PLB
.done
    LDA.w #$0008 : STA.b $0C
    JML $018A43                          ; RTS of RoomDraw_FloorChunks
.vanilla
    LDY.b $0C
    LDA.w $9B02,Y                        ; RoomQuadrantDataOffset,Y
    JML $018A24

; Hush_BeginEnding (JSL from Hush_Wipe when the last fade-out ends): module := $13 (ending.asm), state $B0 := 0.
Hush_BeginEnding:
    LDA.b #$13 : STA.b $10               ; module $13: Hush_EndingModule
    STZ.b $11
    STZ.b $B0
    LDA.b #$00
    STA.l !hush_gfx                       ; the font replaces the HUD graphics: the next game loads everything again
    STA.l !hush_trans
    RTL
Hush_Transition_End:
assert pc() <= $0EF400                       ; E6: the block must stay inside its src/FREESPACE.md row (pc = the first free byte)
