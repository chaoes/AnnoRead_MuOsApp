package.path = package.path .. ";./src/?.lua"
local storage = require("src.storage")
local sources_view = require("src.views.sources")
local json = require("src.json")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assertion failed (expected true)")
    end
end

print("=== Running Multi-Source Files & Disable-Only Feature Tests ===")

-- Setup temporary test source files in sources/
os.execute("mkdir -p sources")

local tmp_single_file = "sources/_test_single_source.json"
local tmp_multi_file = "sources/_test_multi_sources.json"
local tmp_wrapped_file = "sources/_test_wrapped_source.json"
local tmp_bad_file = "sources/_test_invalid_syntax.json"

local f_single = io.open(tmp_single_file, "w")
f_single:write([[
{
    "bookSourceName": "测试单个源",
    "bookSourceUrl": "https://test.single.com",
    "searchUrl": "https://test.single.com/search?q={{key}}",
    "enabled": true
}
]])
f_single:close()

local f_multi = io.open(tmp_multi_file, "w")
f_multi:write([[
[
    {
        "bookSourceName": "测试数组源A",
        "bookSourceUrl": "https://test.array.com/a",
        "searchUrl": "https://test.array.com/search?q={{key}}",
        "enabled": true
    },
    {
        "bookSourceName": "测试数组源B",
        "bookSourceUrl": "https://test.array.com/b",
        "searchUrl": "https://test.array.com/search?q={{key}}",
        "enabled": true
    }
]
]])
f_multi:close()

local f_wrapped = io.open(tmp_wrapped_file, "w")
f_wrapped:write([[
{
    "data": [
        {
            "bookSourceName": "测试包装源C",
            "bookSourceUrl": "https://test.wrapped.com/c",
            "searchUrl": "https://test.wrapped.com/search?q={{key}}",
            "enabled": true
        }
    ]
}
]])
f_wrapped:close()

local f_bad = io.open(tmp_bad_file, "w")
f_bad:write("{ invalid json content ...")
f_bad:close()

local function cleanup_test_files()
    os.remove(tmp_single_file)
    os.remove(tmp_multi_file)
    os.remove(tmp_wrapped_file)
    os.remove(tmp_bad_file)
end

local ok, err = pcall(function()
    print("--- 1. Testing Multi-Source File Scanning & Merging ---")
    storage.init()
    local sources = storage.get_sources()
    local by_url = {}
    for _, s in ipairs(sources) do
        by_url[s.bookSourceUrl] = s
    end

    -- Custom source files must be loaded
    assert_true(by_url["https://test.single.com"] ~= nil, "single-source JSON file should be loaded")
    assert_eq(by_url["https://test.single.com"].bookSourceName, "测试单个源", "single-source name check")

    assert_true(by_url["https://test.array.com/a"] ~= nil, "array source A should be loaded")
    assert_true(by_url["https://test.array.com/b"] ~= nil, "array source B should be loaded")
    assert_true(by_url["https://test.wrapped.com/c"] ~= nil, "wrapped data source C should be loaded")

    print("✔ All format variants (single object, array, wrapped data) successfully loaded and merged")

    print("--- 2. Testing Sources Directory Exposure ---")
    local udir = storage.get_user_sources_dir()
    assert_true(udir ~= nil and #udir > 0, "get_user_sources_dir should return a valid directory path")
    assert_true(storage.USER_SOURCES_DIR == "sources", "storage.USER_SOURCES_DIR should be 'sources'")
    assert_true(storage.SOURCES_DIR == "assets/sources", "storage.SOURCES_DIR should be 'assets/sources'")

    print("--- 3. Testing Removal of Delete Function (Y Key Disabled) ---")
    sources_view.init()
    local count_before = #storage.get_sources()

    -- Simulate pressing 'y'
    local input_mock_y = {
        pressed = function(k) return k == "y" end
    }
    sources_view.update(0.016, input_mock_y)

    local count_after = #storage.get_sources()
    assert_eq(count_after, count_before, "Pressing Y MUST NOT delete book source")
    print("✔ Deletion via Y key successfully eliminated")

    print("--- 4. Testing Disable / Enable (停用 / 启用) Functionality ---")
    -- Find index of our test single source
    local single_idx = nil
    for idx, s in ipairs(storage.get_sources()) do
        if s.bookSourceUrl == "https://test.single.com" then
            single_idx = idx
            break
        end
    end
    assert_true(single_idx ~= nil, "test source index found")

    -- Move focus to single_idx
    sources_view.init()
    local input_mock_down = { pressed = function(k) return k == "down" end }
    for i = 1, single_idx - 1 do
        sources_view.update(0.016, input_mock_down)
    end

    -- Toggle disable with X
    local input_mock_x = { pressed = function(k) return k == "x" end }
    sources_view.update(0.016, input_mock_x)
    assert_eq(storage.get_sources()[single_idx].enabled, false, "Source should now be disabled (停用)")

    -- Check enabled counts
    local enabled_cnt, total_cnt = sources_view.get_enabled_counts()
    assert_eq(enabled_cnt, total_cnt - 1, "Enabled count should be total - 1")

    -- Test persistence across reload
    print("--- 5. Testing Persistence of Disabled State Across Reload ---")
    storage.reload_sources()
    local reloaded_sources = storage.get_sources()
    local reloaded_single = nil
    for _, s in ipairs(reloaded_sources) do
        if s.bookSourceUrl == "https://test.single.com" then
            reloaded_single = s
            break
        end
    end
    assert_true(reloaded_single ~= nil, "Source still present after reload")
    assert_eq(reloaded_single.enabled, false, "Source MUST REMAIN DISABLED after reloading from files")

    -- Toggle re-enable with X
    sources_view.update(0.016, input_mock_x)
    assert_eq(storage.get_sources()[single_idx].enabled, true, "Source should be re-enabled (启用)")

    -- Test batch disable (L2) and batch enable (R2)
    local input_mock_l2 = { pressed = function(k) return k == "l2" end }
    sources_view.update(0.016, input_mock_l2)
    local enc, _ = sources_view.get_enabled_counts()
    assert_eq(enc, 0, "L2 should disable all sources")

    local input_mock_r2 = { pressed = function(k) return k == "r2" end }
    sources_view.update(0.016, input_mock_r2)
    local enc2, tot2 = sources_view.get_enabled_counts()
    assert_eq(enc2, tot2, "R2 should enable all sources")

    print("✔ Disable/Enable toggle, batch L2/R2, and reload persistence tests passed")
end)

cleanup_test_files()

if not ok then
    error(err)
end

-- Re-init storage cleanly so subsequent tests use clean defaults
storage.init()

print("ALL MULTI-SOURCE & DISABLE TESTS PASSED SUCCESSFULLY!")
