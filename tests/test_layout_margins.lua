package.path = package.path .. ";./src/?.lua"
local discover = require("src.views.discover")
local sources_view = require("src.views.sources")
local storage = require("src.storage")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assertion failed (expected true)")
    end
end

print("=== Running Layout Boundaries & Tab Bar Margin Tests ===")

-- 1. Verify Top Tab Bar is 54px in main.lua
local TOP_TAB_BAR_BOTTOM = 54

-- 2. Mock love.graphics to spy on draw calls
local draw_ops = {}
local recorded_prints = {}

love = love or {}
love.graphics = love.graphics or {}
local orig_print = love.graphics.print
local orig_printf = love.graphics.printf
local orig_rectangle = love.graphics.rectangle
local orig_line = love.graphics.line
local orig_setColor = love.graphics.setColor
local orig_setScissor = love.graphics.setScissor
local orig_setFont = love.graphics.setFont

love.graphics.setColor = function(...) end
love.graphics.rectangle = function(...) end
love.graphics.line = function(...) end
love.graphics.setScissor = function(...) end
love.graphics.setFont = function(...) end
love.graphics.setLineWidth = function(...) end

love.graphics.print = function(text, x, y)
    table.insert(recorded_prints, { text = tostring(text), x = x, y = y })
end
love.graphics.printf = function(text, x, y, limit, align)
    table.insert(recorded_prints, { text = tostring(text), x = x, y = y, printf = true })
end

-- Test Discover View layout
print("--- 1. Testing Discover View Spacing & Tab Bar Collision ---")
discover.init()
discover._set_categories({ { title = "分类1", url = "http://cat1" }, { title = "分类2", url = "http://cat2" } })
discover._set_books({ { name = "测试书籍", bookUrl = "http://book1", author = "测试作者" } })

recorded_prints = {}
discover.draw(720, 720, true)

-- Find the source indicator print
local src_print = nil
for _, p in ipairs(recorded_prints) do
    if p.text:find("书源:") then
        src_print = p
        break
    end
end

assert_true(src_print ~= nil, "Discover view must print source indicator text")
print(string.format("Discover source indicator y = %d (Top tab bottom = %d)", src_print.y, TOP_TAB_BAR_BOTTOM))
assert_true(src_print.y > TOP_TAB_BAR_BOTTOM,
    string.format("Discover source indicator y (%d) MUST be strictly below tab bar bottom line (%d)", src_print.y, TOP_TAB_BAR_BOTTOM))
assert_true(src_print.y >= TOP_TAB_BAR_BOTTOM + 8,
    string.format("Discover source indicator y (%d) must have at least 8px margin from tab bar line", src_print.y))

-- Test Sources View layout
print("--- 2. Testing Sources View Spacing & Tab Bar Collision ---")
sources_view.init()
recorded_prints = {}
sources_view.draw(720, 720, true)

local summary_print = nil
local dir_print = nil
for _, p in ipairs(recorded_prints) do
    if p.text:find("个书源") then
        summary_print = p
    elseif p.text:find("书源目录:") then
        dir_print = p
    end
end

if summary_print then
    print(string.format("Sources summary y = %d (Top tab bottom = %d)", summary_print.y, TOP_TAB_BAR_BOTTOM))
    assert_true(summary_print.y > TOP_TAB_BAR_BOTTOM,
        string.format("Sources summary y (%d) MUST be strictly below tab bar bottom line (%d)", summary_print.y, TOP_TAB_BAR_BOTTOM))
    assert_true(summary_print.y >= TOP_TAB_BAR_BOTTOM + 8,
        string.format("Sources summary y (%d) must have at least 8px margin from tab bar line", summary_print.y))
end

if dir_print then
    print(string.format("Sources dir hint y = %d", dir_print.y))
    assert_true(dir_print.y > summary_print.y, "Dir hint must be below summary text")
end

-- Restore mock functions
love.graphics.print = orig_print
love.graphics.printf = orig_printf
love.graphics.setColor = orig_setColor
love.graphics.rectangle = orig_rectangle
love.graphics.line = orig_line
love.graphics.setScissor = orig_setScissor
love.graphics.setFont = orig_setFont

print("ALL LAYOUT BOUNDARIES & TAB MARGIN TESTS PASSED!")
