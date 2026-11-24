; =============================================================================
; HOOK: SA-1 boot + SA-1 idle loop (SA-1 bring-up step 2)
; Address:  $00802C (SNES LoROM), PC offset 0x0802C
; Replaces: `JSR InitializeMemoryAndSRAM` (20 C0 87) in Reset
;           (vendor/usdasm/bank_00.asm:34; the routine is at $0087C0, bank_00.asm:1317-1380)
; Does:     opens I-RAM / BW-RAM writes for the SNES, clears the mailbox, points the
;           SA-1 reset vector at Hush_Sa1Entry and releases the SA-1, then runs
;           InitializeMemoryAndSRAM as before; the SA-1 counts a heartbeat in
;           I-RAM and acknowledges (clears) any command byte; no light work yet.
;           Step 3: the SA-1 also zeroes light_l3ok (BW-RAM) once at its start.
;           Step 4: a command no longer is just acknowledged: the idle loop JSLs
;           Hush_LightJob (light.asm), which takes the staged inputs, clears the
;           command and runs one frame of the light worker on the SA-1.
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
!SA1_L3OK  = $41C7D0                ; light_l3ok (BW-RAM, light.asm !L3B+!L3_OK; asserted there): := 0 at every SA-1 start
; Step 4 (light.asm "SA-1 light worker"; docs/ram_map.md "SA-1 memory"): long addresses of the mailbox for both CPUs ($00:3000-$37FF
; is I-RAM for the SNES, Sa1.cpp:43-44, and for the SA-1, Sa1.cpp:46-49).
!SA1_CMDL  = $003000                ; command byte: $FF = "light frame" (Hush_LightPost), 0 = taken (Hush_LightJob)
!SA1_STATL = $003001                ; status: 1 idle, 2 running the light worker
; ($003004 / $003005 sa1_trow / sa1_nmiup: the step 4 row lock, unused since step 5a)
!SA1_PUBF  = $00300A                ; step 5a: byte, 1 = light_pub rows published, the NMI owns them; 0 = the SA-1 may write light_pub
!SA1_PUBT  = $00300B                ; step 5a: byte first published tile row t0, byte $00300C = tile rows n (the NMI advances both)
!SA1_RUNS  = $3006                  ; word: light commands run by the SA-1 (+1 per Hush_LightJob; probe counter)
!SA1_SKIP  = $3008                  ; word: SNES frames whose inputs were not staged (the previous command not taken yet; probe counter)
!SA1_DP    = $3100                  ; SA-1 direct page of the worker: $00-$0F scratch, $20-$23 / $E2-$E3 / $E8-$E9 input copies
!SA1_STAGE = $3200                  ; 320 B: inputs staged by the SNES (Hush_LightPost), layout !SA1_IN_*
!SA1_IN    = $3400                  ; 320 B: the SA-1's copy for the running command (Hush_LightJob)
!SA1_INLEN = $0140
!SA1_IN_SPR  = !SA1_IN-$0D00        ; + $0D00..$0E2F: WRAM $7E0D00-$7E0E2F (sprite arrays)
!SA1_IN_ROOM = !SA1_IN+$0130        ; word: $7EC900 (hush_room)
!SA1_IN_INK  = !SA1_IN+$0132        ; 6: $7EC908-$7EC90D (ink x, y, timer)
!SA1_IN_DP   = !SA1_IN+$0138        ; 8: DP $20-$23 (Link y, x), $E2-$E3, $E8-$E9 (BG2 scroll)

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
    LDA.b !SA1_BEAT-$3000               ; A = 0
    STA.l !SA1_L3OK                     ; step 3: light_l3ok := 0, so the SNES rebuilds the light tables / RAM code at the first room
                                        ; load after every power-on / reset (BW-RAM is battery-backed and, unlike WRAM bank $7F, not
                                        ; zeroed by the intro clear, bank_0C.asm:88-113; a stale copy of an older build must not pass)
.loop                                   ; M = 0, X = 0
    INC.b !SA1_BEAT-$3000
    LDA.b !SA1_CMD-$3000
    AND.w #$00FF
    BEQ .loop
    JSL Hush_LightJob                   ; step 4: any command = one light frame (light.asm; acknowledges the command itself)
    BRA .loop
Hush_Sa1Entry_End:
assert pc() <= $00CF80
