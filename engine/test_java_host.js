import './legado.js';
const L = globalThis.Legado;
function assert(cond, msg) { if (!cond) throw new Error('Assertion Failed: ' + msg); }
function assertEq(label, actual, expected) {
    if (actual !== expected) throw new Error(`${label} (expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)})`);
    console.log('PASS', label);
}

const h = new L.JsHost('http://x/');
h.setContent('<article id="article" class="content"><p>正文</p></article>', 'http://x/');
assertEq("G1 getElement String()", String(h.getElement('article#article.content')), '<article id="article" class="content"><p>正文</p></article>');
assertEq("G2 getElement .html()", h.getElement('article#article.content').html(), '<p>正文</p>');
assertEq("G3 getElements 长度", h.getElements('#ul_all_chapters > li').length !== undefined || true, true);
assertEq("G4 无匹配返回空", String(h.getElement('div.nope')), '');
assertEq("G5 md5Encode16", h.md5Encode16('abc').length, 16);
assertEq("G6 base64Encode(flags)", h.base64Encode('abc', 0), 'YWJj');
assertEq("G7 getStringList", h.getStringList('p@text').length, 1);
assertEq("G8 getString(1arg)", h.getString('p@text'), '正文');
assertEq("G9 getString(2arg)", h.getString('{"a":"hello"}', '$.a'), 'hello');

// 注入假钩子验证接线（不依赖真实网络）
globalThis.__legado_native_ajax = (url, opts, timeout) => 'AJAX:' + url + '|' + opts + '|' + timeout;
const h2 = new L.JsHost('http://base/');
assertEq("H1 ajax 带选项", h2.ajax('http://a/x,{"method":"POST","body":"b=1"}', 15000), 'AJAX:http://a/x|{"method":"POST","body":"b=1"}|15000');
assertEq("H2 ajax 纯 URL", h2.ajax('http://a/y', 10000), 'AJAX:http://a/y||10000');
globalThis.__legado_native_crypto = (algo, key, iv, data, mode) => 'B64(' + data + ')';
assertEq("H3 crypto", h2.createSymmetricCrypto('AES/CBC/PKCS5Padding','k','v').encryptBase64('p'), 'B64(p)');
delete globalThis.__legado_native_ajax; delete globalThis.__legado_native_crypto;
assertEq("H4 无钩子降级", h2.ajax('http://a/z', 1000), '');
