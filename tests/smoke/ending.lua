-- Smoke (E6): the ending screen. Clearing the last room fades out into module $13 (Hush_EndingModule): black screen, two text lines
-- ("THE VAULT IS EMPTY" / "AND NOBODY HEARD A THING"), the run's stats ("RETRIES nnn", "TIME mmM ssS"), "PRESS START", song $13 (fanfare).
-- START (after 90 frames) fades out to the title; START there starts a fresh game (stats reset). Also: SELECT does nothing in a room.
-- The text is read back from the BG3 tilemap in VRAM (word $6000 + 32 row + col; a glyph = the 8x16 tile pair T(c) / T(c) + 16, T(c) = ((c & $F0) << 1) | (c & $0F)).
-- @timeout 200
package.path = os.getenv("HUSH_ROOT") .. "/tests/lib/?.lua;" .. package.path
local hush = require("hush")
local bot = require("bot")

local V = emu.memType.snesVideoRam
local function word(col, row) return emu.read16((0x6000 + 32 * row + col) * 2, V, false) end
local function code(ch)
  if ch == " " then return 0x59 end
  if ch:match("%u") then return ch:byte() - 65 end
  if ch:match("%l") then return 0x1A + ch:byte() - 97 end
  if ch:match("%d") then return 0x34 + ch:byte() - 48 end
  error("no font code for " .. ch)
end
local function tile(c) return ((c & 0xF0) << 1) | (c & 0x0F) end
-- the text of a line as drawn: every glyph's top / bottom tile (blank = $20FF for spaces)
local function check_line(col, row, text, pal_hi)
  for i = 1, #text do
    local ch = text:sub(i, i)
    local top, bot_ = word(col + i - 1, row), word(col + i - 1, row + 1)
    if ch == " " then
      hush.assert_eq(top, 0x20FF, "blank cell in '" .. text .. "' at " .. i)
    else
      local t = tile(code(ch))
      hush.assert_eq(top, (pal_hi << 8) | t, "'" .. text .. "' glyph " .. i .. " ('" .. ch .. "') top tile")
      hush.assert_eq(bot_, (pal_hi << 8) | (t + 16), "'" .. text .. "' glyph " .. i .. " ('" .. ch .. "') bottom tile")
    end
  end
end

hush.test("ending: last room -> ending screen -> title -> new game", function()
  local m = bot.rooms()
  local starts = {}
  emu.addMemoryCallback(function(_, v) if v == 0x13 then starts[#starts + 1] = hush.frame() end end, emu.callbackType.write, 0x2140, 0x2140)
  bot.start_new_game()

  -- SELECT does nothing (it used to open the save / continue message)
  hush.hold({ "select" }, 8)
  hush.wait(4)
  hush.assert_eq(hush.read("game_mode"), 0x07, "SELECT does not leave the room module")
  hush.assert_eq(hush.read("submodule"), 0x00, "SELECT opens no message")

  -- the last room: two catches (retries), then the exit
  local last = m.count - 1
  bot.jump_to_room(last)
  hush.wait(20)
  local r = m.rooms[m.count]
  for i = 1, 2 do
    bot.poke(0x7EC902, 1)
    hush.wait(12)
  end
  hush.assert_eq(bot.peek(0x7EC912), 2, "two retries counted")
  hush.wait(120)                          -- a couple of seconds of play time (2 s = 120 frames of hush_sec / hush_fsub)
  local x, y = bot.exit_pos(r.exits[1])
  bot.teleport(x, y)
  local f0 = hush.frame()
  local reached
  for f = 1, 120 do
    hush.wait(1)
    if hush.read("game_mode") == 0x13 and bot.peek(0x7E00B0) == 2 then reached = f; break end
  end
  hush.assert(reached ~= nil, "the ending module ($13) ran its fade-in")
  hush.log("last exit -> ending screen fully lit after " .. reached .. " frames")
  hush.wait(10)
  hush.screenshot("ending")
  local sec, retries = bot.peek(0x7EC914) + 256 * bot.peek(0x7EC915), bot.peek(0x7EC912) + 256 * bot.peek(0x7EC913)
  hush.log(string.format("stats: retries %d, play time %d s", retries, sec))
  hush.assert_eq(retries, 2, "retries")
  hush.assert(sec >= 2, "at least the two seconds waited in the last room")
  hush.assert_eq(bot.peek(0x7E0013), 0x0F, "full brightness")
  hush.assert_eq(bot.peek(0x7E001C), 0x04, "BG3 only")
  -- text
  check_line(7, 6, "THE VAULT IS EMPTY", 0x24)
  check_line(4, 9, "AND NOBODY HEARD A THING", 0x24)
  check_line(10, 14, string.format("RETRIES %03d", retries), 0x24)
  check_line(10, 17, string.format("TIME %02dM %02dS", sec // 60, sec % 60), 0x24)
  check_line(10, 23, "PRESS START", 0x28)
  hush.assert_eq(word(0, 0), 0x20FF, "the rest of the map is blank")
  hush.assert_eq(word(31, 27), 0x20FF, "the rest of the map is blank (corner)")
  hush.assert_eq(bot.peek(0x7E0130), 0x13, "song $13 (fanfare) is the current song")
  hush.assert(#starts >= 1 and starts[#starts] >= f0, "song $13 was sent to the APU")

  -- START too early (before 90 frames in the wait state) is ignored
  hush.assert(bot.peek(0x7EC917) < 90, "in the first 90 frames of the wait state")
  hush.press({ "start" }, 3, 1)
  hush.wait(12)
  hush.assert_eq(hush.read("game_mode"), 0x13, "START before 90 frames is ignored: still on the ending screen")
  hush.assert_eq(bot.peek(0x7E00B0), 2, "still waiting")
  hush.wait(80)
  hush.screenshot("ending_late")
  hush.press({ "start" }, 3, 1)
  local t = 0
  while not (hush.read("game_mode") == 0x00 and hush.read("submodule") == 0x08) do
    hush.wait(1); t = t + 1
    hush.assert(t < 900, string.format("title not reached after START (mode=%02X sub=%02X)", hush.read("game_mode"), hush.read("submodule")))
  end
  hush.log("START on the ending screen -> title after " .. t .. " frames")
  hush.wait(40)
  hush.screenshot("title_again")

  -- a fresh game: stats reset, room 1
  hush.press({ "start" }, 4, 4)
  bot.wait_control()
  hush.assert_eq(hush.read("room_id"), m.first_id, "second game starts in room 1")
  hush.assert_eq(bot.peek(0x7EC912) + 256 * bot.peek(0x7EC913), 0, "retries reset")
  hush.assert(bot.peek(0x7EC914) + 256 * bot.peek(0x7EC915) <= 1, "play time reset")
  hush.wait(10)
  hush.screenshot("second_game")
  hush.pass(string.format("ending screen ok (retries %d, %d s)", retries, sec))
end)
