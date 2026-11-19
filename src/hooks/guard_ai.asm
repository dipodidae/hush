; =============================================================================
; HOOK: guard_ai  (E2: the stealth AI replaces vanilla Guard_Main for sprite types $41-$43)
;
; Address:  $05C155 (SNES LoROM), 8 bytes: the entry of Sprite_41_BlueGuard / _42_GreenGuard / _43_RedGuard
;           (all three jump-table entries point here; the soldier jump table in SpriteModule_Active_bank05 is
;            a PHA/RTS dispatch, so this routine runs as a JSR from `.main` at $05B5D3 with DB = $05, M = X = 8)
; Replaces: `LDA.w $0DB0,X : BNE Probe : JMP.w Guard_Main`   (BD B0 0D D0 03 4C 27 C2)
;           vendor/usdasm/bank_05.asm:11942-11946 ($05C155-$05C15C); `Probe` stays at $05C15D untouched
;
; Address:  $0DB0C1 (SNES LoROM), 3 bytes: SpriteData_OAMHarm rows $41 / $42 / $43 (blue / green / red soldier)
; Replaces: `08 08 08` (vendor/usdasm/bank_0D.asm:5871-5873 = "$0DB0C1-$0DB0C3 db $08 ; ... $08"; hmwo oooo: o = OAM entries - 1)
; Does:     `04 04 04`: 5 OAM entries per guard (head, lantern, body, icon, shadow). Only LoadSpriteProperties
;           ($0DB823) reads the table (copies it to $0E40,X, the per-sprite value used by DoSpriteOAMandTimers and the shadow).
; Does:     JML Hush_GuardEntry + 4 NOPs. Hush_GuardEntry repeats the `$0DB0 != 0` test (a non-zero value is the
;           PARENT+1 of a vanilla probe sprite; HUSH never spawns probes, but the branch is kept: JML Probe) and
;           otherwise runs Hush_GuardAI, then returns with JML to the RTS at $05C226 (EXIT_05C226,
;           bank_05.asm:12112) so the caller (an RTS-dispatch inside bank 05) resumes exactly as after Guard_Main.
;           NOTHING of vanilla Guard_Main runs: no probe sprites (Guard_SendOutProbe/FireProbe are never called),
;           no CheckDamageToLink, no ParrySwordAttacks, no sword/arrow damage, no $0FDC "noise" alerting
;           (AlertSprites $088AB9 and WeaponTink $088F8E still set $0FDC, but nobody reads it any more).
;
; Awareness (spr_aware = $0D80,X, docs/ram_map.md):
;     0 UNAWARE    patrol (move: patrol) or stand (move: still); sees Link in a 90-degree cone, range 5 cells dark / 8 lit
;     1 SUSPICIOUS '?'; stops, turns to Link, $0DF0 = 60 frames; if Link is still seen when it ends -> ALERT;
;                  not seen for 120 frames ($0E10) -> UNAWARE
;     2 ALERT      '!' (amber palette row 6); chases at 1.125 px/frame (patrol 0.75), contact = CAUGHT ($7EC902 = 1,
;                  Hush_Tick restarts the room); out of sight for 180 frames ($0E10) -> UNAWARE
;     3 ASLEEP     'Z'; dart sleep, 240 + 240 frames ($0DF0 and the chunk counter $0D90); ignores everything
; Other sprite variables (all reset to 0 by ResetSpriteProperties when the sprite spawns, bank_0D.asm:7869-7916):
;     $0DE0 facing (0 right, 1 left, 2 down, 3 up; the draw reads it, the vanilla head direction $0EB0 / body frame $0DC0 are unused now),
;     $0E80 walk animation counter, $0E00 patrol wall pause (60), $0D90 pause flag (state 0) / sleep chunks (state 3),
;     $0EE0 ink "stand still" timer (60), $0E30 bit 3 (value 8) = `move: still` (roomgen STILL_SUBTYPE),
;     $0DB0 must stay 0 (non-zero = vanilla probe).
; Cost (tests/dev/cpu_load.lua: scanline where the game logic ends, NMI = 225): ~8 lines per idle guard (E4; 16 with the vanilla draw),
;     about half of it the draw. To fit the frame the AI looks around only every 2nd (unaware) / 4th
;     (suspicious, alert) frame, staggered by slot ((slot xor $1A) & mask), the sword box is only built while Link swings or dashes,
;     and $0BE0 bit 7 makes CheckSpriteTileCollision skip the pit / water / conveyor checks. An empty room ends at line 114,
;     6 guards at line 163, 8 guards at 179 (E4; with the vanilla draw 6 guards = 211 and 7 or more dropped the game to 30 fps).
; Sword: only state 0 and 3 (unaware / asleep) die (Link's sword box from SetupActionHitbox_long $06F57E vs the sprite
;     box SetupSpriteHitbox_long $0683EA, CheckIfHitboxesOverlap_long $0683E6); states 1 and 2 ignore the sword.
; Arrows / bombs: see guard_hooks.asm (CheckAncillaDamageToSprite, Bomb_CheckSpriteAndPlayerDamage).
; Draw (E4, replaces the vanilla soldier drawing Guard_HandleAllAnimation $05C680 = 9 OAM entries from 60 cells): Hush_DrawGuard in
;     guard_draw.asm (bank $07) writes 5 OAM entries per guard from the cells of GFX_BC (sheet contract: docs/gfx/art_map.md section 5):
;     entry 0 head (16x16), 1 lantern (8x8), 2 body (16x16), 3 awareness icon (8x8, GFX_C5 tiles $FC-$FE), 4 shadow (tile $6C).
;     SpriteData_OAMHarm $0DB0C1-C3 (the per-type OAM allocation, $08 = 9 entries) is now $04 = 5 entries; DoSpriteOAMandTimers
;     $0683F2 allocates ((n & $1F) + 1) * 4 bytes. The AI itself (timing, movement, collision) is unchanged.
;
; Space:    src/FREESPACE.md rows: hook $05C155-$05C15C, hook $0DB0C1-$0DB0C3 (OAM count); free blocks $0EEE21 (NULL_0EEE21, "FREE ROM: 0x05DF",
;           bank_0E.asm:11950; all $FF in vanilla ROM, no references in vendor/usdasm)
; =============================================================================

!hush_room    = $7EC900
!hush_caught  = $7EC902
!hush_range   = $7EC906
!hush_ink_x   = $7EC908
!hush_ink_y   = $7EC90A
!hush_ink_t   = $7EC90C

macro retif(cond)                        ; return when the condition holds (a long branch to an RTS is out of reach)
    <cond> ?do
    BRA ?skip
?do:
    RTS
?skip:
endmacro

macro abs16(src, dst)                    ; 16-bit absolute value of a direct page word (M = 16 bit)
    LDA.b <src>
    BPL ?pos
    EOR.w #$FFFF
    INC A
?pos:
    STA.b <dst>
endmacro

org $05C155
    JML Hush_GuardEntry
    NOP : NOP : NOP : NOP

org $0DB0C1                              ; SpriteData_OAMHarm for $41-$43: 5 OAM entries instead of 9
    db $04, $04, $04

; -----------------------------------------------------------------------------
org $0EEE22                              ; $0EEE21 stays $FF: the dialogue loader scans bank $0E text for the $FF end marker
Hush_GuardEntry:
    LDA.w $0DB0,X
    BEQ .guard
    JML $05C15D                          ; vanilla Probe (parent+1 in $0DB0): never reached in HUSH, kept intact
.guard
    PHB : PHK : PLB                      ; DB = $0E: the tables below are reachable with absolute addressing
    JSR Hush_GuardAI
    PLB
    JML $05C226                          ; RTS in bank 05 (EXIT_05C226)

; -----------------------------------------------------------------------------
; Hush_GuardAI: X = sprite slot, M = X = 8 bit, DB = $0E.
Hush_GuardAI:
    JSL Hush_DrawGuard                   ; guard_draw.asm: palette row, head + lantern + body + icon + shadow (5 OAM entries)
    LDA.b $11 : ORA.w $0FC1
    BNE .out                             ; transitions / menus: frozen (like CheckIfActive_bank05)

    LDA.w $0D80,X
    BEQ .go0
    CMP.b #$01 : BEQ .go1
    CMP.b #$02 : BEQ .go2
    JMP .asleep
.go0
    JMP .unaware
.go1
    JMP .suspicious
.go2
    JMP .alert
.out
    RTS

; ---- 0: UNAWARE ------------------------------------------------------------
.unaware
    JSR Hush_SwordCheck
    %retif(BCS)                          ; died
    JSL Hush_Geom
    JSR Hush_Contact
    BCC +
    LDA.b #$02 : STA.w $0D80,X          ; touched: alert at once
    LDA.b #180 : STA.w $0E10,X
    RTS
+   LDA.w $0EE0,X                        ; ink stand-still: the guard does not look around either
    BNE .stand0
    TXA : EOR.b $1A : AND.b #$01         ; looks every 2nd frame (staggered by slot): the AI must fit the frame budget
    BNE .patrol
    LDA.b #$00
    JSL Hush_Vision                      ; cone + range + line of sight
    BCC .patrol
    LDA.b #$01 : STA.w $0D80,X          ; notice: SUSPICIOUS
    LDA.b #60  : STA.w $0DF0,X
    LDA.b #120 : STA.w $0E10,X
    STZ.w $0D90,X
    STZ.w $0D50,X : STZ.w $0D40,X
    JMP Hush_FaceLink
.patrol
    JMP Hush_Patrol
.stand0
    STZ.w $0D50,X : STZ.w $0D40,X
    RTS

; ---- 1: SUSPICIOUS ----------------------------------------------------------
.suspicious
    JSL Hush_Geom
    JSR Hush_Contact
    BCC +
    LDA.b #$02 : STA.w $0D80,X
    LDA.b #180 : STA.w $0E10,X
    RTS
+   JSR Hush_InkCheck
    %retif(BCS)
    TXA : EOR.b $1A : AND.b #$03         ; senses every 4th frame (staggered by slot)
    %retif(BNE)
    LDA.b #$01
    JSL Hush_Vision                      ; range + line of sight, any direction: the investigating guard turns
    BCC .unseen
    JSR Hush_FaceLink
    LDA.b #120 : STA.w $0E10,X
    LDA.w $0DF0,X
    %retif(BNE)
    LDA.b #$02 : STA.w $0D80,X          ; the 60 frames are over and Link is still there: ALERT
    LDA.b #180 : STA.w $0E10,X
    RTS
.unseen
    LDA.w $0E10,X
    %retif(BNE)
    STZ.w $0D80,X                        ; lost him for 120 frames: back to UNAWARE
    RTS

; ---- 2: ALERT --------------------------------------------------------------
.alert
    JSL Hush_Geom
    JSR Hush_Contact
    BCC +
    LDA.b #$01 : STA.l !hush_caught     ; CAUGHT: Hush_Tick restarts the room next frame
    STZ.w $0D50,X : STZ.w $0D40,X
    RTS
+   JSR Hush_InkCheck
    %retif(BCS)
    TXA : EOR.b $1A : AND.b #$03         ; looks every 4th frame (staggered by slot)
    BNE +
    LDA.b #$01
    JSL Hush_Vision                      ; (clobbers the Hush_Geom data)
    PHP
    JSL Hush_Geom
    PLP
    BCC +
    LDA.b #180 : STA.w $0E10,X
+   LDA.w $0E10,X
    BNE .chase
    STZ.w $0D80,X                        ; lost him for 180 frames: UNAWARE (stays where he is)
    STZ.w $0D50,X : STZ.w $0D40,X
    RTS
.chase
    JMP Hush_Chase

; ---- 3: ASLEEP -------------------------------------------------------------
.asleep
    JSR Hush_SwordCheck
    %retif(BCS)
    JSL Hush_Geom
    JSR Hush_Solid                       ; a sleeping guard is a solid obstacle
    LDA.w $0DF0,X
    %retif(BNE)
    LDA.w $0D90,X
    BEQ .wake
    DEC.w $0D90,X
    LDA.b #240 : STA.w $0DF0,X
    RTS
.wake
    STZ.w $0D80,X                        ; UNAWARE again
    RTS

; -----------------------------------------------------------------------------
; Hush_SwordCheck: C = 1 when Link's sword box overlaps this guard (it dies: poof, sprite gone). Clobbers $00-$0F.
Hush_SwordCheck:
    LDA.b $3C : ORA.w $0372              ; no sword swing / dash: no sword box (SetupActionHitbox_validity[0] = no box)
    BEQ .no
    LDA.w $0F20,X : CMP.b $EE : BNE .no
    JSL $06F57E                          ; SetupActionHitbox_long: Link's sword box ($00-$03, $08-$09; no box: $08 = $80)
    JSL $0683EA                          ; SetupSpriteHitbox_long: this sprite's box ($04-$07, $0A-$0B)
    JSL $0683E6                          ; CheckIfHitboxesOverlap_long
    BCC .no
    JSL $05AB9C                          ; SpawnPoofGarnish (X = sprite)
    STZ.w $0DD0,X                        ; gone until the room is restarted
    SEC
    RTS
.no
    CLC
    RTS

; -----------------------------------------------------------------------------
; Hush_Contact: C = 1 when Link's box touches the guard (|dx| < 16 and |dy| < 16 from Hush_Geom: $04 / $06).
Hush_Contact:
    LDA.w $0F20,X : CMP.b $EE : BNE .no
    REP #$20
    LDA.b $04 : CMP.w #$0010 : BCS .no16
    LDA.b $06 : CMP.w #$0010 : BCS .no16
    SEP #$20
    SEC
    RTS
.no16
    SEP #$20
.no
    CLC
    RTS

; -----------------------------------------------------------------------------
; Hush_Solid: an ASLEEP guard blocks Link: when the two 16x16 boxes overlap (|dx| < 16 and |dy| < 16, Hush_Geom data) Link is pushed
; out along the axis of the smaller overlap (A 16-px push at most; normal walking overlaps 1-2 px).
Hush_Solid:
    LDA.w $0F20,X : CMP.b $EE : BNE .no
    REP #$20
    LDA.w #$0010 : SEC : SBC.b $04 : BEQ .no16 : BMI .no16 : STA.b $08      ; overlap in x
    LDA.w #$0010 : SEC : SBC.b $06 : BEQ .no16 : BMI .no16 : STA.b $0A      ; overlap in y
    LDA.b $08 : CMP.b $0A : BCS .push_y
    LDA.b $00 : BMI .west
    LDA.b $22 : CLC : ADC.b $08 : STA.b $22 : BRA .done
.west
    LDA.b $22 : SEC : SBC.b $08 : STA.b $22 : BRA .done
.push_y
    LDA.b $02 : BMI .north
    LDA.b $20 : CLC : ADC.b $0A : STA.b $20 : BRA .done
.north
    LDA.b $20 : SEC : SBC.b $0A : STA.b $20
.done
.no16
    SEP #$20
.no
    RTS

; -----------------------------------------------------------------------------
; Hush_InkCheck: if an ink cloud is on the line to Link or on the guard itself: UNAWARE, stand still 60 frames. C = 1 then.
Hush_InkCheck:
    LDA.l !hush_ink_t : ORA.l !hush_ink_t+1
    BEQ .no
    LDA.b #$02
    JSL Hush_Vision                      ; mode 2: C = 0 when the cloud blocks the line (or covers the guard)
    BCS .clear
    STZ.w $0D80,X
    LDA.b #60 : STA.w $0EE0,X
    STZ.w $0D50,X : STZ.w $0D40,X
    SEC
    RTS
.clear
    JSL Hush_Geom                        ; Hush_Vision clobbered the Hush_Geom data of the caller
.no
    CLC
    RTS

; -----------------------------------------------------------------------------
; Hush_FaceLink: facing := the direction of the larger axis towards Link.
Hush_FaceLink:
    JSL Hush_Geom                        ; $00 dx, $02 dy (16-bit, Link minus guard)
    REP #$20
    %abs16($00, $04)
    %abs16($02, $06)
    LDA.b $06 : CMP.b $04
    SEP #$20
    BEQ .horizontal
    BCC .horizontal
    LDA.b $03 : ASL A : LDA.b #$02 : ADC.b #$00  ; down 2 / up 3
    BRA .set
.horizontal
    LDA.b $01 : ASL A : LDA.b #$00 : ROL A       ; right 0 / left 1
.set
    STA.w $0DE0,X
    RTS

; -----------------------------------------------------------------------------
; Hush_Step: A = speed base (0 patrol, 8 alert), Y = direction. Moves one frame, then vanilla tile collision.
;            Z = 1 free, Z = 0 blocked: the position (and sub-pixels) from before the move are restored, so a guard never
;            creeps into a wall (the vanilla pushback alone lets one creep ~1 px per 8 frames: found by ai_deescalate).
Hush_Step:
    STA.b $0F
    TYA : CLC : ADC.b $0F : TAY
    LDA.w $0D10,X : PHA : LDA.w $0D30,X : PHA : LDA.w $0D00,X : PHA : LDA.w $0D20,X : PHA
    LDA.w $0D70,X : PHA : LDA.w $0D60,X : PHA
    LDA.w Hush_VelTab,Y   : STA.w $0D50,X
    LDA.w Hush_VelTab+4,Y : STA.w $0D40,X
    LDA.w $0BE0,X : ORA.b #$80 : STA.w $0BE0,X   ; bit 7: CheckSpriteTileCollision skips the pit / water / conveyor checks (bank_06.asm:19549)
    JSR Hush_MoveAxis                    ; Y axis ($0D40/$0D60/$0D00/$0D20); the same arrays at X + $10 are the X axis
    TXA : CLC : ADC.b #$10 : TAX
    JSR Hush_MoveAxis
    TXA : SEC : SBC.b #$10 : TAX
    JSL $06E496                          ; CheckSpriteTileCollision_long -> A = $0E70,X
    AND.b #$0F
    STA.b $0F
    BNE .blocked
    PLA : PLA : PLA : PLA : PLA : PLA
    BRA .out
.blocked
    PLA : STA.w $0D60,X : PLA : STA.w $0D70,X
    PLA : STA.w $0D20,X : PLA : STA.w $0D00,X
    PLA : STA.w $0D30,X : PLA : STA.w $0D10,X
.out
    LDA.b $0F
    RTS

; Hush_MoveAxis: the body of MoveSpriteY_bank05 ($05FA00): moves along the array set starting at X (X or X + $10).
Hush_MoveAxis:
    LDA.w $0D40,X
    BEQ .done
    ASL A : ASL A : ASL A : ASL A
    CLC : ADC.w $0D60,X : STA.w $0D60,X
    LDA.w $0D40,X
    PHP
    LSR A : LSR A : LSR A : LSR A
    LDY.b #$00
    PLP
    BPL +
    ORA.b #$F0
    DEY
+   ADC.w $0D00,X : STA.w $0D00,X
    TYA
    ADC.w $0D20,X : STA.w $0D20,X
.done
    RTS

; -----------------------------------------------------------------------------
; Hush_Patrol: state 0. `move: still` (subtype bit 3) never walks; patrol guards walk along their facing axis, pause
; 60 frames when blocked, then turn 180 degrees.
Hush_Patrol:
    LDA.w $0E30,X : AND.b #$08 : BNE .stand
    LDA.w $0EE0,X : BNE .stand
    LDA.w $0D90,X : BEQ .walk
    LDA.w $0E00,X : BNE .stand
    STZ.w $0D90,X
    LDA.w $0DE0,X : EOR.b #$01 : STA.w $0DE0,X
.walk
    LDY.w $0DE0,X
    LDA.b #$00
    JSR Hush_Step
    BEQ .moved
    LDA.b #$01 : STA.w $0D90,X           ; blocked: pause, then turn around
    LDA.b #60  : STA.w $0E00,X
.stand
    STZ.w $0D50,X : STZ.w $0D40,X
    RTS
.moved
    INC.w $0E80,X
    RTS

; -----------------------------------------------------------------------------
; Hush_Chase: state 2. Step along the larger axis towards Link; when blocked slide along the other axis.
Hush_Chase:                              ; $00 dx, $02 dy, $04 |dx|, $06 |dy| from Hush_Geom
    LDA.b $01 : ASL A : LDA.b #$00 : ROL A : STA.b $08           ; horizontal direction (0 right / 1 left)
    LDA.b $03 : ASL A : LDA.b #$02 : ADC.b #$00 : STA.b $09      ; vertical direction (2 down / 3 up)
    REP #$20
    LDA.b $04 : CMP.b $06
    BCC .vertical_first
    LDA.b $06 : CMP.w #$0003
    SEP #$20
    BCC .no_slide_v
    LDA.b $09 : BRA .push_h
.no_slide_v
    LDA.b #$FF                                                   ; hardly any offset on the other axis: no slide
.push_h
    PHA
    LDY.b $08
    BRA .try
.vertical_first
    LDA.b $04 : CMP.w #$0003
    SEP #$20
    BCC .no_slide_h
    LDA.b $08 : BRA .push_v
.no_slide_h
    LDA.b #$FF
.push_v
    PHA
    LDY.b $09
.try
    TYA : STA.w $0DE0,X
    LDA.b #$08
    JSR Hush_Step
    BEQ .free
    PLA                                                          ; blocked: try the other axis
    CMP.b #$FF
    BEQ .stuck
    TAY
    TYA : STA.w $0DE0,X
    LDA.b #$08
    JSR Hush_Step
    BEQ .moved
.stuck
    STZ.w $0D50,X : STZ.w $0D40,X
    RTS
.free
    PLA
.moved
    INC.w $0E80,X
    RTS

; -----------------------------------------------------------------------------
; Tables (DB = $0E)
Hush_VelTab:                             ; 1/16 px per frame: [base + dir]; Y values at +4
    db  12, -12,   0,   0                ; patrol X  (0.75 px/frame)
    db   0,   0,  12, -12                ; patrol Y
    db  18, -18,   0,   0                ; alert X   (1.125 px/frame = 1.5 x patrol, vanilla AppliedSpeed18)
    db   0,   0,  18, -18                ; alert Y

Hush_AI_End:
