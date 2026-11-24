-- tests/lib/hush.lua : shared helpers for HUSH headless tests (MesenCE --testRunner).
--
-- Usage from a test script (run via tools/run_test.py, which sets the env vars):
--
--   package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
--   local hush = require("hush")
--   hush.test("my test", function()
--     hush.wait(60)
--     hush.hold({"right"}, 30)
--     hush.assert(hush.read("link_x") > 0, "Link should have an X")
--     hush.pass()
--   end)
--
-- Test bodies run as a coroutine that is advanced once per emulated frame
-- (endFrame event). hush.wait / hold / press / play yield until done.
--
-- Environment (set by tools/run_test.py):
--   HUSH_ROOT   repo root (to find docs/ram_map.md)
--   HUSH_OUT    directory for screenshots / dumps for this test
--   HUSH_STATE  optional savestate file loaded before the body starts
--
-- API verified against MesenCE 2.2.1: UI/Debugger/Documentation/LuaDocumentation.json
-- (emu.read/read16/write, emu.setInput, emu.addEventCallback, emu.addMemoryCallback,
--  emu.loadSavestate (exec callbacks only), emu.takeScreenshot, emu.stop).

local hush = {}

hush.ROOT  = os.getenv("HUSH_ROOT") or "."
hush.OUT   = os.getenv("HUSH_OUT")  or "."
hush.STATE = os.getenv("HUSH_STATE")

local BUTTONS = { "a", "b", "x", "y", "l", "r", "start", "select", "up", "down", "left", "right" }
local WRAM = emu.memType.snesWorkRam
local WRAM_SIZE = 0x20000

-- ---------------------------------------------------------------------------
-- RAM map: parsed from docs/ram_map.md (single source of truth)
-- ---------------------------------------------------------------------------

hush.ram = {}

-- Memory types (MesenCE LuaDocumentation.json:607 snesWorkRam, :608 snesSaveRam, :617 sa1InternalRam).
-- SA-1 BW-RAM is the cartridge save RAM (Sa1BwRamHandler.h:52 IMemoryHandler(MemoryType::SnesSaveRam)); the SNES sees it at
-- $40-$4F:0000-FFFF (Sa1.cpp:68), so offset = (bank - $40) * $10000 + addr (docs/ram_map.md "SA-1 memory").
-- I-RAM (2 KB) at $00-$3F/$80-$BF:3000-3FFF (Sa1.cpp:43-44), offset = addr & $7FF.
hush.WRAM, hush.BWRAM, hush.IRAM = WRAM, emu.memType.snesSaveRam, emu.memType.sa1InternalRam

-- 24-bit SNES CPU address -> memType, offset (errors on anything not WRAM / BW-RAM / I-RAM)
function hush.locate(a)
  local bank, lo = a >> 16, a & 0xFFFF
  if bank == 0x7E or bank == 0x7F then return WRAM, a - 0x7E0000 end
  if bank >= 0x40 and bank <= 0x4F then return hush.BWRAM, (bank - 0x40) * 0x10000 + lo end
  if ((bank <= 0x3F) or (bank >= 0x80 and bank <= 0xBF)) and lo >= 0x3000 and lo <= 0x3FFF then return hush.IRAM, lo & 0x7FF end
  error(string.format("address $%06X is not WRAM ($7E-$7F), BW-RAM ($40-$4F) or I-RAM ($xx:3000-3FFF)", a), 2)
end

local function load_ram_map()
  local path = hush.ROOT .. "/docs/ram_map.md"
  local f, err = io.open(path, "r")
  if not f then error("cannot open " .. path .. ": " .. tostring(err)) end
  local n = 0
  for line in f:lines() do
    -- WRAM rows: | `name` | `$7Exxxx` | bytes |   (backticked: must be WRAM)
    local name, addr, bytes = line:match("^|%s*`([%w_]+)`%s*|%s*`%$(%x+)`%s*|%s*(%d+)%s*|")
    local a
    if name then
      a = tonumber(addr, 16)
      if a < 0x7E0000 or a > 0x7FFFFF then
        error("ram_map.md: " .. name .. " is not in WRAM ($7E0000-$7FFFFF): $" .. addr)
      end
    else
      -- SA-1 rows (ram_map.md "HUSH lighting" / "SA-1 memory"): | `name` | $bb:aaaa | bytes |   (unbackticked)
      local bk, lo
      name, bk, lo, bytes = line:match("^|%s*`([%w_]+)`%s*|%s*%$(%x%x):(%x%x%x%x)%s*|%s*(%d+)%s*|")
      if name then a = tonumber(bk, 16) * 0x10000 + tonumber(lo, 16) end
    end
    if name then
      local ok, mem, off = pcall(hush.locate, a)
      if not ok then error("ram_map.md: " .. name .. ": " .. tostring(mem)) end
      hush.ram[name] = { addr = off, bytes = tonumber(bytes), mem = mem, cpu = a }
      n = n + 1
    end
  end
  f:close()
  if n == 0 then error("no RAM entries parsed from " .. path) end
end

-- Raw access by RAM-map name + byte offset, routed to the row's memory (WRAM / BW-RAM / I-RAM):
--   hush.peek("light_done")  hush.peek16("light_dirty")  hush.peek("light_gmap", s * 224 + i)  hush.poke("light_on", 0)
local function entry(name, lvl)
  local e = hush.ram[name]
  if not e then error("unknown RAM name '" .. tostring(name) .. "' (see docs/ram_map.md)", lvl + 1) end
  return e
end
function hush.peek(name, off)   local e = entry(name, 2); return emu.read(e.addr + (off or 0), e.mem, false) end
function hush.peek16(name, off) local e = entry(name, 2); local a = e.addr + (off or 0); return emu.read(a, e.mem, false) + 256 * emu.read(a + 1, e.mem, false) end
function hush.poke(name, v, off) local e = entry(name, 2); emu.write(e.addr + (off or 0), v & 0xFF, e.mem) end
-- by 24-bit CPU address ($7E/$7F WRAM, $40-$4F BW-RAM, $xx:3000 I-RAM)
function hush.peek_addr(a) local m, o = hush.locate(a); return emu.read(o, m, false) end
function hush.poke_addr(a, v) local m, o = hush.locate(a); emu.write(o, v & 0xFF, m) end

-- hush.read("link_x")          -> 16-bit value
-- hush.read("health")          -> 8-bit value
-- hush.read("spr_type", slot)  -> byte of a 16-slot array (slot 0..15)
function hush.read(name, index)
  local e = entry(name, 2)
  if e.bytes == 16 then
    if index == nil or index < 0 or index > 15 then
      error("RAM array '" .. name .. "' needs a slot index 0..15", 2)
    end
    return emu.read(e.addr + index, e.mem, false)
  end
  if e.bytes == 2 then return emu.read(e.addr, e.mem, false) + 256 * emu.read(e.addr + 1, e.mem, false) end
  if e.bytes == 1 then return emu.read(e.addr, e.mem, false) end
  error("unsupported size " .. e.bytes .. " for '" .. name .. "'", 2)
end

-- hush.write("hush_meter", 4)          -> poke a 1-byte variable
-- hush.write("spr_aware", 1, slot)     -> poke one slot of a 16-slot array
-- (2-byte names are written little endian.) Test-only: forcing states the spec says are RAM-observable.
function hush.write(name, v, index)
  local e = entry(name, 2)
  if e.bytes == 16 then
    if index == nil or index < 0 or index > 15 then
      error("RAM array '" .. name .. "' needs a slot index 0..15", 2)
    end
    emu.write(e.addr + index, v & 0xFF, e.mem)
  elseif e.bytes == 2 then
    emu.write(e.addr, v & 0xFF, e.mem); emu.write(e.addr + 1, (v >> 8) & 0xFF, e.mem)
  elseif e.bytes == 1 then
    emu.write(e.addr, v & 0xFF, e.mem)
  else
    error("unsupported size " .. e.bytes .. " for '" .. name .. "'", 2)
  end
end

-- Sprite position helper: (hi << 8) | lo, same coordinate space as Link.
function hush.sprite(slot)
  return {
    slot   = slot,
    type   = hush.read("spr_type", slot),
    state  = hush.read("spr_state", slot),
    x      = hush.read("spr_x_hi", slot) * 256 + hush.read("spr_x_lo", slot),
    y      = hush.read("spr_y_hi", slot) * 256 + hush.read("spr_y_lo", slot),
    health = hush.read("spr_health", slot),
  }
end

-- Active sprites (state 0x09) as a list of hush.sprite tables.
function hush.active_sprites()
  local out = {}
  for i = 0, 15 do
    if hush.read("spr_state", i) == 0x09 then out[#out + 1] = hush.sprite(i) end
  end
  return out
end

function hush.link()
  return { x = hush.read("link_x"), y = hush.read("link_y"), layer = hush.read("link_layer") }
end

-- Whole WRAM as a binary string (for determinism comparisons).
function hush.dump_ram()
  local chunks, buf = {}, {}
  for i = 0, WRAM_SIZE - 1 do
    buf[#buf + 1] = string.char(emu.read(i, WRAM, false))
    if #buf == 4096 then chunks[#chunks + 1] = table.concat(buf); buf = {} end
  end
  if #buf > 0 then chunks[#chunks + 1] = table.concat(buf) end
  return table.concat(chunks)
end

-- Compare two dumps; returns nil if equal, else a message listing first diffs.
function hush.diff_dumps(a, b, max_report)
  max_report = max_report or 10
  if a == b then return nil end
  local diffs, total = {}, 0
  for i = 1, math.min(#a, #b) do
    if a:byte(i) ~= b:byte(i) then
      total = total + 1
      if #diffs < max_report then
        diffs[#diffs + 1] = string.format("$%06X: %02X vs %02X", 0x7E0000 + i - 1, a:byte(i), b:byte(i))
      end
    end
  end
  return string.format("%d byte(s) differ (%d vs %d bytes); first: %s", total, #a, #b, table.concat(diffs, ", "))
end

-- ---------------------------------------------------------------------------
-- Result reporting
-- ---------------------------------------------------------------------------

local finished = false

function hush.pass(msg)
  if finished then return end
  finished = true
  print("HUSH_RESULT: PASS" .. (msg and (" - " .. msg) or ""))
  emu.stop(0)
end

function hush.fail(msg)
  if finished then return end
  finished = true
  print("HUSH_RESULT: FAIL - " .. tostring(msg))
  emu.stop(1)
end

-- Assertions raise a table error that the runner turns into hush.fail(msg).
function hush.assert(cond, msg)
  if not cond then error({ hush_fail = msg or "assertion failed" }, 2) end
end

function hush.assert_eq(actual, expected, msg)
  if actual ~= expected then
    error({ hush_fail = string.format("%s (expected %s, got %s)", msg or "assert_eq", tostring(expected), tostring(actual)) }, 2)
  end
end

function hush.assert_gt(actual, bound, msg)
  if not (actual > bound) then
    error({ hush_fail = string.format("%s (expected > %s, got %s)", msg or "assert_gt", tostring(bound), tostring(actual)) }, 2)
  end
end

function hush.log(...)
  print("[hush] " .. table.concat({ ... }, " "))
end

-- ---------------------------------------------------------------------------
-- Screenshots
-- ---------------------------------------------------------------------------

function hush.screenshot(name)
  local png = emu.takeScreenshot()
  local path = string.format("%s/%s.png", hush.OUT, name or "screenshot")
  local f, err = io.open(path, "wb")
  if not f then hush.log("screenshot failed: " .. tostring(err)); return nil end
  f:write(png)
  f:close()
  hush.log("screenshot " .. path)
  return path
end

-- ---------------------------------------------------------------------------
-- Frame scheduler (coroutine advanced once per frame)
-- ---------------------------------------------------------------------------

local co, held, wait_left, state_pending = nil, {}, 0, false
local frame = 0

function hush.frame() return frame end

local function resume()
  if finished or not co then return end
  if state_pending then return end            -- waiting for the exec callback to load a state
  if wait_left > 0 then wait_left = wait_left - 1; if wait_left > 0 then return end end
  local ok, err = coroutine.resume(co)
  if not ok then
    if type(err) == "table" and err.hush_fail then
      hush.fail(err.hush_fail)
    else
      hush.fail("script error: " .. tostring(err) .. "\n" .. debug.traceback(co))
    end
  elseif coroutine.status(co) == "dead" and not finished then
    hush.fail("test body ended without calling hush.pass() or hush.fail()")
  end
end

-- Block the test body for n frames.
function hush.wait(n)
  n = n or 1
  if n <= 0 then return end
  wait_left = n
  coroutine.yield()
end

local function held_table(buttons)
  local t = {}
  for _, b in ipairs(BUTTONS) do t[b] = false end
  for _, b in ipairs(buttons or {}) do
    local key = b:lower()
    if t[key] == nil then error("unknown button '" .. b .. "' (valid: " .. table.concat(BUTTONS, ",") .. ")", 3) end
    t[key] = true
  end
  return t
end

-- Hold the listed buttons for n frames, then release.
function hush.hold(buttons, n)
  held = held_table(buttons)
  hush.wait(n)
  held = held_table({})
end

-- Tap: hold for `frames` (default 2), then release for `gap` (default 2) frames.
function hush.press(buttons, frames, gap)
  hush.hold(buttons, frames or 2)
  hush.wait(gap or 2)
end

-- Input script format (one step per line, '#' comments):
--     <frames> <button>[+<button>...]     e.g.  30 right+b
--     <frames> -                          idle for <frames>
function hush.parse_input_script(path)
  local f, err = io.open(path, "r")
  if not f then error("cannot open input script " .. path .. ": " .. tostring(err)) end
  local steps = {}
  for line in f:lines() do
    line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
    if line ~= "" then
      local n, btns = line:match("^(%d+)%s+(%S+)$")
      if not n then f:close(); error("bad input script line in " .. path .. ": '" .. line .. "'") end
      local list = {}
      if btns ~= "-" then for b in btns:gmatch("[^+]+") do list[#list + 1] = b end end
      steps[#steps + 1] = { frames = tonumber(n), buttons = list }
    end
  end
  f:close()
  return steps
end

function hush.play(path)
  if path:sub(1, 1) ~= "/" then path = hush.ROOT .. "/" .. path end
  for _, s in ipairs(hush.parse_input_script(path)) do hush.hold(s.buttons, s.frames) end
end

-- Apply the held buttons to player 1 once per frame, before the game polls.
emu.addEventCallback(function()
  emu.setInput(held, 0)
end, emu.eventType.inputPolled)

-- ---------------------------------------------------------------------------
-- Savestates (emu.loadSavestate only works inside an exec callback)
-- ---------------------------------------------------------------------------

-- Load a savestate file, then continue after the next frame boundary.
function hush.load_state(path)
  if path:sub(1, 1) ~= "/" then path = hush.ROOT .. "/" .. path end
  local f, err = io.open(path, "rb")
  if not f then error({ hush_fail = "cannot open savestate " .. path .. ": " .. tostring(err) }) end
  local data = f:read("*a")
  f:close()
  state_pending = true
  local ref
  ref = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
    state_pending = false
    local ok = emu.loadSavestate(data)
    if not ok then hush.fail("emu.loadSavestate rejected " .. path) end
    held = held_table({})
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  wait_left = 0
  coroutine.yield()
  -- one frame so the loaded state settles before the test reads RAM
  hush.wait(1)
end

-- Write the current emulator state to a savestate file (dev/QA utility; the
-- committed-to-nothing states in tests/states/ are normally made by hand).
function hush.save_state(path)
  if path:sub(1, 1) ~= "/" then path = hush.ROOT .. "/" .. path end
  state_pending = true
  local ref
  ref = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
    local data = emu.createSavestate()
    local f, err = io.open(path, "wb")
    if not f then hush.fail("cannot write savestate " .. path .. ": " .. tostring(err)); return end
    f:write(data)
    f:close()
    state_pending = false
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  wait_left = 0
  coroutine.yield()
  hush.wait(1)
end

-- In-memory savestates (QA: the solution recorder and replays start every room from the same post-new-game state, so a replay
-- cannot depend on what the previous room left in RAM: item cursor, Link sub-pixels, frame counter ...).
--   local s0 = hush.snapshot()     -- the current state as a string
--   hush.restore(s0)               -- back to exactly that state (continues after the next frame boundary)
function hush.snapshot()
  local data
  state_pending = true
  local ref
  ref = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
    data = emu.createSavestate()
    state_pending = false
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  wait_left = 0
  coroutine.yield()
  hush.wait(1)
  return data
end

function hush.restore(data)
  state_pending = true
  local ref
  ref = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
    state_pending = false
    if not emu.loadSavestate(data) then hush.fail("emu.loadSavestate rejected the in-memory state") end
    held = held_table({})
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  wait_left = 0
  coroutine.yield()
  hush.wait(1)
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

function hush.test(name, body)
  load_ram_map()
  print("HUSH_TEST: " .. name)
  co = coroutine.create(function()
    if hush.STATE and hush.STATE ~= "" then hush.load_state(hush.STATE) end
    body()
  end)
  emu.addEventCallback(function() frame = frame + 1; resume() end, emu.eventType.endFrame)
end

return hush
