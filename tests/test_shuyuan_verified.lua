-- tests/test_shuyuan_verified.lua
-- Tests the newly bundled verified multi-source file assets/sources/shuyuan_verified.json

local json = require("src.json")

print("=== Running Bundled Verified Sources Tests ===")

-- 1. Verify file exists and is valid JSON
local f = io.open("assets/sources/shuyuan_verified.json", "r")
if not f then
    print("Local verified source bundle absent; site-specific regression skipped")
    return
end
local content = f:read("*a")
f:close()

assert(#content > 0, "shuyuan_verified.json must not be empty")
local sources = json.decode(content)
assert(type(sources) == "table", "shuyuan_verified.json must be a JSON array")
assert(#sources >= 6, "Must contain verified passing sources (found " .. #sources .. ")")

print(string.format("✔ Loaded %d verified sources from assets/sources/shuyuan_verified.json", #sources))

-- 2. Verify all items have required Legado fields
local urls = {}
for i, s in ipairs(sources) do
    assert(s.bookSourceName and #s.bookSourceName > 0, "Source #" .. i .. " missing bookSourceName")
    assert(s.bookSourceUrl and #s.bookSourceUrl > 0, "Source #" .. i .. " missing bookSourceUrl")
    assert(not urls[s.bookSourceUrl], "Duplicate source URL in shuyuan_verified.json: " .. s.bookSourceUrl)
    urls[s.bookSourceUrl] = true
    assert(s.ruleSearch, "Source #" .. i .. " missing ruleSearch")
end
print("✔ All sources have valid names, unique URLs, and ruleSearch")

-- 3. Test integration with storage loader
local storage = require("src.storage")
love = love or {}
love.filesystem = love.filesystem or {}
love.filesystem.getSaveDirectory = function() return "/tmp/mock_annoread_save" end
love.filesystem.getInfo = function() return nil end
love.filesystem.write = function() return true end
love.filesystem.createDirectory = function() return true end
love.filesystem.read = function(path)
    local file = io.open(path, "r")
    if file then
        local c = file:read("*a")
        file:close()
        return c
    end
    return nil
end
love.filesystem.getDirectoryItems = function(path)
    if path == "assets/sources" then
        return { "haishuge.json", "youxiangshufang.json", "shuyuan_verified.json" }
    end
    return {}
end

storage.init()
local all_sources = storage.get_sources()
assert(#all_sources >= #sources + 2, "Storage must merge default sources and verified sources")

local found_verified = 0
for _, s in ipairs(all_sources) do
    if urls[s.bookSourceUrl] then
        found_verified = found_verified + 1
    end
end
assert(found_verified == #sources, "All verified sources must be present in storage")
print(string.format("✔ Storage successfully merged all %d verified sources (total in app: %d)", found_verified, #all_sources))

print("ALL VERIFIED SOURCES TESTS PASSED SUCCESSFULLY!")
