-- tests/test_reader_navigation_fixes.lua
--
-- Tests for:
-- 1. Reading view: When at page 1 of current chapter, pressing left/up jumps to the LAST page of the previous chapter.
-- 2. Catalog drawer: Pressing left/right jumps 10 chapters (page turning), preventing tedious single-line navigation.

package.path = "./?.lua;./?/init.lua;" .. package.path

local files, dirs = {}, {}
love = love or {}
love.filesystem = love.filesystem or {}
function love.filesystem.getInfo(path)
    if files[path] ~= nil then return { type = "file" } end
    if dirs[path] then return { type = "directory" } end
end
function love.filesystem.createDirectory(path) dirs[path] = true; return true end
function love.filesystem.write(path, value)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then dirs[dir] = true end
    files[path] = value
    return true
end
function love.filesystem.read(path) return files[path] end
function love.filesystem.remove(path) files[path], dirs[path] = nil, nil; return true end
function love.filesystem.getDirectoryItems(path)
    local result, prefix = {}, path .. "/"
    local found = {}
    for p in pairs(files) do
        if p:sub(1, #prefix) == prefix then
            local child = p:sub(#prefix + 1):match("^[^/]+")
            if child and not found[child] then found[child] = true; result[#result + 1] = child end
        end
    end
    return result
end
love.timer = love.timer or { getTime = function() return 1 end }

local reader = require("src.views.reader")
local input = require("src.input")
local storage = require("src.storage")
local cache = require("src.cache")
local http = require("src.http")
http.request_async = function(opts, cb)
    if cb then cb("") end
end

local function assert_true(cond, msg)
    if not cond then error(msg or "Expected true") end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

local function frame_action(view, action)
    input.on_gamepadpressed(nil, action)
    local res = view.update(0.016, input)
    input.update()
    input.on_gamepadreleased(nil, action)
    input.update()
    return res
end

print("=== Running Reader Navigation & Catalog Paging Unit Tests ===")

local mock_source = {
    bookSourceUrl = "https://mock.nav.test",
    bookSourceName = "导航测试源",
    ruleToc = {
        chapterList = ".chapter-list a",
        chapterName = "text",
        chapterUrl = "href"
    },
    ruleContent = {
        content = "#content@text"
    }
}
storage.init()
table.insert(storage.get_sources(), mock_source)

local mock_book = {
    bookUrl = "https://mock.nav.test/book/1",
    tocUrl = "https://mock.nav.test/toc",
    name = "翻页测试书",
    origin = mock_source.bookSourceUrl,
    originName = mock_source.bookSourceName
}

local mock_chapters = {}
for i = 1, 30 do
    table.insert(mock_chapters, {
        title = string.format("第%d章 测试章节", i),
        url = string.format("https://mock.nav.test/c%d.html", i)
    })
    local content_lines = {}
    for l = 1, 40 do
        table.insert(content_lines, string.format("这是第%d章的第%d段文字内容，用来填充页面排版测试。", i, l))
    end
    cache.save_chapter_url(mock_book.bookUrl, mock_chapters[i].url, table.concat(content_lines, "\n\n"))
end

-- Save TOC into cache so offline open loads all 30 chapters immediately
cache.save_toc(mock_book.bookUrl, mock_book.origin, mock_chapters, mock_book.tocUrl)

reader.open_book(mock_book)
assert_true(#reader.get_chapters() == 30, "Reader should have 30 chapters loaded")

print("--- 1. Testing backward jump from first page to previous chapter's LAST page ---")
-- Load Chapter 2 at page 1
reader.load_chapter(2)
assert_eq(reader.get_chapter_index(), 2, "Current chapter should be 2")
assert_eq(reader.get_current_page(), 1, "Current page should be 1")

-- Also inspect total pages of Chapter 1
reader.load_chapter(1)
local chap1_total_pages = reader.get_total_pages()
assert_true(chap1_total_pages > 1, "Chapter 1 should have multiple pages (> 1), got " .. tostring(chap1_total_pages))

-- Go back to Chapter 2, Page 1
reader.load_chapter(2)
assert_eq(reader.get_chapter_index(), 2, "Current chapter should be 2")
assert_eq(reader.get_current_page(), 1, "Current page should be 1")

-- Press Left (dpleft) to turn back
frame_action(reader, "dpleft")
assert_eq(reader.get_chapter_index(), 1, "Should have jumped to Chapter 1")
assert_eq(reader.get_current_page(), chap1_total_pages, "Should have jumped to Chapter 1's LAST page")

-- Test with Up (dpup) as well from Chapter 3
reader.load_chapter(3)
assert_eq(reader.get_chapter_index(), 3, "Current chapter should be 3")
assert_eq(reader.get_current_page(), 1, "Current page should be 1")

frame_action(reader, "dpup")
assert_eq(reader.get_chapter_index(), 2, "Should have jumped to Chapter 2")
local chap2_total_pages = reader.get_total_pages()
assert_true(chap2_total_pages > 1, "Chapter 2 should have multiple pages")
assert_eq(reader.get_current_page(), chap2_total_pages, "Should have jumped to Chapter 2's LAST page")

print("✔ Backward chapter jump landed on last page as expected!")

print("--- 2. Testing Catalog Drawer Navigation with Left / Right keys ---")
-- Open catalog
reader.open_catalog()
assert_true(reader.is_catalog_open(), "Catalog drawer should be open")

-- Currently selected index starts at current chapter (Chapter 2)
assert_eq(reader.get_catalog_selected_idx(), 2, "Catalog selected index should start at chapter 2")

-- Press Right (dpright) -> jumps +10 chapters (to 12)
frame_action(reader, "dpright")
assert_eq(reader.get_catalog_selected_idx(), 12, "Catalog should jump +10 on Right press")

-- Press Right again -> jumps to 22
frame_action(reader, "dpright")
assert_eq(reader.get_catalog_selected_idx(), 22, "Catalog should jump +10 on Right press")

-- Press Right again -> jumps to 30 (clamped to #chapters)
frame_action(reader, "dpright")
assert_eq(reader.get_catalog_selected_idx(), 30, "Catalog should clamp to max chapters")

-- Press Left (dpleft) -> jumps -10 (to 20)
frame_action(reader, "dpleft")
assert_eq(reader.get_catalog_selected_idx(), 20, "Catalog should jump -10 on Left press")

-- Press Left twice -> jumps to 10, then 1 (clamped to 1)
frame_action(reader, "dpleft")
assert_eq(reader.get_catalog_selected_idx(), 10, "Catalog should jump -10 on Left press")
frame_action(reader, "dpleft")
assert_eq(reader.get_catalog_selected_idx(), 1, "Catalog should clamp to 1 on Left press")

print("✔ Catalog Left/Right 10-chapter paging works perfectly!")

print("🎉 ALL READER NAVIGATION FIXES TESTS PASSED SUCCESSFULLY! 🎉")
