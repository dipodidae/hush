-- GFX scenes: HUSH rooms with guards (E1: the real rooms, loaded with the debug jump hush_room_req = N+1,
-- docs/ram_map.md; vanilla Hyrule Castle rooms are no longer reachable). Reached from the dev state
-- build/dev_states/gfx_room.mss. Verified: the soldier sprite types (0x41-0x43) are present after the load.
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

hush.test("gfx scenes: HUSH rooms with guards", function()
  local m = dofile(hush.ROOT .. "/build/rooms_gen.lua")
  local picked = {}
  for i, r in ipairs(m.rooms) do
    if #r.guards > 0 and #picked < 3 then picked[#picked + 1] = { i - 1, string.format("guard_room_%02d", i) } end
  end
  hush.assert(#picked > 0, "no compiled room has a guard")
  for n, e in ipairs(picked) do
    hush.load_state("build/dev_states/gfx_room.mss")
    hush.wait(20)
    poke(0x7EC901, e[1] + 1)
    local t = 0
    hush.wait(3)
    while not (hush.read("game_mode") == 0x07 and hush.read("submodule") == 0x00) and t < 600 do hush.wait(5); t = t + 5 end
    hush.wait(30)
    hush.assert(hush.read("game_mode") == 0x07, e[2] .. ": not in a room (module " .. hush.read("game_mode") .. ")")
    hush.assert(guards() > 0, e[2] .. ": no guard sprites present")
    gfx.snap(e[2])
    if n == 1 then
      -- let the guards notice Link (vanilla chase behaviour = the closest stand-in for an alert guard)
      hush.hold({ "down" }, 90); gfx.snap(e[2] .. "_guards_react")
      poke(0x7EF359, 1)
      hush.hold({ "b" }, 3); hush.wait(3); gfx.snap(e[2] .. "_sword_swing")
      hush.wait(120); gfx.snap(e[2] .. "_later")
    end
  end
  hush.pass("guard rooms dumped")
end)
