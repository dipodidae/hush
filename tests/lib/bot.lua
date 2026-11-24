-- tests/lib/bot.lua : tiny movement bot on top of hush.lua.
--
--   local bot = require("bot")
--   bot.start_new_game()                 -- cold boot -> title -> START -> controllable in room 1
--   bot.wait_control()                   -- wait for module 7 / submodule 0 (player control)
--   bot.walk_to(px, py [, timeout])      -- absolute Link pixel coordinates (like $7E0020/$7E0022); true on arrival
--   bot.jump_to_room(n)                  -- debug jump via hush_room_req (room n, 0-based), then wait_control
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

local bot = {}
local W = emu.memType.snesWorkRam

-- 24-bit CPU address, routed by hush.locate: $7E/$7F WRAM, $40-$4F SA-1 BW-RAM, $xx:3000-3FFF SA-1 I-RAM
function bot.poke(addr, v) hush.poke_addr(addr, v) end
function bot.peek(addr) return hush.peek_addr(addr) end

-- Wait until the game is in the underworld module with no submodule running (Link controllable).
function bot.wait_control(max)
  max = max or 900
  local stable = 0
  for _ = 1, max do
    if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0x00 then
      stable = stable + 1
      if stable >= 3 then return true end
    else
      stable = 0
    end
    hush.wait(1)
  end
  hush.assert(false, string.format("never reached player control (mode=%02X sub=%02X)", hush.read("game_mode"), hush.read("submodule")))
end

function bot.jump_to_room(n)
  bot.poke(0x7EC901, n + 1)
  hush.wait(2)
  bot.wait_control()
end

-- Same as jump_to_room, but first waits until the frame counter ($1A, one tick per game-loop pass) is a multiple of 4: guards look every
-- 2nd (unaware) / 4th (suspicious, alert) frame by `(slot xor $1A) & mask`, so the phase of $1A at the start of a room decides on which
-- frame a guard may notice Link. The solution recorder and the replays (tests/solutions) both enter rooms this way, which makes a
-- replay in a long session identical to the recording in a fresh one.
function bot.jump_to_room_synced(n)
  for _ = 1, 8 do
    if bot.peek(0x7E001A) % 4 == 0 then break end
    hush.wait(1)
  end
  bot.jump_to_room(n)
end

-- Press direction buttons toward absolute pixel (px, py) until within `tol` px on both axes.
function bot.walk_to(px, py, timeout, tol, extra)
  timeout, tol = timeout or 600, tol or 2
  for _ = 1, timeout do
    local x, y = hush.read("link_x"), hush.read("link_y")
    local dx, dy = px - x, py - y
    if math.abs(dx) <= tol and math.abs(dy) <= tol then return true end
    local b = {}
    if dx > tol then b[#b + 1] = "right" elseif dx < -tol then b[#b + 1] = "left" end
    if dy > tol then b[#b + 1] = "down" elseif dy < -tol then b[#b + 1] = "up" end
    for _, e in ipairs(extra or {}) do b[#b + 1] = e end
    hush.hold(b, 1)
    if hush.read("game_mode") ~= 0x07 then return false end   -- room changed under us
  end
  return false
end

-- ---------------------------------------------------------------------------------------------
-- Room metadata from tools/roomgen.py (build/rooms_gen.lua): positions are absolute Link coordinates.
-- ---------------------------------------------------------------------------------------------
function bot.rooms()
  -- HUSH_ROOMS_LUA: set by tools/run_test.py (build/rooms_gen.lua, or build/dev/rooms_gen.lua for `-- @rom dev` tests)
  if not bot._rooms then bot._rooms = dofile(os.getenv("HUSH_ROOMS_LUA") or (hush.ROOT .. "/build/rooms_gen.lua")) end
  return bot._rooms
end

-- Wait for the title screen (module 0, submodule 8), press START, wait for room 1.
function bot.wait_title(max)
  max = max or 900
  for _ = 1, max do
    if hush.read("game_mode") == 0x00 and hush.read("submodule") == 0x08 then return true end
    hush.wait(1)
  end
  hush.assert(false, "title screen not reached")
end

function bot.start_new_game()
  bot.wait_title()
  hush.wait(10)
  hush.press({ "start" }, 4, 4)
  bot.wait_control()
end

-- Link position that puts the centre of his collision box in the middle of exit rect `e` ({x0,y0,x1,y1}).
function bot.exit_pos(e)
  local m = bot.rooms()
  return (e[1] + e[3]) // 2 - m.feet_dx, (e[2] + e[4]) // 2 - m.feet_dy
end

-- Poke Link's coordinates (teleport).
function bot.teleport(x, y)
  emu.write(0x20, y & 0xFF, W); emu.write(0x21, (y >> 8) & 0xFF, W)
  emu.write(0x22, x & 0xFF, W); emu.write(0x23, (x >> 8) & 0xFF, W)
end

-- Shortest 4-connected path over the grid from "S" to the nearest "X", as a list of cells {cx, cy}.
-- Guard cells are blocked. Returns nil if there is none.
function bot.path(room)
  local g = room.grid
  local sx, sy
  for r = 1, #g do
    local c = g[r]:find("S", 1, true)
    if c then sx, sy = c - 1, r - 1 end
  end
  local function blocked(cx, cy)
    local ch = g[cy + 1]:sub(cx + 1, cx + 1)
    return ch == "#" or ch == "p" or ch == "O" or ch == "W" or ch:match("[a-h]") ~= nil
  end
  local prev, queue, head = { [sy * 16 + sx] = -1 }, { { sx, sy } }, 1
  while head <= #queue do
    local cx, cy = queue[head][1], queue[head][2]
    head = head + 1
    if g[cy + 1]:sub(cx + 1, cx + 1) == "X" then
      local out, k = {}, cy * 16 + cx
      while k ~= -1 do table.insert(out, 1, { k % 16, k // 16 }); k = prev[k] end
      return out
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = cx + d[1], cy + d[2]
      if nx >= 0 and nx < 16 and ny >= 0 and ny < 14 and not prev[ny * 16 + nx] and not blocked(nx, ny) then
        prev[ny * 16 + nx] = cy * 16 + cx
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return nil
end

-- Walk Link cell by cell along bot.path(room) (axis by axis, so he lines up with 1-cell gaps).
-- Returns true if the room changed or the last cell was reached.
function bot.walk_exit(room)
  local m = bot.rooms()
  local p = bot.path(room)
  hush.assert(p ~= nil, room.id .. ": no path from S to an exit")
  local start_room = bot.peek(0x7EC900)
  for i = 2, #p do
    local tx = room.base_x + m.win_x + p[i][1] * 16
    local ty = room.base_y + m.win_y + p[i][2] * 16 - 8
    -- one axis at a time, exact alignment first on the axis we are not moving along
    for _ = 1, 160 do
      local x, y = hush.read("link_x"), hush.read("link_y")
      if bot.peek(0x7EC900) ~= start_room or hush.read("game_mode") ~= 0x07 then return true end
      local b = {}
      if p[i][1] ~= p[i - 1][1] then
        if y < ty - 1 then b = { "down" } elseif y > ty + 1 then b = { "up" } end
        if #b == 0 then
          if x < tx then b = { "right" } elseif x > tx then b = { "left" } else break end
        end
      else
        if x < tx - 1 then b = { "right" } elseif x > tx + 1 then b = { "left" } end
        if #b == 0 then
          if y < ty then b = { "down" } elseif y > ty then b = { "up" } else break end
        end
      end
      hush.hold(b, 1)
    end
  end
  hush.wait(5)
  return true
end

return bot
