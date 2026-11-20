-- Dev utility (QA, not a test): replay a final-room input script exactly like tests/solutions/meter_budget.lua (post-new-game
-- snapshot + bot.jump_to_room_synced) and log every awareness transition with Link's cell and every guard's slot, spec letter
-- (rooms_gen guards list = slot order, tests/lib/ai.lua:9), cell, facing and state.
-- Input: tests/solutions/final.inputs (USE_REC = true: build/test-results/dev_record_final/final.inputs).
-- Other rooms / files: a wrapper sets the globals PROBE_ROOM (room id) and PROBE_FILE (repo-relative) and dofile()s this script
-- (e.g. tests/dev/b008_probe.lua).
-- Output: stdout PROBE lines; $HUSH_OUT/probe.csv (f, g, link x,y,cell, dir, then per slot x,y,cell,dir,aware).
--   .venv/bin/python tools/run_test.py tests/dev/final_probe.lua
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("final_probe", function()
  local m = bot.rooms()
  local idx, r
  local rid = PROBE_ROOM or "final"
  for i, rr in ipairs(m.rooms) do if rr.id == rid then idx, r = i - 1, rr end end
  -- the installed replay, or a fresh recording (tests/dev/record_final.lua): run_test.py passes no env,
  -- so the switch is this flag; set it to true while iterating on tests/dev/plans/final_qa.plan.
  local USE_REC = false
  local path = hush.ROOT .. (USE_REC and "/build/test-results/dev_record_final/final.inputs" or "/tests/solutions/final.inputs")
  if PROBE_FILE then path = hush.ROOT .. "/" .. PROBE_FILE end
  print("PROBE: room " .. rid .. " inputs " .. path)
  local steps = hush.parse_input_script(path)
  bot.start_new_game()
  local s0 = hush.snapshot()
  hush.restore(s0)
  bot.jump_to_room_synced(idx)
  local ng = #r.guards
  local ox, oy = r.base_x + m.win_x, r.base_y + m.win_y
  local function lcell() return (hush.read("link_x") - ox + 8) // 16, (hush.read("link_y") + 16 - oy) // 16 end
  local function gcell(k) local s = hush.sprite(k); return (s.x - ox + 8) // 16, (s.y - oy + 8) // 16 end
  for k = 0, ng - 1 do
    local cx, cy = gcell(k)
    print(string.format("PROBE: slot %d = spec guard '%s' (rooms_gen) at cell (%d,%d) px (%d,%d) dir %d", k, r.guards[k + 1].id, cx, cy,
      hush.sprite(k).x, hush.sprite(k).y, bot.peek(0x7E0DE0 + k)))
  end
  local csv = io.open(hush.OUT .. "/probe.csv", "w")
  local prev, f, g, last1a = {}, 0, 0, bot.peek(0x7E001A)
  local done = false
  local function snap()
    local t = {}
    for k = 0, ng - 1 do
      local cx, cy = gcell(k)
      t[#t + 1] = string.format("%s:(%d,%d)d%d a%d", r.guards[k + 1].id, cx, cy, bot.peek(0x7E0DE0 + k), hush.read("spr_aware", k))
    end
    return table.concat(t, " ")
  end
  local function frame(btns)
    hush.hold(btns, 1)
    f = f + 1
    local a1 = bot.peek(0x7E001A)
    if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 then g = g + ((a1 - last1a) & 0xFF) end
    last1a = a1
    if hush.read("hush_room") ~= idx or hush.read("game_mode") == 0x13 then done = true; return end
    if hush.read("game_mode") ~= 0x07 then return end   -- item menu: the game is paused
    local lx, ly = lcell()
    local ink = hush.read("hush_ink_t")
    if (ink > 0) ~= (prev.ink or false) then
      print(string.format("PROBE: f%d g%d ink cloud %s (t=%d) at (%d,%d) link (%d,%d) px (%d,%d)", f, g, ink > 0 and "ON" or "OFF", ink,
        hush.read("hush_ink_x"), hush.read("hush_ink_y"), lx, ly, hush.read("link_x"), hush.read("link_y")))
      prev.ink = ink > 0
    end
    local row = { f, g, ink, hush.read("link_x"), hush.read("link_y"), lx, ly, hush.read("link_dir"), table.concat(btns, "+") }
    for k = 0, ng - 1 do
      local s = hush.sprite(k); local cx, cy = gcell(k)
      local a = hush.read("spr_aware", k)
      row[#row + 1] = string.format("%s %d %d %d %d %d %d", r.guards[k + 1].id, s.x, s.y, cx, cy, bot.peek(0x7E0DE0 + k), a)
      if prev[k] ~= nil and prev[k] ~= a then
        print(string.format("PROBE: f%d g%d slot %d (%s) aware %d->%d  link (%d,%d) px (%d,%d) dir %d | %s", f, g, k, r.guards[k + 1].id,
          prev[k], a, lx, ly, hush.read("link_x"), hush.read("link_y"), hush.read("link_dir"), snap()))
      end
      prev[k] = a
    end
    csv:write(table.concat(row, ","), "\n")
  end
  for _, s in ipairs(steps) do
    for _ = 1, s.frames do frame(s.buttons); if done then break end end
    if done then break end
  end
  for _ = 1, 30 do if done then break end; frame({}) end
  csv:close()
  print(string.format("PROBE: end f%d g%d done=%s room=%d mode=%d meter=%d caught=%d", f, g, tostring(done), hush.read("hush_room"),
    hush.read("game_mode"), hush.read("hush_meter"), bot.peek(0x7EC902)))
  hush.pass("probe")
end)
