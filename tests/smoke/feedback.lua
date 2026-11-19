-- Smoke (E6): sound effects and the caught flash. The APU ports $2140-$2143 are watched with write callbacks (the NMI copies the SFX / song
-- variables $012C-$012F there, bank_00.asm:239-291); low 6 bits = the id (bits 6-7 of the SFX ports are the pan).
--   '?'  SFX2.3C on $2142   '!'  SFX3.04 on $2143   knife kill SFX3.08 on $2143   dart sleep SFX3.0B on $2143   caught SFX2.26 on $2142
-- and while hush_flash runs (6 frames) the colour-math flash is on (CGWSEL $99 = 0, CGADSUB $9A = $3B, COLDATA $9C-$9E decaying) and
-- restored afterwards. Screenshots of every flash frame go to the result directory.
-- @rom dev
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

local log = {}
local function watch()
  for p = 0, 3 do
    emu.addMemoryCallback(function(_, v) if v ~= 0 then log[#log + 1] = { f = hush.frame(), port = p, id = v & 0x3F, raw = v } end end,
      emu.callbackType.write, 0x2140 + p, 0x2140 + p)
  end
end
local function seen(port, id, since)
  for _, e in ipairs(log) do if e.port == port and e.id == id and e.f >= (since or 0) then return e.f end end
  return nil
end
local function wait_for(port, id, since, max)
  for _ = 1, max do
    if seen(port, id, since) then return true end
    hush.wait(1)
  end
  return seen(port, id, since) ~= nil
end

hush.test("feedback: ?, !, knife, dart, caught sounds + flash", function()
  local r = ai.enter("ai4_dark")
  watch()
  hush.assert_eq(bot.peek(0x7EF340), 2, "Link has the bow")

  -- '?' then '!': Link stands in front of the east-facing guard
  local t0 = hush.frame()
  ai.link_to(0, 44, 0)
  hush.assert(ai.wait_state(0, ai.S.SUSPICIOUS, 20), "the guard notices Link")
  hush.assert(wait_for(2, 0x3C, t0, 6), "SFX2.3C ('?') went to the APU on notice")
  hush.assert_eq(seen(3, 0x04, t0), nil, "no alert sound yet")
  local ta = hush.frame()
  hush.assert(ai.wait_state(0, ai.S.ALERT, 90), "60 frames later: ALERT")
  hush.assert(wait_for(3, 0x04, ta, 6), "SFX3.04 ('!') went to the APU on alert")

  -- caught: contact with the alert guard. Flash registers are read every frame.
  local tc = hush.frame()
  local base99, base9a = bot.peek(0x7E0099), bot.peek(0x7E009A)
  local flash_frames, shots, r_seen = 0, 0, {}
  for f = 1, 80 do
    hush.wait(1)
    local fl = hush.read("hush_flash")
    if fl ~= 0 then
      flash_frames = flash_frames + 1
      r_seen[#r_seen + 1] = bot.peek(0x7E009C) & 0x1F
      hush.assert_eq(bot.peek(0x7E0099), 0x00, "flash: fixed colour")
      hush.assert_eq(bot.peek(0x7E009A), 0x3B, "flash: add to BG1, BG2, OBJ, backdrop")
      hush.assert_eq(bot.peek(0x7E0013), 0x0F, "the screen stays on during the flash")
      shots = shots + 1
      hush.screenshot("flash" .. shots)
    elseif flash_frames > 0 then
      break
    end
  end
  hush.log("flash frames " .. flash_frames .. ", red intensity per frame: " .. table.concat(r_seen, " "))
  hush.assert(flash_frames >= 4 and flash_frames <= 6, "the flash lasts 5 frames (+-1), got " .. flash_frames)
  hush.assert(r_seen[1] > r_seen[#r_seen], "the flash decays")
  hush.assert(seen(2, 0x26, tc) ~= nil, "SFX2.26 (Link's hurt cry) played when caught")
  hush.wait(2)
  hush.assert_eq(bot.peek(0x7E0099), base99, "CGWSEL restored")
  hush.assert_eq(bot.peek(0x7E009A), base9a, "CGADSUB restored")
  hush.assert_eq(bot.peek(0x7E009C), 0x20, "COLDATA red plane restored")
  hush.assert_eq(bot.peek(0x7E0013), 0x0F, "full brightness")
  hush.screenshot("after_flash")

  -- knife takedown: unaware guard from behind
  ai.restart(); hush.wait(8); bot.wait_control()
  local tk = hush.frame()
  ai.link_to(0, -26, 0); bot.poke(0x7E002F, 6); hush.wait(1); hush.hold({ "b" }, 2)
  hush.assert(ai.watch(14, function() return not ai.alive(0) end) ~= nil, "the guard dies")
  hush.assert(wait_for(3, 0x08, tk, 4), "SFX3.08 (hit) on the knife takedown")

  -- dart sleep
  ai.restart(); hush.wait(8); bot.wait_control()
  bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3)
  ai.link_to(0, -60, 0); bot.poke(0x7E002F, 6); hush.wait(2)
  local td = hush.frame()
  hush.press({ "y" }, 3, 1)
  hush.assert(ai.watch(40, function() return ai.state(0) == ai.S.ASLEEP end) ~= nil, "the dart puts him to sleep")
  hush.assert(wait_for(3, 0x0B, td, 4), "SFX3.0B (chime) on the dart sleep")
  hush.pass("sounds: ? " .. tostring(seen(2, 0x3C)) .. ", ! " .. tostring(seen(3, 0x04)) .. ", caught " .. tostring(seen(2, 0x26)) ..
    ", knife " .. tostring(seen(3, 0x08)) .. ", dart " .. tostring(seen(3, 0x0B)))
end)
