package.path = package.path .. ";./src/?.lua"
local search = require("src.views.search")

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)))
    end
end

print("=== Running Search Aggregation Unit Tests ===")

-- 1. Test Aggregating Duplicate Books
local res = {}
res = search.aggregate_book_item(res, {
    name = "完美世界",
    author = "辰东",
    bookUrl = "https://s1.com/book/1",
    origin = "https://s1.com",
    originName = "源1",
    latestChapterTitle = "第100章 战",
    latencyMs = 300
})

assertEq(#res, 1, "Should have 1 item")
assertEq(#res[1].candidates, 1, "Should have 1 candidate")
assertEq(res[1].originName, "源1", "Initial source")

-- 2. Add second candidate with lower latency (120ms vs 300ms)
res = search.aggregate_book_item(res, {
    name = "完美世界",
    author = "辰东",
    bookUrl = "https://s2.com/book/2",
    origin = "https://s2.com",
    originName = "源2",
    latestChapterTitle = "第120章 终",
    latencyMs = 120
})

assertEq(#res, 1, "Should remain 1 card")
assertEq(#res[1].candidates, 2, "Should aggregate 2 sources")
assertEq(res[1].originName, "源2", "Best source should be lower latency 源2")
assertEq(res[1].latencyMs, 120, "Best latency should be 120")
assertEq(res[1].latestChapterTitle, "第120章 终", "Should update latest chapter")

-- Test Important 1: tocUrl should be synchronized upon promotion
res = search.aggregate_book_item(res, {
    name = "完美世界",
    author = "辰东",
    bookUrl = "https://s3.com/book/3",
    tocUrl = "https://s3.com/toc/3",
    origin = "https://s3.com",
    originName = "源3",
    latencyMs = 50
})
assertEq(res[1].tocUrl, "https://s3.com/toc/3", "Promoted candidate must synchronize tocUrl")

-- 3. Add book with different author (not duplicate)
res = search.aggregate_book_item(res, {
    name = "完美世界",
    author = "同名作者B",
    bookUrl = "https://s3.com/book/3",
    origin = "https://s3.com",
    originName = "源3",
    latencyMs = 150
})

assertEq(#res, 2, "Different author should create separate card")

print("✔ Search Aggregation Tests passed successfully!")
