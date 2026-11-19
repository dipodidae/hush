-- Smoke (E6): music per floor. roomgen writes EntranceData.song = the floor's song on the first room of a floor ($10 / $11 / $16),
-- $1C on the last (heist) room and $FF ("keep") elsewhere; Hush_RoomMusic starts it when the room's fade-in ends. Checks the APU port
-- $2140 (writes) and the NMI's bookkeeping: $0133 = last song sent (bank_00.asm:243-255), $0130 = current song (:260), and that the SPC
-- answers (the sound engine echoes the song id on its output port, which the NMI compares against $0133, bank_00.asm:239-247).
-- Rooms inside a floor must not touch port 0 (the track keeps playing).
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local writes, zero_after = {}, {}     -- zero_after[song] = frame of the first 0 written to APUIO0 after that song (the NMI only clears the port once the SPC echoed the id)
local function nz_writes_since(f)
  local out = {}
  for _, w in ipairs(writes) do if w.f >= f then out[#out + 1] = w.v end end
  return out
end

hush.test("music: a song per floor, started once", function()
  local last
  emu.addMemoryCallback(function(_, v)
    if v ~= 0 then writes[#writes + 1] = { f = hush.frame(), v = v }; last = v
    elseif last and not zero_after[last] then zero_after[last] = hush.frame() end
  end, emu.callbackType.write, 0x2140, 0x2140)
  local m = bot.rooms()
  local want = {}
  for i, r in ipairs(m.rooms) do want[i - 1] = r.song end
  hush.assert_eq(want[0], 0x10, "room 0 = floor 1 song $10 (Hyrule Castle)")
  hush.assert_eq(want[1], 0xFF, "room 1 keeps the music")
  hush.assert_eq(want[6], 0x11, "room 6 = first floor-2 room, song $11")
  hush.assert_eq(want[14], 0x16, "room 14 = first floor-3 room, song $16")
  hush.assert_eq(want[m.count - 1], 0x1C, "the heist room has its own song $1C (Suspense)")

  bot.start_new_game()
  hush.wait(60)
  hush.assert_eq(bot.peek(0x7E0130), 0x10, "$0130 (current song) = $10 after the new game")
  hush.assert_eq(bot.peek(0x7E0133), 0x10, "$0133 (last song sent to the APU) = $10")
  local seen10 = false
  for _, w in ipairs(writes) do if w.v == 0x10 then seen10 = true end end
  hush.assert(seen10, "$10 was written to APUIO0")
  hush.assert(zero_after[0x10] ~= nil, "the SPC echoed $10: the NMI cleared APUIO0 afterwards (bank_00.asm:239-247)")

  -- inside floor 1: no new song command
  local f0 = hush.frame()
  bot.jump_to_room(4)
  hush.wait(40)
  hush.assert_eq(#nz_writes_since(f0), 0, "room 4 (same floor): nothing written to APUIO0")
  hush.assert_eq(bot.peek(0x7E0130), 0x10, "still song $10")

  for _, idx in ipairs({ 6, 9, 14, 17, m.count - 1 }) do
    local f1 = hush.frame()
    bot.jump_to_room(idx)
    hush.wait(40)
    local w = nz_writes_since(f1)
    if want[idx] == 0xFF then
      hush.assert_eq(#w, 0, "room " .. idx .. " keeps the music")
    else
      hush.assert_eq(#w, 1, "room " .. idx .. ": exactly one song command")
      hush.assert_eq(w[1], want[idx], "room " .. idx .. " plays song $" .. string.format("%02X", want[idx]))
      hush.assert_eq(bot.peek(0x7E0130), want[idx], "$0130 follows")
    end
  end
  hush.pass("songs " .. string.format("$%02X $%02X $%02X $%02X", 0x10, 0x11, 0x16, 0x1C) .. " started per floor, none inside a floor")
end)
