package.path = package.path .. ";./src/?.lua"
local reader = require("src.views.reader")
local legado = require("src.legado")
local storage = require("src.storage")
local cache = require("src.cache")
local http = require("src.http")
local json = require("src.json")

storage.init()
cache.init()

print("=== Running Recursive Pagination (TOC & Content) Unit Tests ===")

-- 1. Test TOC Recursive Pagination
local mock_source = {
    bookSourceUrl = "https://mock.novel.com",
    bookSourceName = "分页测试源",
    ruleToc = {
        chapterList = ".chapter-list a",
        chapterName = "text",
        chapterUrl = "href",
        nextTocUrl = "a.next@href"
    },
    ruleContent = {
        content = "#content@text",
        nextContentUrl = "a.next-page@href"
    }
}

table.insert(storage.get_sources(), mock_source)

local page1_toc_html = [[
<div class="chapter-list">
    <a href="/c1.html">第1章</a>
    <a href="/c2.html">第2章</a>
</div>
<a class="next" href="https://mock.novel.com/toc/page2.html">下一页</a>
]]

local page2_toc_html = [[
<div class="chapter-list">
    <a href="/c3.html">第3章</a>
    <a href="/c4.html">第4章</a>
</div>
]]

-- Mock http requests for TOC
local requested_urls = {}
http.request_async = function(opts, cb)
    table.insert(requested_urls, opts.url)
    if opts.url == "https://mock.novel.com/toc/page1.html" or opts.url == "https://mock.novel.com/book/100" then
        cb(page1_toc_html)
    elseif opts.url == "https://mock.novel.com/toc/page2.html" then
        cb(page2_toc_html)
    end
end

local mock_book = {
    bookUrl = "https://mock.novel.com/book/100",
    tocUrl = "https://mock.novel.com/toc/page1.html",
    name = "分页书",
    origin = mock_source.bookSourceUrl,
    originName = mock_source.bookSourceName
}

reader.open_book(mock_book)

local chs = reader.get_chapters()
assert(#chs == 4, "TOC should recursively fetch 2 pages totaling 4 chapters, got " .. tostring(#chs))
assert(chs[1].title == "第1章" and chs[4].title == "第4章", "Chapter titles mismatch")

-- 2. Test Content Recursive Pagination
local page1_content = [[
<div id="content">第一页正文。</div>
<a class="next-page" href="https://mock.novel.com/c1_part2.html">下一页</a>
]]
local page2_content = [[
<div id="content">第二页正文完结。</div>
]]

http.request_async = function(opts, cb)
    if opts.url:find("c1_part2.html") then
        cb(page2_content, opts.tag, opts.payload)
    else
        cb(page1_content, opts.tag, opts.payload)
    end
end

cache.delete_chapter(mock_book.bookUrl, 1)
reader.load_chapter(1)

local content = reader.get_current_content()
assert(content:find("第一页正文") and content:find("第二页正文完结"), "Content pagination should assemble both parts")

print("✔ Recursive Pagination Tests passed successfully!")
