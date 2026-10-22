import './legado.js';
const L = globalThis.Legado;
function assert(cond, msg) { if (!cond) throw new Error('Assertion Failed: ' + msg); }
function assertEq(label, actual, expected) {
    if (actual !== expected) throw new Error(`${label} (expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)})`);
    console.log('PASS', label);
}

assertEq("A1 @css 字符串规则", L.RuleAnalyzer.extractString('<div class="x">hi</div>', '@css:.x@text'), 'hi');
assertEq("A2 @css+##", L.RuleAnalyzer.extractString('<div class="x">正文 一秒记住 完</div>', '@css:.x@text##一秒记住'), '正文  完');
assertEq("A3 :eq(1)", L.RuleAnalyzer.extractString('<p>x<a>1</a></p><p>y<a>2</a></p>', '@css:p:eq(1)>a@text'), '2');

assertEq("B1 !0 排除", L.RuleAnalyzer.extractList('<li>h</li><li>a</li><li>b</li>', 'tag.li!0').length, 2);
assertEq("B2 ownText", L.RuleAnalyzer.extractString('<p>a<span>b</span></p>', 'tag.p@ownText'), 'a');
assertEq("B3 children", L.RuleAnalyzer.extractList('<div><a>1</a><b>2</b></div>', 'tag.div@children').length, 2);
assertEq("B4 text.", L.RuleAnalyzer.extractString('<div>foo bar</div>', 'text.bar'), 'foo bar');
assertEq("B5 all", L.RuleAnalyzer.extractString('<p>a<span>b</span></p>', 'tag.p@all'), '<p>a<span>b</span></p>');

const html1 = '<a href="/read1.html">C1</a><a href="/read2.html">C2</a>';
assertEq("C1 AllInOne 长度", L.RuleAnalyzer.extractList(html1, ':href="(/read[^"]*html)">([^<]*)').length, 2);
assertEq("C2 倒序", L.RuleAnalyzer.extractList('<li><a>1</a></li><li><a>2</a></li>', '-tag.li@tag.a@text').join(','), '2,1');

// 书源一真实形态：倒序 AllInOne + $1/$2 捕获组
{
    const items = L.RuleAnalyzer.extractList('<a href="/read1.html">Ch1</a><a href="/read2.html">Ch2</a>',
        '-:href="(/read[^"]*html)">([^<]*)');
    assertEq("C3 倒序后首项为 Ch2", L.RuleAnalyzer.extractString(items[0], '$2'), 'Ch2');
    assertEq("C4 首项 URL 捕获组", L.RuleAnalyzer.extractString(items[0], '$1'), '/read2.html');
}

assertEq("D1 %% 交错", L.RuleAnalyzer.extractString('<a>X</a><b>Y</b>', 'tag.a@text%%tag.b@text'), 'X\nY');
assertEq("D2 @put", L.RuleAnalyzer.extractString('{"bid":123}', '@put:{bid:"$.bid"}'), '123');
assertEq("D3 @get", L.RuleAnalyzer.extractString('{"bid":123}', '@put:{bid:"$.bid"}@get:bid'), '123');

// --- Task 5: nextTocUrl / nextContentUrl / isVip / chapterInfo ---
const tocR = L.LegadoEngine.parseToc({ruleToc:{chapterList:'tag.a',chapterName:'text',chapterUrl:'href',
    nextTocUrl:'tag.a.next@href', isVip:'tag.span@text'}},
    '<a href="/1">c1</a><a class="next" href="/p2">n</a>', 'http://x/');
assertEq("E1 章节数(排除next)", tocR.chapters.length, 1);
assertEq("E2 nextTocUrl", tocR.nextTocUrl, 'http://x/p2');
const ctR = L.LegadoEngine.parseContent({ruleContent:{content:'tag.div@text',nextContentUrl:'a.next@href'}},
    '<div>p1</div><a class="next" href="/n2">下一页</a>', 'http://x/');
assertEq("E3 nextContentUrl", ctR.nextContentUrl, 'http://x/n2');
assertEq("E4 content", ctR.content, 'p1');

assertEq("F1 {{js}}", L.LegadoEngine.buildSearchRequest({bookSourceUrl:'http://x',searchUrl:'/s?p={{(page-1)*20}}'},'k',3).url, 'http://x/s?p=40');
assertEq("F2 {{base64}}", L.LegadoEngine.buildSearchRequest({bookSourceUrl:'http://x',searchUrl:'/s?k={{java.base64Encode(key)}}'},'kw',1).url, 'http://x/s?k=a3c=');
assertEq("F3 charset", L.LegadoEngine.buildSearchRequest({bookSourceUrl:'http://x',searchUrl:'/s?q={{key}},{"charset":"gbk"}'},'k',1).charset, 'gbk');
// OnlyOne ###：单次替换 + $1 回填。采用书源一真实模式形态
// `##:author\"[^\"]+\"([^\"]*)##$1###`，输入与之匹配。
assertEq("F4 OnlyOne ###", L.RuleAnalyzer.extractString(':author"xx"辰东', '##:author\\"[^\\"]+\\"([^\\"]*)##$1###'), '辰东');
assertEq("F5 递归 JSONPath", L.RuleAnalyzer.extractList('{"a":{"books":[{"t":1},{"t":2}]}}', '$..books[*]').length, 2);

// Real source from nyasama collection: XPath contains() and relative `.//` rules.
{
    const html = `<div class="bookbox"><h2 class="bookname"><a href="/book/demo.html">凡人修仙传</a></h2><div class="author">作者：忘语</div><div class="update">简介：正文简介</div></div>`;
    const source = {
        bookSourceName: '思兔阅读', bookSourceUrl: 'https://www.sto66.com',
        ruleSearch: {
            bookList: "//*[contains(@class, 'bookbox')]",
            name: "@XPath:.//*[contains(@class, 'bookname')]/a/text()",
            author: "@XPath:.//div[contains(@class, 'author')][1]/text()##作者：",
            bookUrl: "@XPath:.//*[contains(@class, 'bookname')]/a/@href",
            intro: "@XPath:.//*[contains(@class, 'update')]//text()##简介："
        }
    };
    const books = L.LegadoEngine.parseSearchResult(source, html, 'https://www.sto66.com/search/test.html');
    assertEq("G1 XPath contains() list", books.length, 1);
    assertEq("G2 relative XPath name", books[0].name, '凡人修仙传');
    assertEq("G3 relative XPath author", books[0].author, '忘语');
    assertEq("G4 relative XPath URL", books[0].bookUrl, 'https://www.sto66.com/book/demo.html');
    assertEq("G4b XPath regex cleanup", books[0].intro, '正文简介');
    assertEq("G5 XPath contains text predicate", L.RuleAnalyzer.extractList('<div>甲</div><div>乙</div>', "//div[contains(text(), '乙')]").length, 1);
    assertEq("G6 XPath contains node predicate", L.RuleAnalyzer.extractString('<div class="author">作者：忘语</div><div class="count">字数：767</div>', "//div[contains(@class, 'author')]/text()"), '作者：忘语');
    const chapterPage = `<div id="allchapter"><dl><dd><a href="/chapter/one.html">第一章</a></dd><dd><a href="/chapter/two.html">第二章</a></dd></dl><a href="/chapter/full.html">查看全部章节 &gt;&gt;</a></div>`;
    const book = { bookUrl: 'https://www.sto66.com/book/demo.html' };
    const detail = L.LegadoEngine.parseBookInfo({ bookSourceUrl: 'https://www.sto66.com', ruleBookInfo: { tocUrl: "//*[@id='allchapter']//a[contains(text(), '查看全部章节')]/@href" } }, chapterPage, book.bookUrl, book);
    assertEq("G7 XPath contains(text()) detail URL", detail.tocUrl, 'https://www.sto66.com/chapter/full.html');
    const toc = L.LegadoEngine.parseToc({ bookSourceUrl: 'https://www.sto66.com', ruleToc: { chapterList: "//*[@id='allchapter']//dd[a]", chapterName: '@XPath:.//a/text()', chapterUrl: '@XPath:.//a/@href' } }, chapterPage, detail.tocUrl, book);
    assertEq("G8 XPath filtered chapter list", toc.chapters.length, 2);
    assertEq("G9 XPath chapter title", toc.chapters[0].title, '第一章');
    assertEq("G10 XPath chapter URL", toc.chapters[0].url, 'https://www.sto66.com/chapter/one.html');
    const htmlContent = `<div id="content"><p>第一段正文</p><p>第二段正文</p></div>`;
    const content = L.LegadoEngine.parseContent({ bookSourceUrl: 'https://www.sto66.com', ruleContent: { content: "//*[@id='content']/p/text()" } }, htmlContent, toc.chapters[0].url);
    assertEq("G11 XPath chapter body", content.content, '第一段正文\n第二段正文');
}
