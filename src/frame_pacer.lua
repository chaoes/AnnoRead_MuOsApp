-- src/frame_pacer.lua
--
-- Power saving: LÖVE's default love.run renders "flat out" and never yields the
-- CPU, which on a handheld means the SoC stays pegged and the battery drains
-- fast. main.lua therefore installs a custom love.run that sleeps for the
-- remainder of each frame; this module decides how long that frame should last.
--
-- Strategy:
--   * While the player is interacting (any key/gamepad activity in the last
--     ACTIVE_WINDOW seconds) or a view is busy (loading / caching / toast), run
--     at the full 60 FPS for snappy input.
--   * Once everything is static, drop the redraw rate:
--       - reader  -> FPS_READER_IDLE  (the page is static text; 15 FPS is
--                                    imperceptible and roughly quarters the GPU
--                                    and CPU wake-ups vs 60)
--       - UI tabs -> FPS_UI_IDLE      (20 FPS still lets the short scroll
--                                    smoothing settle)
--
-- The drop is fade-in/out: interacting instantly snaps back to 60 FPS and it
-- only settles to the idle rate after the window elapses, so nothing ever feels
-- laggy.
--
-- Pure logic (no love.* calls) so it unit-tests under plain LuaJIT.

local pacer = {}

local FPS_ACTIVE = 60
local FPS_READER_IDLE = 15
local FPS_UI_IDLE = 20

-- How long the app keeps rendering at full speed after the last input event.
local ACTIVE_WINDOW = 0.6

local target = FPS_ACTIVE
local idle_elapsed = ACTIVE_WINDOW

function pacer.init()
    target = FPS_ACTIVE
    idle_elapsed = ACTIVE_WINDOW
end

-- Call on any user interaction (key/gamepad/mouse event or a held input) to
-- snap back to full frame rate.
function pacer.note_activity()
    idle_elapsed = 0
end

-- opts.busy     -> true while a view is loading / downloading / showing a toast
-- opts.context  -> "reader" or "ui" (ignored while busy or recently active)
-- Returns the chosen target FPS for this frame.
function pacer.update(dt, opts)
    opts = opts or {}
    idle_elapsed = idle_elapsed + (dt or 0)

    if opts.busy or idle_elapsed < ACTIVE_WINDOW then
        target = FPS_ACTIVE
    elseif opts.context == "reader" then
        target = FPS_READER_IDLE
    else
        target = FPS_UI_IDLE
    end
    return target
end

function pacer.get_target_fps()
    return target
end

-- Seconds one frame should take at the current target rate.
function pacer.get_frame_time()
    return 1 / target
end

pacer.FPS_ACTIVE = FPS_ACTIVE
pacer.FPS_READER_IDLE = FPS_READER_IDLE
pacer.FPS_UI_IDLE = FPS_UI_IDLE
pacer.ACTIVE_WINDOW = ACTIVE_WINDOW

return pacer
