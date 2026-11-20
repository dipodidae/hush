-- Solutions (stealth meter, criterion 9 + the budget rule): every room replayed from its recorded tests/solutions/<id>.inputs (same
-- entry as all_rooms.lua: post-new-game snapshot + synced debug jump) with the meter accounting checked every frame.
--   * pillars.md:204 "an intended solution may cost at most 2 small hits (8 of 32 units) and no big hit"; r05 is the only spec that
--     plans a "?" (1 small hit). The hits are counted from the guards' awareness transitions with the spec's table and cooldown
--     (pillars.md:52-70, tests/lib/meter.lua `budget`), so this part is meaningful even without the engine's meter.
--   * the engine's meter must agree: 32 on the first replay frame (criterion 1), never rises inside the room, 0..32 / multiple of 4
--     (pillars.md:47-48), and at the last frame before the exit equals 32 - the spec cost.
--   * criterion 9 (pillars.md:115-117): vanilla health == max at the end of every gameplay frame, game-over module ($12) never runs.
--   * pillars.md:204: only r05 plans a "?": small hits must be exactly 1 in r05 and 0 everywhere else (final: 32 at the exit).
-- Risk: r15 ((1,6) is a transit cell since the B-004 spec change; a glimpse there would show up here as a small hit) and any
-- replay recorded with a "?" glimpse. Per-room lines: `SOLUTION: meter <id> PASS|FAIL ...` (shown by tools/run_test.py).
-- Room clearing itself is owned by all_rooms.lua; here a room that is not cleared is reported but only its meter checks count.
-- Env: HUSH_ONLY=r05,r15 restricts the run.
-- @timeout 600
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local meter = require("meter")

local SMALL_MAX, BIG_MAX = 2, 0                       -- pillars.md:204
-- pillars.md:204 "r05 is the only spec whose intended solution plans a "?" (1 small hit, 28 left)": every other replay must have
-- exactly 0 small hits (meter 32 at the exit) and r05 exactly 1. A replay that glimpses a "?" the spec does not plan (e.g. the
-- old final.inputs: guard e at f1033, walking into row 4 before the cloud was up) does not follow its intended_solution.
local PLANNED_SMALL = { r05 = 1 }

local function replay(idx, r, steps)
  local b = meter.budget(#r.guards)
  local vanilla, advanced = nil, false
  local function frame()
    local v = meter.vanilla_ok()
    if v and not vanilla then vanilla = string.format("frame %d: %s", b.frames + 1, v) end
    if hush.read("hush_room") ~= idx or hush.read("game_mode") == 0x13 then return true end
    b:step()
    return false
  end
  for _, s in ipairs(steps) do
    for _ = 1, s.frames do
      hush.hold(s.buttons, 1)
      if frame() then advanced = true; break end
    end
    if advanced then break end
  end
  if not advanced then
    for _ = 1, 30 do hush.hold({}, 1); if frame() then advanced = true; break end end
  end
  -- the frames after the exit (fade, next room / ending) are still gameplay-adjacent: keep the vanilla check for 60 more frames
  for _ = 1, 60 do
    hush.wait(1)
    local v = meter.vanilla_ok()
    if v and not vanilla then vanilla = "after the exit: " .. v end
  end
  return b, advanced, vanilla
end

hush.test("meter_budget: every solution within 2 small hits, no big hit; meter agrees; health full", function()
  local m = bot.rooms()
  local only = {}
  for id in (os.getenv("HUSH_ONLY") or ""):gmatch("[^,]+") do only[id] = true end
  local filter = next(only) ~= nil
  bot.start_new_game()
  local s0 = hush.snapshot()
  local failures, n_pass = {}, 0
  for i = 1, m.count do
    local r = m.rooms[i]
    if not filter or only[r.id] then
      local path = hush.ROOT .. "/tests/solutions/" .. r.id .. ".inputs"
      local f = io.open(path, "r")
      local problems = {}
      local detail = ""
      if not f then
        problems[#problems + 1] = "no tests/solutions/" .. r.id .. ".inputs"
      else
        f:close()
        local steps = hush.parse_input_script(path)
        hush.restore(s0)
        bot.jump_to_room_synced(i - 1)
        local b, advanced, vanilla = replay(i - 1, r, steps)
        detail = b:summary() .. (advanced and "" or " (exit not reached; see all_rooms)")
        if vanilla then problems[#problems + 1] = "criterion 9: " .. vanilla end
        if b.small > SMALL_MAX then problems[#problems + 1] = string.format("budget: %d small hits > %d (pillars.md:204)", b.small, SMALL_MAX) end
        local planned = PLANNED_SMALL[r.id] or 0
        if b.small ~= planned then
          problems[#problems + 1] = string.format("%d small hit(s), the spec plans %d (pillars.md:204: r05 is the only room with a \"?\")", b.small, planned)
        end
        if b.big > BIG_MAX then problems[#problems + 1] = string.format("budget: %d big hit(s), none allowed (pillars.md:204)", b.big) end
        if b.meter_first ~= 32 then problems[#problems + 1] = string.format("criterion 1: hush_meter %s on the first replay frame, expected 32", tostring(b.meter_first)) end
        if b.meter_bad then problems[#problems + 1] = b.meter_bad end
        if b.meter_rise then problems[#problems + 1] = b.meter_rise .. " (pillars.md:50-51)" end
        if b.meter_last ~= nil and b.meter_last ~= b:expected_end() then
          problems[#problems + 1] = string.format("hush_meter %d at the exit, spec cost says %d (pillars.md:52-70)", b.meter_last, b:expected_end())
        end
      end
      local status = #problems == 0 and "PASS" or "FAIL"
      if status == "PASS" then n_pass = n_pass + 1 else failures[#failures + 1] = r.id .. ": " .. table.concat(problems, "; ") end
      print(string.format("SOLUTION: meter %-6s %-4s %s%s", r.id, status, detail, #problems > 0 and (" | " .. table.concat(problems, "; ")) or ""))
    end
  end
  print(string.format("SOLUTION: meter summary pass=%d fail=%d", n_pass, #failures))
  if #failures > 0 then hush.fail(#failures .. " room(s): " .. table.concat(failures, " || ")) end
  hush.pass(n_pass .. " rooms within the meter budget, meter consistent, health full")
end)
