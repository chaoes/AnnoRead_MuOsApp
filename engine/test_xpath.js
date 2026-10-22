import './legado.js';
const L = globalThis.Legado;

function assert(condition, message) {
    if (!condition) throw new Error("Assertion Failed: " + message);
}

console.log("=== Testing XPath 1.0 Integration ===");

const html = `
<div class="novel">
    <h1 class="title">完美世界</h1>
    <div class="meta">
        <span property="author">辰东</span>
    </div>
    <div class="chapters">
        <a href="/c1.html">第1章</a>
        <a href="/c2.html">第2章</a>
    </div>
</div>
`;

// 1. Text extraction by class attribute predicate
const title = L.RuleAnalyzer.extractString(html, '//*[@class="title"]/text()');
console.log("title extracted:", title);
assert(title === "完美世界", "XPath title failed: " + title);

// 2. Attribute extraction by property predicate
const author = L.RuleAnalyzer.extractString(html, '//span[@property="author"]/text()');
console.log("author extracted:", author);
assert(author === "辰东", "XPath author failed: " + author);

// 3. List extraction with attribute
const list = L.RuleAnalyzer.extractList(html, '//div[@class="chapters"]/a/@href');
console.log("list length:", list.length);
assert(list.length === 2, "XPath list length failed: " + list.length);
assert(list[0] === "/c1.html" || (list[0].attr && list[0].attr('href') === "/c1.html"), "XPath item 1 failed");

// 4. @XPath: prefix compatibility
const titlePrefixed = L.RuleAnalyzer.extractString(html, '@XPath://h1/text()');
assert(titlePrefixed === "完美世界", "@XPath: prefix failed: " + titlePrefixed);

// 5. XML / EPUB Namespace support (e.g. fb:title or opf:meta)
const xml = `<package><metadata><dc:creator>爱潜水的乌贼</dc:creator></metadata></package>`;
const creator = L.RuleAnalyzer.extractString(xml, '//dc:creator/text()');
assert(creator === "爱潜水的乌贼", "Namespace tag failed: " + creator);

// 6. Direct child / vs descendant // distinction
const nested = `<div class="box"><p><a href="/inner">内</a></p><a href="/direct">直</a></div>`;
const directList = L.RuleAnalyzer.extractList(nested, '//div[@class="box"]/a/@href');
assert(directList.length === 1 && directList[0] === "/direct", "Direct child / should only match direct children");

// 7. Malformed predicate safely returns empty rather than matching all nodes
const malformed = L.RuleAnalyzer.extractList(html, '//[[bad-syntax');
assert(malformed.length === 0, "Malformed XPath should return empty, got " + malformed.length);

console.log("✔ All XPath tests passed successfully!");
