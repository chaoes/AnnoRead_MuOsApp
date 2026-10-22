package.path = package.path .. ";./src/?.lua"

local legado = require("legado")

print("=== Running Love2D Legado Engine Unit Tests ===")

local ok = legado.init()
assert(ok, "Legado engine init failed")

-- Test evaluate expression
local eval_val = legado.eval("JSON.stringify({ status: 'ok', engine: 'QuickJS' })")
assert(eval_val:find('"status":"ok"'), "Eval json failed")

-- Test BookSource Parsing
local raw_source = [[
[
  {
    "bookSourceName": "全宇宙书库",
    "bookSourceUrl": "https://universe.books.com",
    "ruleSearch": {
      "bookList": ".item",
      "name": ".title@text",
      "author": ".author@text"
    }
  }
]
]]
local sources = legado.parseSources(raw_source)
assert(sources:find("全宇宙书库"), "Source name parsing failed")

-- Test Content Clean
local content_source = [[
{
  "bookSourceUrl": "https://universe.books.com",
  "ruleContent": {
    "content": "#content@html",
    "replaceRegex": "##欢迎访问.*##"
  }
}
]]
local sample_html = [[
<div id="content">
  <p>银河历 4000 年，人类步入深空。</p>
  <p>欢迎访问 全宇宙书库 官方网站！</p>
  <p>在遥远的猎户座旋臂上...</p>
</div>
]]
local parsed_content = legado.parseContent(content_source, sample_html)
local content_text = type(parsed_content) == "table" and parsed_content.content or parsed_content
assert(content_text:find("银河历 4000 年"), "Content text missing")
assert(not content_text:find("欢迎访问"), "replaceRegex failed to clean advertisement")

-- Task 11 tests:
local json = require("json")
local aes = require("aes")
legado.register_callbacks()

-- createSymmetricCrypto 经 Lua 回调应产出与 openssl 一致的密文
local enc = legado.eval([[
  String(java.createSymmetricCrypto('AES/CBC/PKCS5Padding',
    'CjsVDGnRIcj7IPG7Bec7V8hZFtp87DII','3126252674073386').encryptBase64('{"id":"0RNQ","page":2}'))
]])
assert(enc == 'vWCsZu9q24/ymkS98AmmbwybPd7g0tm7zEYOmab42X8=', "crypto mismatch: " .. enc)

-- ajax 失败必须降级为空串而非崩溃（Review Focus）
local empty = legado.eval([[ String(java.ajax('http://127.0.0.1:1/nope', 2000)) ]])
assert(empty == '', "ajax 失败应返回空串, got: " .. empty)

-- parseToc 结构
local src_json = json.encode({ bookSourceUrl = "https://x", ruleToc = { chapterList = "tag.a", chapterName = "text", chapterUrl = "href" } })
local toc_html = '<a href="/1">第1章</a><a href="/2">第2章</a>'
local toc = legado.parseToc(src_json, toc_html, "https://x/")
assert(type(toc) == "table" and toc.chapters and #toc.chapters == 2, "parseToc.chapters missing")

print("✔ All Love2D Legado Engine unit tests passed successfully!")
