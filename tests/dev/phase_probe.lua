-- Dev utility (E6): at which frame counter ($1A) phase does a room's AI start after a debug jump (bot.jump_to_room_synced)?
-- The guards look every 2nd / 4th frame by (slot xor $1A) & mask, so the solution replays only stay valid when this phase is unchanged.
--   HUSH_ROM=/tmp/opencode/hush_base.sfc .venv/bin/python tools/run_test.py tests/dev/phase_probe.lua
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
hush.test("phase probe", function()
  bot.start_new_game()
  for _, room in ipairs({ 3, 7, 12, 20, 0 }) do
    for _ = 1, 8 do if bot.peek(0x7E001A) % 4 == 0 then break end hush.wait(1) end
    local a0 = bot.peek(0x7E001A)
    bot.poke(0x7EC901, room + 1)
    local frames, passes, first = 0, 0, nil
    local last1a = a0
    while frames < 400 do
      hush.wait(1); frames = frames + 1
      local a = bot.peek(0x7E001A)
      if a ~= last1a then passes = passes + 1; last1a = a end
      if hush.read("hush_room") == room and hush.read("game_mode") == 7 and hush.read("submodule") == 0 and bot.peek(0x7E0010) == 7 and not first then
        first = { frames = frames, a = a, passes = passes }
        break
      end
    end
    hush.log(string.format("room %2d: $1A at request %3d (mod4 %d); AI starts after %3d frames, %3d main-loop passes, $1A = %3d (mod4 %d)",
      room, a0, a0 % 4, first.frames, first.passes, first.a, first.a % 4))
    hush.wait(5)
  end
  hush.pass()
end)
