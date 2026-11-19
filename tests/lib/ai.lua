-- tests/lib/ai.lua : helpers for the E2 stealth-AI tests. They run on the DEV ROM (`-- @rom dev`, rooms of tests/dev/rooms).
--
--   local ai = require("ai")
--   ai.enter("ai4_dark")            -- full load of that dev room, returns the room metadata (bot.rooms() row)
--   ai.state(0)                     -- awareness of guard slot 0 (spr_aware, docs/ram_map.md): 0 unaware 1 suspicious 2 alert 3 asleep
--   ai.link_to(slot, dx, dy)        -- teleport Link so that his centre is (dx, dy) from the guard's centre
--   ai.wait_state(slot, 1, 90)      -- wait until the guard reaches that state (false after the timeout)
--   ai.restart()                    -- ask for the fast restart through the "caught" flag (what a guard does)
-- Slot of guard k (1-based, row-major order of the guard cells in the grid) = k - 1: LoadUnderworldSprites assigns slots in
-- sprite-list order and tools/roomgen.py writes the list in the same order.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local ai = {}
ai.S = { UNAWARE = 0, SUSPICIOUS = 1, ALERT = 2, ASLEEP = 3 }

function ai.room_index(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1, r end end
  error({ hush_fail = "no dev room " .. id })
end

-- Cold boot (once per test) and enter a room by id; waits until the guards are present and idle.
function ai.enter(id)
  if not ai._booted then bot.start_new_game(); ai._booted = true end
  local idx, r = ai.room_index(id)
  bot.jump_to_room(idx)
  hush.wait(5)
  return r
end

function ai.state(slot) return hush.read("spr_aware", slot) end   -- docs/ram_map.md: the AI's debug API
function ai.alive(slot) return bot.peek(0x7E0DD0 + slot) == 9 end
function ai.pos(slot) local s = hush.sprite(slot); return s.x, s.y end
function ai.dir(slot) return bot.peek(0x7E0DE0 + slot) end
function ai.caught() return bot.peek(0x7EC902) ~= 0 end
function ai.ink_t() return bot.peek(0x7EC90C) + 256 * bot.peek(0x7EC90D) end

-- Link's centre = (x + 8, y + 16); the guard's centre = (x + 8, y + 8) (docs/engine_notes.md section 1).
function ai.link_to(slot, dx, dy)
  local gx, gy = ai.pos(slot)
  bot.teleport(gx + dx, gy + dy - 8)
end

function ai.wait_state(slot, state, max)
  for _ = 1, max do
    if ai.state(slot) == state then return true end
    hush.wait(1)
  end
  return ai.state(slot) == state
end

-- Run n frames; fail at the first frame the predicate holds (returns the frame number) or nil.
function ai.watch(n, pred)
  for f = 1, n do
    hush.wait(1)
    if pred() then return f end
  end
  return nil
end

-- The fast restart on demand: what a guard does when he catches Link (hush_caught := 1, Hush_Tick restarts next frame).
function ai.restart()
  bot.poke(0x7EC902, 1)
  hush.wait(2)
end

-- Park Link far from everything (top-left of the room) and let every guard calm down: used between sub-tests.
function ai.reset(room)
  ai.restart()
  hush.wait(8)
  bot.wait_control()
end

return ai
