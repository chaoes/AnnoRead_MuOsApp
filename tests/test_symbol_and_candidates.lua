local keyboard = require("src.keyboard")

print("--- Testing Symbol Mode & Candidate Layout ---")

-- 1. Test symbol mode toggle
keyboard.open("", function() end, function() end)
assert(keyboard.is_symbol_mode() == false, "Initially not in symbol mode")

-- Switch to symbol mode
keyboard.toggle_symbol_mode()
assert(keyboard.is_symbol_mode() == true, "Should be in symbol mode")

-- In symbol mode, row keys should be full symbol set
local keys_r1 = keyboard.get_active_row_keys(1)
assert(#keys_r1 > 0, "Row 1 should have symbol keys")

-- Test Chinese full-width symbols vs English half-width symbols in symbol mode
assert(keyboard.get_input_mode() == "zh", "Current input mode should be zh")
local zh_sym_r2 = keyboard.get_active_row_keys(2)
assert(zh_sym_r2[1] == "，", "Chinese symbol row 2 first key should be '，'")

keyboard.toggle_input_mode()
assert(keyboard.get_input_mode() == "en", "Current input mode should be en")
local en_sym_r2 = keyboard.get_active_row_keys(2)
assert(en_sym_r2[1] == ",", "English symbol row 2 first key should be ','")

-- 2. Test candidate box hitboxes and no extra tag offset
keyboard.toggle_symbol_mode() -- back to letter mode
keyboard.toggle_input_mode() -- back to zh
keyboard.handle_key("n")
keyboard.handle_key("i")

local cands = keyboard.get_paged_candidates()
assert(#cands > 0, "Should have candidates for 'ni'")
local hitboxes = keyboard.get_candidate_hitboxes(720, 720)
assert(#hitboxes == #cands, "Hitbox count should match candidate count")
-- Click first candidate hitbox directly
local hb1 = hitboxes[1]
keyboard.mousepressed(hb1.x + 5, hb1.y + 5, 1)
assert(keyboard.get_text() == cands[1], "Clicking first candidate box should precisely select first candidate")
assert(keyboard.get_buffer() == "", "Buffer should be cleared after selecting candidate")

print("Symbol Mode & Candidate Layout tests passed!")
