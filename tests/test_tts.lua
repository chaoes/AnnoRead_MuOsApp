-- tests/test_tts.lua
-- Unit tests for src/tts.lua and its integration into src/views/reader.lua

package.path = package.path .. ";./?.lua;./src/?.lua"

print("=== Running MiMo TTS & Reader Integration Tests ===")

local tts = require("src.tts")

-- 1. Test Base64 Decoder
print("--- 1. Testing Base64 Decoding ---")
local test_str = "Hello MiMo TTS"
-- base64("Hello MiMo TTS") = "SGVsbG8gTWlNbyBUVFM="
local b64 = "SGVsbG8gTWlNbyBUVFM="
local decoded = tts.decode_base64(b64)
assert(decoded == test_str, "Base64 decode failed: expected " .. test_str .. ", got " .. tostring(decoded))
print("✔ Base64 decoder passed!")

-- 2. Test TTS Initial State
print("--- 2. Testing TTS Initial State ---")
assert(tts.is_playing() == false, "TTS should not be playing initially")
tts.stop()
assert(tts.is_playing() == false, "TTS stop should be idempotent")
print("✔ Initial state verified!")

-- 3. Test Reader Integration with TTS Menu Item
print("--- 3. Testing Reader Action Menu contains TTS ---")
local reader = require("src.views.reader")
reader.open_book({ name = "朗读测试书", bookUrl = "http://tts.test/book", author = "测试" })

-- Open select menu
reader.open_menu()
assert(reader.is_menu_open(), "Menu should be open")

-- Fake some reader content
local sample_text = "第一段文字，这是第一段。\n\n第二段文字，这是第二段。\n\n第三段文字，这是第三段。"
reader.set_content_for_test(sample_text)

local mock_font = {
    getWidth = function(self, str) return #str * 8 end,
    getHeight = function(self) return 20 end,
}
local wrapped, raw = reader.wrap_chinese_text(sample_text, mock_font, 600)
assert(#raw == 3, "Should extract 3 raw paragraphs")
assert(#wrapped == 3, "Should wrap 3 paragraphs")

local pgs = reader.paginate_paragraphs(wrapped, mock_font, 700, 1.6, 10)
assert(#pgs >= 1, "Should have at least 1 page")
assert(pgs[1][1].para_idx == 1, "First line should belong to paragraph 1")

print("✔ Reader paragraph splitting and pagination verified!")

-- 4. Test Toggle TTS from Reader
print("--- 4. Testing Reader Toggle TTS ---")
tts.set_api_key("test-key")
-- Mock http.request_async for TTS so network calls succeed with mock audio data
local http = require("src.http")
local orig_request_async = http.request_async
local req_called = false
local requested_url = nil

http.request_async = function(opts, cb)
    req_called = true
    requested_url = opts.url
    assert(opts.url:find("token%-plan%-cn%.xiaomimimo%.com"), "URL should target token-plan-cn.xiaomimimo.com")
    assert(opts.headers and opts.headers["api-key"], "Should send api-key header")
    local body_data = require("src.json").decode(opts.body)
    assert(body_data.model == "mimo-v2.5-tts", "Model should be mimo-v2.5-tts")
    -- Simulate async callback returning mock wav base64 audio response
    if cb then
        local mock_resp = '{"choices":[{"message":{"audio":{"data":"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="}}}]}'
        cb(mock_resp)
    end
end

-- Reader toggle TTS (clear disk cache for clean test)
local tts_cache = require("src.tts_cache")
tts_cache.clear_all(reader.get_book_key())
reader.toggle_tts()
assert(tts.is_active() == true, "TTS should be active after toggle_tts")
assert(req_called == true, "HTTP request_async should have been triggered for TTS")

-- Update TTS
tts.update(0.1)

-- Stop TTS
reader.toggle_tts()
assert(tts.is_active() == false, "TTS should stop after second toggle_tts")

-- 5. Test Automatic TTS Stop on B key (Reader Exit)
print("--- 5. Testing Reader Exit (B key) Stops TTS ---")
reader.close_menu()
reader.toggle_tts()
assert(tts.is_active() == true, "TTS should be active before exit")
local exit_res = reader.update(0.016, {
    pressed = function(k) return k == "b" end
})
assert(exit_res and exit_res.action == "close_reader", "Pressing B in reader should return close_reader action")
assert(tts.is_active() == false, "TTS must be stopped after reader exit (B key)")
print("✔ Reader exit stops TTS verified!")

-- Restore http.request_async
http.request_async = orig_request_async
print("✔ Reader toggle TTS and HTTP pipeline verified!")

print("🎉 ALL MIMO TTS & READER INTEGRATION TESTS PASSED! 🎉")
