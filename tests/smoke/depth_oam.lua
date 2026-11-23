-- Smoke (design/tiles.md 2.1 rule 3, revision 4; acceptance criterion 7.10 "In-emulator"): OAM priorities in the finished OAM buffer.
--   * Link's body entries are OAM priority 2   (so a priority-1 wall top hides him, a priority-0 quarter does not)
--   * guard head / body entries are OAM priority 2
--   * "?" / "!" awareness icon entries are OAM priority 3   (drawn above every room tile, never hidden by a priority-1 wall top)
-- Read after each frame from the OAM buffer $7E0800 (4 bytes per entry: x, y, tile, attr; attr bits 4-5 = priority) - the same buffer
-- tests/dev/oam_probe.lua lists. Identification (measured with tests/dev/depth_oam_probe.lua on this build, r14):
--   Link   = name table 0, OBJ palette 7 (attr $2E), within -8..+24 px x / -16..+32 px y of Link's screen position ($20/$22 - $E8/$E2);
--   guard  = name table 1, tiles $40-$67 (GFX_BC head / body blocks, docs/gfx/art_map.md section 5);
--   icon   = name table 1, tile $FC "?" / $FD "!" (docs/gfx/art_map.md section 6; "Z" $FE is not named by the spec and not checked).
-- Guards are forced suspicious, then alert (like tests/smoke/guard_draw.lua: hush_aprev set so the meter does not drain) while Link walks.
-- Not covered here (human screenshot check of 7.10): the guard-in-a-lane picture.
-- @timeout 120
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local function room_index(id)
  for i, r in ipairs(bot.rooms().rooms) do if r.id == id then return i - 1 end end
  error({ hush_fail = "no room " .. id })
end

local function w16(a) return bot.peek(a) + 256 * bot.peek(a + 1) end

local seen = { link = 0, guard = 0, icon = 0, frames = 0 }
local first_bad
local function bad(msg) if not first_bad then first_bad = string.format("frame %d: %s", hush.frame(), msg) end end

local function scan(tag)
  local lx = (hush.read("link_x") - w16(0x7E00E2)) & 0xFFFF
  local ly = (hush.read("link_y") - w16(0x7E00E8)) & 0xFFFF
  local nlink = 0
  for i = 0, 127 do
    local b = 0x7E0800 + i * 4
    local x, y, t, a = bot.peek(b), bot.peek(b + 1), bot.peek(b + 2), bot.peek(b + 3)
    if (bot.peek(0x7E0A20 + i) & 1) ~= 0 then x = x - 256 end
    if y < 0xE0 then
      local prio, pal, nt = (a >> 4) & 3, (a >> 1) & 7, a & 1
      local where = string.format("%s oam %d tile $%02X attr $%02X at (%d,%d)", tag, i, t, a, x, y)
      if nt == 0 and pal == 7 and x >= lx - 8 and x <= lx + 24 and y >= ly - 16 and y <= ly + 32 then
        nlink = nlink + 1
        if prio ~= 2 then bad(where .. string.format(": Link body entry priority %d, design/tiles.md 2.1 rule 3 says 2", prio)) end
      elseif nt == 1 and t >= 0x40 and t <= 0x67 then
        seen.guard = seen.guard + 1
        if prio ~= 2 then bad(where .. string.format(": guard head/body entry priority %d, design/tiles.md 2.1 rule 3 says 2", prio)) end
      elseif nt == 1 and (t == 0xFC or t == 0xFD) then
        seen.icon = seen.icon + 1
        if prio ~= 3 then bad(where .. string.format(": \"%s\" icon priority %d, design/tiles.md 2.1 rule 3 says 3", t == 0xFC and "?" or "!", prio)) end
      end
    end
  end
  seen.link = seen.link + nlink
  seen.frames = seen.frames + 1
end

hush.test("depth_oam: Link / guard bodies OAM priority 2, ?/! icons priority 3 (tiles.md 2.1)", function()
  bot.start_new_game()
  local moves = { { "right" }, { "up" }, { "left" }, { "down" } }
  for _, id in ipairs({ "r14", "r06" }) do
    bot.jump_to_room(room_index(id))
    hush.wait(10)
    local g = {}
    for s = 0, 15 do if hush.read("spr_type", s) == 0x41 and hush.read("spr_state", s) == 9 then g[#g + 1] = s end end
    hush.assert(#g > 0, id .. ": no guards")
    for _, state in ipairs({ 0, 1, 2 }) do
      for f = 1, 40 do
        for _, s in ipairs(g) do
          bot.poke(0x7E0D80 + s, state); hush.write("hush_aprev", state, s)
          bot.poke(0x7E0E10 + s, 250); bot.poke(0x7E0DF0 + s, 250); bot.poke(0x7E0D90 + s, 5); bot.poke(0x7E0EE0 + s, 60)
        end
        hush.hold(moves[(f // 10) % 4 + 1], 1)
        hush.assert(bot.peek(0x7EC902) == 0, id .. ": nobody caught Link during the sweep")
        scan(string.format("%s state %d", id, state))
      end
      hush.screenshot(string.format("%s_state%d", id, state))
    end
  end
  hush.assert(not first_bad, tostring(first_bad))
  -- non-vacuity: every kind was seen
  hush.assert(seen.link >= seen.frames, string.format("Link entries found: %d in %d frames (identification broken?)", seen.link, seen.frames))
  hush.assert(seen.guard > seen.frames, "guard head/body entries found: " .. seen.guard)
  hush.assert(seen.icon > 40, "icon entries found: " .. seen.icon)
  hush.pass(string.format("%d frames: %d Link, %d guard, %d icon entries with the spec's priorities", seen.frames, seen.link, seen.guard, seen.icon))
end)
