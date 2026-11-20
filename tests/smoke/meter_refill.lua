-- Smoke (stealth meter, criterion 1): pillars.md:100-101 "On room load, advance and every restart, hush_meter = 32 on the first
-- gameplay frame"; pillars.md:49-51 (refill on new game, advance, every restart; nothing else refills it); pillars.md:69-70
-- (cooldowns clear on room entry). Before each entry the meter is drained by a poke (12) and the per-guard bytes are dirtied, so a
-- pass needs a real refill. "First gameplay frame" = the first frame with game_mode 7 / submodule 0 in the new room (load, advance,
-- new game) or the frame hush_retries goes up (restart: Hush_FastRestart runs inside a gameplay frame, docs/engine_notes.md 11.6).
-- @rom dev
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")
local meter = require("meter")

local function playing() return hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 end

local function dirty()
  meter.set(12)
  for s = 0, 3 do
    hush.write("hush_cd_small", 77, s); hush.write("hush_cd_big", 77, s); hush.write("hush_aprev", 2, s)
  end
end

local function entry_clean(what)
  hush.assert_eq(meter.get(), 32, what .. ": hush_meter on the first gameplay frame (pillars.md:100, criterion 1)")
  for s = 0, 3 do
    hush.assert_eq(hush.read("hush_cd_small", s), 0, what .. ": hush_cd_small[" .. s .. "] cleared on room entry (pillars.md:69-70)")
    hush.assert_eq(hush.read("hush_cd_big", s), 0, what .. ": hush_cd_big[" .. s .. "] cleared on room entry (pillars.md:69-70)")
  end
end

hush.test("meter_refill: 32 on the first gameplay frame of new game, load, advance, restart", function()
  -- 1. new game: the meter and per-guard bytes are dirtied on the title screen (not left at power-on zeros), so 32 needs a real write
  bot.wait_title()
  hush.wait(10)
  dirty()
  hush.assert_eq(meter.get(), 12, "precondition: hush_meter dirtied to 12 on the title screen")
  hush.hold({ "start" }, 4)
  hush.assert(not playing(), "still on the title while START is held")
  local f = meter.watch(900, function() return playing() end)
  hush.assert(f ~= nil, "new game reached gameplay")
  entry_clean("new game")
  bot.wait_control()
  ai._booted = true

  -- 2. room load (debug jump) into ai4_dark
  local idx = ai.room_index("ai4_dark")
  dirty()
  bot.poke(0x7EC901, idx + 1)
  f = meter.watch(300, function() return hush.read("hush_room") == idx and playing() end)
  hush.assert(f ~= nil, "debug jump reached gameplay in ai4_dark")
  entry_clean("room load (jump)")
  bot.wait_control(); hush.wait(5)

  -- 3. nothing in a room raises it (pillars.md:50-51): 200 quiet frames at 12 stay 12
  meter.set(12)
  ai.link_to(0, 140, 0)                    -- out of the guard's 80 px dark range (docs/engine_notes.md 11.3)
  local rose = meter.watch(200, function() return meter.get() ~= 12 end)
  hush.assert(rose == nil, "no refill inside a room: meter changed from 12 to " .. meter.get() .. " with no entry (pillars.md:50-51)")

  -- 4. restart (caught path: hush_caught, the same flag a guard sets, docs/ram_map.md)
  dirty()
  local r0 = hush.read("hush_retries")
  hush.write("hush_caught", 1)
  f = meter.watch(10, function() return hush.read("hush_retries") ~= r0 end)
  hush.assert(f ~= nil, "the caught restart ran (hush_retries went up)")
  entry_clean("caught restart")
  bot.wait_control(); hush.wait(5)

  -- 5. advance: touch the exit of ai4_dark -> the next dev room
  local m = bot.rooms()
  local r = m.rooms[idx + 1]
  dirty()
  local x, y = bot.exit_pos(r.exits[1])
  bot.teleport(x, y)
  f = meter.watch(120, function() return hush.read("hush_room") == idx + 1 and playing() end)
  hush.assert(f ~= nil, "exit -> next room reached gameplay")
  entry_clean("advance")
  hush.pass("hush_meter = 32 and cooldowns cleared on new game, load, restart, advance; no refill inside a room")
end)
