; =============================================================================
; ram.asm - shared WRAM defines (no code, no org; emits no bytes)
; Every symbol here is a row in docs/ram_map.md (with the evidence that the
; address is free). Included first from src/main.asm so every hook can use them.
; Older hooks still define their own copies of the E1-E7 variables; asar allows
; an identical redefinition, so new code should use this file.
; =============================================================================

; --- Stealth meter (design/pillars.md "Stealth meter"; docs/ram_map.md "HUSH stealth meter") ---
; Block $7EC950-$7EC98F inside HUSH's $7EC900-$7EC9FF. Not touched by vanilla: no $7EC9xx long
; operand and no absolute $C95x-$C98x RAM operand in vendor/usdasm (only MAP16 / tile data words);
; WRAM.asm:8823 "seemingly Free RAM". Not used by any other HUSH hook (E1-E7 use $7EC900-$7EC943).
!hush_meter      = $7EC950   ; 1: meter 0..32 (multiple of 4); 32 on every room entry
!hush_mflash     = $7EC951   ; 1: HUD hit flash, 16..1 frames left, 0 = none
!hush_mlost      = $7EC952   ; 1: meter value before the last hit (cells hush_meter..hush_mlost flash amber)
!hush_cd_small   = $7EC960   ; 16: per sprite slot, small-hit cooldown (121..0; set 121, DEC before test: blocks +1..+120)
!hush_cd_big     = $7EC970   ; 16: per sprite slot, big-hit cooldown (121..0; set 121, DEC before test: blocks +1..+120)
!hush_aprev      = $7EC980   ; 16: per sprite slot, spr_aware ($0D80,X) seen at the last meter check (transition detect)
