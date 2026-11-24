-- B-010 probe (docs/bugs.md): how long light_done ($40:E7F6, BW-RAM; was $7EE7F6) stays 0 while Link stands still, and which of its conditions holds it at 0.
-- Usage: .venv/bin/python tools/run_test.py tests/dev/b010_light_done.lua        (room: HUSH_ROOM, default r19)
-- Post-new-game state + debug jump, then tests/dev/repros/b010_r19.inputs (walk left 10 frames, stand still 1200), frame by frame.
-- Conditions (docs/ram_map.md light_done row, Hush_L3Done): region running (light_l3reg +0 != $FF), parked amber region (light_l3pk +0
-- != $FF), amber dirty box (light_l3adb x0 != $FF), guard job (light_job +8 != $FF), carrier marked (light_l3reg +8 word != 0), wanted
-- glow d != rendered (light_l3car +48/+64 vs +16/+32, carrier 8), light_dirty != 0.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local W = emu.memType.snesWorkRam
local function rd(a) return emu.read(a, W, false) end
local LM = emu.memType.snesSaveRam       -- light rows: SA-1 BW-RAM since SA-1 step 3 (docs/ram_map.md "HUSH lighting")
local function rl(a) return emu.read(a, LM, false) end
local function rl16(a) return rl(a) + 256 * rl(a + 1) end

hush.test("dev: B-010 light_done liveness probe", function()
  local m = bot.rooms()
  local function ram(n)
    local e = hush.ram[n]
    hush.assert(e and e.mem == LM, "docs/ram_map.md: " .. n .. " missing or not BW-RAM")
    return e.addr
  end
  local DONE, JOB, DIRTY = ram("light_done"), ram("light_job") + 8, ram("light_dirty")
  local REG, PK, ADB, CAR = ram("light_l3reg"), ram("light_l3pk"), ram("light_l3adb"), ram("light_l3car")
  local SIGC = ram("light_sigc")
  local want = os.getenv("HUSH_ROOM") or "r19"
  local ri
  for i = 1, m.count do if m.rooms[i].id == want then ri = i end end
  hush.assert(ri, "no room " .. want)
  bot.start_new_game()
  bot.jump_to_room(ri - 1)
  hush.wait(40)
  local steps = hush.parse_input_script(hush.ROOT .. "/tests/dev/repros/b010_r19.inputs")
  hush.hold(steps[1].buttons, steps[1].frames)
  local n = steps[2].frames
  local cnt = { region = 0, parked = 0, adb = 0, job = 0, marked = 0, glow = 0, dirty = 0 }
  local first_done, done_frames, run, maxrun = nil, 0, 0, 0
  local jobs, sigchg, prevjob, prevsig, lag, prev1a = 0, 0, 0xFF, nil, 0, rd(0x1A)
  for f = 1, n do
    hush.wait(1)
    if rd(0x10) ~= 7 or rd(0x11) ~= 0 then hush.log("frame " .. f .. ": left gameplay (module " .. rd(0x10) .. ")"); break end
    if rd(0x1A) == prev1a then lag = lag + 1 end
    prev1a = rd(0x1A)
    local d = rl(DONE)
    if d == 1 then
      done_frames = done_frames + 1
      if not first_done then first_done = f end
      run = 0
    else
      run = run + 1; if run > maxrun then maxrun = run end
      if rl(REG) ~= 0xFF then cnt.region = cnt.region + 1 end
      if rl(PK) ~= 0xFF then cnt.parked = cnt.parked + 1 end
      if rl(ADB) ~= 0xFF then cnt.adb = cnt.adb + 1 end
      if rl(JOB) ~= 0xFF then cnt.job = cnt.job + 1 end
      if rl16(REG + 8) ~= 0 then cnt.marked = cnt.marked + 1 end
      if rl(CAR + 48 + 8) ~= rl(CAR + 16 + 8) or rl(CAR + 64 + 8) ~= rl(CAR + 32 + 8) then cnt.glow = cnt.glow + 1 end
      if rl16(DIRTY) ~= 0 then cnt.dirty = cnt.dirty + 1 end
    end
    local j = rl(JOB)
    if prevjob == 0xFF and j ~= 0xFF then jobs = jobs + 1 end
    prevjob = j
    local s = {}
    for k = 0, 31 do s[#s + 1] = rl(SIGC + k) end
    s = table.concat(s, ",")
    if prevsig and s ~= prevsig then sigchg = sigchg + 1 end
    prevsig = s
  end
  hush.log(string.format("%s: Link still for %d frames: first light_done=1 at frame %s, done on %d frames, longest done=0 run %d, lag frames %d",
    want, n, tostring(first_done), done_frames, maxrun, lag))
  hush.log(string.format("done=0 frames by condition: region %d, parked %d, amber dirty box %d, guard job %d, marked %d, glow d %d, light_dirty %d",
    cnt.region, cnt.parked, cnt.adb, cnt.job, cnt.marked, cnt.glow, cnt.dirty))
  hush.log(string.format("guard jobs started %d, committed signature changes %d", jobs, sigchg))
  hush.pass(string.format("%s first done at %s, longest done=0 run %d frames", want, tostring(first_done), maxrun))
end)
