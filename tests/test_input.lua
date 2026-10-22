-- tests/test_input.lua
package.path = package.path .. ";./?.lua;./src/?.lua"
local input = require("src.input")

local function assert_true(cond, msg)
    if not cond then error(msg or "Expected true") end
end
local function assert_false(cond, msg)
    if cond then error(msg or "Expected false") end
end
local function assert_eq(a, b, msg)
    if a ~= b then error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a))) end
end

-- 1. Test keyboard press -> single frame trigger
input.on_keypressed("z")
assert_true(input.is_down("a"), "A should be down via 'z'")
assert_true(input.pressed("a"), "A should be pressed in current frame")

-- 2. Test next frame state
input.update()
assert_true(input.is_down("a"), "A should still be down")
assert_false(input.pressed("a"), "A pressed state should clear after update")

-- 3. Test keyboard release
input.on_keyreleased("z")
assert_false(input.is_down("a"), "A should not be down after release")
assert_true(input.released("a"), "A should be released in current frame")

input.update()
assert_false(input.released("a"), "A released state should clear after update")

-- 4. Test Gamepad button mapping (e.g. dpup -> up)
input.on_gamepadpressed(nil, "dpup")
assert_true(input.is_down("up"), "up action should be active on dpup")
assert_true(input.pressed("up"), "up should be pressed")
input.update()
input.on_gamepadreleased(nil, "dpup")
assert_false(input.is_down("up"), "up action should be released")

-- 5. Test Analog axis and deadzone
input.on_gamepadaxis(nil, "leftx", 0.1) -- below 0.2 deadzone
assert_eq(input.get_axis("leftx"), 0, "Axis below deadzone should be 0")

input.on_gamepadaxis(nil, "leftx", 0.8)
assert_true(input.get_axis("leftx") > 0.5, "Axis above deadzone should register")
assert_true(input.is_down("right"), "Analog stick right should trigger right action")

-- [CRIT-1 TEST] Analog stick return to center must release D-pad action
input.on_gamepadaxis(nil, "leftx", 0.0)
input.update()
assert_false(input.is_down("right"), "Analog stick return to center should release right action")

-- [IMP-1 TEST] Multi-key press: releasing one key should not release action if other key still held
input.on_keypressed("z")
input.on_keypressed("return")
assert_true(input.is_down("a"), "A should be down when z and return pressed")
input.on_keyreleased("z")
assert_true(input.is_down("a"), "A should still be down because return is still held")
input.on_keyreleased("return")
assert_false(input.is_down("a"), "A should be released after both keys released")

-- [IMP-3 TEST] Space key should trigger action A
input.on_keypressed("space")
assert_true(input.is_down("a"), "Space key should trigger action A")
input.on_keyreleased("space")

-- 6. Test Dual Analog Sticks (L3, R3 and Right Stick)
input.on_gamepadpressed(nil, "leftstick")
assert_true(input.is_down("l3"), "L3 click should be registered")
input.on_gamepadreleased(nil, "leftstick")
assert_false(input.is_down("l3"), "L3 click should be released")

input.on_gamepadpressed(nil, "rightstick")
assert_true(input.is_down("r3"), "R3 click should be registered")
input.on_gamepadreleased(nil, "rightstick")

input.on_gamepadaxis(nil, "rightx", 0.75)
assert_true(input.get_axis("rightx") > 0.5, "Right stick X should register")
input.on_gamepadaxis(nil, "righty", -0.75)
assert_true(input.get_axis("righty") < -0.5, "Right stick Y should register")

print("All input tests passed!")
