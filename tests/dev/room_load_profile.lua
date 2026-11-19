-- Dev utility (not a test): where do the frames of a room load go? Exec callbacks on every JSL/JSR of Module05/06 log the frame
-- and the master clock; the delta to the next hit is the cost of the call.   .venv/bin/python tools/run_test.py tests/dev/room_load_profile.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local sites = {
 [0x028136]="EnableForceBlank",[0x02814F]="EraseTilemaps",[0x028158]="LoadDefaultGraphics",[0x02815C]="Sprite_LoadGfxProps",
 [0x028160]="LoadDefaultTileTypes",[0x028164]="DecompressSwordGfx",[0x028168]="DecompressShieldGfx",[0x02816C]="InitializeLink",
 [0x028170]="LoadFollowerGraphics",[0x028212]="SearchEquipped",[0x028216]="RebuildHUD",[0x02821A]="UpdateEquippedItem",
 [0x02824A]="LoadUnderworldEntrance",[0x028260]="RebuildHUD_Keys",[0x02826A]="LoadAndDrawRoom",[0x02826D]="LoadUnderworldTileTypes",
 [0x028279]="DecompressAnimatedUWTiles",[0x02827D]="LoadEveryObjectAttributeSet",[0x028286]="InitializeTilesets",
 [0x02828F]="LoadUnderworldPalettes",[0x0282CE]="SetAndSaveVisited",[0x028321]="ResetLampconeAndLink",[0x028328]="ResetThenCacheRoomEntry",
 [0x01873A]="  LAB entry",[0x01880F]="  LAB floors",[0x018812]="  LAB floors done",[0x018834]="  LAB objs1",[0x01884A]="  LAB objs2",[0x01885F]="  LAB objs3",[0x018874]="  LAB objs4",[0x0FFE76]="  BuildRoom DMA start",[0x02C5A7]="  LoadAndDrawRoom end",
 [0x028344]="InitializeFollower",[0x028348]="ResetAllSprites",[0x02834C]="Underworld_ResetSprites",[0x028389]="LoadUWSongBank",
}
hush.test("room load profile", function()
  bot.start_new_game()
  hush.wait(30)
  local log = {}
  local clock = function() return emu.getState()["masterClock"] end
  for a, n in pairs(sites) do
    emu.addMemoryCallback(function() log[#log + 1] = { n = n, f = hush.frame(), c = clock() } end, emu.callbackType.exec, a, a)
  end
  local c0 = clock()
  local f0 = hush.frame()
  bot.poke(0x7EC901, 2)
  local last = ""
  for f = 0, 200 do
    local s = string.format("mode=%02X sub=%02X bright=%02X", hush.read("game_mode"), hush.read("submodule"), bot.peek(0x7E0013))
    if s ~= last then hush.log(string.format("+%3d %s", hush.frame() - f0, s)); last = s end
    hush.wait(1)
  end
  for i, e in ipairs(log) do
    local nxt = log[i + 1]
    hush.log(string.format("%-28s frame +%3d  cost %.2f frames", e.n, e.f - f0, nxt and (nxt.c - e.c) / 357368 or 0))
  end
  hush.pass()
end)
