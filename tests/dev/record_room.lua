-- Dev utility (QA): the solution RECORDER. Executes a plan (closed-loop, pixel-exact walking) on build/hush.sfc and writes the
-- button presses it made as an input script (tests/solutions/<id>.inputs format). The plan comes from tools/solve_rooms.py.
--   HUSH_PLAN=<plan file>   HUSH_REC_OUT=<inputs file to write>   (both absolute or repo-relative)
-- Plan lines (# comments):
--   room N                  0-based room index (jump_to_room); must be the first line
--   goto X Y [xy|yx]        walk to Link pixel position (X, Y) (absolute, like $7E0022/$7E0020), x axis first (default) or y first
--   until T                 idle until game time T (game time = game-loop passes ($1A ticks) in the playing state; the item menu pauses the game, a lagging frame does not count)
--   wait N                  idle N frames
--   face up|down|left|right one-frame tap that turns Link (moves him 1-2 px)
--   item bow|bombs|sword    pick the Y item through the real START menu (the game is paused while the menu is open)
--   shoot                   Y press (dart or pot, whichever item is selected)
--   knife                   B press (sword swing)
--   stab SLOT DIST [MAXWAIT [DIR]] wait until guard SLOT is DIST px (centre to centre) in front of Link, then swing; fails if the guard survives
--   expect_room N           after the plan: hush_room must be N
-- Output: $HUSH_OUT/rec.log (events), the inputs file, final line "REC: ..." on stdout. Fails (non-zero) on any catch.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local DIRS = { up = "up", down = "down", left = "left", right = "right" }
local FACE = { up = 0, down = 2, left = 4, right = 6 }

hush.test("record_room", function()
  local planf = os.getenv("HUSH_PLAN")
  local outf = os.getenv("HUSH_REC_OUT")
  hush.assert(planf and outf, "HUSH_PLAN and HUSH_REC_OUT required")
  if planf:sub(1, 1) ~= "/" then planf = hush.ROOT .. "/" .. planf end
  if outf:sub(1, 1) ~= "/" then outf = hush.ROOT .. "/" .. outf end
  local ops = {}
  for line in io.lines(planf) do
    line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
    if line ~= "" then
      local w = {}
      for tok in line:gmatch("%S+") do w[#w + 1] = tok end
      ops[#ops + 1] = w
    end
  end
  hush.assert(ops[1][1] == "room", "plan must start with 'room N'")
  local idx = tonumber(ops[1][2])
  local room = bot.rooms().rooms[idx + 1]
  bot.start_new_game()
  local s0 = hush.snapshot()    -- every room starts from this post-new-game state (tests/solutions/all_rooms.lua does the same)
  hush.restore(s0)
  bot.jump_to_room_synced(idx)

  local frames, g = {}, 0
  local last1a, lagged = bot.peek(0x7E001A), 0
  local log = io.open(hush.OUT .. "/rec.log", "w")
  local function L(...) local s = table.concat({ ... }, " "); log:write(s, "\n"); log:flush() end
  local csv = io.open(hush.OUT .. "/rec.csv", "w")
  local max_aware, first_aware = 0, nil
  local caught = 0
  local ng = #room.guards

  -- one frame with the given buttons; returns false when the room changed (exit touched)
  local function step(btns)
    frames[#frames + 1] = btns
    hush.hold(btns, 1)
    do   -- game time g = game-loop passes while playing ($1A ticks once per pass); a lagging frame (5+ guards, arrows) does not tick
      local a = bot.peek(0x7E001A)
      local d = (a - last1a) & 0xFF
      last1a = a
      if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 then
        g = g + d
        if d == 0 then lagged = lagged + 1 end
      end
    end
    do   -- per-frame debug row: frame, game time, Link x,y, dir, then per guard x,y,dir,aware,state
      local t = { #frames, g, hush.read("link_x"), hush.read("link_y"), hush.read("link_dir") }
      for k = 0, ng - 1 do
        local sp = hush.sprite(k)
        t[#t + 1] = sp.x; t[#t + 1] = sp.y; t[#t + 1] = bot.peek(0x7E0DE0 + k); t[#t + 1] = hush.read("spr_aware", k); t[#t + 1] = sp.state
      end
      csv:write(table.concat(t, ","), "\n")
    end
    for k = 0, ng - 1 do
      local a = hush.read("spr_aware", k)
      if a ~= 3 and a > max_aware then
        max_aware = a
        if not first_aware then first_aware = g; L(string.format("g=%d guard %d aware=%d link=(%d,%d)", g, k, a, hush.read("link_x"), hush.read("link_y"))) end
      end
    end
    if bot.peek(0x7EC902) ~= 0 or bot.peek(0x7EC903) ~= 0 then caught = caught + 1; L("CAUGHT at g=" .. g); error({ hush_fail = "caught at g=" .. g .. " op " .. (ops.cur or "?") }) end
    return hush.read("hush_room") == idx
  end
  local function idle(n) for _ = 1, n do if not step({}) then return false end end return true end

  local tapn = 1
  local function goto_axis(axis, target)
    local stuck, last = 0, nil
    while true do
      local p = (axis == "x") and hush.read("link_x") or hush.read("link_y")
      local d = target - p
      if d == 0 then return true end
      if p == last then stuck = stuck + 1 else stuck = 0 end
      last = p
      if stuck > 40 then error({ hush_fail = string.format("stuck walking %s to %d (at %d) op %s", axis, target, p, ops.cur or "?") }) end
      local dir
      if axis == "x" then dir = d > 0 and "right" or "left" else dir = d > 0 and "down" or "up" end
      if math.abs(d) >= 4 then
        if not step({ dir }) then return false end
      else
        -- fine alignment: a short tap. A lagging frame (the game loop skipped) swallows a 1-frame tap, so taps get longer when one had no effect
        for _ = 1, tapn do if not step({ dir }) then return false end end
        if not step({}) then return false end
        local p2 = (axis == "x") and hush.read("link_x") or hush.read("link_y")
        if p2 == p then tapn = 2 else tapn = 1 end
      end
    end
  end
  local function goto_xy(x, y, order)
    local axes = (order == "yx") and { "y", "x" } or { "x", "y" }
    for _, ax in ipairs(axes) do
      if not goto_axis(ax, ax == "x" and x or y) then return false end
    end
    return true
  end

  local function press(btns, n, gap)
    for _ = 1, n do if not step(btns) then return false end end
    return idle(gap or 0)
  end

  local function menu_item(name)
    -- START opens the item menu (module $0E); the cursor sits on the equipped item. Moves: right/left over owned items.
    local want = ({ bow = 1, bombs = 4 })[name]     -- HUD slot $0202 (equipped id $0303 = 3 / 1 follows when the menu closes)
    hush.assert(want, "item: unknown " .. tostring(name))
    press({ "start" }, 2, 0)
    for _ = 1, 40 do idle(1); if hush.read("game_mode") == 0x0E and bot.peek(0x7E0200) == 4 then break end end
    hush.assert(bot.peek(0x7E0200) == 4, "item menu did not open")
    local tries = 0
    while bot.peek(0x7E0202) ~= want and tries < 12 do
      press({ "right" }, 2, 6); tries = tries + 1
    end
    L("menu: $0202=" .. bot.peek(0x7E0202) .. " $0303=" .. bot.peek(0x7E0303) .. " after " .. tries .. " moves")
    hush.assert(bot.peek(0x7E0202) == want, "could not select " .. name)
    press({ "start" }, 2, 0)
    for _ = 1, 60 do
      if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 then break end
      idle(1)
    end
    idle(2)
    hush.assert(bot.peek(0x7E0303) == ({ bow = 3, bombs = 1 })[name], "equipped item id is " .. bot.peek(0x7E0303) .. " after selecting " .. name)
  end

  local done = false
  local function run_ops()
  for i = 2, #ops do
    local o = ops[i]
    ops.cur = table.concat(o, " ")
    local c = o[1]
    L(string.format("[g=%d f=%d] %s   link=(%d,%d)", g, #frames, ops.cur, hush.read("link_x"), hush.read("link_y")))
    local alive = true
    if c == "goto" then alive = goto_xy(tonumber(o[2]), tonumber(o[3]), o[4])
    elseif c == "until" then
      local T = tonumber(o[2])
      if g > T then L(string.format("LATE: until %d but game time is already %d", T, g)) end
      while g < T and alive do alive = step({}) end
    elseif c == "wait" then alive = idle(tonumber(o[2]))
    elseif c == "face" then
      for try = 1, 6 do
        if hush.read("link_dir") == FACE[o[2]] and try > 1 then break end
        alive = press({ DIRS[o[2]] }, (try > 1) and 2 or 1, 2)
        if not alive then break end
      end
      L("  facing " .. hush.read("link_dir") .. " (want " .. FACE[o[2]] .. ")")
    elseif c == "item" then menu_item(o[2])
    elseif c == "shoot" then alive = press({ "y" }, 3, 2)
    elseif c == "knife" then alive = press({ "b" }, 2, 12)
    elseif c == "stab" then
      local slot, dist, maxw = tonumber(o[2]), tonumber(o[3]), tonumber(o[4] or "900")
      for try = 1, 6 do   -- the alignment taps may have turned Link
        if not o[5] or hush.read("link_dir") == FACE[o[5]] or not alive then break end
        alive = press({ DIRS[o[5]] }, (try > 1) and 2 or 1, 1)
      end
      local hit = false
      for w = 1, maxw do
        local s = hush.sprite(slot)
        local lx, ly = hush.read("link_x") + 8, hush.read("link_y") + 16
        local gx, gy = s.x + 8, s.y + 8
        local ld = hush.read("link_dir")
        local fwd, lat
        if ld == 6 then fwd, lat = gx - lx, gy - ly
        elseif ld == 4 then fwd, lat = lx - gx, gy - ly
        elseif ld == 2 then fwd, lat = gy - ly, gx - lx
        else fwd, lat = ly - gy, gx - lx end
        if fwd <= dist and fwd >= 0 and math.abs(lat) <= 8 then hit = true; break end
        if not step({}) then alive = false; break end
      end
      hush.assert(hit or not alive, "stab: guard never got within " .. dist)
      if alive then
        L(string.format("stab at g=%d", g))
        alive = press({ "b" }, 2, 0)
        for _ = 1, 20 do if alive then alive = step({}) end end
        hush.assert(bot.peek(0x7E0DD0 + slot) ~= 9 or not alive, "stab missed: guard " .. slot .. " still alive")
      end
    elseif c == "expect_room" then
      hush.assert_eq(hush.read("hush_room"), tonumber(o[2]), "room after plan")
    else
      error({ hush_fail = "unknown plan op " .. c })
    end
    if not alive then done = true; break end
  end
  end
  local okp, err = pcall(run_ops)
  if okp and not done then pcall(idle, 5) end
  csv:close()
  -- the exit loads the next room: give it a moment so hush_room is updated
  for _ = 1, 10 do if hush.read("hush_room") ~= idx then break end; hush.wait(1) end
  local f = io.open(outf, "w")
  f:write(string.format("# recorded by tests/dev/record_room.lua from %s: room %d (%s), %d frames\n", planf:match("[^/]*$"), idx, room.id, #frames))
  local i = 1
  while i <= #frames do
    local j = i
    local key = table.concat(frames[i], "+")
    while j < #frames and table.concat(frames[j + 1], "+") == key do j = j + 1 end
    f:write(string.format("%d %s\n", j - i + 1, key == "" and "-" or key))
    i = j + 1
  end
  f:close()
  if not okp then
    local msg = type(err) == "table" and err.hush_fail or tostring(err)
    print("REC: FAILED " .. tostring(msg) .. string.format(" frames=%d g=%d max_aware=%d", #frames, g, max_aware))
    hush.fail(tostring(msg))
    return
  end
  local ok = hush.read("hush_room") == idx + 1 or hush.read("game_mode") ~= 0x07
  print(string.format("REC: room=%s frames=%d game_time=%d lagged=%d max_aware=%d room_now=%d mode=%d", room.id, #frames, g, lagged, max_aware, hush.read("hush_room"), hush.read("game_mode")))
  if not ok then hush.fail("exit not reached (hush_room " .. hush.read("hush_room") .. ")") end
  hush.pass(string.format("%s cleared in %d frames, max awareness %d", room.id, #frames, max_aware))
end)
