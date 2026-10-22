-- tests/test_settings.lua
--
-- Covers the Settings tab: theme switch, cache management (clear cache of books
-- NOT on the shelf), and the in-app 退出应用 (quit) action.
--
-- Key behaviors asserted:
--   1. Quit returns { action = "quit" } only after an explicit confirmation.
--   2. B / 取消 aborts the dialog and never emits the quit action.
--   3. Theme rows persist via storage and update the live theme.
--   4. Cache-clear actions are gated behind a confirmation.

package.path = package.path .. ";./?.lua;./src/?.lua"

local input = require("src.input")
local storage = require("src.storage")
local theme = require("src.theme")
local cache = require("src.cache")
local settings_view = require("src.views.settings")

-- storage talks to love.filesystem; stub it out for the headless run.
local mock_settings = { theme = "dark", font_size = 20, line_spacing = 1.6, para_spacing = 10, margin_horiz = 28, margin_vert = 40 }
storage.get_reader_settings = function()
    return mock_settings
end
storage.save_reader_settings = function(s)
    mock_settings = s
end
storage.get_books = function() return {} end

-- Track cache maintenance calls without touching the filesystem.
local cache_calls = {}
cache.clear_except = function(keep) cache_calls[#cache_calls + 1] = { "except", keep }; return 3 end
cache.clear_all = function() cache_calls[#cache_calls + 1] = { "all" }; return 5 end
cache.count_chapters = function() return 0 end
cache.list_books = function() return {} end

local function frame_action(view, action)
    input.on_gamepadpressed(nil, action)
    local res = view.update(0.016, input)
    input.update()
    input.on_gamepadreleased(nil, action)
    input.update()
    return res
end

print("--- 1. Settings tab starts closed and not confirming ---")
settings_view.init()
assert(settings_view.is_confirm_open() == false, "Confirm dialog should start closed")

print("--- 2. Quit row (row 3) needs an explicit confirmation ---")
frame_action(settings_view, "dpdown") -- theme -> cache
frame_action(settings_view, "dpdown") -- cache -> quit
local open_res = frame_action(settings_view, "a")
assert(open_res == nil, "Pressing A on quit row must NOT quit directly; it opens a dialog")
assert(settings_view.is_confirm_open(), "Quit confirmation dialog should be open")

print("--- 3. Cancelling with B never emits the quit action ---")
local cancel_res = frame_action(settings_view, "b")
assert(cancel_res == nil, "Cancelling must not emit a quit action")
assert(settings_view.is_confirm_open() == false, "Cancel should close the dialog")

print("--- 4. Confirming with A emits { action = 'quit' } ---")
frame_action(settings_view, "a")           -- reopen dialog
frame_action(settings_view, "dpleft")      -- focus 确定 (index 1)
local quit_res = frame_action(settings_view, "a")
assert(quit_res ~= nil and quit_res.action == "quit", "Confirmed quit must return { action = 'quit' }")
assert(settings_view.is_confirm_open() == false, "Confirming should close the dialog")

print("--- 5. Theme selection row cycles the theme and persists ---")
settings_view.init()
theme.set_theme("dark")
frame_action(settings_view, "dpright")
assert(theme.get_theme_name() == "sepia", "Right on theme row should cycle dark -> sepia")
frame_action(settings_view, "dpright")
assert(theme.get_theme_name() == "light", "Right on theme row should cycle sepia -> light")
frame_action(settings_view, "dpright")
assert(theme.get_theme_name() == "jirai", "Right on theme row should cycle light -> jirai (地雷)")
frame_action(settings_view, "dpright")
assert(theme.get_theme_name() == "dark", "Right on theme row should cycle jirai -> dark")
frame_action(settings_view, "dpleft")
assert(theme.get_theme_name() == "jirai", "Left on theme row should cycle dark -> jirai")

print("--- 6. Cache row: ◀ clears off-shelf cache (behind a confirm) ---")
settings_view.init()
frame_action(settings_view, "dpdown")  -- row 2 = cache
assert(settings_view.is_confirm_open() == false, "No dialog before action")
frame_action(settings_view, "dpleft")  -- request off-shelf cleanup
assert(settings_view.is_confirm_open(), "Off-shelf cleanup must ask for confirmation")
frame_action(settings_view, "dpleft")  -- focus 确定
local before = #cache_calls
frame_action(settings_view, "a")
assert(#cache_calls == before + 1 and cache_calls[#cache_calls][1] == "except",
    "Confirming should call cache.clear_except(keep)")
assert(settings_view.is_confirm_open() == false, "Dialog closes after confirm")

print("--- 7. Cache row: ▶ / A prompts to clear ALL cache ---")
settings_view.init()
frame_action(settings_view, "dpdown")  -- cache row
frame_action(settings_view, "dpright")
assert(settings_view.is_confirm_open(), "Clear-all must ask for confirmation")
frame_action(settings_view, "dpleft")
local before2 = #cache_calls
frame_action(settings_view, "a")
assert(#cache_calls == before2 + 1 and cache_calls[#cache_calls][1] == "all",
    "Confirming should call cache.clear_all()")

print("--- 8. Up from the first row hands focus back to the top tabs ---")
settings_view.init()
local tabs_res = frame_action(settings_view, "dpup")
assert(tabs_res ~= nil and tabs_res.action == "focus_tabs", "Up from first row should return focus_tabs")

print("--- 9. Every settings row fits inside the 720x720 playfield, no overlap ---")
local rows = settings_view._row_layout()
assert(#rows == 4, "There should be 4 settings rows")
-- The persistent bottom hint bar starts at 720-36 = 684.
local BOTTOM_BAR_Y = 720 - 36
for i = 1, #rows do
    local r = rows[i]
    assert(r.y + r.h <= BOTTOM_BAR_Y,
        string.format("Row %d overflows into the bottom bar (bottom=%d, limit=%d)", i, r.y + r.h, BOTTOM_BAR_Y))
    if i > 1 then
        local prev = rows[i - 1]
        assert(r.y >= prev.y + prev.h,
            string.format("Row %d overlaps row %d", i, i - 1))
    end
end
-- The 关于 row carries three lines of text; its card must be tall enough that
-- the last line (drawn at cy+68 with ~17px glyphs) stays inside.
local about = rows[4]
assert(68 + 17 <= about.h,
    string.format("关于 row too short for its last text line (h=%d)", about.h))

print("ALL SETTINGS TAB TESTS PASSED!")
