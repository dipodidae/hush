# Hooks

One file per hook. Include it from `src/main.asm`. Every hook file starts with
this header (copy it):

```asm
; =============================================================================
; HOOK: <short name>
; Address:  $BBAAAA (SNES LoROM), PC offset 0xXXXXX
; Replaces: <the exact vanilla instructions/bytes, e.g. `LDA $0DD0,X : CMP #$09`>
;           (cite vendor/ file:line where it was read)
; Does:     <one sentence>
; Space:    <ledger row in src/FREESPACE.md that covers the hook site and any
;            freespace routine it jumps to>
; =============================================================================
```

The hook site and any freespace routine must both have rows in
`src/FREESPACE.md`.
