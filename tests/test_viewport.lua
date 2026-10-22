-- tests/test_viewport.lua
package.path = package.path .. ";./?.lua;./src/?.lua"
local viewport = require("src.viewport")

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

viewport.init(720, 720)
assert_eq(viewport.get_mode(), "native", "Initial mode should be native")

local w, h = viewport.get_dimensions()
assert_eq(w, 720, "Virtual width")
assert_eq(h, 720, "Virtual height")

viewport.set_mode("pixel_360")
assert_eq(viewport.get_mode(), "pixel_360", "Switched to pixel_360")
w, h = viewport.get_dimensions()
assert_eq(w, 360, "Pixel 360 width")
assert_eq(h, 360, "Pixel 360 height")

viewport.set_mode("pixel_240")
w, h = viewport.get_dimensions()
assert_eq(w, 240, "Pixel 240 width")
assert_eq(h, 240, "Pixel 240 height")

-- Test to_virtual coordinate projection
local vx, vy = viewport.to_virtual(360, 360, 720, 720)
assert_eq(vx, 120, "Virtual X in pixel_240 mode when screen is 720x720")
assert_eq(vy, 120, "Virtual Y in pixel_240 mode when screen is 720x720")

print("All viewport tests passed!")
