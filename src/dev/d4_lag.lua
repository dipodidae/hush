-- Dev probe (engine, L3 D4; not a test): replays the solution inputs (tests/solutions/<id>.inputs, as tests/solutions/all_rooms.lua) and,
-- per lag frame (frame counter $1A did not tick in module 7 / submodule 0), logs the light work of the frame before: LightWork entry /
-- exit scanline, whether Hush_LightAura changed the glow cell, the glow slice / rotation glow calls, and the main loop end line ($00805D,
-- STZ $12: tests/dev/lag_profile.lua). Also the max main-loop end line per room.
--   .venv/bin/python tools/run_test.py src/dev/d4_lag.lua       (HUSH_ONLY=r20,final to limit)
-- @timeout 900
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local symtab
local function sym(name)
  if not symtab then
    symtab = {}
    for line in io.lines(os.getenv("HUSH_ROOT") .. "/build/hush.sym") do
      local b, a, n = line:match("^(%x%x):(%x%x%x%x) (%S+)$")
      if n then symtab[n] = tonumber(b, 16) * 65536 + tonumber(a, 16) end
    end
  end
  return symtab[name] or error("no symbol " .. name)
end

hush.test("d4 lag probe", function()
  local function line() return emu.getState()["ppu.scanline"] end
  local F = {}                                     -- current frame record
  local cbs = {}
  local function on(addr, f) cbs[#cbs + 1] = { emu.addMemoryCallback(f, emu.callbackType.exec, addr, addr), addr } end
  on(sym("Hush_LightWork"), function() F.lw0 = line() end)
  on(sym("Hush_LightWork_out"), function() F.lw1 = line() end)
  on(sym("Hush_L3GSet"), function() F.aura = true end)
  on(sym("Hush_L3GSlice"), function() F.gs0 = line() end)
  on(sym("Hush_LightStep"), function() F.steps = (F.steps or 0) + 1 end)
  on(sym("Hush_L3TPass"), function() F.tp = (F.tp or 0) + 1 end)
  on(sym("Hush_L3Commit"), function() F.gc = (F.gc or 0) + 1 end)
  on(0x00805D, function() F.main = line() end)
  local function tr(name, tag)
    on(sym(name), function() F.tr = (F.tr or "") .. string.format(" %s@%d", tag, line()) end)
  end
  tr("Hush_LightStep", "step"); tr("Hush_LightWedge", "wedge"); tr("Hush_LightCommit", "commit"); tr("Hush_L3TPass", "tpass")
  tr("Hush_L3GRun", "grun"); tr("Hush_L3GRun_x", "gx"); tr("Hush_LightAura", "aura"); tr("Hush_LightWork_exit", "exit")
  tr("Hush_LightBox", "box"); tr("Hush_LightMarkRow", "mark")

  local m = bot.rooms()
  local only = {}
  for id in (os.getenv("HUSH_ONLY") or ""):gmatch("[^,]+") do only[id] = true end
  bot.start_new_game()
  local s0 = hush.snapshot()
  for i = 1, m.count do
    local r = m.rooms[i]
    if next(only) == nil or only[r.id] then
      local steps = hush.parse_input_script(hush.ROOT .. "/tests/solutions/" .. r.id .. ".inputs")
      hush.restore(s0)
      bot.jump_to_room_synced(i - 1)
      local last1a, lag, mainmax, lwmax, frames = bot.peek(0x7E001A), 0, 0, 0, 0
      local prev = {}
      local done = false
      for _, s in ipairs(steps) do
        for _ = 1, s.frames do
          F = {}
          hush.hold(s.buttons, 1)
          frames = frames + 1
          local a1 = bot.peek(0x7E001A)
          if hush.read("game_mode") == 0x07 and hush.read("submodule") == 0 then
            if a1 == last1a then
              lag = lag + 1
              hush.log(string.format("%s frame %d LAG: prev LW %s-%s aura %s slice@%s steps %s tpass %s gcommits %s main %s | this LW %s-%s main %s",
                r.id, frames, tostring(prev.lw0), tostring(prev.lw1), tostring(prev.aura), tostring(prev.gs0), tostring(prev.steps),
                tostring(prev.tp), tostring(prev.gc), tostring(prev.main), tostring(F.lw0), tostring(F.lw1), tostring(F.main)))
              hush.log("  trace:" .. tostring(prev.tr))
            end
            if F.main and F.main < 240 and F.main > mainmax then mainmax = F.main end
            if F.lw1 and F.lw1 > lwmax then lwmax = F.lw1 end
          end
          last1a = a1
          prev = F
          if hush.read("hush_room") ~= i - 1 or hush.read("game_mode") == 0x13 then done = true; break end
        end
        if done then break end
      end
      hush.log(string.format("%s: %d frames, lag %d, max main-loop end line %d, max LightWork exit line %d", r.id, frames, lag, mainmax, lwmax))
    end
  end
  for _, cb in ipairs(cbs) do emu.removeMemoryCallback(cb[1], emu.callbackType.exec, cb[2], cb[2]) end
  hush.pass()
end)
