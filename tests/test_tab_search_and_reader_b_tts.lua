-- tests/test_tab_search_and_reader_b_tts.lua
-- Unit tests for:
-- 1. Tab switching to search does NOT auto-perform search or block GUI
-- 2. Pressing B to exit reader stops TTS playback and cancels pipelines cleanly

package.path = "?.lua;./src/?.lua;" .. package.path

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL: %s | Expected: %s, Got: %s", msg or "", tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL: %s", msg or "assertion failed"))
    end
end

print("=== Running Search Tab Init & Reader B-Key TTS Stop Tests ===")

-- 1. Test Search View Init does NOT auto search
print("--- Test 1: Search View Init No Auto Search ---")
local search = require("src.views.search")
search.init()

assert_eq(search.is_searching(), false, "Search view should not be searching immediately upon init()")
assert_eq(search.is_busy(), false, "Search view should not be busy upon init()")

-- 2. Test Reader B key stops TTS
print("--- Test 2: Reader Exit via B Key Stops TTS ---")
local tts = require("src.tts")
local reader = require("src.views.reader")
tts.set_api_key("test-key")

-- Setup reader book and content
reader.open_book({ name = "B键退出测试", bookUrl = "http://test.com/b_exit", author = "作者" })
local text = "测试段落一内容。\n\n测试段落二内容。"
reader.set_content_for_test(text)

-- Mock HTTP for TTS
local http = require("src.http")
local orig_req = http.request_async
http.request_async = function(opts, cb)
    if cb then
        cb('{"choices":[{"message":{"audio":{"data":"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="}}}]}')
    end
end

reader.toggle_tts()
assert_true(tts.is_active(), "TTS should be active after toggle_tts")

-- Simulate pressing B in reader
local input_b = {
    pressed = function(k) return k == "b" end
}
local res = reader.update(0.016, input_b)
assert_true(res ~= nil and res.action == "close_reader", "Reader update with B should emit close_reader")
assert_eq(tts.is_active(), false, "TTS must be completely stopped after exiting reader via B key")
assert_eq(tts.get_state(), "idle", "TTS state must be idle after exiting reader via B key")

-- Restore HTTP
http.request_async = orig_req

print(string.format("=== All Tests Completed: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
    os.exit(1)
end
