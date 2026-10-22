-- tests/test_jsoup_compat.lua
-- Unit & integration tests for Jsoup selectors, Legado slices, regex attribute matching, and JsoupElements / java.getElements APIs

local legado = require("src.legado")
local json = require("src.json")

print("=== Running Jsoup & Legado Selector Compatibility Tests ===")

legado.init()

-- Test 1: Jsoup regex attribute matching [attr~=pattern] (亿软小说)
print("--- 1. Testing [attr~=pattern] Jsoup regex attribute selector ---")
local yiruan_src = {
    bookSourceUrl = "https://www.yiruan.com",
    ruleSearch = {
        bookList = ".so_list [class~=list_box]",
        name = ".title@text",
        author = ".author@text",
        bookUrl = "a@href"
    }
}
local yiruan_html = [[
<div class="so_list">
    <div class="header">Header</div>
    <div class="col-xs-12 list_box active">
        <span class="title">亿软测试书A</span>
        <span class="author">测试作者A</span>
        <a href="/book/1001.html"></a>
    </div>
    <div class="ignore_item">Other</div>
    <div class="my_list_box_special">
        <span class="title">亿软测试书B</span>
        <span class="author">测试作者B</span>
        <a href="/book/1002.html"></a>
    </div>
</div>
]]

local res_str = legado.parseSearch(json.encode(yiruan_src), yiruan_html, "https://www.yiruan.com")
local books = json.decode(res_str)
assert(type(books) == "table" and #books == 2, "Expected 2 books matching [class~=list_box], got " .. tostring(#books))
assert(books[1].name == "亿软测试书A" and books[1].author == "测试作者A", "Book 1 mismatch")
assert(books[2].name == "亿软测试书B" and books[2].author == "测试作者B", "Book 2 mismatch")
print("✔ [attr~=pattern] regex selector passed")

-- Test 2: Legado slice syntax [start:end] (未来天王)
print("--- 2. Testing [start:end] slice selector ---")
local wlread_src = {
    bookSourceUrl = "https://m.wlread.com",
    ruleSearch = {
        bookList = ".list-item[0:2]",
        name = ".title@text",
        author = ".author@text",
        bookUrl = "a@href"
    }
}
local wlread_html = [[
<div class="search-result">
    <div class="list-item"><span class="title">未来书A</span><span class="author">甲</span><a href="/b/1"></a></div>
    <div class="list-item"><span class="title">未来书B</span><span class="author">乙</span><a href="/b/2"></a></div>
    <div class="list-item"><span class="title">未来书C</span><span class="author">丙</span><a href="/b/3"></a></div>
    <div class="list-item"><span class="title">未来书D</span><span class="author">丁</span><a href="/b/4"></a></div>
</div>
]]
local wlread_str = legado.parseSearch(json.encode(wlread_src), wlread_html, "https://m.wlread.com")
local wlread_books = json.decode(wlread_str)
assert(type(wlread_books) == "table" and #wlread_books == 2, "Expected 2 books from slice [0:2], got " .. tostring(#wlread_books))
assert(wlread_books[1].name == "未来书A" and wlread_books[2].name == "未来书B", "Slice mapping mismatch")
print("✔ [start:end] slice selector passed")

-- Test 3: Negative slice index [1:-1]
print("--- 3. Testing negative slice index [1:-1] ---")
local neg_slice_src = {
    bookSourceUrl = "https://m.test.com",
    ruleSearch = {
        bookList = ".item[1:-1]",
        name = ".title@text",
        bookUrl = "a@href"
    }
}
local neg_html = [[
<div class="box">
    <div class="item"><span class="title">跳过首项</span><a href="/b/0"></a></div>
    <div class="item"><span class="title">保留项1</span><a href="/b/1"></a></div>
    <div class="item"><span class="title">保留项2</span><a href="/b/2"></a></div>
    <div class="item"><span class="title">跳过尾项</span><a href="/b/3"></a></div>
</div>
]]
local neg_str = legado.parseSearch(json.encode(neg_slice_src), neg_html, "https://m.test.com")
local neg_books = json.decode(neg_str)
assert(#neg_books == 2, "Expected 2 books from [1:-1], got " .. tostring(#neg_books))
assert(neg_books[1].name == "保留项1" and neg_books[2].name == "保留项2", "Negative slice mapping mismatch")
print("✔ [1:-1] negative slice passed")

-- Test 4: java.getElements + Jsoup Elements / Element API (永恒阁吧)
print("--- 4. Testing java.getElements with .attr() and .text() in <js> ---")
local yongheng_src = {
    bookSourceUrl = "https://www.28003.com",
    ruleToc = {
        chapterList = [[<js>
        doc = java.getElements(".section-box:eq(1) li a");
        list = [];
        for (i = 0; i < doc.length; i++) {
            d = doc[i];
            url = d.attr("href");
            title = d.text();
            list.push({title: title, url: url});
        }
        list;
        </js>]],
        chapterName = "title",
        chapterUrl = "url"
    }
}
local yongheng_html = [[
<div class="wrapper">
    <div class="section-box">
        <h3>最新章节 (跳过)</h3>
        <ul><li><a href="/read/99.html">最新第99章</a></li></ul>
    </div>
    <div class="section-box">
        <h3>正文目录</h3>
        <ul>
            <li><a href="/read/1.html">第1章 永恒启程</a></li>
            <li><a href="/read/2.html">第2章 天地玄黄</a></li>
            <li><a href="/read/3.html">第3章 宇宙洪荒</a></li>
        </ul>
    </div>
</div>
]]
local yh_toc = legado.parseToc(json.encode(yongheng_src), yongheng_html, "https://www.28003.com/b/1/")
assert(yh_toc and yh_toc.chapters and #yh_toc.chapters == 3, "Expected 3 chapters parsed via java.getElements, got " .. tostring(#(yh_toc.chapters or {})))
assert(yh_toc.chapters[1].title == "第1章 永恒启程" and yh_toc.chapters[1].url == "https://www.28003.com/read/1.html", "Chapter 1 mismatch")
assert(yh_toc.chapters[3].title == "第3章 宇宙洪荒" and yh_toc.chapters[3].url == "https://www.28003.com/read/3.html", "Chapter 3 mismatch")
print("✔ java.getElements + doc[i].attr() / doc[i].text() passed")

-- Test 5: Jsoup pseudo-selectors :not(), :contains(), :has()
print("--- 5. Testing Jsoup pseudo-selectors :not, :contains, :has ---")
local pseudo_eval = [[
(function() {
    var html = '<div id="main"><p class="a">Hello</p><p class="b">World</p><div class="card"><span class="badge">Hot</span><a href="/link1">Item 1</a></div><div class="card"><a href="/link2">Item 2</a></div></div>';
    var doc = Legado.parseHTML(html);
    var notRes = doc.select('p:not(.a)');
    var containsRes = doc.select('p:contains(World)');
    var hasRes = doc.select('.card:has(.badge) a');
    return JSON.stringify({
        notCount: notRes.length,
        notText: notRes.text(),
        containsCount: containsRes.length,
        hasCount: hasRes.length,
        hasHref: hasRes.attr('href')
    });
})()
]]
local p_c = legado.eval(pseudo_eval)
local p_res = json.decode(p_c)
assert(p_res.notCount == 1 and p_res.notText == "World", ":not(.a) selector failed")
assert(p_res.containsCount == 1, ":contains(World) selector failed")
assert(p_res.hasCount == 1 and p_res.hasHref == "/link1", ":has(.badge) selector failed")
print("✔ Jsoup pseudo-selectors :not(), :contains(), :has() passed")

print("ALL JSOUP & LEGADO SELECTOR COMPATIBILITY TESTS PASSED SUCCESSFULLY!")
