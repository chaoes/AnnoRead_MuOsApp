local keyboard = require("src.keyboard")

local function press(action)
    keyboard.update(0.016, { pressed = function(key) return key == action end })
end

local function expect_cursor(row, col, candidate, label)
    local actual_row, actual_col, actual_candidate = keyboard.get_cursor()
    assert(actual_row == row and actual_col == col and
        (candidate == nil or actual_candidate == candidate),
        string.format("%s: expected (%d, %d, %s), got (%d, %d, %d)",
            label, row, col, tostring(candidate), actual_row, actual_col, actual_candidate))
end

keyboard.open("", function() end, function() end)

-- Horizontal wrapping uses the length of the current row, including action keys.
press("left")
expect_cursor(2, 10, nil, "left edge of letter row")
press("right")
expect_cursor(2, 1, nil, "right edge of letter row")
keyboard._set_cursor(5, 1)
press("left")
expect_cursor(5, 3, nil, "left edge of action row")
press("right")
expect_cursor(5, 1, nil, "right edge of action row")

-- Without candidates, the first and last key rows connect vertically.
keyboard._set_cursor(1, 11)
press("up")
expect_cursor(5, 3, nil, "top wraps to bottom and clamps column")
press("down")
expect_cursor(1, 3, nil, "bottom wraps to top")
keyboard._set_cursor(1, 11)
press("down")
expect_cursor(2, 10, nil, "ordinary row move still clamps column")

-- The same horizontal behavior applies to the symbol layout.
keyboard.toggle_symbol_mode()
keyboard._set_cursor(3, 1)
press("left")
expect_cursor(3, #keyboard.get_active_row_keys(3), nil, "symbol row wraps left")
press("right")
expect_cursor(3, 1, nil, "symbol row wraps right")
keyboard.toggle_symbol_mode()

-- Candidate focus keeps its shortcut and loops through every candidate page.
keyboard._set_cursor(2, 5)
keyboard.handle_key("n")
keyboard.handle_key("i")
local count = #keyboard.get_current_candidates()
assert(count > 7, "ni should offer multiple candidate pages")
press("up")
expect_cursor(0, 5, 1, "up enters candidate bar")
press("left")
assert(keyboard.get_current_page() == keyboard.get_total_pages(), "left from first candidate wraps to last page")
expect_cursor(0, 5, ((count - 1) % 7) + 1, "left wraps to last candidate")
press("right")
assert(keyboard.get_current_page() == 1, "right from last candidate wraps to first page")
expect_cursor(0, 5, 1, "right wraps to first candidate")
press("up")
expect_cursor(5, 3, nil, "candidate bar wraps up to bottom row")
press("down")
expect_cursor(0, 3, 1, "bottom row wraps down to candidate bar")
press("down")
expect_cursor(1, 1, nil, "candidate bar moves down to top key row")

keyboard.close()
print("Keyboard edge wrapping tests passed!")
