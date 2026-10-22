package.path = "?.lua;./src/?.lua;" .. package.path

local tts = require("src.tts")
local tts_cache = require("src.tts_cache")
local http = require("src.http")
local json = require("src.json")

local book_key = "mimo-controls-regression"
local paragraph = "这是用于验证可配置语音参数的短句。"
tts_cache.clear_all(book_key)
tts.set_api_key("test-key")
tts.set_voice("苏打")
tts.set_voice_style("低沉、温暖的叙述音色")
tts.set_speed(1.25)
tts.set_pitch(-1)

local requests = {}
local old_request = http.request_async
http.request_async = function(opts)
    requests[#requests + 1] = opts
    return #requests
end

tts.start({ { title = "第一章" }, { title = "第二章" } }, 1,
    { paragraph }, 1, {}, book_key)
tts.set_next_chapter_prefetch(2, { "下一章也应使用相同的语音配置。" })
assert(#requests == 2, "current paragraph and next-chapter prefetch should both request audio")

for _, request in ipairs(requests) do
    local body = json.decode(request.body)
    assert(body.audio.voice == "苏打" and body.audio.format == "wav", "configured preset voice must reach MiMo")
    assert(body.audio.speed == nil and body.audio.pitch == nil,
        "MiMo does not document numeric speed/pitch fields")
    assert(body.messages[1].role == "user" and body.messages[2].role == "assistant")
    assert(body.messages[1].content:find("低沉、温暖的叙述音色", 1, true))
    assert(body.messages[1].content:find("1.25 倍", 1, true))
    assert(body.messages[1].content:find("音高略低", 1, true))
end

local variant = tts.get_cache_variant()
assert(tts_cache.save_audio(book_key, 1, 1, paragraph, "test-audio", variant))
assert(tts_cache.is_cached(book_key, 1, 1, paragraph, variant))
tts.stop()
tts.set_voice("茉莉")
assert(tts.get_cache_variant() ~= variant, "voice change must alter cache identity")
assert(not tts_cache.is_cached(book_key, 1, 1, paragraph, tts.get_cache_variant()),
    "voice change must not replay audio synthesized with the old voice")

variant = tts.get_cache_variant()
tts.set_speed(0.8)
assert(tts.get_cache_variant() ~= variant, "speed change must alter cache identity")
variant = tts.get_cache_variant()
tts.set_pitch(2)
assert(tts.get_cache_variant() ~= variant, "pitch change must alter cache identity")
variant = tts.get_cache_variant()
tts.set_voice_style("清亮")
assert(tts.get_cache_variant() ~= variant, "voice style change must alter cache identity")

http.request_async = old_request
tts_cache.clear_all(book_key)
print("MiMo voice, speed, pitch, and cache variant tests passed")
