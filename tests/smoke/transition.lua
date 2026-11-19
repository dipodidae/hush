-- Smoke (E6): room advance speed + fast load. Touching an exit cell must give control in the next room within 45 frames
-- (was ~160: Module05/06 full load + iris; pillar 4 "retry instantly"): 6 passes of fade-out, one long load pass, 6 passes of fade-in.
-- Also: a FAST load (graphics skipped, hush_gfx = 1) leaves exactly the same VRAM / CGRAM / tile buffers / collision map / palette
-- buffers (BG2 buffer: inside the window) as a FULL load (hush_gfx = 0) of the same room, and the clear chime SFX3.1B (secret chime, bank_01.asm:12737) plays on the exit.
-- @timeout 150
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local W = emu.memType.snesWorkRam

local function grab(memtype, off, n)
  local t = {}
  for i = 0, n - 1 do t[i] = emu.read(off + i, memtype, false) end
  return t
end
local function ndiff(a, b, n)
  local d = 0
  for i = 0, n - 1 do if a[i] ~= b[i] then d = d + 1 end end
  return d
end
-- the BG2 tile buffer is only valid inside the window (tiles x 16..47, y 18..45): the fast floor copy leaves the previous room's tiles outside it
local function window_diff(a, b)
  local d = 0
  for ty = 18, 45 do
    for i = 0, 63 do
      local o = (ty * 64 + 16) * 2 + i
      if a[o] ~= b[o] then d = d + 1 end
    end
  end
  return d
end
local function capture()
  return { vram = grab(emu.memType.snesVideoRam, 0, 0x10000), cgram = grab(emu.memType.snesCgRam, 0, 0x200),
           tm2000 = grab(W, 0x2000, 0x2000), tm4000 = grab(W, 0x4000, 0x2000), coll = grab(W, 0x12000, 0x2000),
           tt = grab(W, 0xFE00, 0x200), pal = grab(W, 0xC500, 0x200) }
end

hush.test("transition: exit -> next room in <= 45 frames, fast load == full load", function()
  local m = bot.rooms()
  local chime = {}
  emu.addMemoryCallback(function(_, v) if (v & 0x3F) == 0x1B then chime[#chime + 1] = hush.frame() end end, emu.callbackType.write, 0x2143, 0x2143)
  bot.start_new_game()
  hush.wait(30)
  hush.screenshot("before")
  local r = m.rooms[1]
  local x, y = bot.exit_pos(r.exits[1])
  bot.teleport(x, y)
  local f0 = hush.frame()
  local bright, sub, ctl = {}, {}, nil
  for f = 1, 90 do
    hush.wait(1)
    bright[f] = bot.peek(0x7E0013); sub[f] = hush.read("game_mode") * 256 + hush.read("submodule")
    if f == 3 then hush.screenshot("fading_out") end
    if hush.read("room_id") == m.rooms[2].room_id and hush.read("game_mode") == 7 and hush.read("submodule") == 0 and bot.peek(0x7E0010) == 7 and not ctl then ctl = f end
  end
  hush.assert(ctl ~= nil, "control in room 2")
  hush.log(string.format("exit touched -> Link controllable in room 2 after %d frames (was ~160); brightness: %s", ctl, table.concat(bright, " ", 1, ctl + 1)))
  hush.assert(ctl <= 45, "advance must take <= 45 frames, took " .. ctl)
  -- fade out down to black, forced blank during the load, fade in to full
  local lo, hi, saw_blank = 99, 0, false
  for f = 1, ctl do
    if bright[f] == 0x80 then saw_blank = true end
    if bright[f] < 0x80 then lo = math.min(lo, bright[f]) end
    hi = math.max(hi, bright[f] < 0x80 and bright[f] or 0)
  end
  hush.assert(saw_blank, "the load runs in forced blank")
  hush.assert_eq(lo, 0, "the fade-out reaches black")
  hush.assert_eq(bright[ctl], 0x0F, "full brightness when the room plays")
  hush.assert(#chime >= 1 and chime[1] - f0 <= 3, "SFX3.1B (clear chime) played on the exit")
  hush.assert_eq(hush.read("hush_room"), 1, "hush_room advanced")
  hush.screenshot("after")

  -- fast vs full load of the same room, from the same state
  hush.wait(20)
  local s0 = hush.snapshot()
  for _, room in ipairs({ 5, 13 }) do
    hush.restore(s0); hush.wait(2)
    bot.poke(0x7EC90E, 1)                     -- hush_gfx: the room graphics are resident (set by the first full load)
    bot.poke(0x7EC901, room + 1); hush.wait(2); bot.wait_control(); hush.wait(30)
    local fast = capture()
    hush.restore(s0); hush.wait(2)
    bot.poke(0x7EC90E, 0)                     -- hush_gfx = 0: everything is loaded again
    bot.poke(0x7EC901, room + 1); hush.wait(2); bot.wait_control(); hush.wait(30)
    local full = capture()
    hush.assert_eq(window_diff(fast.tm2000, full.tm2000), 0, "room " .. room .. ": fast and full load leave the same BG2 tile buffer inside the window")
    for _, k in ipairs({ "vram", "cgram", "tm4000", "coll", "tt", "pal" }) do
      local n = k == "vram" and 0x10000 or k == "cgram" and 0x200 or k == "tt" and 0x200 or k == "pal" and 0x200 or 0x2000
      hush.assert_eq(ndiff(fast[k], full[k], n), 0, "room " .. room .. ": fast and full load leave the same " .. k)
    end
    hush.assert_eq(bot.peek(0x7EC90E), 1, "the full load sets hush_gfx")
  end
  hush.pass(string.format("exit -> control in %d frames; fast load = full load (rooms 5, 13)", ctl))
end)
