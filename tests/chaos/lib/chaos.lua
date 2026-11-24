-- tests/chaos/lib/chaos.lua : the chaos (fuzz) kit. Seeded, deterministic, state-driven (never fixed frame counts for "is it loaded yet").
--
--   package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. package.path
--   local C = require("chaos")
--   C.boot()                                   -- cold boot, new game, in-memory snapshot of the post-new-game state (C.s0)
--   local run = C.enter("mash", seed, "r05")   -- restore C.s0, debug-jump to the room, settle; returns a run object
--   C.guard(run, function() ... run:step({"left"}) ... end)   -- runs the body, prints a CHAOS: line, writes the repro on failure
--   C.finish()                                 -- fails the test if any run failed (after all seeds ran)
--
-- A `run` steps the emulator ONE frame per run:step(buttons) and checks the invariants after every frame (run:check()):
--   * game_mode in {5, 6, 7, $0E} (load / play / item menu); in the last room anything is tolerated for a bounded time after the exit
--     (the ending), as long as the game comes back to the title and a new game starts; hush_room only changes by +1 (an exit), by a
--     jump the run itself asked for (run:jump), or to the same room (restart);
--   * (play: mode 7, submodule 0) camera constant ($E2/$E8 = room base + window), Link inside the window and never inside a solid
--     cell of $7F2000, health full, Link's layer constant, hush_meter 0..32 and a multiple of 4; the game-over module $12 never runs;
--   * sprites: only the room's guards (type $41, state 9 or 0), no sprite in a slot >= #guards, spr_aware in 0..3, guards not inside
--     walls, awareness transitions only along the spec (0->1, 0->2, 0->3, 1->0, 1->2, 2->0, 3->0), a Suspicious / Alert guard never dies;
--   * ancillae: no slot keeps one thing for > 700 frames (leak); hush_ink_t <= 300;
--   * the free RAM $7EC900-$7EE7FF holds only HUSH's documented bytes (docs/ram_map.md) - anything else must stay 0;
--   * the game loop keeps ticking ($1A moves at least once per 400 frames), so no hang.
-- Every failure writes tests/chaos/repros/<scenario>_<seed>.inputs (hush.play compatible; the header comments say how the run was
-- entered and which pokes were made) and the run continues with the next seed; C.finish() fails the test listing all of them.
-- Replay: HUSH_REPLAY=tests/chaos/repros/<file> tools/run_test.py tests/dev/chaos_replay.lua   (the replay prints the same CHAOS: line).
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local C = {}
local W = emu.memType.snesWorkRam
C.BUTTONS = { "a", "b", "x", "y", "l", "r", "start", "select", "up", "down", "left", "right" }

local function rd(off) return emu.read(off, W, false) end
local function rd16(off) return emu.read16(off, W, false) end
C.rd, C.rd16 = rd, rd16

-- ---------------------------------------------------------------------------------------------------------------------------------
-- PRNG (xorshift32; our own so that a seed means the same thing on every Lua build)
-- ---------------------------------------------------------------------------------------------------------------------------------
function C.rng(seed)
  local s = (seed * 2654435761 + 40503) & 0xFFFFFFFF
  if s == 0 then s = 0x9E3779B9 end
  local r = {}
  function r.next()
    s = s ~ ((s << 13) & 0xFFFFFFFF); s = s ~ (s >> 17); s = s ~ ((s << 5) & 0xFFFFFFFF)
    return s
  end
  function r.int(n) return (r.next() >> 3) % n end                  -- 0 .. n-1
  function r.range(a, b) return a + r.int(b - a + 1) end
  function r.chance(num, den) return r.int(den) < num end
  function r.pick(list) return list[1 + r.int(#list)] end
  return r
end

-- Button masher: every button has its own hold timer; an idle button starts with probability rate[b] per frame and is then held for
-- a random length. Opposite d-pad directions are never held together (a real pad cannot). Returns a function: frame -> list of buttons.
local HOLDS = { 1, 1, 2, 3, 5, 8, 13, 21, 40 }
local DIR_HOLDS = { 2, 5, 8, 13, 21, 34, 55, 89 }
local OPP = { up = "down", down = "up", left = "right", right = "left" }
function C.masher(rng, rates)
  local left, held = {}, {}
  for _, b in ipairs(C.BUTTONS) do left[b] = 0; held[b] = false end
  return function()
    for _, b in ipairs(C.BUTTONS) do
      if left[b] > 0 then
        left[b] = left[b] - 1
        if left[b] == 0 then held[b] = false end
      elseif (rates[b] or 0) > 0 and rng.chance(1, rates[b]) then
        local opp = OPP[b]
        if not (opp and held[opp]) then
          left[b] = rng.pick(opp and DIR_HOLDS or HOLDS); held[b] = true
        end
      end
    end
    local out = {}
    for _, b in ipairs(C.BUTTONS) do if held[b] then out[#out + 1] = b end end
    return out
  end
end

-- 1 in N per idle frame
C.RATES_ALL = { up = 14, down = 14, left = 14, right = 14, a = 30, b = 30, x = 80, y = 30, l = 80, r = 80, start = 500, select = 900 }
C.RATES_MENU = { start = 12, select = 30, y = 12, x = 12, up = 40, down = 40, left = 40, right = 40 }

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Boot / enter
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Known issue B-002 (docs/bugs.md): SELECT -> "Save and Quit" leaves the game module ($17) and soft-resets to the title. Tolerated by
-- default (counted as `quits` in the CHAOS line, and the run then has to get a new game started); HUSH_CHAOS_STRICT=1 makes it a failure.
C.STRICT = os.getenv("HUSH_CHAOS_STRICT") == "1"
-- HUSH_CHAOS_SEED=k shifts every seed by 1000*k (explore new inputs); HUSH_CHAOS_SCALE=f multiplies the frame counts (0.2 = quick).
C.BASE = (tonumber(os.getenv("HUSH_CHAOS_SEED") or "") or 0) * 1000
C.SCALE = tonumber(os.getenv("HUSH_CHAOS_SCALE") or "") or 1
function C.frames(n) return math.max(120, math.floor(n * C.SCALE)) end
function C.seed(n) return n + C.BASE end
local logf
-- print + append to build/test-results/<test>/chaos.log (flushed at once: stdout only reaches the runner at exit, so a timeout would hide it)
function C.out(line)
  print(line)
  if not logf then logf = io.open(hush.OUT .. "/chaos.log", "w") end
  if logf then logf:write(line .. "\n"); logf:flush() end
end
C.failures = {}
C.n_runs = 0

function C.boot()
  bot.start_new_game()
  C.s0 = hush.snapshot()
end

local function room_index(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1, r end end
  error({ hush_fail = "no room " .. tostring(id) })
end
C.room_index = room_index

local function key_of(btns)
  if not btns or #btns == 0 then return "-" end
  local set = {}
  for _, b in ipairs(btns) do set[b] = true end
  local out = {}
  for _, b in ipairs(C.BUTTONS) do if set[b] then out[#out + 1] = b end end
  return table.concat(out, "+")
end

local Run = {}
Run.__index = Run

-- Restore the post-new-game snapshot and debug-jump to a room (synced like the solution replays), then wait for control.
function C.enter(scenario, seed, room_id, opts)
  opts = opts or {}
  local idx, room = room_index(room_id)
  hush.restore(C.s0)
  bot.jump_to_room_synced(idx)
  local m = bot.rooms()
  local run = setmetatable({
    scenario = scenario, seed = seed, room_id = room_id, idx = idx, room = room, m = m, ng = #room.guards, nrooms = m.count,
    steps = {}, pokes = {}, n = 0, hooks = {}, opts = opts,
    cur_room = idx, room_since = 0, expect = {}, last1a = rd(0x1A), stall = 0, prev = nil, prev_mode_ok = false,
    ancilla_age = {}, flash_prev = 0, ending = false, ending_frames = 0, menu_frames = 0, menu_run = 0,
    stats = { restarts = 0, lagged = 0, max_aware = 0, rooms = { [idx] = true }, quits = 0, endings = 0, kills = 0, known = {}, menu = 0, jumps = 0, exits = 0, caught_frames = 0 },
    cells = {}, ncells = 0, link_layer = rd(0xEE), inside_cloud = {}, first_check = true,
  }, Run)
  C.n_runs = C.n_runs + 1
  run:load_owned()
  return run
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Stepping, logging, pokes
-- ---------------------------------------------------------------------------------------------------------------------------------
function Run:log(btns)
  local k = key_of(btns)
  local last = self.steps[#self.steps]
  if last and last.key == k then last.frames = last.frames + 1 else self.steps[#self.steps + 1] = { key = k, frames = 1 } end
end

-- One emulated frame with `btns` held, then the invariants.
function Run:step(btns)
  btns = btns or {}
  hush.hold(btns, 1)
  self:log(btns)
  self.n = self.n + 1
  self:check()
end

function Run:idle(n) for _ = 1, n do self:step({}) end end

-- Write a byte into WRAM between two frames (logged in the repro).
function Run:poke(addr, v)
  bot.poke(addr, v)
  self.pokes[#self.pokes + 1] = { frame = self.n, addr = addr, v = v }
end

-- Ask the controller for a room jump (hush_room_req = n + 1); the next hush_room change to `idx` is then legal.
function Run:jump(idx)
  self:poke(0x7EC901, idx + 1)
  self.expect[idx] = self.n
  self.stats.jumps = self.stats.jumps + 1
end
function Run:clear_expect() self.expect = {} end

-- Teleport Link (logged pokes: replays reproduce it).
function Run:teleport(x, y)
  self:poke(0x7E0020, y & 0xFF); self:poke(0x7E0021, (y >> 8) & 0xFF)
  self:poke(0x7E0022, x & 0xFF); self:poke(0x7E0023, (x >> 8) & 0xFF)
end

-- Wait (state-driven, bounded) until Link is controllable: mode 7, submodule 0, brightness full. Returns the frames it took.
function Run:settle(max, btns)
  max = max or 900
  local stable = 0
  for f = 1, max do
    if rd(0x10) == 0x07 and rd(0x11) == 0x00 and rd(0xC903) == 0 then
      stable = stable + 1
      if stable >= 3 then return f end
    else
      stable = 0
    end
    self:step(btns)
  end
  self:fail("never reached player control within " .. max .. " frames (mode " .. string.format("%02X/%02X", rd(0x10), rd(0x11)) .. ")")
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Owned RAM: the bytes docs/ram_map.md gives HUSH inside the "free" block $7EC900-$7EE7FF
-- ---------------------------------------------------------------------------------------------------------------------------------
local FREE_LO, FREE_HI = 0xC900, 0xE7FF
function Run:load_owned()
  local owned = {}
  for _, e in pairs(hush.ram) do
    -- WRAM rows only: SA-1 rows ($40:xxxx BW-RAM, $00:3xxx I-RAM) have offsets in another memory (hush.lua load_ram_map)
    if e.mem == hush.WRAM and e.addr >= FREE_LO and e.addr <= FREE_HI then
      for k = 0, e.bytes - 1 do owned[e.addr + k] = true end
    end
  end
  self.owned = owned
end

C.undocumented = {}
function Run:scan_free()
  for off = FREE_LO, FREE_HI do
    if not self.owned[off] and rd(off) ~= 0 then
      if off < 0xCA00 then
        -- inside HUSH's own block but missing from docs/ram_map.md: a documentation gap, not a crash. Warn once, then treat as owned.
        if not C.undocumented[off] then
          C.undocumented[off] = true
          C.out(string.format("CHAOS: WARN $7E%04X is written but not in docs/ram_map.md (HUSH block $7EC900-$7EC9FF)", off))
        end
        self.owned[off] = true
      else
        self:fail(string.format("stray write to free RAM $7E%04X = $%02X (outside HUSH's documented block)", off, rd(off)))
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Failure + repro
-- ---------------------------------------------------------------------------------------------------------------------------------
function Run:context()
  local g = {}
  for s = 0, math.min(self.ng, 8) - 1 do g[#g + 1] = string.format("g%d=%d/%02X", s, rd(0xD80 + s), rd(0xDD0 + s)) end
  return string.format("frame %d, room %d, mode %02X/%02X, link (%d,%d), flash %d, ink_t %d, %s",
    self.n, rd(0xC900), rd(0x10), rd(0x11), rd16(0x22), rd16(0x20), rd(0xC903), rd16(0xC90C), table.concat(g, " "))
end

-- A violation that is a documented bug (docs/bugs.md): counted and reported once per run, a failure only with HUSH_CHAOS_STRICT=1.
function Run:known(bug, msg)
  if C.STRICT then self:fail(msg .. " (known " .. bug .. ")") end
  self.stats.known[bug] = (self.stats.known[bug] or 0) + 1
  if self.stats.known[bug] == 1 and not C.warned[bug .. self.scenario .. self.seed] then
    C.warned[bug .. self.scenario .. self.seed] = true
    C.out(string.format("CHAOS: KNOWN %s (%s seed %d): %s [%s]", bug, self.scenario, self.seed, msg, self:context()))
  end
end
C.warned = {}

function Run:fail(msg)
  error({ hush_fail = msg .. " [" .. self:context() .. "]" }, 2)
end

function Run:repro_text(msg)
  local L = {}
  L[#L + 1] = string.format("# chaos repro: scenario=%s seed=%d room=%s frames=%d", self.scenario, self.seed, self.room_id, self.n)
  L[#L + 1] = "# failure: " .. tostring(msg):gsub("[\r\n]+", " ")
  L[#L + 1] = "# @room " .. self.room_id
  for _, p in ipairs(self.pokes) do L[#L + 1] = string.format("#@poke %d %06X %d", p.frame, p.addr, p.v) end
  L[#L + 1] = "# frames  buttons"
  for _, s in ipairs(self.steps) do L[#L + 1] = string.format("%d %s", s.frames, s.key) end
  return table.concat(L, "\n") .. "\n"
end

function Run:write_repro(msg)
  if C.NO_REPRO then return nil end
  local text = self:repro_text(msg)
  local name = string.format("%s_%d.inputs", self.scenario, self.seed)
  local paths = { hush.ROOT .. "/tests/chaos/repros/" .. name, hush.OUT .. "/" .. name }
  local written
  for _, p in ipairs(paths) do
    local f = io.open(p, "w")
    if f then f:write(text); f:close(); written = written or p end
  end
  return written
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- The invariants
-- ---------------------------------------------------------------------------------------------------------------------------------
local ALLOWED_MODE = { [0x05] = true, [0x06] = true, [0x07] = true, [0x0E] = true }
local LEGAL = { ["0>1"] = true, ["0>2"] = true, ["0>3"] = true, ["1>0"] = true, ["1>2"] = true, ["2>0"] = true, ["3>0"] = true }

-- the collision map of the current room: $7F2000 = WRAM offset $12000, 64 x 64 bytes
local function solid_at(px, py)
  return rd(0x12000 + (((py & 0x1FF) >> 3) * 64) + ((px & 0x1FF) >> 3)) ~= 0
end
C.solid_at = solid_at

function Run:check()
  local mode, sub = rd(0x10), rd(0x11)
  local room = rd(0xC900)
  local m = self.m

  -- hang watchdog (the main loop increments $1A once per pass; a room load is one very long pass)
  local t = rd(0x1A)
  local ticked = (t ~= self.last1a)
  if ticked then self.stall = 0; self.last1a = t else self.stall = self.stall + 1 end
  if self.stall > 400 and not self.ending then self:fail("game loop stalled: $1A did not tick for 400 frames") end

  -- room index
  if room ~= self.cur_room then
    if room >= self.nrooms then self:fail("hush_room = " .. room .. " (only " .. self.nrooms .. " rooms)") end
    if room == self.cur_room + 1 and self.cur_room + 1 < self.nrooms then
      self.stats.exits = self.stats.exits + 1
    elseif self.expect[room] then
      -- a jump we asked for
    elseif self.ending and room == 0 then
      -- new game after the ending
    else
      self:fail(string.format("hush_room changed %d -> %d without an exit or a requested jump", self.cur_room, room))
    end
    self.expect[room] = nil
    self.cur_room = room
    self.room = m.rooms[room + 1]
    self.ng = #self.room.guards
    self.room_since = self.n
    self.stats.rooms[room] = true
    self.prev = nil
    self.ancilla_age = {}
  end

  -- module
  -- stealth meter criterion 9 (design/pillars.md:115-117): the vanilla game-over module ($12) never runs, not even in the last room
  if mode == 0x12 then self:fail("the vanilla game-over module ($12) ran") end
  local last_room = (room == self.nrooms - 1)
  if not ALLOWED_MODE[mode] then
    if last_room or self.ending or (mode == 0x17 and not C.STRICT) then
      if not self.ending then
        self.ending = true; self.ending_frames = 0
        if mode == 0x17 then self.stats.quits = self.stats.quits + 1 else self.stats.endings = self.stats.endings + 1 end
      end
      self.ending_frames = self.ending_frames + 1
      if self.ending_frames > 3000 then self:fail(string.format("stuck after the last room: module %02X/%02X for 3000 frames", mode, sub)) end
      self.prev = nil
      return
    end
    self:fail(string.format("unexpected game module %02X/%02X (room %d)", mode, sub, room))
  elseif self.ending and mode == 0x07 and sub == 0 then
    self.ending = false
  end
  if mode == 0x0E then
    self.menu_run = self.menu_run + 1
    self.stats.menu = self.stats.menu + 1
    if self.menu_run > (self.opts.menu_limit or 1500) then self:fail("stuck in the menu (module $0E) for " .. self.menu_run .. " frames") end
  else
    self.menu_run = 0
  end

  local flash = rd(0xC903)
  if flash ~= 0 and self.flash_prev == 0 then self.stats.restarts = self.stats.restarts + 1 end
  local reset_event = (flash ~= 0 or self.flash_prev ~= 0)
  self.flash_prev = flash

  if rd(0xC902) ~= 0 then self.stats.caught_frames = self.stats.caught_frames + 1 end

  local playing = (mode == 0x07 and sub == 0x00)
  if not playing then
    self.prev = nil
    self.mode_ok_since = nil
    return
  end
  self.mode_ok_since = self.mode_ok_since or self.n
  local fresh = (self.n - self.mode_ok_since) < 6     -- just left a load: sprites may still be spawning (state 8)

  -- frame lag (statistics only; docs/bugs.md B-001)
  if not ticked then self.stats.lagged = self.stats.lagged + 1 end

  local bx, by = self.room.base_x, self.room.base_y
  local wx, wy = bx + m.win_x, by + m.win_y

  -- camera
  local cx, cy = rd16(0xE2), rd16(0xE8)
  if cx ~= wx or cy ~= wy then self:fail(string.format("camera moved: $E2/$E8 = %d/%d, expected %d/%d", cx, cy, wx, wy)) end

  -- health
  local hp, hpmax = rd(0xF36D), rd(0xF36C)
  if hp ~= hpmax or hp == 0 then self:fail(string.format("health %d / %d (must stay full)", hp, hpmax)) end
  -- stealth meter range (design/pillars.md:47-48): 0..32, always a multiple of 4
  local mt = rd(hush.ram.hush_meter.addr)
  if mt > 32 or mt % 4 ~= 0 then self:fail(string.format("hush_meter = %d (must be 0..32, a multiple of 4)", mt)) end

  -- Link
  local lx, ly = rd16(0x22), rd16(0x20)
  if lx < wx or lx > wx + 256 - 16 or ly < wy - 8 or ly > wy + 224 - 24 then
    self:fail(string.format("Link left the room window: (%d,%d), window x %d..%d y %d..%d", lx, ly, wx, wx + 240, wy - 8, wy + 200))
  end
  -- his collision box (x..x+15, y+8..y+23) must never overlap a solid cell
  if solid_at(lx, ly + 8) or solid_at(lx + 15, ly + 8) or solid_at(lx, ly + 23) or solid_at(lx + 15, ly + 23) then
    self:fail(string.format("Link is inside a wall at (%d,%d) (collision box overlaps a solid tile)", lx, ly))
  end
  local cell = ((lx + 8) >> 4) * 64 + ((ly + 16) >> 4)
  if not self.cells[cell .. ":" .. room] then self.cells[cell .. ":" .. room] = true; self.ncells = self.ncells + 1 end
  local layer = rd(0xEE)
  if layer ~= self.link_layer then self:fail("Link's layer changed to " .. layer) end

  -- sprites
  local ng = self.ng
  local prev, cur = self.prev, {}
  for s = 0, 15 do
    local st = rd(0xDD0 + s)
    local aw = rd(0xD80 + s)
    if s >= ng then
      if st ~= 0 then self:fail(string.format("stray sprite in slot %d: state %02X type %02X (the room has %d guards)", s, st, rd(0xE20 + s), ng)) end
    else
      if st ~= 0 then
        if st == 8 and (fresh or reset_event) then
          -- spawning
        elseif st ~= 9 then
          self:fail(string.format("guard slot %d in state %02X", s, st))
        end
        if rd(0xE20 + s) ~= 0x41 then self:fail(string.format("slot %d has type %02X, not a guard ($41)", s, rd(0xE20 + s))) end
        if aw > 3 then self:fail(string.format("guard %d: spr_aware = %d (0..3)", s, aw)) end
        if aw > self.stats.max_aware and aw ~= 3 then self.stats.max_aware = aw end
        local gx = rd(0xD30 + s) * 256 + rd(0xD10 + s)
        local gy = rd(0xD20 + s) * 256 + rd(0xD00 + s)
        if gx < wx or gx > wx + 240 or gy < wy or gy > wy + 208 then
          self:fail(string.format("guard %d outside the room window: (%d,%d)", s, gx, gy))
        end
        if solid_at(gx + 8, gy + 8) then self:known("B-005", string.format("guard %d stands inside a wall at (%d,%d)", s, gx, gy)) end
        cur[s] = { alive = true, aw = aw, x = gx, y = gy }
      else
        cur[s] = { alive = false, aw = aw }
      end
      if prev and prev[s] and not reset_event then
        local p, c = prev[s], cur[s]
        if p.alive and not c.alive then
          self.stats.kills = self.stats.kills + 1
          if p.aw == 1 or p.aw == 2 then self:fail(string.format("guard %d died while %s (a suspicious / alert guard is immune)", s, p.aw == 1 and "SUSPICIOUS" or "ALERT")) end
        elseif (not p.alive) and c.alive then
          self:fail(string.format("guard %d came back to life without a restart", s))
        elseif p.alive and c.alive and p.aw ~= c.aw then
          if not LEGAL[p.aw .. ">" .. c.aw] then
            self:fail(string.format("guard %d awareness %d -> %d is not a transition of the spec", s, p.aw, c.aw))
          end
        end
      end
    end
  end
  self.prev = cur

  -- ancillae: nothing may sit in a slot for ever; the cloud timer is bounded
  for i = 0, 9 do
    local at = rd(0xC4A + i)
    local a = self.ancilla_age[i]
    if at == 0 then
      self.ancilla_age[i] = nil
    else
      if a then a.n = a.n + 1 else a = { t = at, n = 1 }; self.ancilla_age[i] = a end
      if a.t ~= at then a.t = at; a.n = 1 end
      -- a pot's explosion frame is held while the single global cloud is up, and every new pot restarts the cloud: no age then
      if at == 0x07 and rd16(0xC90C) > 0 then a.n = 1 end
      if a.n > 700 then self:fail(string.format("ancilla slot %d keeps type $%02X for 700 frames (leak)", i, at)) end
    end
  end
  if rd16(0xC90C) > 300 then self:fail("hush_ink_t = " .. rd16(0xC90C) .. " (> 300)") end

  -- free RAM, stack (the stack page is $0100-$01FF: SP outside it = an unbalanced push / pull somewhere)
  if self.n % 16 == 0 then self:scan_free() end
  if self.n % 8 == 0 then
    local sp = emu.getState()["cpu.sp"]
    if sp < 0x0100 or sp > 0x01FF then self:fail(string.format("stack pointer $%04X left the stack page $0100-$01FF", sp)) end
    if not self.min_sp or sp < self.min_sp then self.min_sp = sp end
  end

  for _, h in ipairs(self.hooks) do h(self) end
end

-- Select the Y item through the REAL item menu (START, d-pad until the cursor is on HUD slot `slot`, START) like record_room does.
-- Returns true when $0202 == slot and the game is back in play. Never throws except through the invariants.
function Run:menu_select(slot)
  self:step({ "start" }); self:step({ "start" })
  for _ = 1, 60 do if rd(0x10) == 0x0E and rd(0x0200) == 4 then break end; self:step({}) end
  for _ = 1, 10 do
    local cur = rd(0x0202)
    if cur == slot then break end
    self:step({ cur < slot and "right" or "left" }); self:step({ cur < slot and "right" or "left" }); self:idle(6)
  end
  local ok = (rd(0x0202) == slot)
  for f = 1, 120 do
    if rd(0x10) == 0x07 and rd(0x11) == 0 then break end
    self:step((f % 30) < 3 and { "start" } or {})
  end
  self:idle(3)
  return ok
end

-- number of OAM entries that are on screen (Y < $E0; hidden ones use Y = $F0): a leak signature
function C.oam_visible()
  local n = 0
  for i = 0, 127 do if rd(0x800 + i * 4 + 1) < 0xE0 then n = n + 1 end end
  return n
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Ending / recovery helpers
-- ---------------------------------------------------------------------------------------------------------------------------------
-- After the last room's exit: tap buttons gently (a credits screen may want START / A) until the title shows, START, new game.
-- Bounded; fails the run when the game never comes back.
function Run:resume_after_ending(back_to_idx)
  local f = 0
  while rd(0x10) ~= 0x07 or rd(0x11) ~= 0 or rd(0xC900) ~= 0 do
    f = f + 1
    if f > 3000 then self:fail("could not start a new game after the ending") end
    local b = {}
    if rd(0x10) == 0x00 and rd(0x11) == 0x08 and (f % 12) < 4 then b = { "start" }
    elseif f % 240 < 4 then b = { "a" } end
    self:step(b)
  end
  self.ending = false
  self.mode_ok_since = nil
  self:settle(900)
  if back_to_idx and back_to_idx ~= 0 then
    self:jump(back_to_idx)
    self:idle(2)
    self:settle(900)
  end
end

-- Run the body for one seed: prints the CHAOS: line, writes the repro on failure, never throws.
function C.guard(run, body)
  local ok, err = pcall(body, run)
  local msg
  if not ok then msg = type(err) == "table" and err.hush_fail or ("script error: " .. tostring(err)) end
  local st = run.stats
  local rooms = {}
  for i in pairs(st.rooms) do rooms[#rooms + 1] = i end
  table.sort(rooms)
  local kn = {}
  for b, n in pairs(st.known) do kn[#kn + 1] = b .. "x" .. n end
  table.sort(kn)
  local line = string.format("CHAOS: %-12s %-5s seed=%-4d frames=%-5d restarts=%-3d exits=%d jumps=%d kills=%d quits=%d endings=%d max_aware=%d cells=%-3d menu_frames=%-4d lagged=%-3d rooms=%s%s",
    run.scenario, run.room_id, run.seed, run.n, st.restarts, st.exits, st.jumps, st.kills, st.quits, st.endings, st.max_aware, run.ncells, st.menu, st.lagged, table.concat(rooms, ","),
    #kn > 0 and (" known=" .. table.concat(kn, ",")) or "")
  if ok then
    C.out(line .. " OK")
  else
    local where = run:write_repro(msg)
    C.out(line .. " FAIL")
    C.out(string.format("CHAOS: FAIL %s seed=%d room=%s: %s", run.scenario, run.seed, run.room_id, msg))
    if where then
      C.out(string.format("CHAOS: repro -> %s  (replay: HUSH_REPLAY=%s .venv/bin/python tools/run_test.py tests/dev/chaos_replay.lua)", where, where))
    end
    C.failures[#C.failures + 1] = string.format("%s/%s seed %d: %s", run.scenario, run.room_id, run.seed, msg)
  end
  return ok
end

-- End of a script: fail (listing every failing seed) or pass.
function C.finish(what)
  if #C.failures > 0 then
    local n = math.min(#C.failures, 6)
    local list = {}
    for i = 1, n do list[i] = C.failures[i] end
    hush.fail(string.format("%d of %d runs failed: %s%s", #C.failures, C.n_runs, table.concat(list, " || "), #C.failures > n and " ..." or ""))
  end
  hush.pass(string.format("%d runs, no invariant violated%s", C.n_runs, what and (" (" .. what .. ")") or ""))
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Mash driver
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Random mashing for `frames` frames. The input stream is a pure function of the seed (the ending recovery adds taps, deterministically).
function C.mash(run, rng, frames, rates)
  local next_inputs = C.masher(rng, rates or C.RATES_ALL)
  while run.n < frames do
    if run.ending then
      run:resume_after_ending(run.idx)
    else
      local b = next_inputs()
      if run.menu_run > 200 and (run.menu_run % 40) < 3 then b = { (run.menu_run % 80) < 40 and "start" or "a" } end   -- an impatient human leaves the menu
      run:step(b)
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Hashes (FNV-1a 32) of WRAM ranges: determinism checks
-- ---------------------------------------------------------------------------------------------------------------------------------
function C.hash_ranges(ranges)
  local h = 0x811C9DC5
  for _, r in ipairs(ranges) do
    for off = r[1], r[2] do
      h = ((h ~ rd(off)) * 16777619) & 0xFFFFFFFF
    end
  end
  return h
end

-- the "hush state": Link, sprite tables ($0D00-$0FFF), ancilla/garnish ($0BF0-$0CFF), the HUSH RAM block, the save mirror room flags
C.HUSH_STATE = { { 0x20, 0x23 }, { 0x1A, 0x1A }, { 0xBF0, 0xFFF }, { 0xC900, 0xC9FF }, { 0xF340, 0xF37F }, { 0xF36C, 0xF36D } }
function C.hash_state() return C.hash_ranges(C.HUSH_STATE) end
function C.hash_wram() return C.hash_ranges({ { 0, 0x1FFFF } }) end

return C
