-- tests/test_power_and_safety.lua
--
-- Covers the handheld QoL/power batch:
--   1. Hold Start + Select for ~2s -> a single safe-exit trigger; releasing
--      either button resets the timer.
--   2. While both are held the individual Start/Select actions are swallowed so
--      they never leak to the reader (换源 / menu).
--   3. The frame pacer runs at 60 FPS while active, and drops to a low idle rate
--      (reader 15 / UI 20) only after a quiet window -- and snaps back on input.
--
-- Both modules are pure logic, so this runs under plain LuaJIT (no LÖVE).

package.path = package.path .. ";./?.lua;./src/?.lua"

local input = require("src.input")
local safety_quit = require("src.safety_quit")
local frame_pacer = require("src.frame_pacer")

local function assert_true(cond, msg)
    if not cond then error(msg or "Expected true") end
end

local function hold(action, down)
    if down then input.on_gamepadpressed(nil, action)
    else input.on_gamepadreleased(nil, action) end
end

print("--- 1. Holding Start alone never triggers the safety quit ---")
safety_quit.init()
input.update()
hold("start", true)
input.update()
for _ = 1, 200 do
    assert_true(safety_quit.update(1 / 60, input) == false, "Start alone must not quit")
end
hold("start", false)
input.update()

print("--- 2. Start + Select held ~2s triggers exactly once ---")
safety_quit.init()
hold("start", true)
hold("back", true) -- gamepad 'back' maps to action 'select'
input.update()
local fired = 0
local dt = 1 / 60
for _ = 1, 60 * 4 do
    if safety_quit.update(dt, input) then fired = fired + 1 end
    input.update()
end
assert_true(fired == 1, "The combo must fire exactly once, got " .. fired)

print("--- 3. Releasing either button resets the hold timer ---")
safety_quit.init()
hold("start", true)
hold("back", true)
input.update()
for _ = 1, 60 do safety_quit.update(dt, input); input.update() end -- ~1s held
assert_true(safety_quit.is_holding(), "Should be holding after 1s")
hold("back", false) -- release Select
input.update()
safety_quit.update(dt, input)
input.update()
assert_true(safety_quit.get_progress() == 0, "Releasing a button must reset progress")
-- Re-press and confirm it takes the FULL duration again (no partial credit).
hold("back", true)
input.update()
local fired2 = false
for _ = 1, 60 do -- only 1s more
    if safety_quit.update(dt, input) then fired2 = true end
    input.update()
end
assert_true(not fired2, "Partial hold must not accumulate to a trigger")
hold("back", false); hold("start", false)
input.update()

print("--- 4. Start/Select pressed actions are swallowed while the combo holds ---")
safety_quit.init()
hold("start", true)
hold("back", true)
assert_true(input.pressed("start") or input.pressed("select"),
    "sanity: a fresh press is visible before the combo consumes it")
safety_quit.update(dt, input)
assert_true(not input.pressed("start"), "Start press must be suppressed")
assert_true(not input.pressed("select"), "Select press must be suppressed")
input.update()
hold("back", false); hold("start", false)
input.update()

print("--- 5. Frame pacer: full speed while active, idle rate once quiet ---")
frame_pacer.init()
assert_true(frame_pacer.get_target_fps() == frame_pacer.FPS_ACTIVE, "Start at full rate")

-- Immediately after activity it stays at 60.
frame_pacer.note_activity()
frame_pacer.update(0.016, { context = "reader" })
assert_true(frame_pacer.get_target_fps() == frame_pacer.FPS_ACTIVE,
    "Recently active -> full rate")

-- After the active window in the reader it drops to the low idle rate.
local elapsed = 0
while elapsed < frame_pacer.ACTIVE_WINDOW + 0.1 do
    frame_pacer.update(0.05, { context = "reader" })
    elapsed = elapsed + 0.05
end
assert_true(frame_pacer.get_target_fps() == frame_pacer.FPS_READER_IDLE,
    "Idle reader should settle to the low reader rate")

-- Any new activity snaps back to full speed.
frame_pacer.note_activity()
frame_pacer.update(0.016, { context = "reader" })
assert_true(frame_pacer.get_target_fps() == frame_pacer.FPS_ACTIVE,
    "New input should snap back to full rate")

-- Busy (loading/caching) keeps full rate even when idle.
frame_pacer.init()
frame_pacer.update(0.05, { context = "reader" })
elapsed = 0
while elapsed < frame_pacer.ACTIVE_WINDOW + 0.1 do
    frame_pacer.update(0.05, { context = "reader", busy = true })
    elapsed = elapsed + 0.05
end
assert_true(frame_pacer.get_target_fps() == frame_pacer.FPS_ACTIVE,
    "busy must stay at full rate")

print("ALL POWER & SAFETY TESTS PASSED!")
