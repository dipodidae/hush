-- Replay a chaos repro (tests/chaos/repros/<scenario>_<seed>.inputs, written by tests/chaos/lib/chaos.lua) with the same invariants:
--   HUSH_REPLAY=tests/chaos/repros/mash_7.inputs .venv/bin/python tools/run_test.py tests/dev/chaos_replay.lua [--timeout 300]
-- Header comments of the file: `# @room rNN` (entered like the chaos runs: cold boot, new game, snapshot, restore, synced debug jump),
-- `#@poke <frame> <hex address> <value>` (WRAM pokes applied before that frame). hush.play ignores both, so the file also plays with it.
-- Optional: HUSH_REPLAY_FRAMES=n stops after n frames (bisecting).
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/chaos/lib/?.lua;" .. os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local C = require("chaos")

hush.test("chaos replay", function()
  local path = os.getenv("HUSH_REPLAY")
  hush.assert(path and path ~= "", "set HUSH_REPLAY=<repro file>")
  if path:sub(1, 1) ~= "/" then path = hush.ROOT .. "/" .. path end
  local room, scenario, seed = nil, "replay", 0
  local pokes = {}
  for line in io.lines(path) do
    local r = line:match("^#%s*@room%s+(%S+)")
    if r then room = r end
    local sc, sd = line:match("^# chaos repro: scenario=(%S+) seed=(%d+)")
    if sc then scenario, seed = sc, tonumber(sd) end
    local f, a, v = line:match("^#@poke (%d+) (%x+) (%d+)")
    if f then pokes[#pokes + 1] = { frame = tonumber(f), addr = tonumber(a, 16), v = tonumber(v) } end
  end
  hush.assert(room, "no '# @room' header in " .. path)
  local limit = tonumber(os.getenv("HUSH_REPLAY_FRAMES") or "") or math.huge
  C.NO_REPRO = true     -- do not overwrite / litter tests/chaos/repros while replaying
  C.boot()
  local run = C.enter("replay_" .. scenario, seed, room, { menu_limit = 4000 })
  local pi = 1
  C.guard(run, function()
    for _, s in ipairs(hush.parse_input_script(path)) do
      local btns = s.buttons
      for _ = 1, s.frames do
        if run.n >= limit then return end
        while pokes[pi] and pokes[pi].frame <= run.n do
          local p = pokes[pi]
          if p.addr == 0x7EC901 and p.v > 0 then run:jump(p.v - 1) else run:poke(p.addr, p.v) end
          pi = pi + 1
        end
        run:step(btns)
      end
    end
  end)
  local g = {}
  for k = 0, run.ng - 1 do g[#g + 1] = string.format("%s=%d/%s", run.room.guards[k + 1].id, C.rd(0xD80 + k), C.rd(0xDD0 + k) == 0 and "dead" or "alive") end
  hush.log(string.format("replay end: frame %d, room %d, mode %02X/%02X, Link (%d,%d), guards %s, quits %d, restarts %d, max awareness %d, lagged frames %d",
    run.n, C.rd(0xC900), C.rd(0x10), C.rd(0x11), C.rd16(0x22), C.rd16(0x20), table.concat(g, " "), run.stats.quits, run.stats.restarts, run.stats.max_aware, run.stats.lagged))
  C.finish("replayed " .. run.n .. " frames of " .. path)
end)
