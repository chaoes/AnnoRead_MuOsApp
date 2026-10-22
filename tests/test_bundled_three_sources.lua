-- tests/test_bundled_three_sources.lua
-- Tests the bundled three sources: 亿软小说, 未来天王, 永恒小说
-- File: assets/sources/yruan_weilaitianwang_yongheng.json

local json = require("src.json")
local storage = require("src.storage")
local legado = require("src.legado")

print("=== Running Bundled Three Sources Tests (亿软小说, 未来天王, 永恒小说) ===")

-- 1. Verify assets/sources/yruan_weilaitianwang_yongheng.json exists and is valid JSON array of 3 sources
local f = io.open("assets/sources/yruan_weilaitianwang_yongheng.json", "r")
if not f then
    print("Local three-source bundle absent; site-specific regression skipped")
    return
end
local content = f:read("*a")
f:close()

assert(#content > 0, "yruan_weilaitianwang_yongheng.json must not be empty")
local sources = json.decode(content)
assert(type(sources) == "table" and #sources == 3, "Must contain exactly 3 sources, got " .. tostring(type(sources) == "table" and #sources or 0))

local expected_names = {
    ["亿软小说"] = true,
    ["未来天王"] = true,
    ["永恒小说"] = true
}

local source_map = {}
for i, s in ipairs(sources) do
    assert(s.bookSourceName and expected_names[s.bookSourceName], "Unexpected source name: " .. tostring(s.bookSourceName))
    assert(s.bookSourceUrl and #s.bookSourceUrl > 0, "Missing bookSourceUrl for " .. s.bookSourceName)
    assert(s.ruleSearch, "Missing ruleSearch for " .. s.bookSourceName)
    assert(s.ruleToc, "Missing ruleToc for " .. s.bookSourceName)
    source_map[s.bookSourceName] = s
end
print("✔ 1. Verified assets/sources/yruan_weilaitianwang_yongheng.json structure & fields")

-- 2. Verify storage.init() auto-loads the new file and merges with other sources
storage.init()
local all_sources = storage.get_sources()
assert(#all_sources >= 3, "Storage must contain sources")

local found = {}
for _, s in ipairs(all_sources) do
    if expected_names[s.bookSourceName] then
        found[s.bookSourceName] = s
    end
end

assert(found["亿软小说"], "Storage missing 亿软小说")
assert(found["未来天王"], "Storage missing 未来天王")
assert(found["永恒小说"], "Storage missing 永恒小说")
print(string.format("✔ 2. Storage successfully merged all 3 sources (total active sources in storage: %d)", #all_sources))

-- 3. Verify rule execution for each of the 3 bundled sources using our enhanced engine
legado.init()

-- 3.1 亿软小说: buildSearchRequest, parseSearch, parseToc (regex attr / dd), parseContent (strip HTML comments)
local yr_src = source_map["亿软小说"]
local yr_req_str = legado.buildSearchRequest(json.encode(yr_src), "剑来", 1)
local yr_req = json.decode(yr_req_str)
assert(yr_req and yr_req.url and yr_req.url:find("searchkey="), "亿软小说 searchUrl build failed")

local yr_search_html = [[
<table class="grid">
  <tr><th>书名</th><th>最新章节</th><th>作者</th><th>字数</th><th>类型</th><th>状态</th></tr>
  <tr>
    <td><a href="/book/1001.html">剑来</a></td>
    <td><a href="/book/1001/10.html">第十章</a></td>
    <td>烽火戏诸侯</td>
    <td>500万</td>
    <td>玄幻</td>
    <td>连载</td>
  </tr>
</table>
]]
local yr_search_res = legado.parseSearch(json.encode(yr_src), yr_search_html, yr_src.bookSourceUrl)
local yr_books = json.decode(yr_search_res)
assert(type(yr_books) == "table" and #yr_books == 1, "亿软小说 parseSearch must find 1 book")
assert(yr_books[1].name == "剑来" and yr_books[1].author == "烽火戏诸侯", "亿软小说 book info mismatch")

local yr_toc_html = [[
<div id="list">
    <dd><a href="https://www.yruan.com/read/1_1.html">第一章 降临</a></dd>
    <dd><a href="https://www.yruan.com/read/1_2.html">第二章 觉醒</a></dd>
</div>
]]
local yr_toc_res = legado.parseToc(json.encode(yr_src), yr_toc_html, yr_src.bookSourceUrl)
assert(yr_toc_res and #yr_toc_res.chapters == 2, "亿软小说 parseToc must find 2 chapters")
assert(yr_toc_res.chapters[1].title == "第一章 降临", "亿软小说 chapter 1 title mismatch")

local yr_content_html = [[<div id="content"><!--go-->第一段正文。<!--over--></div>]]
local yr_content_res = legado.parseContent(json.encode(yr_src), yr_content_html, yr_src.bookSourceUrl)
assert(yr_content_res and yr_content_res.content and yr_content_res.content:find("第一段正文。"), "亿软小说 parseContent mismatch")
print("✔ 3.1 亿软小说 ruleSearch/ruleToc/ruleContent verification passed")

-- 3.2 未来天王: buildSearchRequest, parseSearch ([1:-1] slice & regex OnlyOne), parseToc (dd[12:-1] slice), parseContent (@textNodes)
local wl_src = source_map["未来天王"]
local wl_req_str = legado.buildSearchRequest(json.encode(wl_src), "剑来", 1)
local wl_req = json.decode(wl_req_str)
assert(wl_req and wl_req.url and wl_req.url:find("name="), "未来天王 searchUrl build failed")

local wl_search_html = [[
<div class="novelslist2">
    <ul>
        <li><span class="s1">[分类]</span><span class="s2"><b>表头跳过</b></span></li>
        <li><span class="s1">[科幻]</span><span class="s2"><a href="/book/101.html">未来世界A</a></span><span class="s4"><a href="#">作者A</a></span><span class="s6 wid6">连载</span></li>
        <li><span class="s1">[仙侠]</span><span class="s2"><a href="/book/102.html">未来世界B</a></span><span class="s4"><a href="#">作者B</a></span><span class="s6 wid6">完结</span></li>
        <li><span class="s1">[尾部]</span><span class="s2"><b>底部统计跳过</b></span></li>
    </ul>
</div>
]]
local wl_search_res = legado.parseSearch(json.encode(wl_src), wl_search_html, wl_src.bookSourceUrl)
local wl_books = json.decode(wl_search_res)
assert(type(wl_books) == "table" and #wl_books == 2, "未来天王 parseSearch with slice [1:-1] must return 2 books, got " .. tostring(#wl_books))
assert(wl_books[1].name == "未来世界A" and wl_books[1].author == "作者A", "未来天王 book 1 mismatch")
assert(wl_books[2].name == "未来世界B" and wl_books[2].author == "作者B", "未来天王 book 2 mismatch")

local wl_dd_items = {}
for i = 1, 20 do
    table.insert(wl_dd_items, "<dd><a href=\"/book/101/" .. i .. ".html\">第" .. i .. "章</a></dd>")
end
local wl_toc_html = "<div id=\"list\"><dl>" .. table.concat(wl_dd_items, "\n") .. "</dl></div>"
local wl_toc_res = legado.parseToc(json.encode(wl_src), wl_toc_html, wl_src.bookSourceUrl)
assert(wl_toc_res and #wl_toc_res.chapters == 7, "未来天王 parseToc slice [12:-1] expected 7 chapters, got " .. tostring(#wl_toc_res.chapters))
assert(wl_toc_res.chapters[1].title == "第13章", "未来天王 slice chapter title mismatch: " .. tostring(wl_toc_res.chapters[1].title))

local wl_content_html = [[<div id="content">第一段内容。<p>第二段内容。</p>第三段内容。</div>]]
local wl_content_res = legado.parseContent(json.encode(wl_src), wl_content_html, wl_src.bookSourceUrl)
assert(wl_content_res and wl_content_res.content and wl_content_res.content:find("第一段内容。"), "未来天王 parseContent mismatch")
print("✔ 3.2 未来天王 ruleSearch/ruleToc/ruleContent verification passed")

-- 3.3 永恒小说: buildSearchRequest (POST), parseSearch, parseToc, parseContent (java.getElements + Elements.select)
local yh_src = source_map["永恒小说"]
local yh_req_str = legado.buildSearchRequest(json.encode(yh_src), "剑来", 1)
local yh_req = json.decode(yh_req_str)
assert(yh_req and yh_req.body and yh_req.body:find("s="), "永恒小说 POST searchUrl build failed")

local yh_search_html = [[
<div class="bd">
  <ul>
    <li><span>[玄幻]</span><a href="/book/1.html">剑来(烽火戏诸侯)</a></li>
  </ul>
</div>
]]
local yh_search_res = legado.parseSearch(json.encode(yh_src), yh_search_html, yh_src.bookSourceUrl)
local yh_books = json.decode(yh_search_res)
assert(type(yh_books) == "table" and #yh_books == 1, "永恒小说 parseSearch must return 1 book")
assert(yh_books[1].name == "剑来" and yh_books[1].author == "烽火戏诸侯", "永恒小说 search result mismatch")

local yh_toc_html = [[
<div class="list">
    <div data-id="0">
        <li><a href="/ch1.html">永恒序章</a></li>
    </div>
    <div data-id="1">
        <li><a href="/ch2.html">混沌之初</a></li>
    </div>
</div>
]]
local yh_toc_res = legado.parseToc(json.encode(yh_src), yh_toc_html, yh_src.bookSourceUrl)
assert(yh_toc_res and #yh_toc_res.chapters == 2, "永恒小说 parseToc with java.getElements must return 2 chapters")
assert(yh_toc_res.chapters[1].title == "永恒序章", "永恒小说 chapter 1 title mismatch")
assert(yh_toc_res.chapters[2].title == "混沌之初", "永恒小说 chapter 2 title mismatch")

local yh_content_html = [[
<div id="txt">
  <dd data-id="0">第一段正文内容。</dd>
  <dd data-id="1">第二段正文内容。</dd>
  <dd data-id="2">无用广告。</dd>
</div>
]]
local yh_content_res = legado.parseContent(json.encode(yh_src), yh_content_html, yh_src.bookSourceUrl)
assert(yh_content_res and yh_content_res.content and yh_content_res.content:find("第一段正文内容。"), "永恒小说 parseContent line 1 mismatch")
assert(yh_content_res.content:find("第二段正文内容。"), "永恒小说 parseContent line 2 mismatch")
print("✔ 3.3 永恒小说 ruleSearch/ruleToc/ruleContent verification passed")

print("ALL THREE BUNDLED SOURCES TESTS PASSED SUCCESSFULLY!")
