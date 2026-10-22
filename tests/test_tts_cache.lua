-- tests/test_tts_cache.lua
-- Unit tests for persistent disk caching, tone prompts, voice character,
-- chapter prefetching, obsolete cleanup, and cancellation in TTS subsystem.

package.path = "?.lua;./src/?.lua;" .. package.path

local tts = require("src.tts")
local tts_cache = require("src.tts_cache")
local http = require("src.http")
local json = require("src.json")

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

print("=== Running TTS Cache & MiMo Enhancements Test Suite ===")

-- 1. Test default prompt and voice
print("--- Test 1: Default Prompt & Voice ---")
assert_eq(tts.get_voice(), "茉莉", "Default voice must be 茉莉")
assert_eq(tts.get_tone_prompt(), "请用自然流畅的普通话朗读小说，保持叙事连贯，停顿得体。", "Base tone prompt must be stable")
assert_true(tts.get_style_prompt():find("清冷、干净的青年女声", 1, true) ~= nil, "Default voice style should be a cool young woman")
assert_true(tts.get_style_prompt():find("语速稍快", 1, true) ~= nil, "Default style should be slightly fast")

-- 2. Test Book Key & Paragraph Key Hashing
print("--- Test 2: Book Key & Path Generation ---")
local bk = tts_cache.get_book_key("完美世界", "https://example.com/book/123")
assert_true(#bk > 0, "Book key should be non-empty")
assert_true(string.find(bk, "[%w_]+") ~= nil, "Book key is valid string")

local para_text = "那是一个浩瀚无垠的时代，群雄并起。"
local p_hash = tts_cache.hash_str(para_text)
assert_true(type(p_hash) == "number" and p_hash > 0, "Paragraph hash generated")

local p_path = tts_cache.get_para_path(bk, 1, 1, para_text)
assert_true(string.find(p_path, bk, 1, true) ~= nil, "Path includes book key")
assert_true(string.find(p_path, "ch_1", 1, true) ~= nil, "Path includes chapter directory")

-- 3. Test Save, Query, and Load Cache
print("--- Test 3: Disk Audio Cache Save & Retrieval ---")
local dummy_wav = "RIFF....WAVEfmt ....dataDUMMY_AUDIO_BYTES_12345"
local ok_save = tts_cache.save_audio(bk, 1, 1, para_text, dummy_wav)
assert_true(ok_save, "Audio cache saved successfully")

local is_cached = tts_cache.is_cached(bk, 1, 1, para_text)
assert_true(is_cached, "Audio should be identified as cached")

local loaded_wav = tts_cache.get_audio(bk, 1, 1, para_text)
assert_eq(loaded_wav, dummy_wav, "Retrieved audio matches saved bytes")

-- 4. Test Obsolete Chapter Cleanup
print("--- Test 4: Obsolete Cache Cleanup ---")
-- Save audio for chapter 1, 2, 3, 4
tts_cache.save_audio(bk, 1, 1, "ch1 p1", "audio1")
tts_cache.save_audio(bk, 2, 1, "ch2 p1", "audio2")
tts_cache.save_audio(bk, 3, 1, "ch3 p1", "audio3")
tts_cache.save_audio(bk, 4, 1, "ch4 p1", "audio4")

-- Currently at chapter 3, so keep only chapter 3 and next chapter 4
tts_cache.cleanup_obsolete(bk, 3, 4)

assert_true(not tts_cache.is_cached(bk, 1, 1, "ch1 p1"), "Chapter 1 should be evicted")
assert_true(not tts_cache.is_cached(bk, 2, 1, "ch2 p1"), "Chapter 2 should be evicted")
assert_true(tts_cache.is_cached(bk, 3, 1, "ch3 p1"), "Chapter 3 (current) should be retained")
assert_true(tts_cache.is_cached(bk, 4, 1, "ch4 p1"), "Chapter 4 (next chapter) should be retained")

-- 5. Test Chapter Jump & In-Flight Request Cancellation
print("--- Test 5: Chapter Jump and Request Invalidation ---")
local test_chapters = {
    { title = "第1章", url = "http://test.com/1" },
    { title = "第2章", url = "http://test.com/2" },
    { title = "第3章", url = "http://test.com/3" }
}
local paras_ch1 = { "第一章第一段内容", "第一章第二段内容" }
local paras_ch2 = { "第二章第一段内容", "第二章第二段内容" }

local orig_request_async = http.request_async
local req_count = 0
http.request_async = function(opts, cb)
    req_count = req_count + 1
    if cb then
        local mock_resp = '{"choices":[{"message":{"audio":{"data":"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="}}}]}'
        cb(mock_resp)
    end
    return req_count
end

local para_changed = 0
tts.set_api_key("test-key")
tts.start(test_chapters, 1, paras_ch1, 1, {
    on_para_change = function(idx)
        para_changed = idx
    end
}, bk)

assert_eq(tts.get_current_chapter(), 1, "Current chapter is 1")
assert_eq(tts.get_current_para(), 1, "Current paragraph is 1")

-- Simulate jumping to chapter 2
tts.set_chapter_content(2, paras_ch2, 1, bk)
assert_eq(tts.get_current_chapter(), 2, "Chapter updated to 2 after jump")
assert_eq(tts.get_current_para(), 1, "Current paragraph reset to 1")

-- Stop TTS
tts.stop()
assert_eq(tts.get_state(), "idle", "TTS state becomes idle after stop")
assert_true(not tts.is_active(), "TTS is no longer active")

-- 6. Test Next-Chapter Prefetch Scheduling
print("--- Test 6: Next-Chapter Prefetch Pipeline ---")
tts.start(test_chapters, 2, paras_ch2, 1, {}, bk)
tts.set_next_chapter_prefetch(3, { "第三章预拉取段落1", "第三章预拉取段落2" })
assert_true(tts.is_active(), "TTS is active during prefetch")
tts.stop()

http.request_async = orig_request_async

print(string.format("=== Tests Completed: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
    os.exit(1)
end
