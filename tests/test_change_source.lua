package.path = package.path .. ";./src/?.lua"
local change_source = require("src.views.change_source")
local storage = require("src.storage")
local http = require("src.http")
local json = require("src.json")
http.request_async = function() end -- mock for headless test
storage.init()
local test_sources = storage.get_sources()
test_sources[#test_sources + 1] = {
    bookSourceName = "源A",
    bookSourceUrl = "https://source-a.example.invalid",
    searchUrl = "https://source-a.example.invalid/search?q={{key}}",
    enabled = true,
}
test_sources[#test_sources + 1] = {
    bookSourceName = "源B",
    bookSourceUrl = "https://source-b.example.invalid",
    searchUrl = "https://source-b.example.invalid/search?q={{key}}",
    enabled = true,
}

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)))
    end
end

print("=== Running Change Source Unit Tests ===")

change_source.open({ name = "测试书", bookUrl = "http://a/1", origin = "http://a", originName = "源A" }, "第5章 承", 4, function() end)
assert(change_source.is_open(), "面板应打开")
assertEq(#change_source.get_candidates(), 0, "初始无候选")

local prev = change_source.get_previous()
assert(prev ~= nil, "应记录上一书源")
assertEq(prev.originName, "源A", "上一书源名称")
assertEq(prev.chapterIndex, 4, "上一书源章节序号")

-- 注入两个假候选
change_source._inject_candidate({ originName = "源C", latencyMs = 900, latestChapterTitle = "第8章" })
change_source._inject_candidate({ originName = "源B", latencyMs = 300, latestChapterTitle = "第10章" })

local cands = change_source.get_candidates()
assertEq(#cands, 2, "候选数量应为2")
assertEq(cands[1].originName, "源B", "应按延迟升序排在第一位")
assertEq(cands[2].originName, "源C", "应排在第二位")

change_source.close()
assert(not change_source.is_open(), "面板应已关闭")

-- Test session isolation and cancellation
local async_callbacks = {}
http.request_async = function(req, cb)
    table.insert(async_callbacks, cb)
end
change_source.open({ name = "测试书", bookUrl = "http://a/1", origin = "http://a", originName = "源A" }, "第5章 承", 4, function() end)
assert(change_source.is_open(), "面板应重新打开")
assert(#async_callbacks > 0, "应触发并发队列搜索请求")
local old_cb_count = #async_callbacks
-- 关闭面板（模拟用户按B退出）
change_source.close()
assert(not change_source.is_open(), "面板应已关闭")
-- 此时异步网络请求延迟返回，不应向已关闭的面板注入候选
for _, cb in ipairs(async_callbacks) do
    cb(json.encode({ { name = "测试书", bookUrl = "http://b/1", latestChapterTitle = "第9章" } }))
end
assertEq(#change_source.get_candidates(), 0, "会话关闭后返回的异步结果不应注入到已关闭或后续会话中")

-- Task 18: Cache chapter deletion & reload
local cache = require("src.cache")
local reader = require("src.views.reader")
cache.init()
cache.save_chapter("http://a/1", 3, "旧正文")
assert(cache.is_cached("http://a/1", 3), "应已缓存")
assertEq(cache.delete_chapter("http://a/1", 3), true, "删除缓存")
assertEq(cache.is_cached("http://a/1", 3), false, "缓存应被清除")

-- Critical 1: reader.open_book must resolve active_source from book.origin
local b_yx = {
    bookUrl = "https://source-a.example.invalid/book/1",
    name = "幽香书",
    origin = "https://source-a.example.invalid",
    originName = "源A"
}
reader.open_book(b_yx)
assertEq(reader.get_active_source().bookSourceUrl, "https://source-a.example.invalid", "open_book 应使用 book.origin 对应书源")

-- Critical 2: change_source_to must update current_book's URLs and storage
local new_src = { bookSourceUrl = "https://source-b.example.invalid", bookSourceName = "源B" }
local target_book = {
    bookUrl = "https://source-b.example.invalid/book/2",
    tocUrl = "https://source-b.example.invalid/book/2/chapters"
}
reader.change_source_to(target_book, new_src, 1, { { title = "第1章", url = "u1" } })
assertEq(b_yx.bookUrl, "https://source-b.example.invalid/book/2", "换源后 current_book.bookUrl 应更新")
assertEq(b_yx.origin, "https://source-b.example.invalid", "换源后 current_book.origin 应更新")

print("✔ Change Source Unit Tests passed successfully!")
