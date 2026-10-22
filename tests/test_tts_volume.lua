-- tests/test_tts_volume.lua
-- Unit tests for TTS volume boost, PCM soft-knee limiter, and reader settings integration.

package.path = "?.lua;./src/?.lua;" .. package.path

local tts = require("src.tts")
local storage = require("src.storage")

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

print("=== Running TTS Volume Boost & Limiter Tests ===")

-- 1. Test amplify_wav with synthetic 16-bit PCM WAV
print("--- Test 1: WAV PCM Amplification & Soft-Knee Limiter ---")
local sample_rate = 24000
local num_samples = 4
local data_size = num_samples * 2
local total_size = 36 + data_size

local header = "RIFF" .. string.char(
    total_size % 256, math.floor(total_size / 256) % 256, math.floor(total_size / 65536) % 256, math.floor(total_size / 16777216) % 256
) .. "WAVEfmt " .. string.char(16, 0, 0, 0, 1, 0, 1, 0)
.. string.char(sample_rate % 256, math.floor(sample_rate / 256) % 256, 0, 0)
.. string.char((sample_rate * 2) % 256, math.floor((sample_rate * 2) / 256) % 256, 0, 0)
.. string.char(2, 0, 16, 0) .. "data" .. string.char(
    data_size % 256, math.floor(data_size / 256) % 256, math.floor(data_size / 65536) % 256, math.floor(data_size / 16777216) % 256
)

-- Test 4 samples:
-- 1) Small positive (1000) -> should scale cleanly by 3.0x -> 3000
-- 2) Small negative (-1000) -> should scale cleanly by 3.0x -> -3000
-- 3) Large positive (15000) -> 15000 * 3 = 45000 > 30000 -> soft knee compressed <= 32767
-- 4) Large negative (-15000) -> -15000 * 3 = -45000 < -30000 -> soft knee compressed >= -32768
local function int16_to_bytes(val)
    local u = val
    if u < 0 then u = u + 65536 end
    return string.char(u % 256, math.floor(u / 256) % 256)
end

local function bytes_to_int16(str, offset)
    local b1, b2 = string.byte(str, offset, offset + 1)
    local u = b1 + b2 * 256
    if u >= 32768 then u = u - 65536 end
    return u
end

local raw_data = int16_to_bytes(1000) .. int16_to_bytes(-1000) .. int16_to_bytes(15000) .. int16_to_bytes(-15000)
local test_wav = header .. raw_data

local amplified = tts.amplify_wav(test_wav, 3.0)
assert_eq(#amplified, #test_wav, "Amplified WAV size must match original WAV size")

local s1 = bytes_to_int16(amplified, 45)
local s2 = bytes_to_int16(amplified, 47)
local s3 = bytes_to_int16(amplified, 49)
local s4 = bytes_to_int16(amplified, 51)

assert_eq(s1, 3000, "Small positive sample should be multiplied exactly (1000 * 3 = 3000)")
assert_eq(s2, -3000, "Small negative sample should be multiplied exactly (-1000 * 3 = -3000)")
assert_true(s3 > 30000 and s3 <= 32767, "High positive sample should be soft-limited without overflow: " .. tostring(s3))
assert_true(s4 < -30000 and s4 >= -32768, "High negative sample should be soft-limited without underflow: " .. tostring(s4))

-- 2. Test Volume Getters/Setters
print("--- Test 2: Volume Controls & Clamping ---")
tts.set_volume(1.0)
assert_eq(tts.get_volume(), 1.0, "Volume defaults to 1.0")

tts.set_volume(1.8)
assert_eq(tts.get_volume(), 1.8, "Volume can be set to 1.8")

tts.set_volume(0.05)
assert_eq(tts.get_volume(), 0.1, "Volume lower bound clamped to 0.1")

tts.set_volume(3.5)
assert_eq(tts.get_volume(), 2.0, "Volume upper bound clamped to 2.0")

-- 3. Test Storage Defaults & Settings
print("--- Test 3: Storage Reader Settings TTS Volume ---")
local s = storage.get_default_reader_settings()
assert_eq(s.tts_volume, 100, "Default reader settings tts_volume must be 100%")

s.tts_volume = 150
storage.save_reader_settings(s)
local loaded = storage.get_reader_settings()
assert_eq(loaded.tts_volume, 150, "Persisted tts_volume must load correctly")

-- Restore default
s.tts_volume = 100
storage.save_reader_settings(s)

print(string.format("=== Volume Tests Completed: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
    os.exit(1)
end
