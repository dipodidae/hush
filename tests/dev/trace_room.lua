-- Dev utility (QA): per-frame trace of one room on build/hush.sfc.
--   HUSH_TRACE_ROOM=<0-based room index>  HUSH_TRACE_FRAMES=<n>  [HUSH_TRACE_INPUTS=<script>]  [HUSH_TRACE_GHOST=1]
--   [HUSH_TRACE_EXTRA="7E0202 7E0303"] extra WRAM bytes appended to every row
--   [HUSH_TRACE_POKES="addr=val,addr=val"] applied once at frame 0 (e.g. item select in model checks)
-- Writes $HUSH_OUT/trace.csv: one row per frame (f 0 = the first controllable frame, before any input):
--   f,link_x,link_y,room,mode,flash,caught,ink_t,link_dir,then per guard slot: x,y,dir,aware,state, then $1A (frame counter)
-- HUSH_TRACE_GHOST=1 puts Link on the other layer every frame so guards ignore him (their unperturbed patrol).
-- Not a test: runs with `tools/run_test.py tests/dev/trace_room.lua` and always "passes".
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

hush.test("trace_room", function()
  local idx = tonumber(os.getenv("HUSH_TRACE_ROOM") or "0")
  local nfr = tonumber(os.getenv("HUSH_TRACE_FRAMES") or "600")
  local inp = os.getenv("HUSH_TRACE_INPUTS")
  local ghost = os.getenv("HUSH_TRACE_GHOST") == "1"
  local room = bot.rooms().rooms[idx + 1]
  bot.start_new_game()
  bot.jump_to_room(idx)
  -- per-frame input list
  local frames = {}
  if inp and inp ~= "" then
    if inp:sub(1, 1) ~= "/" then inp = hush.ROOT .. "/" .. inp end
    for _, s in ipairs(hush.parse_input_script(inp)) do
      for _ = 1, s.frames do frames[#frames + 1] = s.buttons end
    end
  end
  local extra = {}
  for a in (os.getenv("HUSH_TRACE_EXTRA") or ""):gmatch("(%x+)") do extra[#extra + 1] = tonumber(a, 16) end
  local f = io.open(hush.OUT .. "/trace.csv", "w")
  local ng = #room.guards
  local function row(i)
    local t = { i, hush.read("link_x"), hush.read("link_y"), hush.read("hush_room"), hush.read("game_mode"),
      bot.peek(0x7EC903), bot.peek(0x7EC902), bot.peek(0x7EC90C) + 256 * bot.peek(0x7EC90D), hush.read("link_dir") }
    for k = 0, ng - 1 do
      local s = hush.sprite(k)
      t[#t + 1] = s.x; t[#t + 1] = s.y; t[#t + 1] = bot.peek(0x7E0DE0 + k)
      t[#t + 1] = hush.read("spr_aware", k); t[#t + 1] = s.state
    end
    t[#t + 1] = bot.peek(0x7E001A)   -- frame counter: one tick per game-loop pass; a lagging frame does not advance it
    for _, a in ipairs(extra) do t[#t + 1] = bot.peek(a) end   -- HUSH_TRACE_EXTRA bytes go after the guard columns
    f:write(table.concat(t, ","), "\n")
  end
  local pk = os.getenv("HUSH_TRACE_POKES")
  if pk then for a, v in pk:gmatch("(%x+)=(%x+)") do bot.poke(tonumber(a, 16), tonumber(v, 16)) end end
  row(0)
  for i = 1, nfr do
    if ghost then bot.poke(0x7E00EE, 1) end
    hush.hold(frames[i] or {}, 1)
    row(i)
  end
  f:close()
  hush.pass("traced " .. nfr .. " frames")
end)
