local keyboard = require("src.keyboard")

print("--- Testing Virtual Keyboard ---")
local committed_text = nil
local closed = false

keyboard.open("", function(text) committed_text = text end, function() closed = true end)
assert(keyboard.is_open() == true, "Keyboard should be open")

-- Type 'n' then 'i'
keyboard.handle_key("n")
keyboard.handle_key("i")
assert(keyboard.get_buffer() == "ni", "Pinyin buffer should be 'ni'")
local cands = keyboard.get_current_candidates()
assert(#cands > 0 and cands[1] == "你", "First candidate should be '你'")

-- Select candidate 1
keyboard.select_candidate(1)
assert(keyboard.get_text() == "你", "Committed text should be '你'")
assert(keyboard.get_buffer() == "", "Pinyin buffer should be cleared")

-- Type 'h', 'a', 'o'
keyboard.handle_key("h")
keyboard.handle_key("a")
keyboard.handle_key("o")
assert(keyboard.get_buffer() == "hao", "Pinyin buffer should be 'hao'")
keyboard.select_candidate(1)
assert(keyboard.get_text() == "你好", "Committed text should be '你好'")

-- Test Backspace on text when buffer is empty
keyboard.handle_backspace()
assert(keyboard.get_text() == "你", "Backspace should remove last UTF-8 character")

-- Test close button
keyboard.close()
assert(keyboard.is_open() == false, "Keyboard should be closed")
assert(closed == true, "on_close callback should be called")

print("Virtual Keyboard tests passed!")
