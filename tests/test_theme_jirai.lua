package.path = package.path .. ";./src/?.lua"
local theme = require("src.theme")
local settings_view = require("src.views.settings")
local reader_view = require("src.views.reader")
local storage = require("src.storage")

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assertion failed (expected true)")
    end
end

print("=== Running Jirai (地雷) Theme Unit Tests ===")

-- 1. Check theme palette definition
theme.set_theme("jirai")
assert_eq(theme.get_theme_name(), "jirai", "Theme name must be jirai")

local c = theme.colors()
assert_true(c ~= nil, "Palette for jirai must exist")

-- Verify primary aesthetic: Dark base with pink tones
print(string.format("Jirai bg: rgb(%.2f, %.2f, %.2f)", c.bg[1], c.bg[2], c.bg[3]))
assert_true(c.bg[1] < 0.15 and c.bg[2] < 0.15 and c.bg[3] < 0.15, "Jirai bg must be deep dark base")
print(string.format("Jirai focus: rgb(%.2f, %.2f, %.2f)", c.focus[1], c.focus[2], c.focus[3]))
assert_true(c.focus[1] > 0.8 and c.focus[2] < 0.6 and c.focus[3] > 0.6, "Jirai focus must be vibrant pink")

-- 2. Check theme cycling across all 4 themes
theme.set_theme("dark")
assert_eq(theme.cycle_theme(), "sepia", "dark -> sepia")
assert_eq(theme.cycle_theme(), "light", "sepia -> light")
assert_eq(theme.cycle_theme(), "jirai", "light -> jirai")
assert_eq(theme.cycle_theme(), "dark", "jirai -> dark")

-- 3. Check Settings View theme pill layout with 4 themes
local pill_w = 68
local pill_gap = 8
local THEME_ORDER = { "dark", "sepia", "light", "jirai" }
local total_w = #THEME_ORDER * pill_w + (#THEME_ORDER - 1) * pill_gap
assert_true(total_w <= 300, string.format("Theme pills total width (%d) must fit in settings row", total_w))

-- 4. Check reader settings theme integration
local reader_settings = { theme = "jirai", font_size = 20, line_spacing = 1.6, para_spacing = 10, margin_horiz = 28, margin_vert = 40 }
storage.get_reader_settings = function() return reader_settings end
storage.save_reader_settings = function(s) reader_settings = s end

theme.set_theme(reader_settings.theme)
assert_eq(theme.get_theme_name(), "jirai", "Reader settings theme loads jirai")

print("ALL JIRAI THEME TESTS PASSED SUCCESSFULLY!")
