; =============================================================================
; HOOK: SA-1 cartridge header (SA-1 bring-up step 1)
; Address:  $00FFD5-$00FFD6 (PC 0x07FD5-0x07FD6) and $00FFD8 (PC 0x07FD8), SNES LoROM
; Replaces: InternalROMHeader `db $20` (map mode: lorom), `db $02` (cartridge:
;           ROM+RAM+battery), `db $03` (RAM size: 8 KB)
;           (vendor/usdasm/bank_00.asm:17008-17011; $00FFD7 ROM size `db $0A` stays)
; Does:     declares an SA-1 cartridge: map mode $23 (SA-1), cartridge type $35
;           (SA-1 + RAM + battery), RAM size $07 (128 KB BW-RAM). The header
;           checksum $00FFDC-$00FFDF is fixed up by tools/build.py after the
;           graphics insertion (asar runs with --fix-checksum=off because
;           gfx_insert.py writes the ROM after asar).
;           Mapping: the SA-1 MMC defaults (CXB..FXB = 0,1,2,3) put the 1 MiB ROM
;           at $00-$1F:8000-FFFF in LoROM order, so `lorom` addressing is unchanged.
;           SNES-side banks $70-$7D are not mapped on SA-1 (MesenCE
;           BaseCartridge.cpp:457 `mapSram = ... != SA1`): vanilla SRAM reads/writes
;           there become open bus / dropped; HUSH never loads or saves a file.
; Space:    src/FREESPACE.md rows $00FFD5-$00FFD6, $00FFD8-$00FFD8 (this file),
;           $00FFDC-$00FFDF (tools/build.py checksum)
; =============================================================================

org $00FFD5
    db $23                              ; map mode: SA-1
    db $35                              ; cartridge: SA-1 + RAM + battery
org $00FFD8
    db $07                              ; RAM size: 128 KB BW-RAM (1 KB << 7)
