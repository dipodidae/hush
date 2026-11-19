-- Dev utility (E6): is a FAST room load (graphics skipped, hush_gfx = 1) identical to a FULL load (hush_gfx = 0)?
-- After new game: jump to room N once fast, once full (restoring the post-new-game snapshot in between) and diff VRAM, CGRAM
-- and the WRAM tile / collision / palette buffers.   HUSH_ROOM=5 .venv/bin/python tools/run_test.py tests/dev/fastload_diff.lua
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local W = emu.memType.snesWorkRam

local function grab(memtype, off, n)
  local t = {}
  for i = 0, n - 1 do t[i] = emu.read(off + i, memtype, false) end
  return t
end
local function diff(name, a, b, n, base)
  local d, first = 0, nil
  for i = 0, n - 1 do
    if a[i] ~= b[i] then d = d + 1; first = first or i end
  end
  hush.log(string.format("%-34s %5d / %5d bytes differ%s", name, d, n, first and string.format("  (first at +$%X: %02X vs %02X)", base + first, a[first], b[first]) or ""))
  return d
end
local function capture()
  return {
    vram = grab(emu.memType.snesVideoRam, 0, 0x10000),
    cgram = grab(emu.memType.snesCgRam, 0, 0x200),
    tm2000 = grab(W, 0x2000, 0x2000), tm4000 = grab(W, 0x4000, 0x2000),
    coll = grab(W, 0x12000, 0x2000),
    tt = grab(W, 0xFE00, 0x200),
    pal = grab(W, 0xC500, 0x200), palc = grab(W, 0xC300, 0x200),
    zp = grab(W, 0x0000, 0x100), lo = grab(W, 0x0100, 0x1000),
  }
end
hush.test("fast vs full room load", function()
  local room = tonumber(os.getenv("HUSH_ROOM") or "5")
  bot.start_new_game()
  hush.wait(20)
  local s0 = hush.snapshot()
  bot.poke(0x7EC901, room + 1)
  hush.wait(2); bot.wait_control(); hush.wait(30)
  hush.screenshot("fast")
  local f = capture()
  hush.restore(s0); hush.wait(2)
  bot.poke(0x7EC90E, 0)                 -- hush_gfx := 0: full load
  bot.poke(0x7EC901, room + 1)
  hush.wait(2); bot.wait_control(); hush.wait(30)
  hush.screenshot("full")
  local g = capture()
  -- dump the FAST capture so a second run on another ROM can be compared (tools: see the header)
  local function save(name, t, n)
    local fh = assert(io.open(hush.OUT .. "/" .. name .. ".bin", "wb"))
    local b = {}
    for i = 0, n - 1 do b[#b + 1] = string.char(t[i]) end
    fh:write(table.concat(b)); fh:close()
  end
  save("vram", f.vram, 0x10000); save("cgram", f.cgram, 0x200); save("coll", f.coll, 0x2000)
  save("tm2000", f.tm2000, 0x2000); save("tm4000", f.tm4000, 0x2000)
  local total = 0
  for _, k in ipairs({ "vram", "cgram", "tm2000", "tm4000", "tt", "pal", "palc" }) do total = total + diff(k, f[k], g[k], #f[k] + 1, 0) end
  diff("collision $7F2000", f.coll, g.coll, 0x2000, 0)
  diff("dp $00-$FF", f.zp, g.zp, 0x100, 0)
  local l = {}
  for i = 0, 0xFF do if f.zp[i] ~= g.zp[i] then l[#l + 1] = string.format("$%02X:%02X/%02X", i, f.zp[i], g.zp[i]) end end
  hush.log("  dp diffs (fast/full): " .. table.concat(l, " "))
  diff("$0100-$10FF", f.lo, g.lo, 0x1000, 0x100)
  hush.pass(total == 0 and "identical" or (total .. " differing bytes in VRAM/CGRAM/tilemaps"))
end)
