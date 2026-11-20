-- Dev utility (QA, not a test): final room, Link teleported to col 8 at Link y = Y (no input, no smoke), for Y around the top of
-- cell (8,5) and for 0-3 extra frames before the teleport (AI look phase). Prints, per run, the first frame each guard leaves Unaware
-- (state at that frame), Link's y at the end and the frame of the catch. Same set-up as tests/smoke/mustnot2.lua enter() + tele().
--   .venv/bin/python tools/run_test.py tests/dev/final_top_probe.lua
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("final_top_probe", function()
  local m = bot.rooms()
  local idx, r
  for i, rr in ipairs(m.rooms) do if rr.id == "final" then idx, r = i - 1, rr end end
  bot.start_new_game()
  bot.jump_to_room_synced(idx)
  hush.wait(3)
  local s = hush.snapshot()
  local x0 = r.base_x + m.win_x + 16 * 8
  local yc = r.base_y + m.win_y + 16 * 5 - 8
  print(string.format("PROBE: (8,5) mustnot2 cellpx: x %d, y %d (centre case); room base y %d win_y %d", x0, yc, r.base_y, m.win_y))
  for k = 0, #r.guards - 1 do
    local sp = hush.sprite(k)
    print(string.format("PROBE: slot %d = %s px (%d,%d) dir %d", k, r.guards[k + 1].id, sp.x, sp.y, bot.peek(0x7E0DE0 + k)))
  end
  for y = yc - 16, yc + 2 do
    for pre = 0, 3 do
      hush.restore(s)
      hush.wait(pre)
      bot.teleport(x0, y)
      local first, caught, ylo, yhi = {}, nil, 99999, 0
      for f = 1, 120 do
        hush.hold({}, 1)
        local ly = hush.read("link_y")
        if ly < ylo then ylo = ly end
        if ly > yhi then yhi = ly end
        for k = 0, #r.guards - 1 do
          local a = hush.read("spr_aware", k)
          if a > 0 and a ~= 3 and not first[k] then first[k] = f end
        end
        if not caught and (bot.peek(0x7EC902) ~= 0 or bot.peek(0x7EC903) ~= 0) then caught = f; break end
      end
      local t = {}
      for k = 0, #r.guards - 1 do t[#t + 1] = r.guards[k + 1].id .. "=" .. (first[k] and tostring(first[k]) or "-") end
      print(string.format("PROBE: y %d pre %d  first-notice frame: %s  caught %s  link y %d..%d", y, pre, table.concat(t, " "),
        tostring(caught), ylo, yhi))
    end
  end
  hush.pass("probe")
end)
