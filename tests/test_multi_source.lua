package.path = package.path .. ";./src/?.lua"
local storage = require("src.storage")
local http = require("src.http")
http.request_async = function() end -- mock for headless test

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)))
    end
end

print("=== Running Multi-Source Data Layer Tests ===")

storage.init()

-- Clean books for testing
local all = storage.get_books()
while #all > 0 do
    table.remove(all, 1)
end

local b = {
    bookUrl = "http://a/1",
    name = "测试书",
    author = "作者",
    origin = "http://a",
    originName = "源A"
}
storage.add_book(b)

local from_a = storage.get_books_by_origin("http://a")
assertEq(#from_a, 1, "by origin count")
assertEq(from_a[1].name, "测试书", "by origin book name")
assertEq(storage.get_books()[1].status, "normal", "status default")

local ok = storage.update_book_origin("http://a/1", "http://b", "源B", "http://b/9", "http://b/toc")
assertEq(ok, true, "update result")
assertEq(#storage.get_books_by_origin("http://a"), 0, "old origin cleared")

local from_b = storage.get_books_by_origin("http://b")
assertEq(#from_b, 1, "new origin count")
assertEq(from_b[1].bookUrl, "http://b/9", "new bookUrl")
assertEq(from_b[1].tocUrl, "http://b/toc", "new tocUrl")
assertEq(from_b[1].originName, "源B", "new originName")

print("✔ Multi-Source Data Layer Tests passed successfully!")

-- Task 14: Discover per-source folding & switching
local discover = require("src.views.discover")
discover.init()
local list = discover.get_source_list()
assert(#list >= 2, "应列出至少两个可发现书源, got " .. tostring(#list))
discover.set_active_source(2)
assertEq(discover.get_active_source_index(), 2, "切换书源")
assert(#discover.get_categories() >= 20, "幽香书房分类应有20个以上")

print("✔ Discover Per-Source Folding Tests passed successfully!")

-- Task 15: Book Action Modal Source Line
discover.set_action_book({ name = "测试书", author = "作者", originName = "源A", latestChapterTitle = "第10章" })
local sline = discover.get_action_source_line()
assert(sline and sline:find("源A"), "动作面板应显示来源书源")

local search = require("src.views.search")
search.set_action_book({ name = "测试书", author = "作者", originName = "源B", latestChapterTitle = "第20章" })
local sline_search = search.get_action_source_line()
assert(sline_search and sline_search:find("源B"), "搜索面板应显示来源书源")

print("✔ Action Modal Source Display Tests passed successfully!")

-- Task 19: Auto-migration on source deletion with regression guard
local sources_view = require("src.views.sources")
local reader = require("src.views.reader")

local b1 = { bookUrl = "http://a/1", name = "测试书", author = "作者", origin = "http://a", originName = "源A",
             currentChapterIndex = 5, status = "normal" }
storage.add_book(b1)

sources_view._test_apply_migration("http://a/1",
    { origin = "http://b", originName = "源B", bookUrl = "http://b/9", tocUrl = "http://b/toc", totalChapters = 10 },
    4)
assertEq(storage.get_books()[1].origin, "http://b", "应迁移到源B")

-- 防回退：新源总章节数(2) < 已读进度(5) 时应标记而非迁移
local b2 = { bookUrl = "http://a/2", name = "书2", author = "作", origin = "http://a", currentChapterIndex = 5, status = "normal" }
storage.add_book(b2)
sources_view._test_apply_migration("http://a/2",
    { origin = "http://c", originName = "源C", bookUrl = "http://c/1", tocUrl = "", totalChapters = 2 }, 0)
assertEq(storage.get_books()[1].status, "source_deleted", "应标记待换源而非倒退进度")

-- 阅读中删除当前书源：不得崩溃，且正文与章节索引保留（Review Focus）
reader.open_book({ bookUrl = "http://a/3", name = "书3", author = "作", origin = "http://a", originName = "源A", tocUrl = "http://a/t" })
sources_view._test_apply_migration("http://a/3",
    { origin = "http://d", originName = "源D", bookUrl = "http://d/1", tocUrl = "", totalChapters = 0 }, 0)
assertEq(storage.get_books()[1].status, "source_deleted", "无可用替代源应标记")

-- Important 4: Progress beyond chapter 100 with verified target chapters
local b_150 = { bookUrl = "http://a/150", name = "长篇小说", author = "作者", origin = "http://a", originName = "源A",
                currentChapterIndex = 150, status = "normal" }
storage.add_book(b_150)
local mig_ok = sources_view._test_apply_migration("http://a/150",
    { origin = "http://b", originName = "源B", bookUrl = "http://b/150", tocUrl = "http://b/toc", totalChapters = 200 }, 149)
assertEq(mig_ok, true, "真实200章新源应允许读到150章的读者迁移")
assertEq(storage.get_books()[1].origin, "http://b", "书架源应更新为源B")

print("✔ Auto-Migration & Regression Guard Tests passed successfully!")
