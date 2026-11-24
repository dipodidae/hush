-- Dev probe (engine, SA-1 step 5a; not a test): per frame in room r01 the publish state (sa1_pubf / pubt, light_wd / pubm / dirty /
-- done) and the first BG1 VRAM window word that differs from light_tiles (old or new window layout, LIGHT_WIN0 from build/hush.sym).
--   .venv/bin/python tools/run_test.py src/dev/pub_trace.lua
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local IRAM, BW, V = emu.memType.sa1InternalRam, emu.memType.snesSaveRam, emu.memType.snesVideoRam
local function bw(a) return emu.read(a, BW, false) end
local function bw16(a) return bw(a) + 256 * bw(a + 1) end
local WIN0 = false
for line in io.lines(os.getenv("HUSH_ROOT") .. "/build/hush.sym") do
  if line:match(" Hush_NmiBg1$") then WIN0 = true end
end
local function vram_bg1(trow, tcol)
  if WIN0 then return emu.read16((0x1000 + trow * 32 + tcol) * 2, V, false) end
  local tx, ty = 16 + tcol, 18 + trow
  local w = 0x1000 + (ty >= 32 and 0x800 or 0) + (tx >= 32 and 0x400 or 0) + (ty % 32) * 32 + (tx % 32)
  return emu.read16(w * 2, V, false)
end
hush.test("pub trace", function()
  local wlog = 0
  local function wcb(name) return function(addr, value)
    if wlog < tonumber(os.getenv("WLOG") or "0") then
      wlog = wlog + 1
      local s = emu.getState()
      hush.log(string.format("  write %s $%06X := %02X  sa1 pc %02X%04X  line %d  wd %04X pubf %d", name, addr, value, s["sa1.cpu.k"] or 0, s["sa1.cpu.pc"] or 0,
        s["ppu.scanline"], bw16(0xE744), emu.read(0x0A, IRAM, false)))
    end
  end end
  emu.addMemoryCallback(wcb("tile(9,2)"), emu.callbackType.write, 0x40DAD2, 0x40DAD3, emu.cpuType.sa1, emu.memType.sa1Memory)
  emu.addMemoryCallback(wcb("light_wd"), emu.callbackType.write, 0x40E744, 0x40E745, emu.cpuType.sa1, emu.memType.sa1Memory)
  emu.addMemoryCallback(wcb("pub(9,2)"), emu.callbackType.write, 0x402092, 0x402093, emu.cpuType.sa1, emu.memType.sa1Memory)
  bot.start_new_game()
  bot.jump_to_room(tonumber(os.getenv("ROOM") or "0"))
  local bad = 0
  for f = 1, tonumber(os.getenv("FRAMES") or "20") do
    hush.hold(f % 40 < 20 and { "left" } or { "right" }, 1)
    local diff = "-"
    for r = 0, 27 do for c = 0, 31 do
      if diff == "-" and vram_bg1(r, c) ~= bw16(0xDA40 + r * 64 + c * 2) then
        diff = string.format("(%d,%d) vram %04X tiles %04X pub %04X", c, r, vram_bg1(r, c), bw16(0xDA40 + r * 64 + c * 2), bw16(0x2000 + r * 64 + c * 2))
      end
    end end
    local dirty, done = bw16(0xE742), bw(0xE7F6)
    if diff ~= "-" and dirty == 0 then bad = bad + 1 end
    hush.log(string.format("f%3d mod %02X pubf %d t0 %2d n %2d wd %04X pubm %04X dirty %04X done %d  diff %s%s", f, emu.read(0x7E0010, emu.memType.snesMemory, false),
      emu.read(0x0A, IRAM, false), emu.read(0x0B, IRAM, false), emu.read(0x0C, IRAM, false), bw16(0xE744), bw16(0xE746), dirty, done, diff,
      (diff ~= "-" and dirty == 0) and "  <-- BAD" or ""))
  end
  hush.log("frames with dirty = 0 and VRAM != light_tiles: " .. bad .. (WIN0 and " (window 0..31 x 0..27)" or " (window 16..47 x 18..45)"))
  local s, ks = emu.getState(), {}
  for k, v in pairs(s) do if k:find("croll") and k:find("ppu") then ks[#ks + 1] = k .. "=" .. tostring(v) end end
  table.sort(ks)
  hush.log("PPU scroll state: " .. table.concat(ks, " ") .. string.format("  ($E0 %04X $E6 %04X $0120 %04X $0124 %04X)",
    emu.read16(0x7E00E0, emu.memType.snesMemory, false), emu.read16(0x7E00E6, emu.memType.snesMemory, false),
    emu.read16(0x7E0120, emu.memType.snesMemory, false), emu.read16(0x7E0124, emu.memType.snesMemory, false)))
  hush.pass()
end)
