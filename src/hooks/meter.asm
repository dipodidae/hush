; =============================================================================
; HOOKS: meter  (M5: the stealth meter replaces hearts and health; design/pillars.md:42-122 "Stealth meter")
;
; Hook 1  NO DAMAGE
; Address:  $07807F (SNES LoROM), PC offset 0x03807F, 5 bytes: the entry of LinkControlHandler (runs every frame of the player module)
; Replaces: `LDA.w $0373 : BEQ .no_damage`   (AD 73 03 F0 77)   vendor/usdasm/bank_07.asm:109-111 (.no_damage = $0780FB, :195)
; Does:     `STZ.w $0373 : BRA .no_damage` (9C 73 03 80 77). The pending damage of Link ($0373) is dropped before it is applied: no
;           health loss, no hurt cry / i-frames, and the `.you_died` branch (bank_07.asm:170-188, module $12 = game over) can never run.
;           Pillars.md:79-85: vanilla damage is ignored, not converted. (Recoil set by a sprite still moves Link; HUSH guards set none, E2.)
;
; Hook 2  HUD BAR
; Address:  $0DFB94 (SNES LoROM), PC offset 0x06FB94, 6 bytes: UpdateHUDBuffer_skip_item, the start of the two heart-row passes
; Replaces: `SEP #$30 : LDA.b #FullHeartTiles : STA.b $0A`   (E2 30 A9 FD 85 0A)   vendor/usdasm/bank_0D.asm:17327-17331 (FullHeartTiles = $0DF9FD, :16995)
; Does:     `JSL Hush_MeterHud : BRA UpdateHUDBuffer_skip_hearts` ($0DFC09, bank_0D.asm:17408). Every vanilla HUD rebuild (RebuildHUD
;           bank_0D.asm:17139, HandleItemRefills bank_0D.asm:13011) draws the 8 meter cells instead of the hearts. The only other heart writer,
;           AnimateHeartRefill (bank_0D.asm:16551, $A3/$A4 flip tiles into $7EC768), runs only after `.keep_healing` (bank_0D.asm:12953), i.e.
;           with health < max at HandleItemRefills; Hush_FrameHook sets health := max earlier in the same frame and hook 1 removes every
;           damage, so it cannot run; and Hush_MeterFrame redraws the cells after HandleItemRefills every Module07 frame anyway.
;
; In-block call redirections (same size, inside existing HUSH blocks, no new ledger rows):
;   transition.asm  Hush_Refills      `JSL Hush_SaveLink`     -> `JSL Hush_MeterFrame`   (end of every Module07 frame, after the guards ran)
;   room_ctrl.asm   Hush_LoadRoom     `JSL Hush_ResetRuntime` -> `JSL Hush_MeterLoad`    (new game, debug jump, advance: refill)
;   guard_runtime   Hush_FastRestart  `JSL Hush_CountRetry`   -> `JSL Hush_MeterRestart` (caught / meter-empty restart: refill)
;
; Hush_MeterFrame (end of a Module07 frame, M = X = 8, preserves P):
;   * module 7, submodule 0 (a gameplay frame, the same test as tests/lib/meter.lua): health := max (criterion 9); the hit flash counts
;     down; per sprite slot the cooldowns count down and spr_aware ($0D80,X) is compared with hush_aprev: for a guard ($41-$43)
;     0->1 = small 4 (if hush_cd_small = 0; cd := 121), 0->2 / 1->2 = big 16 (if hush_cd_big = 0; cd := 121), anything else 0.
;     The cooldowns are decremented before the test, so a hit in frame H blocks the same size in H+1..H+120 and allows it from H+121
;     (pillars.md:65-66, :107-109; B-007).
;     The sum is taken off hush_meter (clamped at 0); a hit sets hush_mlost (the value before) and hush_mflash := 16; 0 sets hush_caught,
;     so Hush_Tick runs the normal caught restart next frame (criterion 7).
;   * module 7, any submodule: the 8 cells are drawn and the HUD upload flag $16 is kept set (NMI bank_00.asm:1951-1967).
; Hush_MeterHud (any M/X, preserves P): cells i = 0..7 at $7EC768 + 2i (BG3 row 3, cols 20-27, docs/gfx/hud_map.md:37); threshold 4(i+1):
;   meter >= t: filled $24A0 (violet), at meter <= 8 amber $34A0 while $1A bit 4 is set (alternates every 16 frames);
;   else hush_mflash > 0 and hush_mlost >= t: $34A0 (amber: just lost); else drained $24A2. Tile words from art (palette 1 violet, 5 amber).
; Hush_MeterRefill: meter := 32, mlost := 32, flash 0, cooldowns 0, hush_aprev := the current spr_aware (no false transition on entry).
;
; RAM: docs/ram_map.md "HUSH stealth meter" ($7EC950-$7EC98F); vanilla: $0373 (damage), $7EF36C/$7EF36D (health max / health),
;      $0D80 spr_aware, $0E20 spr_type, $1A frame counter, $16 HUD upload flag, $10/$11 module / submodule; scratch $00.
; Space: src/FREESPACE.md rows: hook $07807F-$078083, hook $0DFB94-$0DFB99, free $1BB1E0-$1BB33F (NULL_1BB1E0, bank_1B.asm:6-209;
;        all $FF in vanilla ROM, no references in vendor/usdasm).
; =============================================================================

!hush_caught = $7EC902

pushpc
org $07807F                              ; LinkControlHandler: `LDA.w $0373 : BEQ .no_damage`
    STZ.w $0373
    db $80, $0780FB-$078084              ; BRA .no_damage ($0780FB) as bytes: `BRA $0780FB` (numeric operand) assembled to a wrong offset and froze the game
assert pc() == $078084

org $0DFB94                              ; UpdateHUDBuffer_skip_item: `SEP #$30 : LDA.b #FullHeartTiles : STA.b $0A`
    JSL Hush_MeterHud
    db $80, $0DFC09-$0DFB9A              ; BRA UpdateHUDBuffer_skip_hearts ($0DFC09)
assert pc() == $0DFB9A
pullpc

org $1BB1E0
; -----------------------------------------------------------------------------
Hush_MeterFrame:                         ; JSL from Hush_Refills ($028856), M = X = 8
    JSL Hush_SaveLink                    ; the call this replaces (feedback.asm)
    PHP
    SEP #$30
    LDA.b $10 : CMP.b #$07 : BEQ +       ; the ending / a load was started this pass
    JMP .out
+   LDA.b $11 : BEQ +                    ; fades, menus: no meter logic
    JMP .draw
+   LDA.l $7EF36C : STA.l $7EF36D        ; criterion 9: health = max at the end of every gameplay frame
    LDA.l !hush_mflash : BEQ +
    DEC A : STA.l !hush_mflash
+   STZ.b $00                            ; units lost this frame
    LDX.b #$0F
.slot
    LDA.l !hush_cd_small,X : BEQ +
    DEC A : STA.l !hush_cd_small,X
+   LDA.l !hush_cd_big,X : BEQ +
    DEC A : STA.l !hush_cd_big,X
+   LDA.l $7E0D80,X : TAY                ; Y = spr_aware now
    CMP.l !hush_aprev,X : BEQ .next
    LDA.l $7E0E20,X : SEC : SBC.b #$41
    CMP.b #$03 : BCS .store              ; not a guard ($41-$43): no hit
    LDA.l !hush_aprev,X : BNE .from1
    CPY.b #$01 : BEQ .small              ; 0 -> 1
.from1
    CMP.b #$02 : BCS .store              ; from 2 / 3: never a hit
    CPY.b #$02 : BNE .store              ; 0 / 1 -> 2: big
    LDA.l !hush_cd_big,X : BNE .store
    LDA.b #121 : STA.l !hush_cd_big,X    ; 121: decremented before the test, so frames H+1..H+120 see 120..1 (blocked), H+121 sees 0 (B-007)
    LDA.b #16
    BRA .add
.small
    LDA.l !hush_cd_small,X : BNE .store
    LDA.b #121 : STA.l !hush_cd_small,X  ; see .from1 (B-007)
    LDA.b #4
.add
    CLC : ADC.b $00 : STA.b $00
.store
    TYA : STA.l !hush_aprev,X
.next
    DEX : BPL .slot
    LDA.b $00 : BEQ .draw
    LDA.l !hush_meter : STA.l !hush_mlost
    SEC : SBC.b $00 : BCS +
    LDA.b #$00                           ; clamp at 0
+   STA.l !hush_meter
    BNE +
    LDA.b #$01 : STA.l !hush_caught      ; empty: the caught restart, next frame (Hush_Tick)
+   LDA.b #16 : STA.l !hush_mflash
.draw
    JSL Hush_MeterHud
    LDA.b #$01 : TSB.b $16               ; HUD buffer upload stays on
.out
    PLP
    RTL

; -----------------------------------------------------------------------------
Hush_MeterHud:                           ; any M/X, preserves P; writes $7EC768-$7EC777, scratch $00
    PHP
    SEP #$30
    LDX.b #$0E                           ; X = 2 * cell
.cell
    TXA : ASL A : ADC.b #$04 : STA.b $00 ; threshold 4 * (cell + 1) (ASL of <= 14 leaves C = 0)
    LDY.b #$A0                           ; filled tile
    LDA.l !hush_meter : CMP.b $00 : BCC .lost
    CMP.b #$09 : BCS .violet             ; healthy: never amber
    LDA.b $1A : AND.b #$10 : BNE .amber  ; low: alternate every 16 frames
    BRA .violet
.lost
    LDA.l !hush_mflash : BEQ .drained
    LDA.l !hush_mlost : CMP.b $00 : BCS .amber   ; lost by the last hit: amber while the flash runs
.drained
    LDY.b #$A2                           ; empty container
.violet
    LDA.b #$24 : BRA .put
.amber
    LDA.b #$34
.put
    STA.l $7EC769,X
    TYA : STA.l $7EC768,X
    DEX : DEX : BPL .cell
    PLP
    RTL

; -----------------------------------------------------------------------------
Hush_MeterRefill:                        ; any M/X, preserves P
    PHP
    SEP #$30
    LDA.b #32 : STA.l !hush_meter : STA.l !hush_mlost
    LDA.b #$00 : STA.l !hush_mflash
    LDX.b #$0F
-   LDA.b #$00 : STA.l !hush_cd_small,X : STA.l !hush_cd_big,X
    LDA.l $7E0D80,X : STA.l !hush_aprev,X
    DEX : BPL -
    PLP
    RTL

Hush_MeterLoad:                          ; JSL from Hush_LoadRoom (replaces `JSL Hush_ResetRuntime`)
    JSL Hush_ResetRuntime
    JML Hush_MeterRefill                 ; its RTL returns to Hush_LoadRoom

Hush_MeterRestart:                       ; JSL from Hush_FastRestart (replaces `JSL Hush_CountRetry`)
    JSL Hush_CountRetry
    JML Hush_MeterRefill
Hush_Meter_End:
assert pc() <= $1BB340                       ; the block must stay inside its src/FREESPACE.md row (ends $1BB327 at M5)
