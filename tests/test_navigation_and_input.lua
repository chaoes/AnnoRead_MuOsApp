-- tests/test_navigation_and_input.lua
package.path = package.path .. ";./?.lua;./src/?.lua"

local input = require("src.input")
local storage = require("src.storage")
local theme = require("src.theme")
local http = require("src.http")
http.request_async = function() end -- mock for headless test

local function assert_true(cond, msg)
    if not cond then error(msg or "Expected true") end
end

local function assert_false(cond, msg)
    if cond then error(msg or "Expected false") end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

print("--- 1. Testing Keyboard Backspace / Escape Mapping ---")
input.on_keypressed("backspace")
assert_true(input.is_down("b"), "Backspace should trigger action 'b'")
assert_true(input.pressed("b"), "Action 'b' should be pressed in frame")
input.update()
assert_false(input.pressed("b"), "Action 'b' pressed should be cleared after update")
input.on_keyreleased("backspace")
input.update()

input.on_keypressed("escape")
assert_true(input.is_down("b"), "Escape should trigger action 'b'")
assert_true(input.pressed("b"), "Action 'b' should be pressed in frame")
input.update()
input.on_keyreleased("escape")
input.update()

print("--- 2. Testing Text Input Mode vs Action Keys ---")
input.set_text_input_mode(true)
input.on_keypressed("a")
assert_false(input.is_down("left"), "In text input mode, key 'a' must not trigger 'left'")
input.on_keypressed("z")
assert_false(input.is_down("a"), "In text input mode, key 'z' must not trigger 'a'")

-- Arrow keys still work in text input mode
input.on_keypressed("up")
assert_true(input.pressed("up"), "Arrow up should work in text input mode")
input.update()
input.on_keyreleased("up")
input.update()

input.set_text_input_mode(false)
input.on_keypressed("z")
assert_true(input.is_down("a"), "Outside text input mode, key 'z' triggers action 'a'")
input.on_keyreleased("z")
input.update()

print("--- 3. Testing Bookshelf Navigation to Top Tabs ---")
local bookshelf = require("src.views.bookshelf")
bookshelf.init()

-- Simulating pressing Up on the first book -> focus_tabs
input.on_keypressed("up")
local res = bookshelf.update(0.016, input)
input.update()
input.on_keyreleased("up")
input.update()

assert_true(res ~= nil and res.action == "focus_tabs", "Bookshelf should return focus_tabs when pressing Up from item 1")

print("--- 4. Testing Discover Subzone Navigation ---")
local discover = require("src.views.discover")
discover.init()

-- When at categories, Up should trigger focus_tabs
input.on_keypressed("up")
local res_disc = discover.update(0.016, input)
input.update()
input.on_keyreleased("up")
input.update()
assert_true(res_disc ~= nil and res_disc.action == "focus_tabs", "Discover should return focus_tabs when pressing Up from categories")

print("--- 5. Testing Search View Navigation & Subzones ---")
local search = require("src.views.search")
search.init()

-- From default preset subzone, Up goes to input box
input.on_keypressed("up")
search.update(0.016, input)
input.update()
input.on_keyreleased("up")
input.update()

-- From input box, Up triggers focus_tabs
input.on_keypressed("up")
local res_search = search.update(0.016, input)
input.update()
input.on_keyreleased("up")
input.update()
assert_true(res_search ~= nil and res_search.action == "focus_tabs", "Search should return focus_tabs when pressing Up from search bar")

print("--- 6. Testing Reader Actions via Unified Action Layer ---")
local reader = require("src.views.reader")
local book_mock = { name = "测试书籍", bookUrl = "http://test.com/book" }
reader.open_book(book_mock)

-- Helper: simulate a full frame with one key for a view that uses input actions
local function frame_key(view, key)
    input.on_keypressed(key)
    local res = view.update(0.016, input)
    input.update()
    input.on_keyreleased(key)
    input.update()
    return res
end

-- 'A' (or keyboard 'z') must OPEN the chapter catalog (single-handler)
frame_key(reader, "z") -- action 'a' -> catalog
assert_true(reader.is_catalog_open(), "A should open the catalog exactly once")

-- 'B' (or keyboard 'escape') must CLOSE the catalog
frame_key(reader, "escape")
assert_false(reader.is_catalog_open(), "B should close the catalog exactly once")

-- Tab/Select opens the reader action menu (换源 / 重载 / 缓存全书 / 排版)
frame_key(reader, "tab")
assert_true(reader.is_menu_open(), "Select should open the reader action menu")
frame_key(reader, "escape")
assert_false(reader.is_menu_open(), "B should close the action menu")

-- When reading, Escape/Backspace (action 'b') should save & exit
local ret2 = frame_key(reader, "escape")
assert_true(ret2 ~= nil and ret2.action == "close_reader", "Escape in reading must return close_reader")

-- X (action 'x') opens layout settings (single-handler, no double-toggle)
frame_key(reader, "c") -- keyboard 'c' -> action 'x' (排版)
assert_true(reader.is_settings_open(), "X should open settings exactly once")

-- X again closes settings
frame_key(reader, "c")
assert_false(reader.is_settings_open(), "X should close settings exactly once")

print("--- 7. Testing Gamepad D-pad & Shoulder Mappings ---")
input.on_gamepadpressed(nil, "dpup")
assert_true(input.pressed("up"), "Gamepad dpup should map to 'up'")
input.update()
input.on_gamepadreleased(nil, "dpup")
input.update()

input.on_gamepadpressed(nil, "leftshoulder")
assert_true(input.pressed("l1"), "Gamepad leftshoulder should map to 'l1'")
input.update()
input.on_gamepadreleased(nil, "leftshoulder")
input.update()

input.on_gamepadpressed(nil, "b")
assert_true(input.pressed("b"), "Gamepad b button should map to 'b'")
input.update()
input.on_gamepadreleased(nil, "b")
input.update()

print("--- 8. Testing Dedicated Search Button Navigation ---")
search.init()
-- Move to input
input.on_keypressed("up")
search.update(0.016, input)
input.update()
input.on_keyreleased("up")
input.update()

-- From input, pressing right navigates to dedicated search button
input.on_keypressed("right")
search.update(0.016, input)
input.update()
input.on_keyreleased("right")
input.update()

-- From search button, pressing left navigates back to input
input.on_keypressed("left")
search.update(0.016, input)
input.update()
input.on_keyreleased("left")
input.update()

-- Move to search button and press A to trigger search
input.on_keypressed("right")
search.update(0.016, input)
input.update()
input.on_keyreleased("right")
input.update()

input.on_keypressed("z") -- action "a"
search.update(0.016, input)
input.update()
input.on_keyreleased("z")
input.update()

print("--- 9. Testing Reader Settings Modal ---")
reader.open_book(book_mock)
assert_false(reader.is_settings_open(), "Settings modal initially closed")

-- Open settings via 'x'
reader.open_settings()
assert_true(reader.is_settings_open(), "Settings modal opened")

-- Row 2: font size modification
input.on_keypressed("down")
reader.update(0.016, input)
input.update()
input.on_keyreleased("down")
input.update()

local initial_settings = storage.get_reader_settings()
local initial_font_size = initial_settings.font_size

-- Increase font size with Right
input.on_keypressed("right")
reader.update(0.016, input)
input.update()
input.on_keyreleased("right")
input.update()

local updated_settings = storage.get_reader_settings()
assert_eq(updated_settings.font_size, initial_font_size + 2, "Font size should increase by 2")

-- Close settings with Escape (action 'b')
input.on_keypressed("escape")
local close_res = reader.update(0.016, input)
input.update()
input.on_keyreleased("escape")
input.update()
assert_eq(close_res, nil, "Closing settings should return nil action")
assert_false(reader.is_settings_open(), "Settings modal should be closed")

print("--- 10. Testing Bookshelf Removal Dialog ---")
local test_book = { name = "书架测试书", bookUrl = "http://test.com/shelf_book", author = "测试者" }
storage.add_book(test_book)
assert_true(storage.is_in_bookshelf(test_book), "Book should be in bookshelf")

bookshelf.init()
-- Press C (action 'x') to trigger removal modal
input.on_keypressed("c")
bookshelf.update(0.016, input)
input.update()
input.on_keyreleased("c")
input.update()
assert_true(bookshelf.is_remove_dialog_open(), "Bookshelf removal confirmation should be open")

-- Press A to confirm removal
input.on_keypressed("z") -- action 'a'
bookshelf.update(0.016, input)
input.update()
input.on_keyreleased("z")
input.update()
assert_false(bookshelf.is_remove_dialog_open(), "Removal modal should be closed")
assert_false(storage.is_in_bookshelf(test_book), "Book should be removed from bookshelf")

print("--- 11. Testing Non-Bookshelf Reading Without Auto-Adding ---")
local unadded_book = { name = "未入库书籍", bookUrl = "http://test.com/unadded", author = "路人甲" }
assert_false(storage.is_in_bookshelf(unadded_book), "Book should not initially be in bookshelf")

-- Reading the book directly must not add it to bookshelf
reader.open_book(unadded_book)
assert_false(storage.is_in_bookshelf(unadded_book), "Opening unadded book in reader must NOT auto-add to bookshelf")

-- Exiting reader must not add it to bookshelf
local exit_res = frame_key(reader, "escape")
assert_true(exit_res ~= nil and exit_res.action == "close_reader", "Reader exit should return close_reader")
assert_false(storage.is_in_bookshelf(unadded_book), "Exiting reader must NOT auto-add to bookshelf")

-- Adding to bookshelf from reader via 'y' key (keyboard 'v' or 'y')
reader.open_book(unadded_book)
input.on_keypressed("y") -- action 'y'
reader.update(0.016, input)
input.update()
input.on_keyreleased("y")
input.update()
assert_true(storage.is_in_bookshelf(unadded_book), "Pressing Y in reader should add book to bookshelf")

-- Clean up test book
storage.remove_book_by_url(unadded_book.bookUrl)
assert_false(storage.is_in_bookshelf(unadded_book), "Cleaned up test book")

print("--- 12. Testing Virtual Keyboard in Search View ---")
search.init()
-- Move focus to input
input.on_keypressed("up")
search.update(0.016, input)
input.update()
input.on_keyreleased("up")
input.update()

-- Press A on input box -> activates keyboard
assert_false(search.is_keyboard_open(), "Keyboard should initially be closed")
input.on_keypressed("z") -- action 'a'
search.update(0.016, input)
input.update()
input.on_keyreleased("z")
input.update()
assert_true(search.is_keyboard_open(), "Pressing A on search input should open virtual keyboard")

-- Close keyboard via escape / B
local keyboard_mod = require("src.keyboard")
keyboard_mod.close()
assert_false(search.is_keyboard_open(), "Closing keyboard should update state")

print("ALL NAVIGATION AND INPUT TESTS PASSED!")
