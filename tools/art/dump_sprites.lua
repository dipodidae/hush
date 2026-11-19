-- tools/art/dump_sprites.lua : per-frame OAM + sprite name table 0 VRAM + guard/Link state log (research helper for docs/gfx/art_map.md).
--   HUSH_RESULTS=build/art_research .venv/bin/python tools/run_test.py tools/art/dump_sprites.lua
-- Output (HUSH_OUT): frames.txt, plus <scene>.cgram snapshots.
-- @timeout 280
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local gfx = require("gfx")

local W = emu.memType.snesWorkRam
local V = emu.memType.snesVideoRam
local O = emu.memType.snesSpriteRam
local C = emu.memType.snesCgRam
local out = assert(io.open(hush.OUT .. "/frames.txt", "w"))
local last_vram = nil

local function hexrange(mem, a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", emu.read(a + i, mem, false)) end
  return table.concat(t)
end
local function wr(a) return emu.read(a, W, false) end

local function record(label)
  local slots = {}
  for s = 0, 5 do
    slots[#slots + 1] = string.format("%d:%02X,%02X,%d,%d,%d,%d,%d,%d,%02X,%d", s, wr(0x0E20 + s), wr(0x0DD0 + s),
      wr(0x0D30 + s) * 256 + wr(0x0D10 + s), wr(0x0D20 + s) * 256 + wr(0x0D00 + s), wr(0x0DE0 + s), wr(0x0D80 + s),
      wr(0x0DC0 + s), wr(0x0EB0 + s), wr(0x0F50 + s), wr(0x0E80 + s))
  end
  local v = hexrange(V, 0x8000, 0x2000)
  local vs = (v == last_vram) and "=" or v
  last_vram = v
  -- Link DMA source words $0AC0-$0AF7 (DoNMIUpdates, bank_00.asm:1742-1900) and the ancilla types ($0C4A)
  local dma = {}
  for a = 0x0AC0, 0x0AF6, 2 do dma[#dma + 1] = string.format("%04X", wr(a) + 256 * wr(a + 1)) end
  local anc = {}
  for a = 0, 9 do anc[#anc + 1] = string.format("%02X", wr(0x0C4A + a)) end
  out:write(string.format("F|%s|%d|L=%d,%d,%d,%d,%d,%d|%s|%s|%s|%s|%s\n", label, hush.frame(),
    wr(0x22) + 256 * wr(0x23), wr(0x20) + 256 * wr(0x21), wr(0x2F), wr(0x3C), wr(0x5D), wr(0x0372),
    table.concat(slots, ";"), hexrange(O, 0, 0x220), vs, table.concat(dma, ","), table.concat(anc, ",")))
end

local function step(label, n, buttons)
  for _ = 1, n do
    bot.poke(0x7EC902, 0)
    hush.hold(buttons or {}, 1)
    record(label)
  end
end

local function kill_guards() for s = 0, 15 do bot.poke(0x7E0DD0 + s, 0) end end
local function cgram(name)
  local f = assert(io.open(hush.OUT .. "/" .. name .. ".cgram", "wb"))
  for i = 0, 0x1FF do f:write(string.char(emu.read(i, C, false))) end
  f:close()
end

hush.test("art dump: sprites", function()
  bot.start_new_game()

  -- ===== guards ===============================================================
  local gscenes = { { 5, "r06" }, { 8, "r09" }, { 1, "r02" }, { 3, "r04" } }
  for _, g in ipairs(gscenes) do
    bot.jump_to_room(g[1])
    hush.wait(30)
    local tag = g[2]
    step(tag .. "_unaware", 220)
    cgram(tag .. "_unaware")
    -- suspicious (keep poking so the AI does not calm him down)
    for _ = 1, 40 do bot.poke(0x7E0D80, 1); bot.poke(0x7E0DF0, 50); bot.poke(0x7E0E10, 100); step(tag .. "_susp", 1) end
    cgram(tag .. "_susp")
    for _ = 1, 150 do bot.poke(0x7E0D80, 2); bot.poke(0x7E0E10, 150); step(tag .. "_alert", 1) end
    cgram(tag .. "_alert")
    for _ = 1, 30 do bot.poke(0x7E0D80, 3); bot.poke(0x7E0DF0, 100); bot.poke(0x7E0D90, 1); step(tag .. "_asleep", 1) end
  end

  -- ===== Link, sword, bow, bombs (room 11 = index 10: open floor, all tools, guards removed) ==============
  local IDX = 10
  bot.jump_to_room(IDX)
  hush.wait(30)
  local rm = bot.rooms().rooms[IDX + 1]
  local m = bot.rooms()
  local function home(cx, cy)
    bot.teleport(rm.base_x + m.win_x + cx * 16, rm.base_y + m.win_y + cy * 16 - 8)
    for s2 = 0, 15 do bot.poke(0x7E0DD0 + s2, 0) end   -- no guards
    hush.wait(2)
  end
  home(7, 10)
  step("link_idle", 30)
  local dirs = { { "down", 2 }, { "up", 0 }, { "left", 4 }, { "right", 6 } }
  for _, d in ipairs(dirs) do
    home(7, 10)
    step("link_walk_" .. d[1], 28, { d[1] })
    step("link_idle_" .. d[1], 20)
  end
  for _, d in ipairs(dirs) do
    home(7, 10)
    step("link_face_" .. d[1], 4, { d[1] })
    step("link_sword_" .. d[1], 40, { "b" })
    step("link_idle", 30)
  end
  home(7, 10)
  step("link_face_down", 4, { "down" })
  step("link_sword_charge", 80, { "b" })
  step("link_sword_charge_idle", 30)
  for _, d in ipairs(dirs) do
    home(7, 10)
    bot.poke(0x7E0202, 1); bot.poke(0x7E0303, 3); bot.poke(0x7EF377, 30)
    step("link_face_" .. d[1], 4, { d[1] })
    step("bow_" .. d[1], 40, { "y" })
    step("link_idle", 40)
  end
  home(7, 10)
  bot.poke(0x7E0202, 4); bot.poke(0x7E0303, 1); bot.poke(0x7EF343, 8)
  step("link_face_down", 4, { "down" })
  step("bomb_place", 8, { "y" })
  step("bomb_wait", 150)
  cgram("bomb")
  step("bomb_boom", 340)
  -- ===== sword kill of an unaware guard (poof) in room 3 (index 2): Link behind the east-facing still guard =====
  bot.jump_to_room(2)
  hush.wait(30)
  do
    local gx = hush.read("spr_x_hi", 0) * 256 + hush.read("spr_x_lo", 0)
    local gy = hush.read("spr_y_hi", 0) * 256 + hush.read("spr_y_lo", 0)
    bot.teleport(gx - 28, gy - 8)
    bot.poke(0x7E002F, 6)
    hush.wait(2)
    step("poof_idle", 4)
    step("poof_swing", 70, { "b" })
    step("poof_after", 60)
  end
  out:close()
  hush.pass("frames logged")
end)
