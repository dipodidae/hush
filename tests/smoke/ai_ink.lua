-- Smoke (E2): ink pots (the bomb slot). A bomb explodes into an INK CLOUD: no damage to anyone, no recoil; the cloud (radius 24 px,
-- 300 frames) hides Link: a guard whose line to Link crosses it does not see him, and suspicious / alert guards on such a
-- line (or inside the cloud) drop to UNAWARE at once and stand still for 60 frames.
-- @rom dev
-- @timeout 180
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local ai = require("ai")

local function set_cloud(cx, cy, t)
  bot.poke(0x7EC908, cx & 0xFF); bot.poke(0x7EC909, cx >> 8)
  bot.poke(0x7EC90A, cy & 0xFF); bot.poke(0x7EC90B, cy >> 8)
  bot.poke(0x7EC90C, t & 0xFF);  bot.poke(0x7EC90D, t >> 8)
end

hush.test("ai_ink: the cloud blocks sight, calms guards, hurts nobody", function()
  ai.enter("ai4_dark")
  local gx, gy = ai.pos(0)

  -- 1. a cloud between guard and Link: not seen; cloud gone: seen
  ai.restart(); hush.wait(8)
  set_cloud(gx + 8 + 36, gy + 8, 300)
  ai.link_to(0, 64, 0)
  hush.wait(30)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "Link behind the ink cloud (64 px, cloud at 36) is not seen")
  set_cloud(0, 0, 0)
  hush.wait(3)
  hush.assert(ai.state(0) ~= ai.S.UNAWARE, "without the cloud he is seen")

  -- 2. an ALERT guard whose line to Link crosses the cloud: unaware at once, stands still 60 frames
  ai.restart(); hush.wait(8)
  bot.poke(0x7E0D80, 2); bot.poke(0x7E0E10, 180)
  set_cloud(gx + 8 + 36, gy + 8, 300)
  ai.link_to(0, 70, 0)
  hush.wait(2)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "alert guard, cloud on the line: unaware")
  local x1 = ai.pos(0)
  hush.wait(50)
  hush.assert_eq((ai.pos(0)), x1, "and he stands still (60 frames)")
  hush.assert(not ai.caught(), "never caught")

  -- 3. a suspicious guard standing inside the cloud
  ai.restart(); hush.wait(8)
  bot.poke(0x7E0D80, 1); bot.poke(0x7E0DF0, 255); bot.poke(0x7E0E10, 255)
  set_cloud(gx + 8, gy + 8, 300)
  ai.link_to(0, 40, 0)
  hush.wait(2)
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "suspicious guard inside the cloud: unaware")

  -- 4. the real thing: a bomb at Link's feet, guard 30 px away behind Link's back
  ai.restart(); hush.wait(10); bot.wait_control()
  bot.poke(0x7E0202, 4); bot.poke(0x7E0303, 1)         -- bombs (HUD index 4, equipped id 1)
  ai.link_to(0, -30, 0)
  bot.poke(0x7E002F, 6)
  hush.wait(5)
  local lx, ly = hush.read("link_x"), hush.read("link_y")
  local bombs0 = bot.peek(0x7EF343)
  hush.press({ "y" }, 3, 1)
  hush.assert_eq(bot.peek(0x7EF343), bombs0 - 1, "one ink pot used")
  local t_boom
  for f = 1, 260 do
    hush.wait(1)
    if ai.ink_t() ~= 0 then t_boom = f; break end
  end
  hush.assert(t_boom ~= nil, "the bomb explodes into a cloud")
  hush.log("cloud appeared " .. t_boom .. " frames after the bomb was placed; t=" .. ai.ink_t())
  hush.assert(ai.ink_t() >= 290 and ai.ink_t() <= 300, "300 frames at the start")
  local cx = bot.peek(0x7EC908) + 256 * bot.peek(0x7EC909)
  local cy = bot.peek(0x7EC90A) + 256 * bot.peek(0x7EC90B)
  hush.log(string.format("cloud centre (%d,%d), Link (%d,%d)", cx, cy, lx, ly))
  hush.assert(math.abs(cx - (lx + 8)) <= 24 and math.abs(cy - (ly + 16)) <= 16, "the cloud is centred on the bomb (placed in front of Link)")
  hush.wait(20)
  hush.screenshot("cloud")
  hush.assert_eq(hush.read("link_x"), lx, "no recoil (x)")
  hush.assert_eq(hush.read("link_y"), ly, "no recoil (y)")
  hush.assert_eq(hush.read("health"), 0x18, "no damage to Link")
  hush.assert(ai.alive(0), "the guard 30 px away was inside the blast box and is unhurt")
  hush.assert_eq(ai.state(0), ai.S.UNAWARE, "and unaware")
  hush.assert_eq(bot.peek(0x7E0EF0), 0, "no hit timer on the guard")
  hush.assert(not ai.caught(), "no catch")
  -- the explosion graphic stays while the cloud lives, then the ancilla ends
  local function bomb_ancillae()
    local n = 0
    for i = 0, 9 do if bot.peek(0x7E0C4A + i) == 0x07 then n = n + 1 end end
    return n
  end
  hush.assert_eq(bomb_ancillae(), 1, "the explosion is held while the cloud lives")
  hush.wait(150)
  hush.assert_eq(bomb_ancillae(), 1, "still there after 170 frames")
  local f = ai.watch(200, function() return ai.ink_t() == 0 end)
  hush.assert(f ~= nil, "the cloud ends")
  hush.log("cloud lasted about " .. (20 + 150 + f) .. " frames")
  hush.assert(20 + 150 + f >= 290 and 20 + 150 + f <= 305, "300 frames")
  hush.wait(40)
  hush.assert_eq(bomb_ancillae(), 0, "the explosion finishes after the cloud")
  hush.pass("ink cloud: 300 frames, blocks sight, calms guards, no damage")
end)
