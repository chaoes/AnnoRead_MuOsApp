package.path = package.path .. ";./src/?.lua"
local http = require("src.http")
local requests = {}
http.request_async = function(opts, cb)
    table.insert(requests, opts)
end

local storage = require("src.storage")
storage.init()
storage.get_sources = function()
    return {{
        bookSourceName = "测试发现源",
        bookSourceUrl = "https://books.example.invalid",
        exploreUrl = "测试分类::/books",
        enabled = true,
    }}
end
local legado = require("src.legado")
legado.parseExploreCategories = function()
    return '[{"title":"测试分类","url":"/books"}]'
end

local discover = require("src.views.discover")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assertion failed (expected true)")
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

print("=== Running Discover View Fixes & Adaptability Tests ===")

-- Mock love.graphics
love = love or {}
love.graphics = love.graphics or {}
local recorded_prints = {}
love.graphics.setColor = function(...) end
love.graphics.rectangle = function(...) end
love.graphics.line = function(...) end
love.graphics.setScissor = function(...) end
love.graphics.setFont = function(...) end
love.graphics.setLineWidth = function(...) end
love.graphics.print = function(text, x, y)
    table.insert(recorded_prints, { text = tostring(text), x = x, y = y })
end
love.graphics.printf = function(text, x, y, limit, align)
    table.insert(recorded_prints, { text = tostring(text), x = x, y = y, printf = true })
end

-- 1. Test Empty Categories Safe Draw & Prompt
print("--- 1. Testing Empty Categories Safe Draw & Prompt ---")
recorded_prints = {}
discover.init()
discover._set_categories({})
discover.draw(720, 720, false)

local has_src_indicator = false
local has_guidance_prompt = false
for _, p in ipairs(recorded_prints) do
    if p.text:match("%[◀ L2%] 书源:") then
        has_src_indicator = true
    end
    if p.text:match("按 %[L2 / R2%] 切换其他书源") then
        has_guidance_prompt = true
    end
end
assert_true(has_src_indicator, "Source indicator bar should be visible even when categories are empty")
assert_true(has_guidance_prompt, "Guidance prompt should guide user when categories are empty")
print("✔ Empty categories safe draw and guidance prompt verified")

-- 2. Test Relative Category URL Resolution
print("--- 2. Testing Relative Category URL Resolution ---")
requests = {}
discover.init()
local cur_idx = discover.get_active_source_index()
local src_list = discover.get_source_list()
local cur_src = src_list[cur_idx]
assert_true(cur_src ~= nil and cur_src.bookSourceUrl ~= nil, "Active source must have a bookSourceUrl")

-- Set a relative URL category
discover._set_categories({ { title = "测试相对URL分类", url = "/book/sort1/0/1.html" } })
discover.load_category_books(1)

assert_true(#requests > 0, "http.request_async should have been called")
local req = requests[#requests]
local expected_prefix = cur_src.bookSourceUrl:gsub("/+$", "")
assert_true(req.url:match("^https?://"), "Resolved URL must start with http:// or https://")
assert_eq(req.url, expected_prefix .. "/book/sort1/0/1.html", "Relative URL must be resolved against bookSourceUrl")
print("✔ Relative category URL resolution verified: " .. req.url)

-- 3. Test Auto Selection of Capable Discover Source on Init
print("--- 3. Testing Auto Selection of Capable Discover Source ---")
discover.init()
local cats = discover.get_categories()
assert_true(#cats > 0, "discover.init() should auto-select a source that has valid categories")
print(string.format("✔ Auto selected source [%s] at index %d with %d categories",
    src_list[discover.get_active_source_index()].bookSourceName,
    discover.get_active_source_index(),
    #cats))

print("ALL DISCOVER FIXES TESTS PASSED SUCCESSFULLY!")
