-- tests/lib/meter.lua : helpers for the stealth meter tests (design/pillars.md:42-122 "Stealth meter", budget rule pillars.md:204).
--
--   local meter = require("meter")
--   meter.get()                         -- hush_meter (docs/ram_map.md "HUSH stealth meter")
--   meter.notice(slot) / meter.alert(slot)   -- force a guard Suspicious / Alert (spr_aware poke + the AI timers that keep him there)
--   meter.cells()                       -- the 8 HUD meter cells (16-bit tilemap words) from the HUD buffer
--   meter.vanilla_ok()                  -- nil, or a message: health != max, or the game-over module runs (criterion 9)
--   local b = meter.budget(ng)          -- per-frame tracker of a replay: spec-derived hit cost from awareness transitions
--   b:step() ... b:summary()
--
-- HUD: the HUD buffer is $7EC700 = tilemap row 2 col 0, 32 words per row (docs/gfx/hud_map.md:12); the meter cells are row 3,
-- cols 20-27 = $7EC768 + 2*i (hud_map.md:37: "Hearts row 3 from col 20 ($7EC768)"; pillars.md:86-88 puts the bar there).
-- Not a docs/ram_map.md row (it is a vanilla HUD buffer, not a variable), so it is read by address here, with that citation.
-- VRAM: BG3 tilemap word $6000 + 32*row + col (tests/smoke/hud.lua, hud_map.md section 2).
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

local M = {}
local W = emu.memType.snesWorkRam
local V = emu.memType.snesVideoRam

M.FULL = 32
M.SMALL = 4
M.BIG = 16
M.COOLDOWN = 120
M.HUD_CELL0 = 0x7EC768 - 0x7E0000      -- WRAM offset of cell 0 (row 3, col 20)

function M.get() return hush.read("hush_meter") end
function M.set(v) hush.write("hush_meter", v) end

-- Suspicious that stays Suspicious while Link is out of range: $0DF0 investigation 255, $0E10 lost-sight 255
-- (docs/engine_notes.md 11.2; the same pokes as tests/smoke/ai_darts.lua / ai_caught.lua).
function M.notice(slot)
  hush.write("spr_aware", 1, slot)
  emu.write(0x0DF0 + slot, 255, W)
  hush.write("spr_timer_lost", 255, slot)
end
-- Alert with the 180-frame lost-sight timer (engine_notes 11.2; same pokes as tests/smoke/ai_deescalate.lua).
function M.alert(slot)
  hush.write("spr_aware", 2, slot)
  hush.write("spr_timer_lost", 180, slot)
end

function M.cells()
  local t = {}
  for i = 0, 7 do t[i] = emu.read16(M.HUD_CELL0 + 2 * i, W, false) end
  return t
end
function M.vram_cells()
  local t = {}
  for i = 0, 7 do t[i] = emu.read16((0x6000 + 32 * 3 + 20 + i) * 2, V, false) end
  return t
end
function M.pal(word) return (word >> 10) & 7 end
function M.fmt(c)
  local s = {}
  for i = 0, 7 do s[#s + 1] = string.format("%04X", c[i]) end
  return table.concat(s, " ")
end

-- Criterion 9 (pillars.md:115-117): health == max at the end of every gameplay frame; the game-over module ($12,
-- docs/ram_map.md `game_mode`) never runs. Returns nil if fine, else a message.
function M.vanilla_ok()
  local mode = hush.read("game_mode")
  if mode == 0x12 then return "the vanilla game-over module ($12) ran" end
  if mode == 0x07 and hush.read("submodule") == 0 then
    local hp, mx = hush.read("health"), hush.read("health_max")
    if hp ~= mx then return string.format("health %d != max %d at the end of a gameplay frame", hp, mx) end
  end
  return nil
end

-- Spec model of the hits of one room (pillars.md:52-70): per guard slot, 0->1 = small 4, 0->2 / 1->2 = big 16, everything else 0.
-- Cooldown (pillars.md:65-66 "cannot cause another hit of the same size for 120 gameplay frames", :107-109): if a hit of a size is
-- applied in gameplay frame H, a transition of that size from the same slot seen in frame H+1 .. H+120 is blocked (costs 0, is not
-- a hit, does not restart the cooldown); from H+121 on it hits again. Frames are counted here as this tracker's playing frames
-- (module 7 / submodule 0), so the block test is "g - last <= 120", checked BEFORE anything is counted down (the reverse order
-- would let H+120 through).
-- Counts only from awareness, so it works whether or not the engine has a meter; the meter itself is compared separately.
function M.budget(ng)
  local b = { ng = ng, prev = {}, lasts = {}, lastb = {}, g = 0, small = 0, big = 0, blocked = 0, cost = 0, events = {}, frames = 0,
              meter_min = 255, meter_rise = nil, meter_bad = nil, meter_first = nil, meter_last = nil, vanilla = nil }
  local function cooling(last, g) return last ~= nil and g - last <= M.COOLDOWN end
  function b:step()
    self.frames = self.frames + 1
    local playing = hush.read("game_mode") == 0x07 and hush.read("submodule") == 0
    local v = M.vanilla_ok()
    if v and not self.vanilla then self.vanilla = string.format("frame %d: %s", self.frames, v) end
    if not playing then return end
    self.g = self.g + 1                          -- gameplay frame number of the frame just finished
    for s = 0, self.ng - 1 do
      local a = hush.read("spr_aware", s)
      local p = self.prev[s]
      if p ~= nil and p ~= a then
        if p == 0 and a == 1 then
          if not cooling(self.lasts[s], self.g) then
            self.small = self.small + 1; self.cost = self.cost + M.SMALL; self.lasts[s] = self.g
            self.events[#self.events + 1] = string.format("f%d g%d ?(-4)", self.frames, s)
          else self.blocked = self.blocked + 1 end
        elseif a == 2 and (p == 0 or p == 1) then
          if not cooling(self.lastb[s], self.g) then
            self.big = self.big + 1; self.cost = self.cost + M.BIG; self.lastb[s] = self.g
            self.events[#self.events + 1] = string.format("f%d g%d !(-16)", self.frames, s)
          else self.blocked = self.blocked + 1 end
        end
      end
      self.prev[s] = a
    end
    local m = M.get()
    if self.meter_first == nil then self.meter_first = m end
    if self.meter_last ~= nil and m > self.meter_last and not self.meter_rise then
      self.meter_rise = string.format("frame %d: meter rose %d -> %d inside the room", self.frames, self.meter_last, m)
    end
    if (m > M.FULL or m % 4 ~= 0) and not self.meter_bad then
      self.meter_bad = string.format("frame %d: hush_meter = %d (must be 0..32, multiple of 4)", self.frames, m)
    end
    if m < self.meter_min then self.meter_min = m end
    self.meter_last = m
  end
  function b:expected_end() return math.max(0, M.FULL - self.cost) end
  function b:summary()
    return string.format("small=%d big=%d blocked=%d model_cost=%d meter first=%s last=%s min=%d%s",
      self.small, self.big, self.blocked, self.cost, tostring(self.meter_first), tostring(self.meter_last), self.meter_min,
      #self.events > 0 and (" hits[" .. table.concat(self.events, ", ") .. "]") or "")
  end
  return b
end

-- Run up to n frames, calling f(frame) after each; stops early when f returns true. Returns the frame or nil.
function M.watch(n, f)
  for i = 1, n do
    hush.wait(1)
    if f(i) then return i end
  end
  return nil
end

return M
