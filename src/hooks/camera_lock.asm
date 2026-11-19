; =============================================================================
; HOOK: camera_lock  (the camera never scrolls, no screen-edge room transitions)
;
; Site 1 - HandleUnderworldCamera
; Address:  $02BA31 (SNES LoROM), 3 bytes
; Replaces: `REP #$20 : LDA.w #$0001`   (C2 20 A9 01 00 ...)  vendor/usdasm/bank_02.asm:10800-10803
;           (the routine computes $E2/$E8/$E0/$E6 from Link's position and ends `SEP #$20 : RTS`)
; Does:     `SEP #$20 : RTS` (E2 20 60). $E2/$E8 stay what LoadUnderworldEntrance loaded from
;           EntranceData.horizontal_scroll / vertical_scroll, i.e. the room's 256x224 window.
;           Callers (JSR at $0287BE, $028C49, $028F24, $028FA0) expect M=8 on return, as the original ends.
;
; Site 2 - Underworld_TryScreenEdgeTransition
; Address:  $02885E, 3 bytes
; Replaces: `REP #$20 : LDA.b $30`   (C2 20 A5 30 ...)  vendor/usdasm/bank_02.asm:1513-1516
; Does:     `SEP #$20 : RTS` (E2 20 60), same exit state as the original (`.exit: SEP #$20 : RTS`,
;           bank_02.asm:1578-1580). Walking into the room border can no longer start a room scroll
;           (Link is confined by the solid grid walls anyway).
;
; Space:    src/FREESPACE.md hook rows $02885E and $02BA31
; =============================================================================

org $02BA31
    SEP #$20
    RTS

org $02885E
    SEP #$20
    RTS
