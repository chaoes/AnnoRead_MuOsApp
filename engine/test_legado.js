import './legado.js';

function assert(condition, message) {
    if (!condition) {
        throw new Error("Assertion Failed: " + message);
    }
}

function assertEquals(expected, actual, message) {
    if (expected !== actual) {
        throw new Error(`Assertion Failed: ${message || ''} (Expected: ${JSON.stringify(expected)}, Actual: ${JSON.stringify(actual)})`);
    }
}

console.log("=== Starting Legado QuickJS Engine Tests ===");

// 1. Test BookSource JSON Parsing
{
    const jsonStr = `
    [
      {
        "bookSourceUrl": "https://example.com/source",
        "bookSourceName": "测试书源",
        "bookSourceType": 0,
        "enabled": true,
        "searchUrl": "https://example.com/search?q={{key}}&page={{page}}",
        "ruleSearch": {
          "bookList": "div.book-item",
          "name": "h3.title@text",
          "author": "span.author@text",
          "bookUrl": "a@href"
        }
      },
      {
        "invalidItem": 123
      }
    ]
    `;

    const sources = Legado.LegadoEngine.parseBookSources(jsonStr);
    assertEquals(1, sources.length, "Should filter out invalid source item");
    assertEquals("测试书源", sources[0].bookSourceName);
    assertEquals("https://example.com/source", sources[0].bookSourceUrl);
    assertEquals("div.book-item", sources[0].ruleSearch.bookList);
    console.log("✔ Test 1: BookSource JSON Parsing Passed");
}

// 2. Test RuleAnalyzer CSS, @ Chain, Negative Index, Direct Attrs, and Regex
{
    const html = `
    <div class="crumbs">
        <a href="/">首页</a>
        <a href="/category/xuanhuan">玄幻小说</a>
        <a href="/book/100">斗破苍穹（精校版）</a>
    </div>
    <div class="book-item">
        <h3 class="title">诡秘之主（全本）</h3>
        <span class="author">作者：爱潜水的乌贼</span>
        <a href="/book/12345" title="点击阅读">开始阅读</a>
    </div>
    `;

    const doc = Legado.parseHTML(html);

    // Negative Index & Chaining
    const lastLinkText = Legado.RuleAnalyzer.extractString(doc, "class.crumbs@tag.a.-1@text");
    assertEquals("斗破苍穹（精校版）", lastLinkText, "Negative index -1 should get last link");

    // Positive Index 0
    const firstLinkText = Legado.RuleAnalyzer.extractString(doc, "class.crumbs@tag.a.0@text");
    assertEquals("首页", firstLinkText, "Index 0 should get first link");

    // Direct Attr href with URL resolution
    const item = doc.selectFirst("div.book-item");
    const link = Legado.RuleAnalyzer.extractString(item, "a@href", "https://example.com");
    assertEquals("https://example.com/book/12345", link, "Should resolve relative URL");

    // Regex replacement
    const cleanTitle = Legado.RuleAnalyzer.extractString(item, "h3.title@text##（.*）##");
    assertEquals("诡秘之主", cleanTitle, "Regex should strip parentheses content");

    const cleanAuthor = Legado.RuleAnalyzer.extractString(item, "span.author@text##作者：##");
    assertEquals("爱潜水的乌贼", cleanAuthor, "Regex should strip prefix");

    console.log("✔ Test 2: RuleAnalyzer CSS, Indexing & Regex Passed");
}

// 3. Test Alternative Rule Fallback (||)
{
    const html = `
    <div class="main-content">
        <div class="novel-intro">这是一部宏大的玄幻小说。</div>
    </div>
    `;
    const doc = Legado.parseHTML(html);
    const result = Legado.RuleAnalyzer.extractString(doc, "class.wrong-intro@text||class.novel-intro@text");
    assertEquals("这是一部宏大的玄幻小说。", result, "Fallback || should match second alternative");
    console.log("✔ Test 3: Alternative Rule Fallback Passed");
}

// 4. Test JavaScript Sandbox & java.* host functions
{
    // java.put and java.get
    const script1 = `
        java.put("token", "secret_123");
        return java.get("token");
    `;
    const res1 = Legado.RuleAnalyzer.extractString("test", `<js>${script1}</js>`);
    assertEquals("secret_123", res1, "java.put and get must work");

    // java.base64Encode and decode
    const b64 = Legado.base64Encode("Legado QuickJS");
    assertEquals("Legado QuickJS", Legado.base64Decode(b64), "Base64 roundtrip");

    // java.md5Encode
    const md5Hex = Legado.md5("legado");
    assertEquals("bbd6a62a8a291b19a802e4ad64547fff", md5Hex, "MD5 hash match");

    // java.timeFormat
    const host = new Legado.JsHost();
    const formatted = host.timeFormat(1700000000000, "yyyy-MM-dd");
    assert(formatted.length === 10, "Formatted date length");

    // JSONPath java.getString
    const jsonVal = host.getString('{"data": {"title": "庆余年"}}', '$.data.title');
    assertEquals("庆余年", jsonVal, "getString JSONPath");

    console.log("✔ Test 4: JavaScript Sandbox & Host Functions Passed");
}

// 5. Test Search Request Building and Parsing
{
    const source = {
        bookSourceUrl: "https://biquge.tv",
        bookSourceName: "笔趣阁",
        searchUrl: "https://biquge.tv/search?q={{key}}&p={{page}}, {\"method\": \"POST\", \"headers\": {\"X-Custom\": \"val\"}}",
        ruleSearch: {
            bookList: "div.item",
            name: "h4.title@text",
            author: "span.author@text",
            bookUrl: "a@href",
            intro: "p.desc@text"
        }
    };

    const req = Legado.LegadoEngine.buildSearchRequest(source, "遮天", 2);
    assertEquals("POST", req.method);
    assertEquals("https://biquge.tv/search?q=%E9%81%AE%E5%A4%A9&p=2", req.url);
    assertEquals("val", req.headers["X-Custom"]);

    const mockResponseHtml = `
    <div class="result-list">
        <div class="item">
            <h4 class="title">《遮天》</h4>
            <span class="author">辰东</span>
            <a href="/book/zhetian/">阅读</a>
            <p class="desc">冰冷与黑暗并存的宇宙深处...</p>
        </div>
        <div class="item">
            <h4 class="title">完美世界</h4>
            <span class="author">辰东</span>
            <a href="/book/wanmei/">阅读</a>
            <p class="desc">一粒尘可填海...</p>
        </div>
    </div>
    `;

    const books = Legado.LegadoEngine.parseSearchResult(source, mockResponseHtml);
    assertEquals(2, books.length);
    assertEquals("遮天", books[0].name);
    assertEquals("辰东", books[0].author);
    assertEquals("https://biquge.tv/book/zhetian/", books[0].bookUrl);
    assertEquals("冰冷与黑暗并存的宇宙深处...", books[0].intro);
    console.log("✔ Test 5: Search Request & Result Parsing Passed");
}

// 6. Test TOC & Content Parsing
{
    const source = {
        bookSourceUrl: "https://biquge.tv",
        ruleToc: {
            chapterList: "div.list@ul@li@a",
            chapterName: "text",
            chapterUrl: "href"
        },
        ruleContent: {
            content: "div#content@html",
            replaceRegex: "##广告：.*##"
        }
    };

    const tocHtml = `
    <div class="list">
        <ul>
            <li><a href="/c1.html">第一章 星空中的青铜巨棺</a></li>
            <li><a href="/c2.html">第二章 降临泰山</a></li>
        </ul>
    </div>
    `;

    const tocResult = Legado.LegadoEngine.parseToc(source, tocHtml, "https://biquge.tv/book/1/");
    const chapters = tocResult.chapters;
    assertEquals(2, chapters.length);
    assertEquals("第一章 星空中的青铜巨棺", chapters[0].title);
    assertEquals("https://biquge.tv/c1.html", chapters[0].url);

    const contentHtml = `
    <div id="content">
        <p>生命是世间最伟大的奇迹。<br/></p>
        <p>广告：关注微信公众号获取最新章节！</p>
        <p>登临泰山，让人顿生绝顶我为峰之感。</p>
    </div>
    `;

    const cleanedContent = Legado.LegadoEngine.parseContent(source, contentHtml).content;
    assert(!cleanedContent.includes("广告："), "Ad should be filtered out by replaceRegex");
    assert(cleanedContent.includes("生命是世间最伟大的奇迹。"), "Main content preserved");
    assert(cleanedContent.includes("登临泰山"), "Paragraph preserved");

    console.log("✔ Test 6: TOC & Content Parsing Passed");
}

console.log("🎉 ALL LEGADO QUICKJS ENGINE TESTS PASSED SUCCESSFULLY! 🎉");
