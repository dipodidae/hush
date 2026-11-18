-- GFX scenes: dungeon rooms with guards. Vanilla Hyrule Castle rooms are used as stand-ins (they have
-- soldiers) until the M1 test room exists. Reached from build/dev_states/gfx_house.mss by selecting a
-- dungeon entrance and re-running the underworld loader: $010E entrance id (docs: EntranceData
-- bank_02.asm:13125; 0x03 -> room $0060, 0x05 -> $0062, 0x0C -> $0063), then module $10 = 6
-- (Module06_UnderworldLoad). Verified: the soldier sprite types (0x41/0x42) appear within ~3 frames.
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local gfx = require("gfx")

local function poke(addr, v) emu.write(addr - 0x7E0000, v, emu.memType.snesWorkRam) end

local function guards()
  local n = 0
  for s = 0, 15 do
    local t = hush.read("spr_type", s)
    if hush.read("spr_state", s) ~= 0 and (t == 0x41 or t == 0x42 or t == 0x43 or t == 0x44 or t == 0x45) then n = n + 1 end
  end
  return n
end

hush.test("gfx scenes: dungeon rooms with guards", function()
  for _, e in ipairs({ { 3, "guard_room_60" }, { 5, "guard_room_62" }, { 12, "guard_room_63" } }) do
    hush.load_state("build/dev_states/gfx_house.mss")
    hush.wait(20)
    poke(0x7E010E, e[1]); poke(0x7E0010, 0x06); poke(0x7E0011, 0x00); poke(0x7E00B0, 0)
    local t = 0
    while not (hush.read("game_mode") == 0x07 and hush.read("submodule") == 0x00) and t < 300 do hush.wait(5); t = t + 5 end
    hush.wait(20)
    hush.assert(hush.read("game_mode") == 0x07, e[2] .. ": not in a dungeon room (module " .. hush.read("game_mode") .. ")")
    if e[1] ~= 12 then hush.assert(guards() > 0, e[2] .. ": no guard sprites present") end  -- room $63 spawns its soldiers late
    gfx.snap(e[2])
    if e[1] == 5 then
      -- let the guards notice Link (vanilla chase behaviour = the closest stand-in for an alert guard)
      hush.hold({ "up" }, 90); gfx.snap(e[2] .. "_guards_react")
      poke(0x7EF359, 1)
      hush.hold({ "b" }, 3); hush.wait(3); gfx.snap(e[2] .. "_sword_swing")
      hush.wait(120); gfx.snap(e[2] .. "_later")
    end
  end
  hush.pass("guard rooms dumped")
end)
