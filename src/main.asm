; =============================================================================
; HUSH - main entry point
; Assembled by asar (see tools/build.py). The input is a copy of the vanilla
; US 1.0 ALttP ROM at build/hush.sfc; we only patch it, never regenerate it.
;
; Rules (see AGENTS.md):
;  - Every `org` must fall inside a region listed in src/FREESPACE.md.
;  - One file per hook under src/hooks/, header comment = address + the vanilla
;    code it replaces.
;  - No `freecode` / `freedata` (they allocate space behind the ledger's back).
; =============================================================================

lorom

; Hooks are included here, one line each, e.g.:
; incsrc "hooks/awareness_detect.asm"
incsrc "hooks/intro_skip.asm"       ; A0: boot straight to the title screen
