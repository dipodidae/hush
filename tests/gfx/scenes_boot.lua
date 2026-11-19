-- GFX scenes reachable from a cold boot by scripted input (no savestate needed).
-- Dumps VRAM/CGRAM/OAM/PPU + screenshot per scene into build/test-results/gfx_scenes_boot/ for
-- tools/gfx_leakcheck.py. The flow is driven by the game module ($10) rather than fixed delays, because
-- the (cut) intro runs for a build-dependent number of frames. Module numbers: 0 intro, 1 file select,
-- 4 name entry, 5 load file, 7 dungeon/house, 0x0E menu/text (docs/ram_map.md `game_mode`).
-- @timeout 300
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local gfx = require("gfx")

local function tap(b, n) for _ = 1, (n or 1) do hush.press(b, 4, 8) end end
local function mode() return hush.read("game_mode") end

local function until_mode(want, what, max_tries, key)
  local tries = 0
  while mode() ~= want do
    tap({ key or "start" }); hush.wait(20)
    tries = tries + 1
    hush.assert(tries < (max_tries or 200), what .. ": never reached module " .. want .. ", stuck in " .. mode())
  end
end

hush.test("gfx scenes: cold boot -> title -> START -> room 1 (E1: no file select / name entry / house any more)", function()
  -- A0 intro skip (src/hooks/intro_skip.asm): boot goes straight to the title screen (module 0,
  -- submodule 8, "PRESS START") with no triforce / sword animation, within ~6 s of power-on.
  local waited = 0
  while not (mode() == 0 and hush.read("submodule") == 8) do
    hush.wait(5); waited = waited + 5
    hush.assert(waited < 600, "title screen not reached within 600 frames (module " .. mode() .. ", sub " .. hush.read("submodule") .. ")")
  end
  hush.wait(30); gfx.snap("title")
  hush.assert(hush.read("submodule") == 8, "title screen left by itself (attract mode must not start)")
  hush.wait(600); gfx.snap("title_idle")
  hush.assert(mode() == 0 and hush.read("submodule") == 8, "title screen timed out into another scene")
  -- E1 (src/hooks/new_game.asm): START goes straight into room 1 of the tower. The file-select, name-entry and
  -- Link's-house scenes of vanilla can no longer be reached, so they are no longer dumped.
  tap({ "start" })
  local tries, stable = 0, 0
  while stable < 6 do
    if mode() == 0x07 and hush.read("submodule") == 0x00 then stable = stable + 1 else stable = 0 end
    hush.wait(30)
    tries = tries + 1
    hush.assert(tries < 100, "never reached gameplay; module=" .. mode())
  end
  hush.wait(120)
  gfx.snap("room1_gameplay")
  -- dev state for the other gfx scenes; made from THIS build, so it never carries vanilla VRAM/CGRAM
  os.execute("mkdir -p '" .. hush.ROOT .. "/build/dev_states'")
  hush.save_state("build/dev_states/gfx_room.mss")
  -- SELECT in gameplay opens the vanilla save/continue message: the only text box still reachable
  tap({ "select" }); hush.wait(90)
  gfx.snap("text_box")
  hush.pass("scenes dumped")
end)
