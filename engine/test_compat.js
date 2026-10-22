// Executed by test_compat_native.c inside the real QuickJS C bridge.
(() => {
    const L = Legado;
    const assert = (ok, message) => { if (!ok) throw new Error(message); };

    const urlScript = {bookSourceUrl: 'https://t.test',
        searchUrl: '@js: let u=baseUrl + "/s?q=" + encodeURIComponent(key); u'};
    assert(L.LegadoEngine.buildSearchRequest(urlScript, 'a b', 1).url ===
        'https://t.test/s?q=a%20b', '@js statement URL result');

    const imported = L.LegadoEngine.parseBookSources(JSON.stringify([{
        bookSourceUrl: 'https://a.test', bookSourceName: 'A',
        jsLib: 'function make(k) { function localOnly() { return 1; } return "/x?" + k; }',
        extraField: 7
    }]))[0];
    assert(imported.extraField === 7 && imported.jsLib.includes('function make'),
        'source import must preserve unknown fields and jsLib');
    const libReq = L.LegadoEngine.buildSearchRequest(
        Object.assign(imported, {searchUrl: '{{make(key)}}'}), 'ok', 1);
    assert(libReq.url === 'https://a.test/x?ok', 'source jsLib function call');

    const stateA = {bookSourceUrl: 'https://state-a.test',
        searchUrl: '@js: java.put("k", "A"); cache.put("cacheKey", "C"); source.setVariable("slot"); baseUrl'};
    const stateB = {bookSourceUrl: 'https://state-b.test',
        searchUrl: '@js: java.get("k") || cache.get("cacheKey") || "empty"'};
    L.LegadoEngine.buildSearchRequest(stateA, '', 1);
    assert(L.LegadoEngine.buildSearchRequest(stateB, '', 1).url ===
        'https://state-b.test/empty', 'state must be isolated by source');
    assert(L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://state-a.test',
        searchUrl: '@js: source.getVariable()'}, '', 1).url ===
        'https://state-a.test/slot', 'source variable slot persists between stages');

    const jsonSource = {bookSourceUrl: 'https://j.test', ruleSearch: {
        bookList: '.data[*]', name: 'novelName', author: 'authorName', bookUrl: 'url'}};
    const rows = L.LegadoEngine.parseSearchResult(jsonSource,
        JSON.stringify({data: [{novelName: '剑来', authorName: '烽火戏诸侯', url: '/book/1'}]}));
    assert(rows.length === 1 && rows[0].name === '剑来' && rows[0].author === '烽火戏诸侯' &&
        rows[0].bookUrl === 'https://j.test/book/1', 'JSON data[*] object fields and URL resolution');

    const optionsReq = L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://o.test',
        searchUrl: '@js: ({url:baseUrl+"/search",method:"POST",body:{q:key}})'}, 'abc', 1);
    assert(optionsReq.url === 'https://o.test/search' && optionsReq.method === 'POST' &&
        optionsReq.body === '{"q":"abc"}', 'object request options follow formatRequest');
    const dataUriReq = L.LegadoEngine.formatRequest('https://data.test',
        'data:;base64,YQ==,{"type":"聆听月与悦"}');
    assert(dataUriReq.url === 'data:;base64,YQ==' && dataUriReq.type === '聆听月与悦',
        'data URI request stays absolute and preserves response type option');
    assert(L.resolveUrl('https://data.test/path', 'data:text/plain,hello') ===
        'data:text/plain,hello', 'data scheme is absolute during URL resolution');

    const previousCryptoCallback = globalThis.__legado_native_crypto;
    let cryptoArgs = null;
    globalThis.__legado_native_crypto = (algo, key, iv, data, mode) => {
        cryptoArgs = [algo, key, iv, data, mode];
        return 'fixture plaintext';
    };
    const aesVector = new L.JsHost('https://crypto.test').aesBase64DecodeToString(
        'dkmrrIEZskbO6Y6bEukZfQ==', '2b7e151628aed2a6abf7158809cf4f3c',
        'AES/CBC/PKCS5Padding', '000102030405060708090a0b0c0d0e0f');
    assert(aesVector === 'fixture plaintext' && cryptoArgs[0] === 'AES/CBC/PKCS5Padding' &&
        cryptoArgs[1] === '2b7e151628aed2a6abf7158809cf4f3c' &&
        cryptoArgs[2] === '000102030405060708090a0b0c0d0e0f' &&
        cryptoArgs[3] === 'dkmrrIEZskbO6Y6bEukZfQ==' && cryptoArgs[4] === 1,
        'AES-CBC known vector maps Base64 ciphertext/key/IV to native decrypt mode');
    let unsupportedCipherDiagnosed = false;
    try { new L.JsHost('https://crypto.test').aesBase64DecodeToString('x', 'k', 'AES/ECB/NoPadding', 'v'); }
    catch (e) { unsupportedCipherDiagnosed = /unsupported algorithm/.test(e.message); }
    assert(unsupportedCipherDiagnosed, 'unsupported AES algorithm is diagnosed');
    if (previousCryptoCallback === undefined) delete globalThis.__legado_native_crypto;
    else globalThis.__legado_native_crypto = previousCryptoCallback;
    assert(new L.JsHost('https://hex.test').hexDecodeToString('e88186e590ace69c88e4b88ee682a6') ===
        '聆听月与悦', 'hexDecodeToString decodes UTF-8 multibyte text');
    let invalidHexDiagnosed = false;
    try { new L.JsHost('https://hex.test').hexDecodeToString('e8ff'); }
    catch (e) { invalidHexDiagnosed = /invalid UTF-8/.test(e.message); }
    assert(invalidHexDiagnosed, 'hexDecodeToString rejects invalid UTF-8 rather than mojibake');

    let requestCount = 0, receivedUrl = '', receivedOpts = '';
    globalThis.__legado_native_ajax = (url, opts) => {
        requestCount++; receivedUrl = url; receivedOpts = opts;
        return JSON.stringify({body: 'ok', status: 200, final_url: url + '?redirected', headers: {}, error: null});
    };
    const rawUrl = new L.JsHost('https://connect.test').connect('/path,{"method":"POST"}')
        .raw().request().url();
    assert(rawUrl === 'https://connect.test/path?redirected' && requestCount === 1 &&
        JSON.parse(receivedOpts).method === 'POST' && JSON.parse(receivedOpts)._legado_response_meta === true,
        'connect.raw executes once with metadata and inline options');

    L.clearScriptDiagnostics();
    let sideEffectCount = 0;
    globalThis.__compatCount = () => ++sideEffectCount;
    const completionReq = L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://completion.test',
        searchUrl: '@js: __compatCount(); (()=>{ return baseUrl + "/done"; })()'}, '', 1);
    assert(completionReq.url === 'https://completion.test/done' && sideEffectCount === 1,
        'Program completion preserves trailing IIFE and prior setup runs once');
    sideEffectCount = 0;
    const callResult = L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://call.test',
        searchUrl: '@js: __compatCount()'}, '', 1);
    assert(sideEffectCount === 1 && callResult.url === 'https://call.test/1',
        'trailing function call side effect executes once');
    if (typeof globalThis.__legado_can_eval_program === 'function') {
        sideEffectCount = 0;
        const returnReq = L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://return.test',
            searchUrl: '@js: __compatCount(); return baseUrl + "/returned"'}, '', 1);
        assert(returnReq.url === 'https://return.test/returned' && sideEffectCount === 1,
            'function-body return path executes once');
    }
    sideEffectCount = 0;
    L.clearScriptDiagnostics();
    const failed = L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://e.test',
        searchUrl: '@js: __compatCount(); throw new Error("expected");'}, '', 1);
    assert(sideEffectCount === 1 && L.getScriptDiagnostics().length > 0,
        'failed JS is executed once and diagnosed');
    const undefinedReq = L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://u.test',
        searchUrl: '@js: void 0'}, '', 1);
    assert(undefinedReq.url === '', 'undefined script result has deterministic empty URL');

    L.clearScriptDiagnostics();
    L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://unknown.test',
        searchUrl: '@js: java.methodThatDoesNotExist()'}, '', 1);
    assert(L.getScriptDiagnostics().length > 0, 'unknown host API has a diagnostic');

    sideEffectCount = 0;
    const jsTemplateResult = L.RuleAnalyzer.extractString({id: 7},
        "<js>__compatCount(); 'id={{$.id}}';</js>", 'https://template.test');
    assert(jsTemplateResult === 'id=7' && sideEffectCount === 1,
        'template inside JS executes once and returns its completion value');
    const braceExpression = L.RuleAnalyzer.extractString('not-a-selector',
        "@js: ({key: 'value'}).key", 'https://template.test');
    assert(braceExpression === 'value', 'ordinary JS object braces are not treated as templates');
    const htmlReplaceExpr = L.RuleAnalyzer.extractString('<p>abc</p>',
        "@js: 'abc'.replace(/a/, 'x')", 'https://template.test');
    assert(htmlReplaceExpr === 'xbc', 'valid html.replace-style JS expressions are not rewritten');
    L.LegadoEngine.buildSearchRequest({bookSourceUrl: 'https://hash.test',
        searchUrl: '@js: java.digest("SHA-256", "x")'}, '', 1);
    assert(L.getScriptDiagnostics().length > 1, 'unsupported digest is diagnosed, not faked');

    const html = '<div class="x">ok</div>';
    assert(L.RuleAnalyzer.extractString(html, '@css:.x@text') === 'ok', 'CSS remains available');
    assert(L.RuleAnalyzer.extractString('<p>v</p>', '//p/text()') === 'v', 'XPath remains available');
    assert(L.RuleAnalyzer.extractList('{"a":[1,2]}', '$.a[*]').length === 2, 'JSONPath remains available');

    let prefixScriptCount = 0;
    globalThis.__compatCount = () => ++prefixScriptCount;
    const chainedList = L.RuleAnalyzer.extractList('{"data":[{"id":1},{"id":2}]}',
        '$.data[*]\n<js>__compatCount(); result;</js>');
    assert(chainedList.length === 2 && prefixScriptCount === 1,
        'JSONPath list prefix flows through one JS suffix without scalarizing the array');

    const catalogItems = Array.from({length: 909}, (_, i) => ({
        title: 'fixture chapter ' + (i + 1), item_id: String(100000 + i), version: 'fixture-v1'
    }));
    const source2ChapterList = '$.data.item_data_list\n<js>\nfqUse(java, source, cache);\n' +
        "var md = fqModeName(fqGet('mode') || '小说');\n" +
        "book.type = (md === '漫画') ? 64 : 8;\nresult;\n</js>";
    const source2Fixture = {
        bookSourceUrl: 'https://fq.test',
        jsLib: 'function fqUse(){ globalThis.__compatCount(); } function fqModeName(v){ return v; } function fqGet(){ return "小说"; }',
        ruleBookInfo: {name: '$.name', author: '$.author'},
        ruleToc: {chapterList: source2ChapterList, chapterName: '$.title', chapterUrl: '$.item_id'}
    };
    L.LegadoEngine.parseBookInfo(source2Fixture, JSON.stringify({name: 'fixture book', author: 'fixture author'}));
    const source2Toc = L.LegadoEngine.parseToc(source2Fixture,
        JSON.stringify({data: {item_data_list: catalogItems}}), 'https://fq.test/catalog?book_id=fixture');
    assert(source2Toc.chapters.length === 909 && source2Toc.chapters[0].title === 'fixture chapter 1' &&
        source2Toc.chapters[908].title === 'fixture chapter 909' &&
        prefixScriptCount === 2,
        'source #2 original JSONPath-then-JS chapter-list rule parses 909 items and runs its suffix once');
    const bookContextProbe = Object.assign({}, source2Fixture, {ruleToc: {
        chapterList: '$.data.item_data_list[0]',
        chapterName: '@js: book.name + ":" + JSON.parse(result).title', chapterUrl: '$.item_id'
    }});
    const bookContextToc = L.LegadoEngine.parseToc(bookContextProbe,
        JSON.stringify({data: {item_data_list: [catalogItems[0]]}}), 'https://fq.test/catalog');
    assert(bookContextToc.chapters.length === 1 &&
        bookContextToc.chapters[0].title === 'fixture book:fixture chapter 1',
        'book metadata from parseBookInfo persists into parseToc without a book argument');
    assert(L.RuleAnalyzer.extractString(':author\"xx\"辰东', '##:author\\\"[^\\\"]+\\\"([^\\\"]*)##$1###') === '辰东', 'Regex remains available');
    const replaceResult = L.RuleAnalyzer.extractString('foo foo',
        '<js>let html = result; html = html.replace(/foo/g, "bar"); html;</js>');
    assert(replaceResult === 'bar bar', 'html.replace preserves arbitrary valid rule expressions');

    // Source #8's original JS->JSONPath chain. The HTTP callback is a deterministic
    // API-shaped fixture so this exercises the normal Java.ajax path offline.
    let source8AjaxUrl = '';
    globalThis.__legado_native_ajax = (url, opts) => {
        source8AjaxUrl = String(url);
        return JSON.stringify({data: [{novelName: '中文作品', authorName: '测试作者',
            novelId: 'fixture-1', cover: '', summary: '', wordNum: 123}]});
    };
    const source8 = {bookSourceUrl: 'http://api.myweipin.com', searchUrl: "<js>\nvar baseVariable = JSON.stringify({\n\tsourceType: \"first\",\n\tsourceName: \"🐈猫眼①\",\n\tsourceAPI: \"http://api.myweipin.com\"\n}, null, \"\\t\");\nlet Variable = source.getVariable();\nif ( Variable == null || Variable == undefined || Variable == \"\" ) {\n\t   source.setVariable(baseVariable);\n\t   java.toast(\"初始化成功！\");\n\t}\n\t\nvar key = java.base64Encode(key);\nvar data = {\n\ttype: \"聆听月与悦\"\n\t}\nvar type = JSON.stringify(data);\nvar search_url = `data:;base64,${key},${type}`;\njava.put(\"page\", page);\njava.toast(\"请稍等，正在搜索中！\");\nsearch_url\n</js>",
        ruleSearch: {bookList: "<js>\nvar search_key = java.hexDecodeToString(result);\nvar search_page = java.get(\"page\");\nif (source.getVariable()!=\"\"&&source.getVariable()!=undefined) {\n     var Variable = JSON.parse(source.getVariable());\n     var api = Variable.sourceAPI;\n} else {\n\t    var Variable = \"\";\n}\nvar search_api = api || source.getKey();\nvar search_url = search_api + \"/search?keyword=\" + search_key + \"&page=\" + search_page;\nvar result = java.ajax(search_url);\nif (result !== \"\" && result !== null) {\n    java.toast(\"搜索成功！\");\n    try {\n        var data = JSON.parse(result);\n        var name = data.data[0].novelName;\n\n        if (java.get(\"key\") == name) {\n            java.toast(\"书籍匹配成功！\");\n        } else {\n            java.toast(\"抱歉，没有找到您想要的书籍！\");\n        }\n    } catch (error) {\n        java.toast(\"解析结果时出错: \" + error.message);\n    }\n} else {\n    java.toast(\"抱歉，搜索失败！\");\n}\nresult\n</js>\n$.data[*]", name: '$.novelName', author: '$.authorName'}};
    const source8Request = L.LegadoEngine.buildSearchRequest(source8, '中文', 2);
    const source8Rows = L.LegadoEngine.parseSearchResult(source8, 'e4b8ade69687');
    assert(source8Request.url.startsWith('data:;base64,') &&
        source8AjaxUrl === 'http://api.myweipin.com/search?keyword=中文&page=2' &&
        source8Rows.length === 1 && source8Rows[0].name === '中文作品' &&
        source8Rows[0].author === '测试作者',
        'source #8 original JS bookList followed by $.data[*] parses HTTP JSON fixture');

    const initSource = {bookSourceUrl: 'https://init.test', ruleBookInfo: {
        init: '<js>var data=JSON.parse(result); result=JSON.stringify({name:data.book_name,author:data.author,tocUrl:data.toc_url}); result;</js>',
        name: '$.name', author: '$.author', tocUrl: '$.tocUrl'}};
    const initializedBook = L.LegadoEngine.parseBookInfo(initSource,
        JSON.stringify({book_name: '初始化作品', author: '作者乙', toc_url: '/toc/1'}));
    assert(initializedBook.name === '初始化作品' && initializedBook.author === '作者乙' &&
        initializedBook.tocUrl === 'https://init.test/toc/1',
        'book info JS init transforms source JSON before field extraction');

    const putInitSource = {bookSourceUrl: 'https://put-init.test', ruleBookInfo: {
        init: '@put:{n:"[property$=book_name]@content",\n a:"[property$=author]@content",\n k:"[property~=category]@content"}',
        name: '@get:{n}', author: '@get:{a}', kind: '@get:{k}'}};
    const putInitBook = L.LegadoEngine.parseBookInfo(putInitSource,
        '<meta property="book_name" content="多键初始化作品"><meta property="author" content="作者丙"><meta property="category" content="玄幻">');
    assert(putInitBook.name === '多键初始化作品' && putInitBook.author === '作者丙' &&
        putInitBook.kind === '玄幻', 'multi-key @put init values are available to later book fields');

    const templatedRule = '/novel/{{$.novelId}}/chapters,' +
        JSON.stringify({headers: JSON.stringify({'X-Test': 'yes'})});
    const templatedUrl = L.RuleAnalyzer.extractString({novelId: 'id-1'},
        templatedRule, 'https://book.test');
    const templatedReq = L.LegadoEngine.formatRequest('https://book.test', templatedUrl);
    assert(templatedReq.url === 'https://book.test/novel/id-1/chapters' &&
        templatedReq.headers['X-Test'] === 'yes',
        'JSONPath URL templates and stringified inline headers survive request formatting');

    const source6 = {bookSourceUrl: 'https://source6.test', ruleSearch: {
        bookList: '$.data[*]', name: '$.novelName',
        bookUrl: '@js: var headers={"X-Source":"ok"}; "/novel/{{$.novelId}}/chapters,"+java.put("headers",JSON.stringify({headers:headers}))'}};
    const source6Rows = L.LegadoEngine.parseSearchResult(source6,
        JSON.stringify({data: [{novelName: '模板作品', novelId: 'id-6'}]}));
    const source6Req = L.LegadoEngine.formatRequest(source6.bookSourceUrl, source6Rows[0].bookUrl);
    assert(source6Req.url === 'https://source6.test/novel/id-6/chapters' &&
        source6Req.headers['X-Source'] === 'ok',
        'source #6 JS URL template retains and formats inline headers');

    const source3 = {bookSourceUrl: 'https://deqi.test', ruleSearch: {
        bookList: "<js>var d = [];\nvar doc = org.jsoup.Jsoup.parse(result, baseUrl);\nif (doc.select('.bookbox').size() > 0) {\n    d = doc.select('.bookbox');\n} else {\n    var name = doc.select('h1.booktitle').text();\n    if (name) {\n        var url = doc.select('link[rel=canonical]').attr('href') || doc.select('meta[property=og:novel:read_url]').attr('content');\n        var author = doc.select('.booktag a').first().text();\n        var last = doc.select('.bookchapter').text();\n        var frag = '<div class=\"bookbox\"><h4 class=\"bookname\"><a href=\"' + url + '\">' + name + '</a></h4><div class=\"author\">作者：' + author + '</div><div class=\"cat\"><a>' + last + '</a></div></div>';\n        d = org.jsoup.Jsoup.parseBodyFragment(frag).select('.bookbox');\n    }\n}\nd;</js>",
        name: 'class.bookname@tag.a@text', author: 'class.author.0@text##作者：',
        bookUrl: 'class.bookname@tag.a@href', lastChapter: 'class.cat@tag.a@text'}};
    const source3Rows = L.LegadoEngine.parseSearchResult(source3,
        '<h1 class="booktitle">JSoup映射作品</h1><link rel="canonical" href="https://deqi.test/book/1"><div class="booktag"><a>作者丁</a></div><div class="bookchapter">最新章节</div>');
    assert(source3Rows.length === 1 && source3Rows[0].name === 'JSoup映射作品' &&
        source3Rows[0].author === '作者丁' && source3Rows[0].bookUrl === 'https://deqi.test/book/1',
        'source #3 original Jsoup selector methods map through supported DOM adapter');

    const source12ReadLink = '<div><a class="btnlink b_hot mbs" href="http://read.test/toc/1">点击阅读</a></div>';
    assert(L.RuleAnalyzer.extractString(source12ReadLink, 'text.点击阅读@href', 'https://detail.test/book/1') ===
        'http://read.test/toc/1', 'source #12 text label selects its linked href');

    const source22Card = '<li><a href="/book/1">阅读</a><div class="info"><span>《测试作品》</span><span>作者甲</span><span><a>分类</a></span></div></li>';
    assert(L.RuleAnalyzer.extractString(source22Card, '.info span:nth-child(1)@text ##.*《|》.*') === '测试作品',
        'source #22 nth-child name selector and cleanup');
    assert(L.RuleAnalyzer.extractString(source22Card, 'a:nth-child(1)@href', 'https://list.test/search') ===
        'https://list.test/book/1', 'nth-child link selector extracts first anchor');

    const aliasInput = 'cached listing';
    const aliasRule = '<js>if (/No message|404/.test(src)) { result = "bad"; } else { result = src; } result;</js>';
    assert(L.RuleAnalyzer.extractString(aliasInput, aliasRule) === aliasInput,
        'source #21 src alias matches result in JS rule context');
    const chainedAlias = '<js>result = src; result;</js>\n$.data||$';
    const chainedValue = L.RuleAnalyzer.extractString(
        JSON.stringify({data: [{novelName: 'source 21 fixture'}]}), chainedAlias);
    assert(chainedValue.includes('source 21 fixture'),
        'source #21 JS result continues through trailing JSONPath fallback');

    // CookieStore & cookie.getCookie / java.getCookie compatibility
    const cs = new L.CookieStore();
    cs.setCookie('https://www.mowan.lol', 'X-Device-ID=dev123; Authorization=auth456; Path=/; HttpOnly');
    assert(cs.getCookie('https://www.mowan.lol/api/search').includes('X-Device-ID=dev123'),
        'CookieStore domain matching and cookie serialization');
    assert(cs.getKey('https://www.mowan.lol', 'X-Device-ID') === 'dev123',
        'CookieStore.getKey retrieves specific cookie key');

    const mowanSrc = {
        bookSourceUrl: 'https://www.mowan.lol',
        header: JSON.stringify({ Cookie: 'X-Device-ID=mdev; Authorization=mauth' }),
        jsLib: `let mw="https://www.mowan.lol";
function getCookie(k){
    let{java,cookie}=this;
    let cookieValue=String(cookie.getCookie(mw))||String(java.getCookie(mw));
    let parts=cookieValue.split(";");
    for(let i=0;i<parts.length;i++){
        let part=parts[i].trim();
        let idx=part.indexOf(k+"=");
        if(idx===0){return part.substring(k.length+1)}
    }
    return""
}
function Api(url){
    let XDeviceID=this.getCookie('X-Device-ID');
    let Authorization=this.getCookie('Authorization');
    return mw+url+','+JSON.stringify({headers:JSON.stringify({'Authorization':Authorization,'X-Device-ID':XDeviceID})});
}`,
        searchUrl: '{{Api("/api/search?keyword=" + encodeURIComponent(key))}}',
        ruleSearch: {
            bookList: '$.data.items[*]',
            name: '$.name',
            author: '$.author',
            bookUrl: '/api/book/detail?source={{$.source}}&book_id={{$.id}}\n<js>\n`data:;base64,${java.base64Encode(result)},{"type":"mw"}`\n</js>'
        }
    };

    const mowanSearchReq = L.LegadoEngine.buildSearchRequest(mowanSrc, '完美人生', 1);
    assert(mowanSearchReq.url.includes('/api/search?keyword='),
        'mowan searchUrl generated via jsLib Api() call');
    assert(mowanSearchReq.headers['X-Device-ID'] === 'mdev' && mowanSearchReq.headers['Authorization'] === 'mauth',
        'mowan headers extracted from cookie.getCookie via getCookie(k)');

    const mowanParsed = L.LegadoEngine.parseSearchResult(mowanSrc, JSON.stringify({
        data: {
            items: [
                { name: '完美人生', author: '某作者', id: '1001', source: 'qidian' }
            ]
        }
    }), 'https://www.mowan.lol');
    assert(mowanParsed.length === 1 && mowanParsed[0].name === '完美人生',
        'mowan parseSearchResult parsed book');
    assert(mowanParsed[0].bookUrl.startsWith('data:;base64,'),
        'mowan ruleSearch.bookUrl evaluated URL template and base64 encoded into data URI');

    // Test Jsoup Elements and selectors compatibility
    const jsoupHtml = `
    <html><body>
        <div id="content" class="main-body book-container">
            <h1 class="title">测试书籍</h1>
            <ul class="list">
                <li class="item" data-id="101"><a href="/chap/1">第一章 序章</a></li>
                <li class="item" data-id="102"><a href="/chap/2">第二章 初入</a></li>
                <li class="item special" data-id="103"><a href="/chap/3">第三章 激战</a></li>
                <li class="item" data-id="104"><a href="/chap/4">第四章 终局</a></li>
            </ul>
            <div class="desc">
                <p>这是简短介绍。</p>
                <p class="extra">更多详情与版权信息</p>
            </div>
            <div class="authors">
                <span class="author-name">乌贼</span>
                <span class="author-tag">白金作家</span>
            </div>
        </div>
    </body></html>`;

    const doc = L.parseHTML(jsoupHtml);
    // 1. Selector slice [start:end]
    const sliced = doc.select('ul.list li[1:3]');
    assert(sliced.length === 2, 'li[1:3] slice should return 2 elements');
    assert(sliced[0].attr('data-id') === '102', 'first sliced element id 102');
    assert(sliced[1].attr('data-id') === '103', 'second sliced element id 103');

    // Negative slice [1:-1]
    const slicedNeg = doc.select('ul.list li[1:-1]');
    assert(slicedNeg.length === 2 && slicedNeg[0].attr('data-id') === '102' && slicedNeg[1].attr('data-id') === '103',
        'li[1:-1] slice returns elements excluding first and last');

    // Index selector [0] and negative index [-1]
    const firstLi = doc.select('ul.list li[0]');
    assert(firstLi.length === 1 && firstLi[0].attr('data-id') === '101', 'li[0] selects first item');
    const lastLi = doc.select('ul.list li[-1]');
    assert(lastLi.length === 1 && lastLi[0].attr('data-id') === '104', 'li[-1] selects last item');

    // Regex attribute selector [class~=]
    const regexSelected = doc.select('li[class~="special"]');
    assert(regexSelected.length === 1 && regexSelected[0].attr('data-id') === '103',
        'regex attribute selector [class~="special"] matches');

    // :contains and :matches
    const containLi = doc.select('li:contains(激战)');
    assert(containLi.length === 1 && containLi[0].attr('data-id') === '103', ':contains(激战) matches');
    const matchLi = doc.select('li:matches(第[一二]章)');
    assert(matchLi.length === 2, ':matches regex selector matches 2 items');

    // Combinator + and ~
    const adjacent = doc.select('li.special + li');
    assert(adjacent.length === 1 && adjacent[0].attr('data-id') === '104', 'adjacent sibling selector +');
    const siblings = doc.select('li[data-id="101"] ~ li');
    assert(siblings.length === 3, 'general sibling selector ~');

    // JsoupElements methods in sandbox
    const jsoupResult = L.evalLegadoScript(
        `let d = org.jsoup.Jsoup.parse(html);
         let items = d.select("ul.list li");
         let firstTitle = items.first().text();
         let lastId = items.last().attr("data-id");
         let subTexts = items.select("a").eachText();
         JSON.stringify({ size: items.size(), firstTitle, lastId, subTexts });`,
        jsoupHtml,
        'https://test.org',
        { html: jsoupHtml }
    );
    const parsedJsoupResult = JSON.parse(jsoupResult);
    assert(parsedJsoupResult.size === 4, 'JsoupElements.size() === 4');
    assert(parsedJsoupResult.firstTitle === '第一章 序章', 'JsoupElements.first().text()');
    assert(parsedJsoupResult.lastId === '104', 'JsoupElements.last().attr()');
    assert(parsedJsoupResult.subTexts.length === 4 && parsedJsoupResult.subTexts[2] === '第三章 激战', 'JsoupElements.eachText()');

    // 1. 亿软小说: [href~=/b/] regex attribute selector
    const yruanSrc = {
        bookSourceUrl: 'https://m.yruan.com',
        ruleToc: {
            chapterList: '.catalog ul li a[href~=/b/]',
            chapterName: 'text',
            chapterUrl: 'href'
        }
    };
    const yruanHtml = `
    <div class="catalog">
        <ul>
            <li><a href="/sort/1">按时间倒序</a></li>
            <li><a href="/b/100/1.html">第1章 惊变</a></li>
            <li><a href="/b/100/2.html">第2章 逃亡</a></li>
            <li><a href="/b/100/3.html">第3章 绝地</a></li>
            <li><a href="/manage/report">举报错误</a></li>
        </ul>
    </div>`;
    const yruanToc = L.LegadoEngine.parseToc(yruanSrc, yruanHtml, 'https://m.yruan.com/b/100/');
    assert(yruanToc.chapters && yruanToc.chapters.length === 3,
        'yruan .catalog ul li a[href~=/b/] extracts 3 chapters and filters out sort/report links');
    assert(yruanToc.chapters[0].title === '第1章 惊变' && yruanToc.chapters[0].url === 'https://m.yruan.com/b/100/1.html',
        'yruan chapter title and resolved url');

    // 2. 未来天王: .list-item[0:9] slice selector
    const wlreadSrc = {
        bookSourceUrl: 'https://m.wlread.com',
        ruleSearch: {
            bookList: '.list-item[0:2]',
            name: '.title@text',
            author: '.author@text',
            bookUrl: 'a@href'
        }
    };
    const wlreadHtml = `
    <div class="search-result">
        <div class="list-item"><span class="title">书A</span><span class="author">甲</span><a href="/b/1"></a></div>
        <div class="list-item"><span class="title">书B</span><span class="author">乙</span><a href="/b/2"></a></div>
        <div class="list-item"><span class="title">书C</span><span class="author">丙</span><a href="/b/3"></a></div>
        <div class="list-item"><span class="title">书D</span><span class="author">丁</span><a href="/b/4"></a></div>
    </div>`;
    const wlreadBooks = L.LegadoEngine.parseSearchResult(wlreadSrc, wlreadHtml, 'https://m.wlread.com');
    assert(wlreadBooks && wlreadBooks.length === 2,
        'wlread .list-item[0:2] slice extracts indices 0, 1 (2 books)');
    assert(wlreadBooks[0].name === '书A' && wlreadBooks[1].name === '书B',
        'wlread slice correctly maps books A, B');

    // 3. 永恒阁吧: java.getElements + d.attr / d.text
    const yonghengSrc = {
        bookSourceUrl: 'https://www.28003.com',
        ruleToc: {
            chapterList: `<js>
            doc = java.getElements(".section-box:eq(1) li a");
            list = [];
            for (i = 0; i < doc.length; i++) {
                d = doc[i];
                url = d.attr("href");
                title = d.text();
                list.push({title: title, url: url});
            }
            list;
            </js>`,
            chapterName: 'title',
            chapterUrl: 'url'
        }
    };
    const yonghengHtml = `
    <div class="content">
        <div class="section-box">
            <h3>最新章节</h3>
            <ul>
                <li><a href="/c/99">第99章 决战</a></li>
            </ul>
        </div>
        <div class="section-box">
            <h3>正文目录</h3>
            <ul>
                <li><a href="/c/1">第1章 起始</a></li>
                <li><a href="/c/2">第2章 旅途</a></li>
            </ul>
        </div>
    </div>`;
    const yonghengToc = L.LegadoEngine.parseToc(yonghengSrc, yonghengHtml, 'https://www.28003.com/book/50/');
    assert(yonghengToc.chapters && yonghengToc.chapters.length === 2,
        'yongheng java.getElements + d.attr + d.text successfully parses 2 chapters');
    assert(yonghengToc.chapters[0].title === '第1章 起始' && yonghengToc.chapters[0].url === 'https://www.28003.com/c/1',
        'yongheng chapter 1 parsed with title and url');

    return true;
})();
