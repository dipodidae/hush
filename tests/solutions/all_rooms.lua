-- Solutions (QA): every room of the tower is played from its recorded input script (tests/solutions/<id>.inputs) on the real ROM
-- (build/hush.sfc, rooms of design/rooms) and must be cleared: touching the exit advances hush_room to the next room (the last room
-- ends in the ending screen) and no guard caught Link (no fast restart, hush_caught / hush_flash never set).
-- One cold boot + new game, then each room is entered with the debug jump (hush_room_req) so the replay starts from a fresh load;
-- the real new game -> room 1 path is covered by smoke/newgame. Regenerate the .inputs with `tools/solve_rooms.py` (README).
-- Output: one `SOLUTION:` line per room (also shown by tools/run_test.py), a summary, and the test fails on any unexpected result.
-- Env: HUSH_ONLY=r05,r06 restricts the run (debugging); HUSH_RESULTS etc. as usual.
-- @timeout 600
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

-- Rooms known to be unsolvable with the current engine/spec: room id -> bug id in docs/bugs.md. They are EXPECTED to fail and are
-- reported as XFAIL (never silently skipped); an XFAIL room that suddenly passes is reported as XPASS and fails the test so the
-- entry gets removed.
local EXPECTED_FAIL = {
}

local function replay(idx, r, steps)
  local ng = #r.guards
  local frames, caught, max_aware, g = 0, 0, 0, 0
  local first_aware
  local last1a, lagged = bot.peek(0x7E001A), 0
  local function check()
    frames = frames + 1
    local a1 = bot.peek(0x7E001A)       -- frame counter: no tick = the game loop overran the frame (lag)
    if a1 == last1a and hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 then lagged = lagged + 1 end
    last1a = a1
    if bot.peek(0x7EC902) ~= 0 or bot.peek(0x7EC903) ~= 0 then caught = caught + 1 end
    for k = 0, ng - 1 do
      local a = hush.read("spr_aware", k)
      if a ~= 3 and a > max_aware then max_aware = a; first_aware = first_aware or frames end
    end
    return hush.read("hush_room") ~= idx or hush.read("game_mode") == 0x13   -- the last room ends in the ending screen (module $13, E6)
  end
  local advanced = false
  for _, s in ipairs(steps) do
    for _ = 1, s.frames do
      hush.hold(s.buttons, 1)
      if check() then advanced = true; break end
    end
    if advanced then break end
  end
  if not advanced then
    for _ = 1, 30 do hush.hold({}, 1); if check() then advanced = true; break end end
  end
  return { advanced = advanced, frames = frames, caught = caught, max_aware = max_aware, first_aware = first_aware, lagged = lagged }
end

hush.test("solutions: every room cleared from its recorded inputs", function()
  local m = bot.rooms()
  local only = {}
  for id in (os.getenv("HUSH_ONLY") or ""):gmatch("[^,]+") do only[id] = true end
  local filter = next(only) ~= nil
  bot.start_new_game()
  local s0 = hush.snapshot()   -- every room starts from the post-new-game state (the recorder does the same): no leaks between rooms
  local failures, n_pass, n_xfail = {}, 0, 0
  local total_frames = 0
  for i = 1, m.count do
    local r = m.rooms[i]
    if not filter or only[r.id] then
      local idx = i - 1
      local path = hush.ROOT .. "/tests/solutions/" .. r.id .. ".inputs"
      local f = io.open(path, "r")
      local xf = EXPECTED_FAIL[r.id]
      local status, detail
      if not f then
        status, detail = "MISSING", "no tests/solutions/" .. r.id .. ".inputs"
      else
        f:close()
        local steps = hush.parse_input_script(path)
        hush.restore(s0)
        bot.jump_to_room_synced(idx)
        local res = replay(idx, r, steps)
        total_frames = total_frames + res.frames
        local final = (i == m.count)
        local ok = res.advanced and res.caught == 0
        if ok then
          if final then
            -- the last room fades out into the ending screen (module $13)
            local t = 0
            while hush.read("game_mode") ~= 0x13 and t < 120 do hush.wait(1); t = t + 1 end
            ok = hush.read("game_mode") == 0x13
            if not ok then detail = "exit touched but the game did not show the ending screen" end
          else
            ok = hush.read("hush_room") == i
            if not ok then detail = string.format("hush_room is %d, expected %d", hush.read("hush_room"), i) end
          end
        else
          detail = string.format("%s caught=%d max_aware=%d (first at frame %s) after %d frames",
            res.advanced and "exit reached but" or "exit NOT reached;", res.caught, res.max_aware, tostring(res.first_aware), res.frames)
        end
        status = ok and "PASS" or "FAIL"
        if ok then detail = string.format("%d frames, caught=%d, max awareness %d, lagged frames %d", res.frames, res.caught, res.max_aware, res.lagged) end
      end
      if xf then
        if status == "PASS" then
          status = "XPASS"
          failures[#failures + 1] = r.id .. " passes but is listed in EXPECTED_FAIL (" .. xf .. "): remove the entry"
        else
          n_xfail = n_xfail + 1
          status = "XFAIL"
          detail = "expected failure, see docs/bugs.md " .. xf .. ": " .. tostring(detail)
        end
      elseif status ~= "PASS" then
        failures[#failures + 1] = r.id .. ": " .. status .. " " .. tostring(detail)
      else
        n_pass = n_pass + 1
      end
      print(string.format("SOLUTION: %-6s %-6s %s", r.id, status, tostring(detail)))
    end
  end
  print(string.format("SOLUTION: summary pass=%d xfail=%d fail=%d, %d frames replayed", n_pass, n_xfail, #failures, total_frames))
  if #failures > 0 then hush.fail(table.concat(failures, "; ")) end
  hush.pass(string.format("%d rooms cleared, %d expected failures", n_pass, n_xfail))
end)
