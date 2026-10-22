package.path = package.path .. ";./src/?.lua"
local storage = require("src.storage")
local sources_view = require("src.views.sources")

print("=== Running Sources Batch Toggle Unit Tests ===")

storage.init()
local all_sources = storage.get_sources()
if #all_sources < 2 then
    all_sources[1] = { bookSourceName = "测试源 A", bookSourceUrl = "https://a.example.invalid", enabled = true }
    all_sources[2] = { bookSourceName = "测试源 B", bookSourceUrl = "https://b.example.invalid", enabled = true }
end

-- 1. Batch disable all
sources_view.batch_toggle_all(false)
for _, s in ipairs(storage.get_sources()) do
    assert(s.enabled == false, "Source should be disabled: " .. tostring(s.bookSourceName))
end
local enabled_cnt, total_cnt = sources_view.get_enabled_counts()
assert(enabled_cnt == 0, "Enabled count should be 0")
assert(total_cnt == #all_sources, "Total count mismatch")

-- 2. Batch enable all
sources_view.batch_toggle_all(true)
for _, s in ipairs(storage.get_sources()) do
    assert(s.enabled == true, "Source should be enabled: " .. tostring(s.bookSourceName))
end
enabled_cnt, total_cnt = sources_view.get_enabled_counts()
assert(enabled_cnt == total_cnt, "All sources should be enabled")

print("✔ Sources Batch Toggle Tests passed successfully!")
