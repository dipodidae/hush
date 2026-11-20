-- Dev utility (QA, not a test): README screenshots of the stealth meter (design/pillars.md:42-122) in real gameplay.
-- Every state comes from natural play (pad input only: walking, the item menu, an ink pot); no RAM pokes.
--   r05 (room 4):    walk east along row 9 to (8,9), the guard notices ("?", -4 -> 28)              -> suspicious.png
--                    stand in the open 1 s, he turns Alert ("!", -16 -> 12), shot inside the 16-frame hit flash -> alert.png
--   final (room 20): select Ink Pots in the menu, drop one at (13,11) facing west, step into guard a's view at col 10 ("?" 28,
--                    "!" 12), let him charge to 32 px, retreat into the cloud (a calmed, no refund)           -> ink.png
--                    after the cloud, step back into his view (> 120 frames after his last small hit): "?" again, 12 -> 8;
--                    shot past the hit flash, with the filled cells in their amber blink phase              -> low_meter.png
-- Each shot checks its RAM / VRAM conditions (hush_meter, hush_mflash, spr_aware, the HUD cells in VRAM, the cloud), held for
-- 3+ frames, then re-checked on the frame that is written, and fails if they do not hold: a PNG is never a transition frame or
-- the wrong state. Frames come from emu.getScreenBuffer with frame skipping defeated (see shot()), not hush.screenshot.
-- Output: $HUSH_OUT = build/test-results/dev_readme_shots/{suspicious,alert,ink,low_meter}.png, SHOT lines on stdout,
-- check/<shot>_{hud,guard}.png = 4x crops for checking the meter and the icon by eye.
--   .venv/bin/python tools/run_test.py tests/dev/readme_shots.lua
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local meter = require("meter")
local CUR_ROOM                 -- for the failure messages

local function room(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1, r end end
  error({ hush_fail = "no room " .. id })
end

-- Link coordinates of grid cell (cx, cy) (bot.walk_exit convention)
local function cell_xy(r, cx, cy)
  local m = bot.rooms()
  return r.base_x + m.win_x + cx * 16, r.base_y + m.win_y + cy * 16 - 8
end

local function aware(s) return hush.read("spr_aware", s) end
-- sprite slot of guard `gid` = its index in the rooms_gen guards list (row-major grid order, tests/lib/ai.lua:9)
local function slot_of(r, gid)
  for k, g in ipairs(r.guards) do if g.id == gid then return k - 1 end end
  error({ hush_fail = r.id .. ": no guard " .. gid })
end
local function caught() return bot.peek(0x7EC902) ~= 0 end

local function status(r)
  local t = {}
  for k = 0, #r.guards - 1 do
    local s = hush.sprite(k)
    t[#t + 1] = string.format("%s=%d@%d,%d", r.guards[k + 1].id, aware(k), s.x, s.y)
  end
  return string.format("meter=%d mflash=%d mlost=%d ink_t=%d ink@%d,%d link=(%d,%d) aware[%s] vram=%s", meter.get(), hush.read("hush_mflash"),
    hush.read("hush_mlost"), hush.read("hush_ink_t"), hush.read("hush_ink_x"), hush.read("hush_ink_y"), hush.read("link_x"), hush.read("link_y"), table.concat(t, " "), meter.fmt(meter.vram_cells()))
end

-- Walk toward (px, py) one frame at a time until stop() is true (returns true) or arrival / timeout (returns false).
local function walk_until(px, py, stop, max)
  for _ = 1, max or 400 do
    if stop() then return true end
    local x, y = hush.read("link_x"), hush.read("link_y")
    local b = {}
    if x < px - 1 then b[#b + 1] = "right" elseif x > px + 1 then b[#b + 1] = "left" end
    if y < py - 1 then b[#b + 1] = "down" elseif y > py + 1 then b[#b + 1] = "up" end
    if #b == 0 then hush.wait(1) else hush.hold(b, 1) end
    hush.assert(not caught(), "caught while walking")
  end
  return stop()
end

-- Wait up to max frames until cond() has held for `hold` consecutive frames.
local function wait_stable(cond, hold, max, what)
  local n = 0
  for _ = 1, max do
    hush.wait(1)
    if cond() then n = n + 1; if n >= hold then return end else n = 0 end
    hush.assert(not caught(), what .. ": caught while waiting")
  end
  hush.assert(false, what .. ": condition never held for " .. hold .. " frames; " .. status(CUR_ROOM))
end

-- PNG of the real PPU frame buffer of the frame just finished. emu.takeScreenshot (hush.screenshot) goes through the video
-- decoder thread and can return a frame tens of frames old under --testRunner (seen here: alert.png came out identical to
-- suspicious.png, 60+ frames earlier); emu.getScreenBuffer has no lag (tests/dev/flash_probe.lua:1). Stored (uncompressed) deflate.
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
  local W = 256
  if #buf // W > 240 then W = 512 end
  local x0, y0, w, h, k = 0, 0, W, #buf // W, 1
  if crop then x0, y0, w, h, k = crop[1], crop[2], crop[3], crop[4], crop[5] end
  local rows = {}
  for y = 0, h * k - 1 do
    local t = { "\0" }
    local sy = math.min(math.max(y0 + y // k, 0), #buf // W - 1)
    for x = 0, w * k - 1 do
      local sx = math.min(math.max(x0 + x // k, 0), W - 1)
      local p = buf[sy * W + sx + 1]
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

-- The emulator renders at most one frame per ~10 ms of wall time when it runs faster than real time (frame skipping: the PPU
-- output buffer keeps an old frame; seen here as alert.png == suspicious.png, 48 frames apart, same pixel CRC). So: hold the
-- emulation thread for 40 ms (busy wait; os.clock is CPU time, which a busy loop spends 1:1), run ONE frame so it is rendered,
-- re-check the state, then write that frame. A shot identical to the previous one fails.
local last_sum
local function shot(name, r, desc, cond, gslot)
  local t0 = os.clock(); while os.clock() - t0 < 0.04 do end
  hush.wait(1)
  hush.assert(cond(), name .. ": state changed on the rendered frame; " .. status(r))
  hush.assert(hush.read("game_mode") == 0x07 and hush.read("submodule") == 0, name .. ": not in gameplay")
  hush.assert_eq(bot.peek(0x7EC90F), 0, name .. ": room transition running (hush_trans)")
  hush.assert_eq(hush.read("hush_flash"), 0, name .. ": caught flash running")
  local sum = write_png(name)
  hush.assert(sum ~= last_sum, name .. ": same pixels as the previous shot (a skipped / stale frame)")
  last_sum = sum
  -- 4x crops for checking the small details by eye (meter, the guard's icon): $HUSH_OUT/check/ (not README material)
  os.execute("mkdir -p '" .. hush.OUT .. "/check'")
  write_png("check/" .. name .. "_hud", { 150, 16, 80, 32, 4 })
  local g = hush.sprite(gslot)
  local sx, sy = g.x - hush.read("bg1_x"), g.y - hush.read("bg1_y")
  write_png("check/" .. name .. "_guard", { sx - 24, sy - 24, 64, 64, 4 })
  print(string.format("SHOT: %s.png  %s | %s", name, desc, status(r)))
end

hush.test("readme_shots", function()
  bot.start_new_game()

  ---------------------------------------------------------------- r05: suspicious + alert
  local i5, r5 = room("r05")
  CUR_ROOM = r5
  bot.jump_to_room_synced(i5)
  hush.wait(20)
  local FULL = meter.vram_cells()
  local P_FULL = meter.pal(FULL[0])
  hush.assert_eq(meter.get(), 32, "r05: full meter at entry")
  print("SHOT: r05 entry " .. status(r5))

  -- (1,7) -> (1,9) -> east along row 9 until the guard notices (r05.yaml:43-44: at (8,9) a '?' appears)
  local x19, y19 = cell_xy(r5, 1, 9)
  walk_until(x19, y19, function() return false end, 120)
  local x89, y89 = cell_xy(r5, 8, 9)
  hush.assert(walk_until(x89 + 8, y89, function() return aware(0) ~= 0 end, 300), "r05: the guard never noticed Link on row 9")
  hush.assert_eq(aware(0), 1, "r05: first transition is Suspicious")
  -- suspicious.png: past the 16-frame hit flash, still '?', meter 28 (7 filled + 1 drained)
  local c_sus = function() return hush.read("hush_mflash") == 0 and aware(0) == 1 and meter.get() == 28 end
  wait_stable(c_sus, 3, 40, "suspicious")
  shot("suspicious", r5, "r05, guard '?' (Suspicious), meter 28", c_sus, 0)

  -- alert.png: stand still in the open; after ~1 s he turns Alert (r05.yaml:46-47), big hit 28 -> 12. Shot inside the flash.
  local f = meter.watch(150, function() return aware(0) == 2 end)
  hush.assert(f ~= nil, "r05: the guard never turned Alert")
  local lost = function()       -- lost cells 3..6 drawn amber in VRAM: neither filled (cell 0) nor drained (cell 7)
    local v = meter.vram_cells()
    return v[3] ~= v[0] and v[3] ~= v[7] and v[6] == v[3] and v[2] == v[0]
  end
  local c_alert = function() return aware(0) == 2 and meter.get() == 12 and hush.read("hush_mflash") >= 2 and lost() end
  wait_stable(c_alert, 4, 16, "alert flash")
  shot("alert", r5, "r05, guard '!' (Alert, amber), meter 12 with the 4 lost cells amber (hit flash)", c_alert, 0)

  ---------------------------------------------------------------- final: ink + low meter
  local iF, rF = room("final")
  CUR_ROOM = rF
  bot.jump_to_room_synced(iF)
  hush.wait(20)
  hush.assert_eq(meter.get(), 32, "final: full meter at entry")
  -- item menu, as tests/solutions/final.inputs:7-10 and :43-50 (default item, then two to the right = Ink Pots)
  hush.press({ "start" }, 2, 31); hush.press({ "start" }, 2, 31)
  hush.press({ "start" }, 2, 31); hush.press({ "right" }, 2, 6); hush.press({ "right" }, 2, 6); hush.press({ "start" }, 2, 31)
  bot.wait_control()
  hush.assert_eq(bot.peek(0x7E0202), 4, "final: Ink Pots selected (HUD item index 4, tests/smoke/ai_ink.lua:53)")
  print("SHOT: final entry " .. status(rF))

  -- (14,11) -> (13,11) facing west, drop a pot (lands in front: ~(12,11)), wait for the cloud (ai_ink: 300 frames)
  local x13, y11 = cell_xy(rF, 13, 11)
  walk_until(x13, y11, function() return false end, 60)
  hush.hold({ "left" }, 1)
  local pots = bot.peek(0x7EF343)
  hush.press({ "y" }, 3, 1)
  hush.assert_eq(bot.peek(0x7EF343), pots - 1, "final: one ink pot used")
  local t_pot = hush.frame()
  -- the fuse is ~157 frames (tests/smoke/ai_ink.lua log): long enough for ? (28), ! (12) and a's charge before the cloud is up

  -- west to col 10 (final.yaml:98: a sees row 11 to col 10, lit range 8) until a notices
  local A = slot_of(rF, "a")
  local x10 = cell_xy(rF, 10, 11)
  hush.assert(walk_until(x10 - 8, y11, function() return aware(A) ~= 0 end, 200), "final: a never noticed Link")
  hush.assert_eq(aware(A), 1, "final: a Suspicious first")
  hush.assert_eq(meter.get(), 28, "final: only a noticed")
  local t_small = hush.frame()
  hush.assert(meter.watch(150, function() return aware(A) == 2 end), "final: a never turned Alert")
  hush.assert_eq(meter.get(), 12, "final: ? + ! = 20")
  -- let him charge until he is close (so he ends up next to the cloud), then back east into the cloud: a's line to Link crosses
  -- it -> Unaware at once (ai_ink.lua:1-3), no refund
  local near = meter.watch(150, function() return math.abs(hush.sprite(A).x - hush.read("link_x")) <= 32 or caught() end)
  hush.assert(near ~= nil and not caught(), "final: a did not close in (or caught)")
  print(string.format("SHOT: a charging, %d px from Link, %d frames after the pot | %s", math.abs(hush.sprite(A).x - hush.read("link_x")),
    hush.frame() - t_pot, status(rF)))
  local xc = cell_xy(rF, 12, 11)          -- the pot's cell (12,11): the cloud centre once it is up
  if hush.read("hush_ink_t") > 0 then xc = hush.read("hush_ink_x") - 8 end
  hush.assert(walk_until(xc, y11, function() return aware(A) == 0 end, 120), "final: the cloud did not calm a")
  hush.assert_eq(meter.get(), 12, "final: ink does not refund (pillars.md:77)")
  -- ink.png: the cloud with guard a near it
  local c_ink = function()
    local g = hush.sprite(A)
    return hush.read("hush_ink_t") > 60 and hush.read("hush_mflash") == 0 and aware(A) == 0
      and math.abs(g.x + 8 - hush.read("hush_ink_x")) <= 72
  end
  wait_stable(c_ink, 3, 60, "ink")
  shot("ink", rF, string.format("final, Ink Pot cloud, guard a calmed %d px from its centre, meter 12",
    math.abs(hush.sprite(A).x + 8 - hush.read("hush_ink_x"))), c_ink, A)

  -- after the cloud: step back into a's view; second small hit (> 120 frames after the first) 12 -> 8
  hush.assert(meter.watch(400, function() return hush.read("hush_ink_t") == 0 end), "final: the cloud never ended")
  hush.assert(hush.frame() - t_small > 121, "final: the second notice is past a's small-hit cooldown")
  hush.assert(walk_until(x10 - 8, y11, function() return aware(A) == 1 or meter.get() < 12 end, 400), "final: no second notice")
  -- low_meter.png: meter 8, flash over, filled cells 0-1 in the amber blink phase (palette != the full-meter violet), '?' still up
  local c_low = function()
    local v = meter.vram_cells()
    return meter.get() == 8 and hush.read("hush_mflash") == 0 and aware(A) == 1
      and meter.pal(v[0]) ~= P_FULL and v[1] == v[0] and v[2] ~= v[0]
  end
  wait_stable(c_low, 3, 50, "low meter amber phase")
  shot("low_meter", rF, "final, meter 8, the 2 filled cells in the amber blink phase; guard a Suspicious in the door (his '?' is"
    .. " drawn 22 px up, inside wall row 9, and the priority-1 wall hides it: docs/gfx/art_map.md:164-166)", c_low, A)
  hush.pass("4 shots")
end)
