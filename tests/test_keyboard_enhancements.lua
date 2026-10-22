local keyboard = require("src.keyboard")

print("--- Testing Virtual Keyboard Enhancements ---")
local committed = nil
local live_text = nil
local closed = false

keyboard.open("旧文字", function(text) committed = text end, function() closed = true end, function(text) live_text = text end)
assert(keyboard.is_open() == true, "Keyboard should be open")
assert(keyboard.get_text() == "旧文字", "Initial text should be loaded")

-- 1. Test live text sync on backspace
keyboard.handle_backspace()
assert(keyboard.get_text() == "旧文", "Backspace should pop UTF-8 character from text")
assert(live_text == "旧文", "on_change callback should report live text change")

-- 2. Test clear button clearing text
keyboard.handle_clear()
assert(keyboard.get_text() == "", "Clear should empty text when buffer is empty")
assert(live_text == "", "on_change callback should report empty text")

-- 3. Test mode toggle and symbol sets
assert(keyboard.get_input_mode() == "zh", "Default mode should be zh")
keyboard.toggle_symbol_mode()
assert(keyboard.is_symbol_mode() == true, "Symbol mode should be active")
local syms_zh = keyboard.get_active_row_keys(2)
assert(syms_zh[1] == "，", "Chinese symbols should have full-width comma '，'")
assert(syms_zh[2] == "。", "Chinese symbols should have full-width period '。'")

keyboard.toggle_input_mode()
assert(keyboard.get_input_mode() == "en", "Mode should toggle to en")
local syms_en = keyboard.get_active_row_keys(2)
assert(syms_en[1] == ",", "English symbols should have half-width comma ','")
assert(syms_en[2] == ".", "English symbols should have half-width period '.'")

-- 4. Test typing English symbol
keyboard.handle_key(",")
assert(keyboard.get_text() == ",", "Symbol should be appended to text")
assert(live_text == ",", "on_change callback should receive symbol")

keyboard.toggle_symbol_mode()
assert(keyboard.is_symbol_mode() == false, "Should return to letter mode")

keyboard.close()
assert(keyboard.is_open() == false, "Keyboard should be closed")
print("Virtual Keyboard Enhancements tests passed!")
