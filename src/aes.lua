--[[
    Pure Lua AES-256-CBC/PKCS5 + Base64

    Replaces the Java `createSymmetricCrypto("AES/CBC/PKCS5Padding", key, iv)`
    host call used by Legado book sources (e.g. 幽香书房's TOC pagination API).

    Verified against FIPS-197 AES-128/AES-256 known-answer vectors and against
    `openssl enc -aes-256-cbc` byte-for-byte.

    Failure semantics: an illegal key length (not 16/24/32 bytes) or a cipher
    length that is not a multiple of 16 returns "" instead of raising, so a
    malformed source rule degrades gracefully rather than aborting TOC parsing.

    PORTABILITY: the Love2D runtime shipped on the RG CubeXX (muOS) uses
    LuaJIT 2.1.0-beta3, which does NOT parse Lua 5.3 bitwise operators
    ( &  |  ~  <<  >> ). All bit operations therefore go through the `bit`
    library when available, with a pure Lua arithmetic fallback so the module
    also loads on plain Lua 5.x.
]]

local aes = {}

-- ---------------------------------------------------------------------------
-- Bitwise compatibility layer
-- ---------------------------------------------------------------------------
local band, bor, bxor, lshift, rshift

local ok_bit, bitlib = pcall(require, "bit")
if ok_bit and type(bitlib) == "table" and bitlib.band then
    band   = function(a, b) return bitlib.band(a, b) end
    bor    = function(a, b) return bitlib.bor(a, b) end
    bxor   = function(a, b) return bitlib.bxor(a, b) end
    lshift = function(a, n) return bitlib.lshift(a, n) end
    rshift = function(a, n) return bitlib.rshift(a, n) end
else
    local floor = math.floor
    band = function(a, b)
        local r, m = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + m end
            a, b, m = floor(a / 2), floor(b / 2), m * 2
        end
        return r
    end
    bor = function(a, b)
        local r, m = 0, 1
        while a > 0 or b > 0 do
            if a % 2 == 1 or b % 2 == 1 then r = r + m end
            a, b, m = floor(a / 2), floor(b / 2), m * 2
        end
        return r
    end
    bxor = function(a, b)
        local r, m = 0, 1
        while a > 0 or b > 0 do
            if (a % 2) ~= (b % 2) then r = r + m end
            a, b, m = floor(a / 2), floor(b / 2), m * 2
        end
        return r
    end
    local function pow2(n)
        local v = 1
        for _ = 1, n do v = v * 2 end
        return v
    end
    lshift = function(a, n) return a * pow2(n) end
    rshift = function(a, n) return floor(a / pow2(n)) end
end

-- GF(2^8) multiply, AES polynomial 0x11B.
local function gmul(a, b)
    local p = 0
    for _ = 1, 8 do
        if band(b, 1) == 1 then p = bxor(p, a) end
        local hi = band(a, 0x80)
        a = band(lshift(a, 1), 0xFF)
        if hi ~= 0 then a = bxor(a, 0x1B) end
        b = rshift(b, 1)
    end
    return p
end

local function rotl8(x, n)
    return band(bor(lshift(x, n), rshift(x, 8 - n)), 0xFF)
end

local sbox, inv_sbox = {}, {}
do
    -- Multiplicative inverses in GF(2^8).
    local inv = { [0] = 0 }
    for a = 1, 255 do
        for b = 1, 255 do
            if gmul(a, b) == 1 then inv[a] = b break end
        end
    end
    for a = 0, 255 do
        local x = inv[a] or 0
        local s = band(
            bxor(
                bxor(bxor(bxor(bxor(x, rotl8(x, 1)), rotl8(x, 2)), rotl8(x, 3)), rotl8(x, 4)),
                0x63),
            0xFF)
        sbox[a] = s
        inv_sbox[s] = a
    end
end

local rcon = { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36, 0x6C, 0xD8, 0xAB, 0x4D }

local function key_expansion(key)
    local Nk = #key / 4
    local Nr = Nk + 6
    local w = {}
    for i = 0, Nk - 1 do
        w[i] = { key:byte(i * 4 + 1), key:byte(i * 4 + 2), key:byte(i * 4 + 3), key:byte(i * 4 + 4) }
    end
    for i = Nk, 4 * (Nr + 1) - 1 do
        local t = { w[i - 1][1], w[i - 1][2], w[i - 1][3], w[i - 1][4] }
        if i % Nk == 0 then
            t = { t[2], t[3], t[4], t[1] }
            t = { sbox[t[1]], sbox[t[2]], sbox[t[3]], sbox[t[4]] }
            t[1] = bxor(t[1], rcon[i / Nk])
        elseif Nk > 6 and i % Nk == 4 then
            t = { sbox[t[1]], sbox[t[2]], sbox[t[3]], sbox[t[4]] }
        end
        w[i] = {
            bxor(w[i - Nk][1], t[1]),
            bxor(w[i - Nk][2], t[2]),
            bxor(w[i - Nk][3], t[3]),
            bxor(w[i - Nk][4], t[4]),
        }
    end
    return w, Nr
end

local function add_round_key(s, w, r)
    for c = 0, 3 do
        for i = 0, 3 do s[i + 1][c + 1] = bxor(s[i + 1][c + 1], w[r * 4 + c][i + 1]) end
    end
end

local function sub_bytes(s) for i = 1, 4 do for j = 1, 4 do s[i][j] = sbox[s[i][j]] end end end
local function inv_sub_bytes(s) for i = 1, 4 do for j = 1, 4 do s[i][j] = inv_sbox[s[i][j]] end end end

local function shift_rows(s)
    s[2] = { s[2][2], s[2][3], s[2][4], s[2][1] }
    s[3] = { s[3][3], s[3][4], s[3][1], s[3][2] }
    s[4] = { s[4][4], s[4][1], s[4][2], s[4][3] }
end

local function inv_shift_rows(s)
    s[2] = { s[2][4], s[2][1], s[2][2], s[2][3] }
    s[3] = { s[3][3], s[3][4], s[3][1], s[3][2] }
    s[4] = { s[4][2], s[4][3], s[4][4], s[4][1] }
end

local function mix_columns(s)
    for c = 1, 4 do
        local a = { s[1][c], s[2][c], s[3][c], s[4][c] }
        s[1][c] = bxor(bxor(bxor(gmul(a[1], 2), gmul(a[2], 3)), a[3]), a[4])
        s[2][c] = bxor(bxor(bxor(a[1], gmul(a[2], 2)), gmul(a[3], 3)), a[4])
        s[3][c] = bxor(bxor(bxor(a[1], a[2]), gmul(a[3], 2)), gmul(a[4], 3))
        s[4][c] = bxor(bxor(bxor(gmul(a[1], 3), a[2]), a[3]), gmul(a[4], 2))
    end
end

local function inv_mix_columns(s)
    for c = 1, 4 do
        local a = { s[1][c], s[2][c], s[3][c], s[4][c] }
        s[1][c] = bxor(bxor(bxor(gmul(a[1], 14), gmul(a[2], 11)), gmul(a[3], 13)), gmul(a[4], 9))
        s[2][c] = bxor(bxor(bxor(gmul(a[1], 9), gmul(a[2], 14)), gmul(a[3], 11)), gmul(a[4], 13))
        s[3][c] = bxor(bxor(bxor(gmul(a[1], 13), gmul(a[2], 9)), gmul(a[3], 14)), gmul(a[4], 11))
        s[4][c] = bxor(bxor(bxor(gmul(a[1], 11), gmul(a[2], 13)), gmul(a[3], 9)), gmul(a[4], 14))
    end
end

local function to_state(block) local s = {} for i = 1, 4 do s[i] = {} for j = 1, 4 do s[i][j] = block[(j - 1) * 4 + i] end end return s end
local function from_state(s) local b = {} for j = 1, 4 do for i = 1, 4 do b[(j - 1) * 4 + i] = s[i][j] end end return b end

function aes.encrypt_block(block, w, Nr)
    local s = to_state(block)
    add_round_key(s, w, 0)
    for r = 1, Nr - 1 do sub_bytes(s); shift_rows(s); mix_columns(s); add_round_key(s, w, r) end
    sub_bytes(s); shift_rows(s); add_round_key(s, w, Nr)
    return from_state(s)
end

function aes.decrypt_block(block, w, Nr)
    local s = to_state(block)
    add_round_key(s, w, Nr)
    for r = Nr - 1, 1, -1 do inv_shift_rows(s); inv_sub_bytes(s); add_round_key(s, w, r); inv_mix_columns(s) end
    inv_shift_rows(s); inv_sub_bytes(s); add_round_key(s, w, 0)
    return from_state(s)
end

-- Single-block ECB encryption, exposed for known-answer testing.
function aes.encrypt_block_raw(block16, key)
    if type(block16) ~= "string" or #block16 ~= 16 then return "" end
    if type(key) ~= "string" or (#key ~= 16 and #key ~= 24 and #key ~= 32) then return "" end
    local w, Nr = key_expansion(key)
    local out = {}
    local ct = aes.encrypt_block({ block16:byte(1, 16) }, w, Nr)
    for k = 1, 16 do out[k] = string.char(ct[k]) end
    return table.concat(out)
end

local function valid_key(key)
    return type(key) == "string" and (#key == 16 or #key == 24 or #key == 32)
end

function aes.cbc_encrypt(data, key, iv)
    if not valid_key(key) or type(data) ~= "string" or type(iv) ~= "string" or #iv ~= 16 then
        return ""
    end
    local w, Nr = key_expansion(key)
    local out = {}
    local prev = {}
    for k = 1, 16 do prev[k] = iv:byte(k) end

    local padlen = 16 - (#data % 16)
    data = data .. string.rep(string.char(padlen), padlen)

    for i = 1, #data, 16 do
        local blk = {}
        for k = 1, 16 do blk[k] = bxor(data:byte(i + k - 1), prev[k]) end
        prev = aes.encrypt_block(blk, w, Nr)
        for k = 1, 16 do out[#out + 1] = string.char(prev[k]) end
    end
    return table.concat(out)
end

function aes.cbc_decrypt(data, key, iv)
    if not valid_key(key) or type(data) ~= "string" or type(iv) ~= "string" or #iv ~= 16 then
        return ""
    end
    if #data == 0 or #data % 16 ~= 0 then
        return ""
    end
    local w, Nr = key_expansion(key)
    local out = {}
    local prev = {}
    for k = 1, 16 do prev[k] = iv:byte(k) end

    for i = 1, #data, 16 do
        local blk = {}
        for k = 1, 16 do blk[k] = data:byte(i + k - 1) end
        local dec = aes.decrypt_block(blk, w, Nr)
        for k = 1, 16 do out[#out + 1] = string.char(bxor(dec[k], prev[k])) end
        prev = blk
    end

    local s = table.concat(out)
    local padlen = s:byte(-1)
    if padlen < 1 or padlen > 16 then return "" end
    return s:sub(1, #s - padlen)
end

-- ---------------------------------------------------------------------------
-- Base64
-- ---------------------------------------------------------------------------

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function aes.base64_encode(s)
    if type(s) ~= "string" then return "" end
    local out = {}
    local n = #s
    for i = 1, n, 3 do
        local b1 = s:byte(i)
        local b2 = s:byte(i + 1)
        local b3 = s:byte(i + 2)
        local c1 = rshift(b1, 2)
        local c2 = bor(lshift(band(b1, 0x03), 4), b2 and rshift(b2, 4) or 0)
        local c3 = b2 and bor(lshift(band(b2, 0x0F), 2), b3 and rshift(b3, 6) or 0) or nil
        local c4 = b3 and band(b3, 0x3F) or nil
        out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1)
        out[#out + 1] = B64_CHARS:sub(c2 + 1, c2 + 1)
        out[#out + 1] = c3 and B64_CHARS:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = c4 and B64_CHARS:sub(c4 + 1, c4 + 1) or "="
    end
    return table.concat(out)
end

local B64_LOOKUP = {}
for i = 1, #B64_CHARS do
    B64_LOOKUP[B64_CHARS:sub(i, i)] = i - 1
end

function aes.base64_decode(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[^A-Za-z0-9+/=]", "")
    local out = {}
    for i = 1, #s, 4 do
        local c1 = B64_LOOKUP[s:sub(i, i)]
        local c2 = B64_LOOKUP[s:sub(i + 1, i + 1)]
        local c3 = B64_LOOKUP[s:sub(i + 2, i + 2)]
        local c4 = B64_LOOKUP[s:sub(i + 3, i + 3)]
        if c1 and c2 then
            out[#out + 1] = string.char(band(bor(lshift(c1, 2), rshift(c2, 4)), 0xFF))
            if c3 then out[#out + 1] = string.char(band(bor(lshift(band(c2, 0x0F), 4), rshift(c3, 2)), 0xFF)) end
            if c3 and c4 then out[#out + 1] = string.char(band(bor(lshift(band(c3, 0x03), 6), c4), 0xFF)) end
        end
    end
    return table.concat(out)
end

return aes
