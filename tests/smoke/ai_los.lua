-- Smoke (E2): line of sight. Room ai6_cover (dark): a still guard faces east at cell (3, 6) (centre x 56, y 104 in window pixels),
-- a pillar column stands at x = 96..111 (cells (6,5)-(6,7), solid like a wall). A guard does not see Link through a solid tile:
-- Link straight behind the pillar (in range, in the cone) is NOT seen; next to it, where the line passes above/below the
-- pillar, he IS seen. Samples every 8 px of the straight line are tested against the collision map.
-- @rom dev
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

local function seen_at(dx, dy)
  ai.restart(); hush.wait(8); bot.wait_control()
  ai.link_to(0, dx, dy)
  return ai.watch(20, function() return ai.state(0) ~= ai.S.UNAWARE end) ~= nil
end

hush.test("ai_los: a pillar blocks the line of sight", function()
  ai.enter("ai6_cover")
  hush.assert(seen_at(32, 0), "in front of the pillar (dx 32): seen")
  hush.assert(not seen_at(64, 0), "straight behind the pillar (dx 64, dy 0): NOT seen")
  hush.assert(not seen_at(64, 20), "behind the pillar, line grazes its lower part (dx 64, dy 20): NOT seen")
  hush.assert(seen_at(64, -48), "line passes above the pillar (dx 64, dy -48): seen")
  hush.assert(seen_at(64, 48), "line passes below the pillar (dx 64, dy 48): seen")
  -- the same spot without the pillar in between would be seen: control in the pillar-less room
  ai.enter("ai4_dark")
  hush.assert(seen_at(64, 0), "control: dx 64 in a room without the pillar: seen")
  hush.pass("solid tiles block the line of sight; free lines do not")
end)
