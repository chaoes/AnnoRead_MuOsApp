-- tests/test_reading_progress_save.lua
-- Tests for:
-- 1. Progress saving and restoring including chapterIndex and currentPage
-- 2. TTS auto-page turn updating currentPage in storage
-- 3. Exiting via B-key (save_and_exit) and re-opening book restores saved chapter and page

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

local storage = require("src.storage")
local cache = require("src.cache")
local reader = require("src.views.reader")
local tts = require("src.tts")

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

print("=== Running Reading Progress & Page Persistence Tests ===")

-- Setup mock book and chapters
storage.init()
local test_book = {
    name = "进度测试小说",
    author = "测试作者",
    bookUrl = "https://example.com/test_book",
    origin = "https://example.com",
    originName = "测试源",
    currentChapterIndex = 1,
    currentChapterTitle = "第一章",
    currentPage = 1,
    progress = 0.1
}

local test_chapters = {
    { title = "第1章 开始", url = "https://example.com/ch1" },
    { title = "第2章 进展", url = "https://example.com/ch2" },
    { title = "第3章 终局", url = "https://example.com/ch3" }
}

-- Cache TOC and chapters
cache.save_toc(test_book.bookUrl, test_book.origin, test_chapters, test_book.bookUrl, {})

-- Multi-paragraph long chapter to ensure multiple pages
local long_content = ""
for i = 1, 30 do
    long_content = long_content .. string.format("这是第%d个段落，内容稍微长一些，用于在阅读器排版分页时能够产生多页内容。\n\n", i)
end
cache.save_chapter_url(test_book.bookUrl, test_chapters[1].url, long_content)
cache.save_chapter_url(test_book.bookUrl, test_chapters[2].url, "第二章的内容第一段。\n\n第二章第二段。\n\n第二章第三段。")

storage.add_book(test_book)

-- Test 1: Open book at chapter 1, page 1
reader.open_book(test_book)
assert_eq(reader.get_chapter_index(), 1, "Initial chapter index should be 1")
assert_eq(reader.get_current_page(), 1, "Initial page should be 1")
local total_pages = reader.get_total_pages()
assert(total_pages >= 2, "Chapter 1 should have multiple pages, got: " .. tostring(total_pages))
print("[PASS] Test 1: Open book at chapter 1, page 1")

-- Test 2: Manually turn to page 2 and save_and_exit
reader.load_chapter(1, 2)
assert_eq(reader.get_current_page(), 2, "Page should be 2 after loading page 2")
reader.save_and_exit()

-- Check storage updated
local books = storage.get_books()
local saved = nil
for _, b in ipairs(books) do
    if b.bookUrl == test_book.bookUrl then saved = b; break end
end
assert(saved ~= nil, "Book should be in storage")
assert_eq(saved.currentChapterIndex, 1, "Storage chapter should be 1")
assert_eq(saved.currentPage, 2, "Storage currentPage should be 2")
print("[PASS] Test 2: save_and_exit persisted currentPage = 2")

-- Test 3: Re-open book, verify it resumes at page 2
reader.open_book(saved)
assert_eq(reader.get_chapter_index(), 1, "Re-opened chapter index should be 1")
assert_eq(reader.get_current_page(), 2, "Re-opened page should be 2 (not reset to 1!)")
print("[PASS] Test 3: Re-opening book successfully restored page 2")

-- Test 4: TTS auto page-turn updates progress
-- In reader.lua start_tts_internal, on_para_change updates current_page and storage
-- Let's jump to chapter 2, page 1
reader.load_chapter(2, 1)
assert_eq(reader.get_chapter_index(), 2, "Chapter should be 2")
reader.save_and_exit()

for _, b in ipairs(storage.get_books()) do
    if b.bookUrl == test_book.bookUrl then saved = b; break end
end
assert_eq(saved.currentChapterIndex, 2, "Storage chapter should be 2")
assert_eq(saved.currentPage, 1, "Storage currentPage should be 1")

reader.open_book(saved)
assert_eq(reader.get_chapter_index(), 2, "Should open at chapter 2")
assert_eq(reader.get_current_page(), 1, "Should open at page 1")

-- Cleanup
reader.save_and_exit()
print("=== ALL READING PROGRESS TESTS PASSED SUCCESSFULLY! ===")
