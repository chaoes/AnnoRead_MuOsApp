local keyboard = require("src.keyboard")

print("--- Testing Expanded Candidates & Dual Paging Buttons ---")
keyboard.open("", function() end, function() end)

-- Type 'z', 'a', 'i'
keyboard.handle_key("z")
keyboard.handle_key("a")
keyboard.handle_key("i")

local paged = keyboard.get_paged_candidates()
assert(#paged >= 7, "Candidate bar should display 7 or more candidates per page to fill the bar, got " .. #paged)

-- Test hitboxes calculation with prev/next buttons
local hitboxes, btn_prev, btn_next = keyboard.get_candidate_hitboxes(720, 720)
assert(btn_prev ~= nil and btn_prev.w > 30, "Prev page button hitbox should exist")
assert(btn_next ~= nil and btn_next.w > 30, "Next page button hitbox should exist")

-- Initially on page 1
assert(keyboard.get_current_page() == 1, "Should be on page 1")

-- Click next page button
keyboard.mousepressed(btn_next.x + 5, btn_next.y + 5, 1)
assert(keyboard.get_current_page() == 2, "Clicking next page button should advance to page 2")

-- Click prev page button
keyboard.mousepressed(btn_prev.x + 5, btn_prev.y + 5, 1)
assert(keyboard.get_current_page() == 1, "Clicking prev page button should return to page 1")

print("Expanded Candidates & Dual Paging Buttons tests passed!")
