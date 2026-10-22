package.path = "?.lua;./src/?.lua;" .. package.path

local old_love = love
local old_getenv = os.getenv
local env_override
os.getenv = function(name)
    if name == "MIMO_TTS_API_KEY" then return env_override end
    return old_getenv(name)
end
local tts_config = require("src.tts_config")
local files = {
    ["mimo_tts.json"] = '{"api_key":" save-key ","speed":1.25,"pitch":-1}',
    ["config/mimo_tts.json"] = '{"api_key":"bundled-key","voice":"苏打","voice_style":"低沉温和"}',
}
love = { filesystem = { read = function(path) return files[path] end } }

local loaded = tts_config.load()
assert(loaded.api_key == "save-key", "save directory key should take priority")
assert(loaded.voice == "苏打" and loaded.voice_style == "低沉温和", "bundled style should remain when save file omits it")
assert(loaded.speed == 1.25 and loaded.pitch == -1, "save controls should override bundled controls")
env_override = " environment-key "
assert(tts_config.load().api_key == "environment-key", "environment key should take priority")
env_override = nil
files["mimo_tts.json"] = '{broken json'
assert(tts_config.load().api_key == "bundled-key", "invalid save config should fall back")
files["config/mimo_tts.json"] = nil
loaded = tts_config.load()
assert(loaded.api_key == "" and loaded.voice == "茉莉" and loaded.speed == 1.12 and loaded.pitch == -1,
    "missing config should use safe defaults")
assert(loaded.voice_style:find("清冷、干净的青年女声", 1, true),
    "missing config should use the default young female voice style")
loaded = tts_config.normalize({ speed = 8, pitch = 1.5 })
assert(loaded.speed == 1.12 and loaded.pitch == -1, "out-of-range controls should use defaults")

love = old_love
os.getenv = old_getenv

local tts = require("src.tts")
local http = require("src.http")
local old_request = http.request_async
local requested = false
http.request_async = function()
    requested = true
end
tts.set_api_key("")
local error_text
tts.start({}, 99, { "未配置密钥时不应请求网络" }, 1, {
    on_error = function(message) error_text = message end,
}, "missing-key-test")
assert(not requested, "missing key should not issue an HTTP request")
assert(error_text and error_text:find("mimo_tts.json", 1, true), "missing key should explain how to configure TTS")
http.request_async = old_request
tts.stop()
print("TTS config lookup passed")
