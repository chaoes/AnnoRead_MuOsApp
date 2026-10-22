-- src/safety_quit.lua
--
-- Global "hold Start + Select" safety exit.
--
-- Handhelds have no OS-level window manager, so if the app ever wedges (or the
-- player simply wants out without digging through the 设置 tab) there must be a
-- hardware escape hatch. Holding **Start + Select together** for HOLD_SECONDS
-- triggers a clean shutdown: progress is saved first, then love.event.quit().
--
-- The combo is deliberately *global* (works in the reader, in every tab and on
-- top of every modal) and deliberately *hard to trigger by accident*: both keys
-- must be down at once for the full duration, and releasing either key resets
-- the timer.
--
-- This module is pure logic (no love.* calls except an optional callback), so it
-- is fully unit-testable under plain LuaJIT.

local safety_quit = {}

local HOLD_SECONDS = 2.0

local holding = false
local elapsed = 0

-- on_trigger callback is fired once when the hold completes.
local on_trigger = nil
-- on_tick callback (progress 0..1) is fired every frame while holding; optional.
local on_tick = nil

function safety_quit.init()
    holding = false
    elapsed = 0
end

function safety_quit.set_handlers(opts)
    opts = opts or {}
    on_trigger = opts.on_trigger
    on_tick = opts.on_tick
end

function safety_quit.get_hold_seconds()
    return HOLD_SECONDS
end

function safety_quit.is_holding()
    return holding
end

-- 0..1 progress towards the exit trigger (for an on-screen indicator).
function safety_quit.get_progress()
    if HOLD_SECONDS <= 0 then return 0 end
    local p = elapsed / HOLD_SECONDS
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    return p
end

-- Test/debug hook: force the hold indicator state (screenshot helper).
function safety_quit._test_hold(progress)
    holding = true
    elapsed = (progress or 0.5) * HOLD_SECONDS
end

-- Feed one frame in. `input` is src/input. Returns true exactly once, on the
-- frame the hold completes (so the caller can perform the safe exit).
function safety_quit.update(dt, input)
    if not input then return false end

    local both = input.is_down("start") and input.is_down("select")
    if not both then
        holding = false
        elapsed = 0
        return false
    end

    -- While both keys are held they must not leak their normal single-press
    -- actions (Start changes the source in the reader, Select opens the menu).
    input.consume("start")
    input.consume("select")

    holding = true
    elapsed = elapsed + (dt or 0)

    if on_tick then on_tick(safety_quit.get_progress()) end
    if elapsed < HOLD_SECONDS then return false end

    -- Completed: fire once, then reset so it cannot re-fire while still held.
    holding = false
    elapsed = 0
    if on_trigger then on_trigger() end
    return true
end

return safety_quit
