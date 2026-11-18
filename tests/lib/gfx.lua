-- tests/lib/gfx.lua : dump what the PPU is showing, for tools/gfx_leakcheck.py
--
--   local gfx = require("gfx")
--   gfx.snap("title")     -- writes <HUSH_OUT>/<name>.{vram,cgram,oam,ppu.txt,png}
--
-- Memory types verified in MesenCE 2.2.1 UI/Debugger/Documentation/LuaDocumentation.json
-- (emu.memType.snesVideoRam / snesCgRam / snesSpriteRam); PPU registers from emu.getState().
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

local gfx = {}

local function dump_mem(path, memtype, size)
  local f = assert(io.open(path, "wb"))
  local buf = {}
  for i = 0, size - 1 do
    buf[#buf + 1] = string.char(emu.read(i, memtype, false))
    if #buf == 4096 then f:write(table.concat(buf)); buf = {} end
  end
  if #buf > 0 then f:write(table.concat(buf)) end
  f:close()
end

function gfx.snap(name)
  local base = hush.OUT .. "/" .. name
  dump_mem(base .. ".vram", emu.memType.snesVideoRam, 0x10000)
  dump_mem(base .. ".cgram", emu.memType.snesCgRam, 0x200)
  dump_mem(base .. ".oam", emu.memType.snesSpriteRam, 0x220)
  -- emu.getState() returns a FLAT table with keys like "ppu.layers[0].chrAddress"
  local s = emu.getState()
  local function g(k) return s["ppu." .. k] end
  local f = assert(io.open(base .. ".ppu.txt", "w"))
  f:write(string.format("bgMode=%d\nmainScreenLayers=%d\nsubScreenLayers=%d\nforcedBlank=%s\nscreenBrightness=%d\n",
    g("bgMode"), g("mainScreenLayers"), g("subScreenLayers"), tostring(g("forcedBlank")), g("screenBrightness")))
  f:write(string.format("oamBaseAddress=%d\noamAddressOffset=%d\noamMode=%d\n", g("oamBaseAddress"), g("oamAddressOffset"), g("oamMode")))
  for i = 0, 3 do
    local p = "layers[" .. i .. "]."
    f:write(string.format("layer%d=%d,%d,%d,%d,%d,%d,%s\n", i, g(p .. "tilemapAddress"), g(p .. "chrAddress"),
      g(p .. "hscroll"), g(p .. "vscroll"), g(p .. "doubleWidth") and 1 or 0, g(p .. "doubleHeight") and 1 or 0,
      tostring(g(p .. "largeTiles"))))
  end
  f:close()
  hush.screenshot(name)
  hush.log("snap " .. name .. string.format(" mode=%02X sub=%02X", hush.read("game_mode"), hush.read("submodule")))
end

return gfx
