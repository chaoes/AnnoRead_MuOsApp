package.path = package.path .. ";./src/?.lua"
local aes = require("aes")
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end

-- FIPS-197 AES-128 标准向量
local k128 = ""; for i = 0, 15 do k128 = k128 .. string.char(i) end
local p128 = ""; for i = 0, 15 do p128 = p128 .. string.char(i * 17) end
assert(hex(aes.encrypt_block_raw(p128, k128)) == "69c4e0d86a7b0430d8cdb78070b4c55a", "AES-128 vector failed")

-- AES-256 标准向量
local k256 = ""; for i = 0, 31 do k256 = k256 .. string.char(i) end
assert(hex(aes.encrypt_block_raw(p128, k256)) == "8ea2b7ca516745bfeafc49904b496089", "AES-256 vector failed")

-- CBC 往返
local key, iv = "CjsVDGnRIcj7IPG7Bec7V8hZFtp87DII", "3126252674073386"
local plain = '{"id":"0RNQ","page":2}'
assert(aes.cbc_decrypt(aes.cbc_encrypt(plain, key, iv), key, iv) == plain, "CBC roundtrip failed")

-- 已知密文（openssl 对照）
assert(hex(aes.cbc_encrypt(plain, key, iv)) == "bd60ac66ef6adb8ff29a44bdf009a66f0c9b3ddee0d2d9bbcc460e99a6f8d97f", "openssl mismatch")

-- Base64
assert(aes.base64_encode("abc") == "YWJj", "base64 encode failed")
assert(aes.base64_decode("YWJj") == "abc", "base64 decode failed")

-- 非法输入不得抛错（Review Focus）
assert(aes.cbc_encrypt("x", "shortkey", "0123456789abcdef") == "", "bad key len should return ''")
assert(aes.cbc_decrypt("not16multiple", key, iv) == "", "bad cipher len should return ''")

print("AES tests passed")
