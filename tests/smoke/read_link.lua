-- @requires-state
-- Smoke: from tests/states/test_room.mss, read Link X/Y, hold Right for 60
-- frames, assert X increased. The state must be in a dungeon/room with Link
-- standing in the open and under player control (see README).
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")

hush.test("read_link: X increases when holding Right", function()
  hush.assert_eq(hush.read("submodule"), 0, "state must be in normal gameplay (submodule $11 == 0)")
  local before = hush.link()
  hush.log(string.format("before: x=%d y=%d layer=%d room=$%04X health=$%02X mode=$%02X",
    before.x, before.y, before.layer, hush.read("room_id"), hush.read("health"), hush.read("game_mode")))

  hush.hold({ "right" }, 60)

  local after = hush.link()
  hush.log(string.format("after:  x=%d y=%d", after.x, after.y))
  hush.screenshot("read_link_after")
  hush.assert_gt(after.x, before.x, "Link X should increase after holding Right for 60 frames")
  hush.pass(string.format("x %d -> %d", before.x, after.x))
end)
