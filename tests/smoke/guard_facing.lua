-- Smoke (E1): the guards of every compiled room spawn at their grid cell facing the way the spec says
-- (initial direction $0DE0, guard encoding 0 right / 1 left / 2 down / 3 up; sprite sub-type from tools/roomgen.py).
-- Sampled on the first controllable frame, before the vanilla AI has moved or turned them.
-- @timeout 240
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local DIR = { right = 0, left = 1, down = 2, up = 3 }

hush.test("guard_facing: guards spawn where and how the spec says", function()
  local m = bot.rooms()
  bot.start_new_game()
  local checked = 0
  for i = 1, m.count do
    local r = m.rooms[i]
    if #r.guards > 0 then
      bot.poke(0x7EC901, i)
      -- first frame in module 7 after the reload with every guard sprite present
      local f = 0
      local found
      while not found do
        hush.wait(1); f = f + 1
        hush.assert(f < 600, r.id .. ": guards never appeared")
        if hush.read("game_mode") == 7 and hush.read("room_id") == r.room_id then
          local n, got = 0, {}
          for s = 0, 15 do
            if hush.read("spr_type", s) == 0x41 and hush.read("spr_state", s) == 9 and bot.peek(0x7E0E30 + s) ~= 0 then
              n = n + 1; got[#got + 1] = s
            end
          end
          if n >= #r.guards then found = got end
        end
      end
      for _, g in ipairs(r.guards) do
        local best, bd
        for _, s in ipairs(found) do
          local sp = hush.sprite(s)
          local d = math.abs(sp.x - g.x) + math.abs(sp.y - g.y)
          if not bd or d < bd then best, bd = s, d end
        end
        hush.assert(bd <= 8, string.format("%s guard %s: nearest guard sprite is %d px from cell (%d,%d)", r.id, g.id, bd, g.x, g.y))
        hush.assert_eq(bot.peek(0x7E0DE0 + best), DIR[g.facing], string.format("%s guard %s: initial direction (spec %s)", r.id, g.id, g.facing))
        checked = checked + 1
      end
    end
  end
  hush.assert(checked > 0, "no guard in any room")
  hush.pass(checked .. " guard(s) match their spec")
end)
