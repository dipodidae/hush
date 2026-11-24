-- Dev probe (engine, D2 / B-010; not a test): replays the input of tests/smoke/lighting.lua (jump, 40 frames, 24 legs of 10 frames
-- walking + wait for light_done, r05 ink poke at t = 8) without its checks, and for every wait > LONG frames prints what the light
-- worker did: jobs started per guard slot and their class (1 cone, 2 suspicious, 3 alert), frames per job phase, frames with amber
-- tiles pending, and the guards' awareness states during the wait.
--   .venv/bin/python tools/run_test.py src/dev/d2_legs.lua
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")
local W = emu.memType.snesWorkRam
local function rd(a) return emu.read(a, W, false) end
local LONG = 100

hush.test("D2 legs probe (smoke_lighting replay)", function()
  local m = bot.rooms()
  bot.start_new_game()
  local moves = { { "left" }, { "up" }, { "right" }, { "down" } }
  local all = {}
  for ri = 1, m.count do
    local r = m.rooms[ri]
    bot.jump_to_room(ri - 1)
    hush.wait(40)
    local rmax = 0
    for t = 1, 24 do
      hush.hold(moves[(t // 6) % 4 + 1], 10)
      if r.id == "r05" and t == 8 then
        local gx, gy = rd(0x0D10) + 256 * rd(0x0D30), rd(0x0D00) + 256 * rd(0x0D20)
        bot.poke(0x7EC908, (gx - 40) & 0xFF); bot.poke(0x7EC909, (gx - 40) >> 8)
        bot.poke(0x7EC90A, (gy + 8) & 0xFF); bot.poke(0x7EC90B, (gy + 8) >> 8)
        bot.poke(0x7EC90C, 200); bot.poke(0x7EC90D, 0)
        hush.wait(2)
      end
      local w0 = hush.frame()
      local tr = { jobs = {}, cls = {}, ph = {}, tiles = 0, aw = {}, prevjob = 0xFF, prevsig = nil, n = 0, tl = {} }
      while not (rd(0x10) == 7 and rd(0x11) == 0 and rd(0xE7F6) == 1) do
        if rd(0x10) ~= 7 or rd(0x11) ~= 0 then w0 = hush.frame() end
        if hush.frame() - w0 > 1200 then break end
        hush.wait(1)
        tr.n = tr.n + 1
        if tr.n % 6 == 0 then
          local a = {}
          for s = 0, 7 do if rd(0x0DD0 + s) == 9 and rd(0x0E20 + s) == 0x41 then a[#a + 1] = string.format("%d%d", s, rd(0x0D80 + s)) end end
          tr.tl[#tr.tl + 1] = string.format("%d:j%02X/%d/c%d L%02X T%02X [%s]", tr.n, rd(0xE770), rd(0xE771), rd(0xE76C), rd(0x1DC18), rd(0x1DBC0), table.concat(a, ","))
        end
        local j, ph = rd(0xE770), rd(0xE771)
        local key = (j == 0xFF) and "idle" or ("ph" .. ph)
        tr.ph[key] = (tr.ph[key] or 0) + 1
        local sig = rd(0xE76C) .. "/" .. rd(0xE76E) + 256 * rd(0xE76F)
        if j ~= 0xFF and (j ~= tr.prevjob or sig ~= tr.prevsig) then
          tr.jobs[j] = (tr.jobs[j] or 0) + 1
          local c = rd(0xE76C)
          tr.cls[c] = (tr.cls[c] or 0) + 1
        end
        tr.prevjob, tr.prevsig = j, sig
        if rd(0x1DBC0) ~= 0xFF then tr.tiles = tr.tiles + 1 end
        for s = 0, 7 do
          if rd(0x0DD0 + s) == 9 and rd(0x0E20 + s) == 0x41 then
            local a = rd(0x0D80 + s)
            tr.aw[s] = tr.aw[s] or {}
            tr.aw[s][a] = (tr.aw[s][a] or 0) + 1
          end
        end
      end
      local wf = hush.frame() - w0
      if wf > rmax then rmax = wf end
      if wf > LONG then
        local function kv(t) local o = {} for k, v in pairs(t) do o[#o + 1] = tostring(k) .. ":" .. v end table.sort(o) return table.concat(o, " ") end
        local aw = {}
        for s, t in pairs(tr.aw) do aw[#aw + 1] = "slot" .. s .. "{" .. kv(t) .. "}" end
        table.sort(aw)
        hush.log(string.format("%s t=%d wait %d: jobs by slot {%s}, by class {%s}, frames by phase {%s}, tiles pending %d; awareness %s",
          r.id, t, wf, kv(tr.jobs), kv(tr.cls), kv(tr.ph), tr.tiles, table.concat(aw, " ")))
        if wf > 150 then hush.log("  timeline (frame:job/phase/class LPR ADB [slot+awareness]): " .. table.concat(tr.tl, " | ")) end
      end
    end
    all[#all + 1] = r.id .. " " .. rmax
  end
  hush.log("max wait per room: " .. table.concat(all, ", "))
  hush.pass()
end)
