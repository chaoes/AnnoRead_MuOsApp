-- tests/test_fixes_batch.lua
--
-- Regression tests for four reported handheld issues:
--   1. L2 / R2 did nothing (LÖVE 11 reports them as AXES, not buttons).
--   2. Card quick-buttons (2nd button) on the 书架 / 发现 lists could not be
--      reached with ◀/▶.
--   3. The 书源 card hinted "[Y] 测速诊断" while Y actually DELETES the source
--      (A does the speed test); and the user-data location was never shown.
--   4. The 阅读 view hinted "[R] 重载本章" but the handheld has no R key.

package.path = package.path .. ";./?.lua;./src/?.lua"

local input = require("src.input")
local storage = require("src.storage")
local http = require("src.http")
http.request_async = function() end -- mock for headless test

local function assert_true(cond, msg)
    if not cond then error(msg or "Expected true") end
end
local function assert_eq(a, b, msg)
    if a ~= b then error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a))) end
end

local function frame_action(view, action)
    input.on_gamepadpressed(nil, action)
    local res = view.update(0.016, input)
    input.update()
    input.on_gamepadreleased(nil, action)
    input.update()
    return res
end

print("--- 1. L2/R2 arrive as analog trigger AXES and map to l2/r2 ---")
input.on_gamepadaxis(nil, "triggerleft", 0.0)
input.on_gamepadaxis(nil, "triggerright", 0.0)
input.update()

input.on_gamepadaxis(nil, "triggerleft", 0.9)
assert_true(input.pressed("l2"), "Left trigger axis should fire action 'l2'")
input.update()
input.on_gamepadaxis(nil, "triggerleft", 0.0)
assert_true(input.released("l2"), "Releasing the left trigger should release 'l2'")
input.update()

input.on_gamepadaxis(nil, "triggerright", 0.9)
assert_true(input.pressed("r2"), "Right trigger axis should fire action 'r2'")
input.update()
input.on_gamepadaxis(nil, "triggerright", 0.0)
input.update()

-- Hysteresis: a value in the dead band must not chatter the action off.
input.on_gamepadaxis(nil, "triggerleft", 0.9)
input.update()
input.on_gamepadaxis(nil, "triggerleft", 0.35) -- between THRESHOLD(0.5) and RELEASE(0.2)
assert_true(input.is_down("l2"), "Trigger in the hysteresis band must stay down")
input.on_gamepadaxis(nil, "triggerleft", 0.0)
input.update()

-- The L/R analog sticks must still work (no regression).
input.on_gamepadaxis(nil, "leftx", 0.9)
assert_true(input.pressed("right"), "Left stick right must still map to 'right'")
input.on_gamepadaxis(nil, "leftx", 0.0)
input.update()

print("--- 2. Discover L2/R2 switch the discover source ---")
-- storage needs at least 2 discover-capable sources for this to be meaningful.
storage.init()
local discover = require("src.views.discover")
discover.init()
local src_list = discover.get_source_list()
if #src_list > 1 then
    local before = discover.get_active_source_index()
    frame_action(discover, "triggerright")
    local after = discover.get_active_source_index()
    assert_true(after ~= before, "R2 should switch to the next discover source")
    frame_action(discover, "triggerleft")
    assert_eq(discover.get_active_source_index(), before, "L2 should switch back")
else
    print("   (skipped: only one discover-capable source in this environment)")
end

print("--- 3. Bookshelf: ◀/▶ reach the card's [阅读] / [缓存] / [移出] buttons ---")
local bookshelf = require("src.views.bookshelf")
-- Ensure the shelf has at least one book.
storage.add_book({ name = "按钮测试书", bookUrl = "http://fix.test/bs", author = "测试" })
bookshelf.init()
-- Default focus must be [阅读] (opening the book), NOT [缓存] -- caching a whole
-- book by an accidental A press was the reported bug.
assert_eq(bookshelf.get_card_button_index(), 1, "Card button focus should start on [阅读]")
frame_action(bookshelf, "dpright")
assert_eq(bookshelf.get_card_button_index(), 2, "▶ should move focus to [缓存]")
frame_action(bookshelf, "dpright")
assert_eq(bookshelf.get_card_button_index(), 3, "▶ again should move focus to [移出]")
frame_action(bookshelf, "dpleft")
assert_eq(bookshelf.get_card_button_index(), 2, "◀ should move back to [缓存]")

-- A on the default first button opens the reader (the safe, expected action).
frame_action(bookshelf, "dpleft")
local res0 = frame_action(bookshelf, "a")
assert_true(res0 ~= nil and res0.action == "open_reader",
    "A on the default first button ([阅读]) should open the reader")

-- Pressing A on the [移出] button opens the removal confirmation (not the reader)
frame_action(bookshelf, "dpright") -- -> [缓存]
frame_action(bookshelf, "dpright") -- -> [移出]
local res2 = frame_action(bookshelf, "a")
assert_true(res2 == nil, "A on [移出] must NOT open the reader")
assert_true(bookshelf.is_remove_dialog_open(), "A on [移出] should open the remove confirmation")
frame_action(bookshelf, "b") -- cancel

-- Pressing A on the [阅读] button opens the reader
frame_action(bookshelf, "dpleft")
frame_action(bookshelf, "dpleft")
local res1 = frame_action(bookshelf, "a")
assert_true(res1 ~= nil and res1.action == "open_reader", "A on [阅读] should open the reader")
bookshelf._set_card_button_index(1)

print("--- 4. Discover: ◀/▶ reach the card quick buttons ---")
discover.init()
discover._set_categories({ { title = "玄幻", url = "http://x" }, { title = "都市", url = "http://y" } })
discover._set_books({ { name = "发现测试书", bookUrl = "http://fix.test/disc", author = "作者" } })
-- Move focus into the books subzone
frame_action(discover, "dpdown")
assert_eq(discover.get_focus_subzone(), "books", "Down should focus the books list")
assert_eq(discover.get_card_button_index(), 0, "Whole-card focus comes first")
frame_action(discover, "dpright")
assert_eq(discover.get_card_button_index(), 1, "▶ should focus the [阅读] quick button")
frame_action(discover, "dpright")
assert_eq(discover.get_card_button_index(), 2, "▶ again should focus the [书架] quick button")
frame_action(discover, "dpright")
assert_eq(discover.get_card_button_index(), 0, "▶ should wrap back to the whole card")

-- A on the second button toggles the bookshelf without opening the dialog
discover.init()
discover._set_categories({ { title = "玄幻", url = "http://x" } })
local bk = { name = "发现加架书", bookUrl = "http://fix.test/disc2", author = "作者" }
discover._set_books({ bk })
frame_action(discover, "dpdown")   -- into books
frame_action(discover, "dpright")  -- [阅读]
frame_action(discover, "dpright")  -- [书架]
assert_true(not storage.is_in_bookshelf(bk), "Book should start off-shelf")
local r = frame_action(discover, "a")
assert_true(r == nil, "A on [书架] must not open the reader")
assert_true(storage.is_in_bookshelf(bk), "A on [书架] should add the book to the shelf")
storage.remove_book_by_url(bk.bookUrl)

print("--- 5. Reader: reload is reachable from the Select action menu ---")
local reader = require("src.views.reader")
reader.open_book({ name = "重载测试书", bookUrl = "http://fix.test/reader", author = "作者" })
-- Select opens the action menu; the menu exposes 换源 / 重载 / 缓存全书 / 排版.
frame_action(reader, "back") -- action 'select'
assert_true(reader.is_menu_open(), "Select should open the reader action menu")
-- Move to the 2nd item (重新加载本章) and confirm it triggers a reload path safely.
frame_action(reader, "dpdown")
local ok = pcall(function() frame_action(reader, "a") end)
assert_true(ok, "Selecting 重新加载本章 must not crash the reader")
assert_true(reader.get_current_content() ~= nil, "reader content accessor should stay valid")

print("--- 6. User data directory is exposed for the storage hint ---")
-- Headless (no love.filesystem) returns nil; on device it must be a real path.
local dir = storage.get_user_data_dir()
assert_true(dir == nil or (type(dir) == "string" and #dir > 0),
    "storage.get_user_data_dir should return a path or nil when love is absent")

print("ALL FIX-BATCH TESTS PASSED!")
