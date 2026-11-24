-- Dev utility (QA, not a test): README screenshots of the lantern lighting (design/lighting.md) in real gameplay.
-- Rooms are hard-coded (no env vars); Link stands at the room's start cell, no RAM pokes.
--   r16 (lit): guard a at (7,2) looks down col 7 through the one-cell door (7,8) (r16.yaml:10-14, 35-36); his cone passes the
--              door and spreads out in the south hall                                                       -> light_cone.png
--   r14 (lit, room index 13): four guards light their lanes (r14.yaml:10-16): c and d light the row-4 corridor from both ends,
--              a lights row 9, b walks col 5; c and d stand in the corridor between the row-3 and row-5 walls, so their sprites
--              show the depth rule (feet behind the wall below, head over the wall above)                  -> light_lanes.png
-- Every shot waits until the light engine is idle (docs/ram_map.md: light_dirty == 0, every light_tdirty byte 0, worker byte
-- light_job + 8 == $FF = idle, the check of tests/dev/light_latency.lua render_idle() plus "no job"), so the light is complete,
-- and the committed signature of every guard slot equals its live one (light_sigc vs live_sig, as light_latency.lua).
-- Frames come from emu.getScreenBuffer after a 40 ms busy wait (the no-stale-frame shot() of tests/dev/readme_shots.lua).
-- Output: $HUSH_OUT = build/test-results/dev_readme_light_shots/{light_cone,light_lanes}.png, SHOT lines on stdout,
-- check/<shot>_guard<slot>.png = 4x crops around each named guard.
--   .venv/bin/python tools/run_test.py tests/dev/readme_light_shots.lua
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W = emu.memType.snesWorkRam
local function rd(a) return emu.read(a, W, false) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local LM = emu.memType.snesSaveRam       -- light rows: SA-1 BW-RAM since SA-1 step 3 (docs/ram_map.md "HUSH lighting")
local function rl(a) return emu.read(a, LM, false) end
local function rl16(a) return rl(a) + 256 * rl(a + 1) end
local function ram(name)
  local e = hush.ram[name]
  if not e or e.mem ~= LM then hush.fail("docs/ram_map.md: " .. name .. " missing or not BW-RAM") end
  return e.addr
end

local function room(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1, r end end
  error({ hush_fail = "no room " .. id })
end
local function slot_of(r, gid)
  for k, g in ipairs(r.guards) do if g.id == gid then return k - 1 end end
  error({ hush_fail = r.id .. ": no guard " .. gid })
end
local function caught() return bot.peek(0x7EC902) ~= 0 end
local function aware(s) return hush.read("spr_aware", s) end
-- grid cell of a sprite (inverse of the bot.walk_exit convention: x = base_x + win_x + cx * 16)
local function cell_of(r, s)
  local m, g = bot.rooms(), hush.sprite(s)
  return (g.x + 8 - r.base_x - m.win_x) // 16, (g.y + 8 - r.base_y - m.win_y) // 16
end

-- light engine (docs/ram_map.md rows light_comp, light_dirty, light_tdirty, light_job, light_sigc, light_on)
local L
local function comp(cx, cy) return rl(L.COMP + cy * 16 + cx) end
local function live_sig(s)              -- same as tests/dev/light_latency.lua live_sig()
  local st, typ, aw = rd(0x0DD0 + s), rd(0x0E20 + s), rd(0x0D80 + s)
  if st ~= 9 or typ ~= 0x41 or aw >= 3 then return { 0, 0, 0 } end
  local x = rd(0x0D10 + s) + 256 * rd(0x0D30 + s) + 8 - rd16(0xE2)
  local y = rd(0x0D00 + s) + 256 * rd(0x0D20 + s) + 8 - rd16(0xE8)
  if x < 0 or x >= 256 or y < 0 or y >= 224 then return { 0, 0, 0 } end
  local cls = aw + 1
  return { cls, cls == 1 and (rd(0x0DE0 + s) & 3) or 0, (y // 16 + 8) * 32 + x // 16 + 8 }
end
local function sig_ok(s)
  local a, b = live_sig(s), { rl(L.SIGC + 4 * s), rl(L.SIGC + 4 * s + 1), rl16(L.SIGC + 4 * s + 2) }
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local function light_idle()
  if rl(L.ON) ~= 1 or rl16(L.DIRTY) ~= 0 or rl(L.JOB) ~= 0xFF then return false end
  for i = 0, 111 do if rl(L.TDIRTY + i) ~= 0 then return false end end
  for s = 0, 7 do if not sig_ok(s) then return false end end
  return true
end

local function grid_dump()
  local t = {}
  for cy = 0, 13 do
    local row = {}
    for cx = 0, 15 do local c = comp(cx, cy); row[#row + 1] = c > 0 and tostring(c) or "." end
    t[#t + 1] = table.concat(row)
  end
  return table.concat(t, "\n")
end
local function status(r)
  local t = {}
  for k = 0, #r.guards - 1 do
    local cx, cy = cell_of(r, k)
    t[#t + 1] = string.format("%s=%d@(%d,%d)", r.guards[k + 1].id, aware(k), cx, cy)
  end
  return string.format("dirty=%04X job=%02X link=(%d,%d) aware[%s]", rl16(L.DIRTY), rl(L.JOB), hush.read("link_x"),
    hush.read("link_y"), table.concat(t, " "))
end

local function wait_stable(r, cond, hold, max, what)
  local n = 0
  for _ = 1, max do
    hush.wait(1)
    hush.assert(not caught(), what .. ": caught while waiting")
    if cond() then n = n + 1; if n >= hold then return end else n = 0 end
  end
  hush.assert(false, what .. ": condition never held for " .. hold .. " frames; " .. status(r) .. "\n" .. grid_dump())
end

-- PNG writer: same as tests/dev/readme_shots.lua (stored deflate, emu.getScreenBuffer)
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do c = (c & 1) ~= 0 and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
  CRC[i] = c
end
local function crc32(s, c)
  c = (c or 0) ~ 0xFFFFFFFF
  for i = 1, #s do c = CRC[(c ~ s:byte(i)) & 0xFF] ~ (c >> 8) end
  return c ~ 0xFFFFFFFF
end
local function be32(v) return string.pack(">I4", v & 0xFFFFFFFF) end
local function chunk(kind, data) return be32(#data) .. kind .. data .. be32(crc32(kind .. data)) end

local function write_png(name, crop)
  local buf = emu.getScreenBuffer()
  local Wd = 256
  if #buf // Wd > 240 then Wd = 512 end
  local x0, y0, w, h, k = 0, 0, Wd, #buf // Wd, 1
  if crop then x0, y0, w, h, k = crop[1], crop[2], crop[3], crop[4], crop[5] end
  local rows = {}
  for y = 0, h * k - 1 do
    local t = { "\0" }
    local sy = math.min(math.max(y0 + y // k, 0), #buf // Wd - 1)
    for x = 0, w * k - 1 do
      local sx = math.min(math.max(x0 + x // k, 0), Wd - 1)
      local p = buf[sy * Wd + sx + 1]
      t[#t + 1] = string.char((p >> 16) & 255, (p >> 8) & 255, p & 255)
    end
    rows[#rows + 1] = table.concat(t)
  end
  w, h = w * k, h * k
  local raw = table.concat(rows)
  local a, b = 1, 0
  for i = 1, #raw do a = (a + raw:byte(i)) % 65521; b = (b + a) % 65521 end
  local z = { "\120\1" }
  local pos = 1
  while pos <= #raw do
    local n = math.min(65535, #raw - pos + 1)
    local last = (pos + n > #raw) and 1 or 0
    z[#z + 1] = string.pack("<I1I2I2", last, n, n ~ 0xFFFF) .. raw:sub(pos, pos + n - 1)
    pos = pos + n
  end
  z[#z + 1] = be32((b << 16) | a)
  local png = "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4I4I1I1I1I1I1", w, h, 8, 2, 0, 0, 0))
    .. chunk("IDAT", table.concat(z)) .. chunk("IEND", "")
  local path = string.format("%s/%s.png", hush.OUT, name)
  local f = assert(io.open(path, "wb"))
  f:write(png); f:close()
  local sum = crc32(raw)
  hush.log(string.format("png %s (%dx%d, frame %d, pixel crc %08X)", path, w, h, hush.frame(), sum))
  return sum
end

-- 40 ms busy wait (defeats frame skipping, see readme_shots.lua shot()), one frame, re-check, write that frame.
local last_sum
local function shot(name, r, desc, cond, slots)
  local t0 = os.clock(); while os.clock() - t0 < 0.04 do end
  hush.wait(1)
  hush.assert(cond(), name .. ": state changed on the rendered frame; " .. status(r) .. "\n" .. grid_dump())
  hush.assert(hush.read("game_mode") == 0x07 and hush.read("submodule") == 0, name .. ": not in gameplay")
  hush.assert_eq(bot.peek(0x7EC90F), 0, name .. ": room transition running (hush_trans)")
  hush.assert_eq(hush.read("hush_flash"), 0, name .. ": caught flash running")
  local sum = write_png(name)
  hush.assert(sum ~= last_sum, name .. ": same pixels as the previous shot (a skipped / stale frame)")
  last_sum = sum
  os.execute("mkdir -p '" .. hush.OUT .. "/check'")
  for _, s in ipairs(slots) do
    local g = hush.sprite(s)
    local sx, sy = g.x - hush.read("bg1_x"), g.y - hush.read("bg1_y")
    write_png("check/" .. name .. "_guard" .. s, { sx - 24, sy - 24, 64, 64, 4 })
  end
  print(string.format("SHOT: %s.png  %s | %s\n%s", name, desc, status(r), grid_dump()))
end

hush.test("readme_light_shots", function()
  L = { COMP = ram("light_comp"), SIGC = ram("light_sigc"), DIRTY = ram("light_dirty"), JOB = ram("light_job") + 8,
        TDIRTY = ram("light_tdirty"), ON = ram("light_on") }
  bot.start_new_game()

  ---------------------------------------------------------------- r16: cone through the door
  local i16, r16 = room("r16")
  bot.jump_to_room_synced(i16)
  local A, B = slot_of(r16, "a"), slot_of(r16, "b")
  -- r16.yaml:35-36: a at (7,2) looks down col 7 (sight to row 10); the door is (7,8). Light below the door = rows 9-11.
  -- b (row 5 patrol) must be clear of cols 5-9 so his body / light does not hide or mix with a's cone at the door.
  local c_cone = function()
    local bx = cell_of(r16, B)
    local spread = 0
    for cx = 4, 10 do if cx ~= 7 and comp(cx, 10) > 0 then spread = spread + 1 end end
    return light_idle() and aware(A) == 0 and aware(B) == 0 and (bx <= 3 or bx >= 11)
      and comp(7, 8) > 0 and comp(7, 9) > 0 and comp(7, 10) > 0 and spread >= 2
  end
  wait_stable(r16, c_cone, 3, 900, "r16 cone")
  shot("light_cone", r16, "r16, guard a's lantern cone down col 7 through the door (7,8), spreading in the south hall", c_cone, { A })

  ---------------------------------------------------------------- r14: four lit lanes
  local i14, r14 = room("r14")
  hush.assert_eq(i14, 13, "r14 is room index 13 (bot.jump_to_room(13))")
  bot.jump_to_room_synced(i14)
  local C, D = slot_of(r14, "c"), slot_of(r14, "d")
  -- r14.yaml:51,57: c (1,4) lights east, d (14,4) lights west along the row-4 corridor; r14.yaml:37: a (13,9) lights row 9
  local c_lanes = function()
    if not light_idle() then return false end
    for k = 0, #r14.guards - 1 do if aware(k) ~= 0 then return false end end
    return comp(3, 4) > 0 and comp(12, 4) > 0 and comp(10, 9) > 0
  end
  wait_stable(r14, c_lanes, 3, 900, "r14 lanes")
  shot("light_lanes", r14, "r14 (lit), four guards light their lanes; c and d stand in the row-4 corridor between walls", c_lanes,
    { C, D, slot_of(r14, "a"), slot_of(r14, "b") })
  hush.pass("2 shots")
end)
