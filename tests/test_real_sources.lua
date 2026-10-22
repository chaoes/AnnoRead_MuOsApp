package.path = package.path .. ";./src/?.lua"
local legado = require("legado")
local json = require("json")
legado.init()

print("=== Running Real Sources Integration Test ===")

local f = io.open("assets/sources/haishuge.json", "r")
if not f then
    print("Local site sources absent; site-specific regression skipped")
    return
end
local raw = f:read("*a")
f:close()

local sources = json.decode(legado.parseSources(raw))
assert(#sources == 1, "expected 1 source in haishuge.json, got " .. tostring(#sources))
assert(sources[1].bookSourceName == "书海阁", "haishuge.json must contain 书海阁")

-- Load the second bundled source file and verify both merge into a set.
local f2 = assert(io.open("assets/sources/youxiangshufang.json", "r"), "assets/sources/youxiangshufang.json missing")
local raw2 = f2:read("*a")
f2:close()
local yx_only = json.decode(legado.parseSources(raw2))
assert(#yx_only == 1 and yx_only[1].bookSourceName == "幽香书房", "youxiangshufang.json must contain 幽香书房")

-- Combined set (as storage.load_default_sources would merge them)
sources = { sources[1], yx_only[1] }
local names = {}
for _, s in ipairs(sources) do names[s.bookSourceName] = true end
assert(names["书海阁"] and names["幽香书房"], "both sources must be present")

-- Check rule parsing for both sources offline with fixtures or mock HTML
local sh, yx
for _, s in ipairs(sources) do
    if s.bookSourceName == "书海阁" then sh = s end
    if s.bookSourceName == "幽香书房" then yx = s end
end
assert(sh and yx, "failed to separate sources")

-- 1. Test exploreUrl parsing on both
local sh_cats = json.decode(legado.parseExploreCategories(sh.exploreUrl))
assert(type(sh_cats) == "table" and #sh_cats >= 10, "书海阁 exploreCategories failed")

local yx_cats = json.decode(legado.parseExploreCategories(yx.exploreUrl))
assert(type(yx_cats) == "table" and #yx_cats >= 20, "幽香书房 exploreCategories failed")

-- 2. Test searchUrl building on both
local sh_req = json.decode(legado.buildSearchRequest(json.encode(sh), "测试", 1))
assert(sh_req and sh_req.url and sh_req.url:find("book.washai.net"), "书海阁 searchReq failed")

local yx_req = json.decode(legado.buildSearchRequest(json.encode(yx), "测试", 1))
assert(yx_req and yx_req.url and yx_req.url:find("003I.html"), "幽香书房 searchReq failed")

-- 3. Test 幽香书房 TOC parsing offline using fallback structure
local yx_mock_html = [[
<html>
  <head>
    <meta property="og:novel:latest_chapter_url" content="https://www.yxshufang.com/book/0RNQ-110.html" />
  </head>
  <body>
    <div data-aid="0RNQ"></div>
    <select class="select"><option value="1">1</option><option value="2">2</option></select>
    <ul id="ul_all_chapters">
      <li><a href="/book/0RNQ-1.html" title="第一章 降生">第一章 降生</a></li>
      <li><a href="/book/0RNQ-2.html" title="第二章 成长">第二章 成长</a></li>
    </ul>
  </body>
</html>
]]
local yx_toc = legado.parseToc(json.encode(yx), yx_mock_html, "https://www.yxshufang.com/book/0RNQ.html")
assert(type(yx_toc) == "table" and yx_toc.chapters and #yx_toc.chapters >= 2, "幽香书房 TOC fallback parsing failed")
assert(yx_toc.chapters[1].title:find("第一章"), "幽香书房 chapter 1 title mismatch")

print("✔ Real Sources Integration Test passed successfully!")
