-- tests/test_portability.lua
--
-- Guards against Lua 5.2/5.3-only syntax sneaking into the game sources.
--
-- The RG CubeXX (muOS) ships LuaJIT 2.1.0-beta3, whose parser predates the
-- Lua 5.3 bitwise operators ( & | ~ << >> ). Any source file that uses them
-- raises a syntax error on device (`'then' expected near '&'`), which crashed
-- the reader until src/aes.lua was rewritten to use the `bit` library.
--
-- This test scans every src/**/*.lua plus main.lua / conf.lua with a small
-- tokenizer that skips comments and string literals, then fails if it finds a
-- bare bitwise operator in executable code. It also runs on the host LuaJIT so
-- `make test` catches the mistake long before it reaches the handheld.

package.path = package.path .. ";./?.lua;./src/?.lua"

local function collect_files()
    local files = {}
    local function walk(dir)
        local p = io.popen("find " .. dir .. " -name '*.lua' 2>/dev/null")
        if p then
            for line in p:lines() do files[#files + 1] = line end
            p:close()
        end
    end
    walk("src")
    files[#files + 1] = "main.lua"
    files[#files + 1] = "conf.lua"
    return files
end

-- Replace all string literals and comments with spaces so operator scanning
-- only ever sees executable code.
local function strip_literals(src)
    local out = {}
    local i, n = 1, #src
    local function push_spaces(len)
        for _ = 1, len do out[#out + 1] = " " end
    end

    while i <= n do
        local c = src:sub(i, i)

        -- long bracket [==[ ... ]==] or [[ ... ]]
        if c == "[" then
            local eq = src:match("^%[=*%[", i)
            if eq then
                local close = "]" .. eq:sub(2, -2) .. "]"
                local j = src:find(close, i + #eq, true)
                local endpos = j and (j + #close - 1) or n
                push_spaces(endpos - i + 1)
                i = endpos + 1
            else
                out[#out + 1] = c
                i = i + 1
            end

        -- line comment --  (or long comment --[[ ... ]])
        elseif src:sub(i, i + 1) == "--" then
            local lbr = src:match("^%-%-%[=*%[", i)
            if lbr then
                local eq = lbr:sub(3)          -- the [=*[ part
                local close = "]" .. eq:sub(2, -2) .. "]"
                local j = src:find(close, i + #lbr, true)
                local endpos = j and (j + #close - 1) or n
                push_spaces(endpos - i + 1)
                i = endpos + 1
            else
                local j = src:find("\n", i, true) or (n + 1)
                push_spaces(j - i)
                i = j
            end

        -- short string "..." or '...'
        elseif c == '"' or c == "'" then
            local j = i + 1
            local closed = false
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c then
                    closed = true
                    break
                else
                    j = j + 1
                end
            end
            local endpos = closed and j or n
            push_spaces(endpos - i + 1)
            i = endpos + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end

    return table.concat(out)
end

local function find_illegal_bits(code)
    local hits = {}
    -- << and >>
    if code:find("<<") or code:find(">>") then
        hits[#hits + 1] = "<< or >>"
    end
    -- & not part of && (Lua has no &&; and operator is `and`)
    if code:find("&") then
        hits[#hits + 1] = "&"
    end
    -- | not part of || (Lua has no ||)
    if code:find("|") then
        hits[#hits + 1] = "|"
    end
    -- ~ as an operator, but allow the 5.1 valid ~= (not equal)
    local scan = code
    scan = scan:gsub("~=", "  ")
    if scan:find("~") then
        hits[#hits + 1] = "~"
    end
    return hits
end

local failures = 0
for _, file in ipairs(collect_files()) do
    local f = io.open(file, "r")
    if f then
        local src = f:read("*a")
        f:close()
        local code = strip_literals(src)
        local hits = find_illegal_bits(code)
        if #hits > 0 then
            failures = failures + 1
            print(string.format("PORTABILITY FAIL: %s uses Lua 5.3 bitwise operator(s): %s",
                file, table.concat(hits, ", ")))
        end
    end
end

assert(failures == 0, failures .. " file(s) contain Lua 5.3-only bitwise operators (unsupported on the muOS LuaJIT)")

-- Also assert the AES module still exposes its API after the bit-compat rewrite.
local aes = require("src.aes")
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local k256 = ""; for i = 0, 31 do k256 = k256 .. string.char(i) end
local p = ""; for i = 0, 15 do p = p .. string.char(i * 17) end
assert(hex(aes.encrypt_block_raw(p, k256)) == "8ea2b7ca516745bfeafc49904b496089", "AES-256 KAT regressed after bit-compat rewrite")

print(string.format("Portability tests passed (%d files scanned, no Lua 5.3 bitwise operators)", #collect_files()))
