-- tests/test_font.lua  (LuaJIT-runnable check; no LÖVE required)
--
-- Guarantees the bundled CJK font:
--   1. exists at the expected path,
--   2. is a valid TrueType/OpenType file with a usable cmap,
--   3. covers the Chinese characters + punctuation the app actually renders.
--
-- It parses the raw cmap with a tiny reader so it runs under plain LuaJIT (no
-- LÖVE graphics). This is a cheap safeguard against a future font swap that
-- silently drops glyphs used by the UI.

package.path = package.path .. ";./?.lua;./src/?.lua"

local FONT_PATH = "assets/fonts/MapleMono-NF-CN-Regular.ttf"

local f = assert(io.open(FONT_PATH, "rb"), "bundled font missing: " .. FONT_PATH)
local data = f:read("*a")
f:close()
assert(#data > 100000, "font file looks truncated (" .. #data .. " bytes)")

-- 0-based, big-endian accessors (Lua strings are 1-based, hence the +1).
local function u8(s, off) return s:byte(off + 1) end
local function be16(s, off) return u8(s, off) * 256 + u8(s, off + 1) end
local function be32(s, off)
    return ((u8(s, off) * 256 + u8(s, off + 1)) * 256 + u8(s, off + 2)) * 256 + u8(s, off + 3)
end

assert(data:sub(1, 4) == "\0\1\0\0" or data:sub(1, 4) == "OTTO" or data:sub(1, 4) == "true",
    "not a recognised SFNT font (bad signature)")

local numTables = be16(data, 4)
local cmap_off
for i = 0, numTables - 1 do
    local rec = 12 + i * 16
    if data:sub(rec + 1, rec + 4) == "cmap" then
        cmap_off = be32(data, rec + 8)
        break
    end
end
assert(cmap_off, "font has no cmap table")

local nsub = be16(data, cmap_off + 2)
local best4, best12
for i = 0, nsub - 1 do
    local rec = cmap_off + 4 + i * 8
    local platform = be16(data, rec)
    local off = cmap_off + be32(data, rec + 4)
    local fmt = be16(data, off)
    if fmt == 4 and (platform == 3 or not best4) then best4 = off end
    if fmt == 12 then best12 = off end
end

local covered = {}

-- Prefer format 12 (UCS-4) when present.
if best12 then
    local ngroups = be32(data, best12 + 12)
    local g = best12 + 16
    for _ = 1, ngroups do
        local sc = be32(data, g)
        local ec = be32(data, g + 4)
        if ec - sc < 200000 then
            for cp = sc, ec do covered[cp] = true end
        end
        g = g + 12
    end
end

if best4 then
    local segX2 = be16(data, best4 + 6)
    local seg = segX2 / 2
    local endBase = best4 + 14
    local startBase = endBase + segX2 + 2
    for i = 0, seg - 1 do
        local sc = be16(data, startBase + i * 2)
        local ec = be16(data, endBase + i * 2)
        if ec ~= 0xFFFF and ec - sc < 200000 then
            for cp = sc, ec do covered[cp] = true end
        end
    end
end

local ncov = 0
for _ in pairs(covered) do ncov = ncov + 1 end
assert(ncov > 1000, "cmap coverage suspiciously small (" .. ncov .. " codepoints)")

-- Glyphs the app actually renders (labels, punctuation, arrows).
local SAMPLE = "顺为凡逆则仙只在心中一念间第章蓦然回首大结局搜索发现书架书源设置目录排版缓存清空退出换源重载本章加移出确认取消暗黑羊皮纸明亮作者已读进度页总计启用禁普通海阁幽香最新连载未名简介门口"
        .. "，。！？、；：（）《》【】…"
        .. "◀▶▲▼"
        .. "ABCabc0123456789"

local missing = {}
-- Simple UTF-8 codepoint iteration (LuaJIT 2.1 has no `utf8` library).
local i = 1
while i <= #SAMPLE do
    local c = SAMPLE:byte(i)
    local cp, adv
    if c < 0x80 then cp, adv = c, 1
    elseif c < 0xE0 then cp, adv = c - 0xC0, 2
    elseif c < 0xF0 then cp, adv = c - 0xE0, 3
    else cp, adv = c - 0xF0, 4 end
    for k = 1, adv - 1 do
        cp = cp * 64 + (SAMPLE:byte(i + k) - 0x80)
    end
    if not covered[cp] then
        missing[#missing + 1] = SAMPLE:sub(i, i + adv - 1)
    end
    i = i + adv
end

assert(#missing == 0, "bundled font is missing UI glyphs: " .. table.concat(missing, " "))

print(string.format("Font test passed (%s, %d cmap codepoints, all UI glyphs present)",
    FONT_PATH, ncov))
