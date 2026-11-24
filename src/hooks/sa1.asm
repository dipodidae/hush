; =============================================================================
; HOOK: SA-1 boot + SA-1 idle loop (SA-1 bring-up step 2)
; Address:  $00802C (SNES LoROM), PC offset 0x0802C
; Replaces: `JSR InitializeMemoryAndSRAM` (20 C0 87) in Reset
;           (vendor/usdasm/bank_00.asm:34; the routine is at $0087C0, bank_00.asm:1317-1380)
; Does:     opens I-RAM / BW-RAM writes for the SNES, clears the mailbox, points the
;           SA-1 reset vector at Hush_Sa1Entry and releases the SA-1, then runs
;           InitializeMemoryAndSRAM as before; the SA-1 counts a heartbeat in
;           I-RAM and acknowledges (clears) any command byte; no light work yet.
; Space:    src/FREESPACE.md rows $00802C-$00802E (hook), $0089C2-$0089DF
;           (Hush_Sa1Boot), $00CF46-$00CF7F (Hush_Sa1Entry)
; =============================================================================
;
; Hook point: the JSR is the last call of Reset before NMI / joypad are enabled
; (bank_00.asm:29-37): stack and DP are set, P is SEP #$30 (bank_00.asm:31), DB = $00
; (power-on; Reset never changes it and InitializeMemoryAndSRAM relies on it:
; `STA.w $0000,X` clears low WRAM, bank_00.asm:1326). A JSR (not JSL) because the
; replaced instruction is a 3-byte JSR and the routine it calls ends in RTS (bank 00).
;
; SA-1 registers (MesenCE .tools/src/MesenCE/Core/SNES/Coprocessors/SA1/Sa1.cpp):
;   SNES side  $2200 CCNT: bit 5 = SA-1 reset; a write with bit 5 clear while reset
;                          restarts the SA-1 at the CRV vector (Sa1.cpp:295-311).
;                          Power-on state: reset (Sa1.cpp:843).
;              $2203/$2204 CRV: SA-1 reset vector, bank $00 (Sa1.cpp:332-333, 893-897)
;              $2226 SBWE: bit 7 = BW-RAM writes enabled (Sa1.cpp:354). Needed: the
;                          write-protected area BWPA is reset to $0F = all 256 KB
;                          (Sa1.cpp:844, CpuBwRamHandler.h:45-56), so without SBWE /
;                          CBWE no BW-RAM write lands. BWPA is left alone.
;              $2229 SIWP: bit n = SNES may write I-RAM page n (256 B; Sa1.cpp:358,
;                          Sa1IRamHandler.h:46-50). Power-on 0 = all protected.
;   SA-1 side  $2227 CBWE: bit 7 = BW-RAM writes enabled (Sa1.cpp:173)
;              $222A CIWP: SA-1 I-RAM write pages, zeroed on every SA-1 release
;                          (Sa1.cpp:174, :299), so the SA-1 sets it itself.
; BW-RAM mapping: nothing to write. The SA-1 sees BW-RAM at $40-$5F:0000-FFFF
; unconditionally (Sa1.cpp:69), the SNES at $40-$4F (Sa1.cpp:68); BMAPS $2224 /
; BMAP $2225 (the $00-$3F:6000-7FFF window) stay at their power-on 0 (Sa1.cpp:842).
; I-RAM: the SNES sees it at $00-$3F/$80-$BF:3000-37FF (Sa1.cpp:43-44), the SA-1 at
; $3000-$37FF and $0000-$07FF of the same banks (Sa1.cpp:46-49).
;
; Mailbox (I-RAM, docs/ram_map.md "SA-1"): $3000 command (SNES writes non-zero, the
; SA-1 clears it when done), $3001 status (0 not started, 1 idle), $3002 heartbeat
; word (SA-1 increments it on every idle-loop pass). SA-1 stack top $37FF, DP $3000.

!SA1_CCNT  = $2200
!SA1_CRV   = $2203
!SA1_SBWE  = $2226
!SA1_CBWE  = $2227
!SA1_SIWP  = $2229
!SA1_CIWP  = $222A

!SA1_CMD   = $3000                  ; byte: command (0 = none)
!SA1_STAT  = $3001                  ; byte: 0 not started, 1 idle
!SA1_BEAT  = $3002                  ; word: heartbeat
!SA1_STACK = $37FF                  ; SA-1 stack top (I-RAM)

; --- hook site: Reset `JSR InitializeMemoryAndSRAM` -> `JSR Hush_Sa1Boot` ----
org $00802C
    JSR Hush_Sa1Boot

; --- SNES: boot set-up (NULL_0089C2, 30 bytes) --------------------------------
; JSR from Reset. In: M = X = 1 (SEP #$30, bank_00.asm:31), DB = $00, S = $01FD. Sets up
; and releases the SA-1, then tail-jumps to InitializeMemoryAndSRAM, whose RTS returns to
; Reset ($00802F) with M = X = 1 (bank_00.asm:1373). Not a nested JSR: that routine
; clears WRAM $0002-$1FFF and keeps only the word at $01FE (bank_00.asm:1320-1338, 1369),
; so a second return address on the stack ($01FB-$01FC) would be zeroed.
org $0089C2
Hush_Sa1Boot:
    SEP #$30
    LDA.b #$FF
    STA.w !SA1_SIWP                     ; SNES may write all 8 I-RAM pages
    STA.w !SA1_SBWE                     ; SNES BW-RAM writes on (only bit 7 counts, Sa1.cpp:354)
    REP #$20
    STZ.w !SA1_CMD                      ; command = 0, status = 0 (before the SA-1 runs)
    LDA.w #Hush_Sa1Entry : STA.w !SA1_CRV
    SEP #$20
    STZ.w !SA1_CCNT                     ; release the SA-1 (no reset / wait / IRQ / NMI)
    JMP $87C0                           ; InitializeMemoryAndSRAM (the replaced call); its RTS returns to Reset
Hush_Sa1Boot_End:
assert pc() <= $0089E0

; --- SA-1: entry + idle loop (NULL_00CF46, 58 bytes) --------------------------
; Runs on the SA-1 only, from its reset (E = 1, DB = D = PB = 0, I set: the SA-1 CPU
; uses SnesCpu's Reset, .tools/src/MesenCE/Core/SNES/SnesCpu.Shared.h:16-24).
org $00CF46
Hush_Sa1Entry:
    SEI
    CLC : XCE                           ; native mode
    REP #$30
    LDA.w #!SA1_STACK : TCS
    LDA.w #$3000 : TCD                  ; DP = I-RAM base: $00 = command, $01 = status, $02 = heartbeat
    PHK : PLB                           ; DB = $00 (registers + I-RAM)
    SEP #$20
    LDA.b #$FF : STA.w !SA1_CIWP        ; SA-1 may write all I-RAM pages
    LDA.b #$80 : STA.w !SA1_CBWE        ; SA-1 BW-RAM writes on
    LDA.b #$01 : STA.b !SA1_STAT-$3000  ; status: idle
    REP #$20
    STZ.b !SA1_BEAT-$3000
.loop                                   ; M = 0, X = 0
    INC.b !SA1_BEAT-$3000
    LDA.b !SA1_CMD-$3000
    AND.w #$00FF
    BEQ .loop
    SEP #$20                            ; no commands yet: acknowledge (clear) it
    STZ.b !SA1_CMD-$3000
    REP #$20
    BRA .loop
Hush_Sa1Entry_End:
assert pc() <= $00CF80
