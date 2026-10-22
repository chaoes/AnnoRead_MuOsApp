package.path = "./?.lua;./?/init.lua;" .. package.path
local http = require("src.http")
local transport = require("src.http_transport")
local json = require("src.json")
local base = os.getenv("ANNO_TEST_URL") or "http://127.0.0.1:18763"

local function check(ok, message)
    assert(ok, message)
end

local gzip = http.request_sync_result(base .. "/gzip", nil, 3)
check(gzip.status == 200 and gzip.body == "gzip 测试正文", "gzip response was not decoded")
check(gzip.headers["content-encoding"] == "gzip", "response headers missing")
local deflate = http.request_sync_result(base .. "/deflate", nil, 3)
check(deflate.status == 200 and deflate.body == "deflate payload", "deflate response was not decoded")
local redirect = http.request_sync_result(base .. "/redirect", nil, 3)
check(redirect.status == 200 and redirect.final_url == base .. "/gzip", "redirect metadata incorrect")
check(redirect.body == "gzip 测试正文", "redirect gzip body was not decoded")

local opts = {
    method = "POST",
    headers = { ["X-Test"] = "nested 'quote'", ["Content-Type"] = "application/json" },
    body = json.encode({ nested = { text = "a 'quoted' value", count = 3 } }),
}
local posted = http.request_sync_result(base .. "/echo", json.encode(opts), 3)
check(posted.status == 200, "POST status incorrect")
local response = json.decode(posted.body)
check(response.method == "POST", "POST method not preserved")
check(response.header == "nested 'quote'", "header quoting failed")
check(response.body == opts.body, "nested JSON body was altered")
local table_body = { nested = { text = "table body", count = 4 } }
local table_response = http.request_sync_result(base .. "/echo", json.encode({ method = "POST", body = table_body }), 3)
local table_echo = json.decode(table_response.body)
local decoded_table_body = table_echo and json.decode(table_echo.body)
check(decoded_table_body and decoded_table_body.nested and decoded_table_body.nested.text == "table body" and decoded_table_body.nested.count == 4,
    "table body must be JSON encoded without changing its structure")

local redirected_302 = http.request_sync_result(base .. "/redirect-post-302", json.encode(opts), 3)
check(redirected_302.status == 200, "302 POST redirect failed")
local after_302 = json.decode(redirected_302.body)
check(after_302.method == "GET" and after_302.body == "", "302 must convert POST to GET")
local redirected_307 = http.request_sync_result(base .. "/redirect-post-307", json.encode(opts), 3)
check(redirected_307.status == 200, "307 POST redirect failed")
local after_307 = json.decode(redirected_307.body)
check(after_307.method == "POST" and after_307.body == opts.body, "307 must preserve POST body")

local truncated = http.request_sync_result(base .. "/truncated", nil, 3)
check(truncated.error and truncated.curl_exit_code == 18, "truncated response must report curl exit 18")
check(http.request_sync(base .. "/truncated", nil, 3) == "", "failed transfer must not pass as a normal body")
local unavailable = http.request_sync_result("http://127.0.0.1:1/unavailable", nil, 3)
check(unavailable.error and unavailable.curl_exit_code == 7, "connection failure must report curl exit 7")
check(http.request_sync("http://127.0.0.1:1/unavailable", nil, 3) == "", "curl exit 7 must not pass as a normal body")
local text_data = http.request_sync_result("data:text/plain;charset=utf-8,%E4%B8%AD%E6%96%87", nil, 3)
check(text_data.body == "中文" and text_data.status == 200, "plain data URI must decode as UTF-8 text")
local b64_data = http.request_sync_result("data:text/plain;base64,6IGG5ZCs5pyI5LiO5oKm", nil, 3)
check(b64_data.body == "聆听月与悦", "base64 data URI must decode text")
local hex_data = http.request_sync_result("data:application/octet-stream;base64,AP9B", json.encode({ type = "聆听月与悦" }), 3)
check(hex_data.body == "00ff41", "non-null request type must return binary bytes as lowercase hex")
local binary_http = http.request_sync_result(base .. "/binary", json.encode({ type = "application/octet-stream" }), 3)
check(binary_http.body == "00ff410a", "non-null type must hex encode real HTTP bytes, including NUL and newline")
local inline_binary_http = http.request_sync_result(base .. "/binary, " .. json.encode({ type = "application/octet-stream" }), 3)
check(inline_binary_http.body == "00ff410a", "inline virtual type must hex encode real HTTP response bytes")

local inline_url = base .. "/echo, " .. json.encode({
    method = "POST",
    headers = json.encode({ ["X-Test"] = "inline header" }),
    body = "inline body",
})
local inline = http.request_sync_result(inline_url, nil, 3)
local inline_echo = json.decode(inline.body)
check(inline.status == 200 and inline_echo.method == "POST", "inline options POST method was not applied over default GET")
check(inline_echo.header == "inline header" and inline_echo.body == "inline body", "inline options header/body were lost")
local mixed = http.request_sync_result(inline_url, json.encode({ headers = { ["X-Test"] = "explicit header" } }), 3)
local mixed_echo = json.decode(mixed.body)
check(mixed_echo.method == "POST" and mixed_echo.header == "explicit header" and mixed_echo.body == "inline body",
    "explicit headers must override inline headers while default GET preserves inline method/body")
local comma_url = http.request_sync_result(base .. "/comma,a,b", nil, 3)
check(comma_url.body == "comma URL preserved", "ordinary comma URL must remain intact")

-- Love's worker evaluates this same module and request builder; check both use
-- the same compression and redirect behavior without requiring a Love runtime.
local command = transport.command({ url = base .. "/gzip" }, "headers.tmp")
check(command:find("%-%-compressed") ~= nil, "shared curl command lacks compression")
check(command:find("-L") ~= nil, "shared curl command lacks redirect handling")
local post_command = transport.command({ url = base .. "/echo", method = "POST", body = "payload" })
check(not post_command:find("-X", 1, true), "POST with a body must let curl apply redirect semantics")
local exit7 = transport.parse_output("\n__ANNO_HTTP_META__000\nhttp://127.0.0.1:1/\n7\nconnection refused", "", true, 0)
check(exit7.error and exit7.curl_exit_code == 7, "explicit curl exit code must override LuaJIT close() status")

-- Replay the actual Love worker source with fake channels. Requests still use
-- real curl against the local fixture; this exercises callback delivery and
-- the worker's error-to-empty-string behavior without a Love window.
local worker
local function new_channel()
    local channel = { queue = {} }
    function channel:push(item) self.queue[#self.queue + 1] = item end
    function channel:pop() return table.remove(self.queue, 1) end
    function channel:demand()
        while true do
            local item = self:pop()
            if item then return item end
            coroutine.yield()
        end
    end
    return channel
end
local channels = { http_req_channel = new_channel(), http_res_channel = new_channel() }
local fake_love = { thread = {} }
function fake_love.thread.getChannel(name)
    return channels[name]
end
function fake_love.thread.newThread(code)
    worker = { code = code }
    function worker:start()
        self.co = coroutine.create(function() assert(loadstring(self.code))() end)
    end
    return worker
end
-- Install the fake Love API before first async call so http creates its worker.
love = fake_love
local async_results = {}
local function run_worker_once()
    local ok, err = coroutine.resume(worker.co)
    check(ok, "Love worker failed: " .. tostring(err))
end
http.request_async({ url = base .. "/gzip", tag = "gzip-tag", payload = { key = "gzip-payload" } },
    function(body, tag, payload) async_results.gzip = { body = body, tag = tag, payload = payload } end)
http.request_async({ url = base .. "/truncated", tag = "error-tag", payload = { key = "error-payload" } },
    function(body, tag, payload) async_results.error = { body = body, tag = tag, payload = payload } end)
http.request_async({ url = "data:text/plain;base64,6IGG5ZCs5pyI5LiO5oKm", tag = "data-text" },
    function(body, tag) async_results.data_text = { body = body, tag = tag } end)
http.request_async({ url = "data:application/octet-stream;base64,AP9B", type = "聆听月与悦", tag = "data-hex" },
    function(body, tag) async_results.data_hex = { body = body, tag = tag } end)
http.request_async({ url = base .. "/binary", type = "application/octet-stream", tag = "http-hex" },
    function(body, tag) async_results.http_hex = { body = body, tag = tag } end)
http.request_async({ url = base .. "/echo, " .. json.encode({ method = "POST", headers = { ["X-Test"] = "async inline" }, body = "async body" }), tag = "inline-post" },
    function(body, tag) async_results.inline_post = { body = body, tag = tag } end)
channels.http_req_channel:push("STOP")
run_worker_once()
http.update()
check(async_results.gzip and async_results.gzip.body == "gzip 测试正文", "async gzip response failed")
check(async_results.gzip.tag == "gzip-tag" and async_results.gzip.payload.key == "gzip-payload", "async callback metadata changed")
check(async_results.error and async_results.error.body == "", "async failed transfer must deliver empty body")
check(async_results.error.tag == "error-tag" and async_results.error.payload.key == "error-payload", "async error callback metadata changed")
check(async_results.data_text and async_results.data_text.body == "聆听月与悦" and async_results.data_text.tag == "data-text", "async text data URI failed")
check(async_results.data_hex and async_results.data_hex.body == "00ff41" and async_results.data_hex.tag == "data-hex", "async binary data URI hex failed")
check(async_results.http_hex and async_results.http_hex.body == "00ff410a" and async_results.http_hex.tag == "http-hex", "async HTTP binary hex failed")
local inline_async_echo = async_results.inline_post and json.decode(async_results.inline_post.body)
check(inline_async_echo and inline_async_echo.method == "POST" and inline_async_echo.header == "async inline" and inline_async_echo.body == "async body", "async inline options failed")
love = nil
print("HTTP compatibility tests passed")
