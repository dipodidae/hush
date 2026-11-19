-- Dev utility (QA): WRAM at the first controllable frame of the last room of HUSH_SEQ (e.g. "r14,r15": replay r14, then jump to r15),
-- written to $HUSH_OUT/ram.bin. Used to find state that leaks from one room into the next (replays must start identically).
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("ram_at_room_start", function()
  local ids = {}
  for id in (os.getenv("HUSH_SEQ") or "r01"):gmatch("[^,]+") do ids[#ids + 1] = id end
  bot.start_new_game()
  local rooms = bot.rooms().rooms
  local function idx_of(id) for i, r in ipairs(rooms) do if r.id == id then return i - 1 end end end
  for n, id in ipairs(ids) do
    local idx = idx_of(id)
    bot.jump_to_room_synced(idx)
    if n < #ids then
      local steps = hush.parse_input_script(hush.ROOT .. "/tests/solutions/" .. id .. ".inputs")
      for _, s in ipairs(steps) do for _ = 1, s.frames do hush.hold(s.buttons, 1) end end
      hush.wait(5)
    end
  end
  local f = io.open(hush.OUT .. "/ram.bin", "wb")
  f:write(hush.dump_ram())
  f:close()
  hush.pass("dumped")
end)
