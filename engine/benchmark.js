import './legado.js';

console.log("=== Performance Benchmark for Legado QuickJS Engine ===");

// 1. Generate 1000 book search items HTML
let mockSearchHtml = '<div class="results">';
for (let i = 0; i < 500; i++) {
    mockSearchHtml += `
    <div class="book-card">
        <h3 class="title"><a href="/book/${i}">第 ${i} 本书·玄幻长篇（校对版）</a></h3>
        <span class="author">作者${i % 20}</span>
        <span class="cat">玄幻奇幻</span>
        <p class="intro">这是第 ${i} 本书的详细内容简介，长篇宏大叙事...</p>
        <span class="latest">第 999 章 最终决战</span>
    </div>`;
}
mockSearchHtml += '</div>';

const source = {
    bookSourceUrl: "https://novel.test",
    bookSourceName: "基准测试源",
    ruleSearch: {
        bookList: "div.book-card",
        name: "h3.title@text##（.*）##",
        author: "span.author@text",
        bookUrl: "h3.title a@href",
        kind: "span.cat@text",
        intro: "p.intro@text",
        lastChapter: "span.latest@text"
    }
};

const t0 = Date.now();
const books = Legado.LegadoEngine.parseSearchResult(source, mockSearchHtml);
const t1 = Date.now();

console.log(`Parsed ${books.length} book cards in ${t1 - t0} ms!`);
console.log(`Average time per book: ${((t1 - t0) / books.length).toFixed(4)} ms`);
console.log("Sample parsed item:", JSON.stringify(books[0]));

// 2. Benchmark 2000 chapters TOC
let mockTocHtml = '<ul class="chapter-list">';
for (let i = 0; i < 2000; i++) {
    mockTocHtml += `<li><a href="/chap/${i}.html">第 ${i} 章 天地玄黄 宇宙洪荒</a></li>`;
}
mockTocHtml += '</ul>';

const tocSource = {
    bookSourceUrl: "https://novel.test/book/1/",
    ruleToc: {
        chapterList: "ul.chapter-list li a",
        chapterName: "text",
        chapterUrl: "href"
    }
};

const t2 = Date.now();
const chapters = Legado.LegadoEngine.parseToc(tocSource, mockTocHtml).chapters;
const t3 = Date.now();

console.log(`Parsed ${chapters.length} chapters TOC in ${t3 - t2} ms!`);
console.log(`Average time per chapter: ${((t3 - t2) / chapters.length).toFixed(4)} ms`);
console.log("Sample parsed chapter:", JSON.stringify(chapters[0]));
