-- Smoke (stealth meter, criterion 5): pillars.md:107-109 "A guard made Unaware by ink and re-noticing more than 120 frames after his
-- last small hit lowers it by 4 again; re-noticing within 120 frames lowers it by 0." pillars.md:65-66 "After guard G causes a hit,
-- G cannot cause another hit of the same size for 120 gameplay frames." (pillars.md:63-70: re-notice hits again; a blocked notice is
-- not a hit, so it does not restart the cooldown; a big hit is never blocked by a recent small hit.)
-- @rom dev
-- @timeout 180
--
-- Frame counting (exact):
--   * a "gameplay frame" is one pass of the game's main loop in module 7 / submodule 0; it is counted by frame_counter ($1A,
--     docs/ram_map.md), which vanilla increments once right before RunModule (vendor/usdasm/bank_00.asm:70-73). The meter check runs
--     at the end of that same RunModule pass (src/hooks/meter.asm header), so it sees one value of $1A per check.
--   * H = the value of $1A in the frame whose meter check applies the hit (the first endFrame where hush_meter has dropped).
--   * "re-notice at +k" = the awareness transition is first seen by the meter check of frame H+k: the spr_aware poke is done at the
--     end of frame H+k-1, and after frame H+k hush_aprev (the value the check last saw) has changed (asserted as a precondition).
--   * spec: +1 .. +120 are "for 120 gameplay frames" after the hit -> blocked (cost 0); +121 is the first allowed (cost 4 / 16).
--   * every frame between H and H+k is checked to be module 7 / submodule 0 (otherwise the cooldown would not be counting).
-- +120 and +121 cannot both be tried on one guard in one timeline (the guard must be Unaware again in between), so both branch from
-- one in-memory snapshot taken at about +100 (hush.snapshot / restore restore $1A too).
-- All boundary cases are run and logged, then the test fails listing every case that broke the spec.
-- The guard is calmed by a real ink cloud (hush_ink_x / _y / _t poked, as tests/smoke/ai_ink.lua does: the guard standing in the
-- cloud drops to Unaware, docs/engine_notes.md 11.5); the notices are forced (spr_aware poke). Link is parked out of range.
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local ai = require("ai")
local meter = require("meter")

local fails = {}
local function check(ok, msg)
  hush.log((ok and "ok   " or "FAIL ") .. msg)
  if not ok then fails[#fails + 1] = msg end
end

local function fc() return hush.read("frame_counter") end
local function since(base) return (fc() - base) % 256 end

local function cloud(cx, cy, t)
  hush.write("hush_ink_x", cx); hush.write("hush_ink_y", cy); hush.write("hush_ink_t", t)
end

local function ink_calm(gx, gy)
  cloud(gx + 8, gy + 8, 300)
  local f = meter.watch(8, function() return ai.state(0) == ai.S.UNAWARE end)
  hush.assert(f ~= nil, "precondition: the ink cloud made the guard Unaware")
  cloud(0, 0, 0)
  hush.wait(2)
  hush.assert_eq(hush.read("hush_aprev", 0), 0, "precondition: the meter check has seen the guard Unaware")
end

-- Wait (one endFrame at a time) until the last finished gameplay frame is base+n; every frame must be module 7 / submodule 0.
local function wait_to(base, n)
  hush.assert(since(base) <= n, string.format("precondition: not past +%d already (at +%d)", n, since(base)))
  while since(base) < n do
    hush.wait(1)
    hush.assert(hush.read("game_mode") == 0x07 and hush.read("submodule") == 0,
      string.format("precondition: gameplay frame at +%d (module 7 / submodule 0)", since(base)))
  end
end

-- Transition seen by the meter check of frame base+k: poke at the end of base+k-1, run one frame. Returns the units it cost.
local function transition_at(base, k, poke, want_aware, what)
  wait_to(base, k - 1)
  local m0 = meter.get()
  poke(0)
  hush.wait(1)
  hush.assert_eq(since(base), k, what .. ": precondition: exactly one gameplay frame ran after the poke")
  hush.assert_eq(hush.read("hush_aprev", 0), want_aware, what .. ": precondition: the meter check of frame +" .. k .. " saw the transition")
  return m0 - meter.get()
end

-- The frame in which a hit lands: wait until the meter drops, return $1A of that frame.
local function hit_frame(n, what)
  local m0 = meter.get()
  local f = meter.watch(n, function() return meter.get() ~= m0 end)
  hush.assert(f ~= nil, what .. ": the meter dropped")
  return fc(), m0 - meter.get()
end

hush.test("meter_cooldown: blocked +1..+120 after a hit, allowed from +121 (small and big, criterion 5)", function()
  ai.enter("ai4_dark")
  ai.link_to(0, 140, 0)
  hush.wait(4)
  local gx, gy = ai.pos(0)
  hush.assert_eq(meter.get(), 32, "full meter before the first notice (pillars.md:100)")

  -- ===== small hit =====
  meter.notice(0)
  local H, d = hit_frame(6, "first notice")
  hush.assert_eq(d, 4, "first notice = -4 (criterion 2)")
  hush.assert_eq(hush.read("hush_aprev", 0), 1, "precondition: the hit frame is the frame the check saw 0 -> 1")

  -- +40: blocked (pillars.md:108-109 "within 120 frames lowers it by 0")
  ink_calm(gx, gy)
  d = transition_at(H, 40, meter.notice, 1, "small +40")
  check(d == 0, string.format("small: re-notice at +40 costs 0 (pillars.md:108-109) [cost %d]", d))

  -- snapshot at ~+100 with the guard Unaware again, then branch
  ink_calm(gx, gy)
  wait_to(H, 100)
  local snap = hush.snapshot()
  hush.assert(since(H) <= 110, "precondition: snapshot taken before +110")

  -- +121: allowed (pillars.md:107-108 "more than 120 frames ... lowers it by 4 again"; the +40 notice was blocked, so not a hit
  -- and did not restart the cooldown, pillars.md:65-66)
  d = transition_at(H, 121, meter.notice, 1, "small +121")
  check(d == 4, string.format("small: re-notice at +121 costs 4 (pillars.md:107-108) [cost %d]", d))

  -- +120: blocked (pillars.md:65-66 "for 120 gameplay frames", :108-109 "within 120 frames lowers it by 0")
  hush.restore(snap)
  d = transition_at(H, 120, meter.notice, 1, "small +120")
  check(d == 0, string.format("small: re-notice at exactly +120 costs 0 (pillars.md:65-66, :108-109) [cost %d]", d))

  -- ===== big hit ===== (from the +120 branch: guard Suspicious; meter reset to 32 so every cost below is visible unclamped)
  meter.set(32)
  hush.wait(2)
  meter.alert(0)
  local Hb
  Hb, d = hit_frame(6, "first alert")
  check(d == 16, string.format("big: Suspicious -> Alert costs 16, not blocked by the recent small hit (criterion 3, pillars.md:66-68) [cost %d]", d))
  meter.set(32)

  -- early re-alert (from Unaware, 0 -> 2 is big, pillars.md:58): blocked
  ink_calm(gx, gy)
  local k = since(Hb) + 1
  d = transition_at(Hb, k, meter.alert, 2, "big +" .. k)
  check(d == 0, string.format("big: re-alert at +%d costs 0 (pillars.md:65-66) [cost %d]", k, d))

  ink_calm(gx, gy)
  wait_to(Hb, 100)
  local snapb = hush.snapshot()
  hush.assert(since(Hb) <= 110, "precondition: big snapshot taken before +110")

  d = transition_at(Hb, 121, meter.alert, 2, "big +121")
  check(d == 16, string.format("big: re-alert at +121 costs 16 (pillars.md:65-66) [cost %d]", d))

  hush.restore(snapb)
  d = transition_at(Hb, 120, meter.alert, 2, "big +120")
  check(d == 0, string.format("big: re-alert at exactly +120 costs 0 (pillars.md:65-66) [cost %d]", d))

  hush.assert(not ai.caught(), "precondition: never caught")
  hush.assert(#fails == 0, #fails .. " cooldown case(s) broke the spec: " .. table.concat(fails, "; "))
  hush.pass("per-guard cooldown: +1..+120 blocked, +121 allowed, small and big; blocked notices do not restart it")
end)
