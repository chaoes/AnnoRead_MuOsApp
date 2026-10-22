local input = {}

local key_mappings = {
    -- Keyboard keys to action
    z = "a",
    ["return"] = "a",
    enter = "a",
    space = "a", -- Align with standard Jump/Action and documentation

    x = "b",
    backspace = "b",
    escape = "b",

    c = "x",

    v = "y",
    y = "y",

    up = "up",
    down = "down",
    left = "left",
    right = "right",

    w = "up",
    s = "down",
    a = "left",
    d = "right",

    q = "l1",
    pageup = "l1",

    e = "r1",
    pagedown = "r1",

    ["1"] = "l2",
    ["2"] = "r2",
    ["3"] = "l3",
    ["4"] = "r3",
    f = "l3",
    g = "r3",

    -- Right stick simulation on keyboard
    i = "r_up",
    k = "r_down",
    j = "r_left",
    l = "r_right",

    p = "start",
    f1 = "start",
    menu = "start",

    tab = "select",
    rshift = "select"
}

local text_input_mode = false

function input.set_text_input_mode(enabled)
    text_input_mode = enabled == true
end

function input.is_text_input_mode()
    return text_input_mode
end

local gamepad_mappings = {
    a = "a",
    b = "b",
    x = "x",
    y = "y",

    dpup = "up",
    dpdown = "down",
    dpleft = "left",
    dpright = "right",

    leftshoulder = "l1",
    rightshoulder = "r1",

    -- L2 / R2 are *axes* in LÖVE 11 (triggerleft / triggerright), handled in
    -- on_gamepadaxis below. These button entries are a harmless fallback for any
    -- platform that happens to report the triggers as buttons instead.
    triggerleft = "l2",
    triggerright = "r2",

    start = "start",
    back = "select",
    guide = "menu",

    leftstick = "l3",
    rightstick = "r3"
}

-- Analog triggers fire as axes with a 0..1 range; treat a firm pull as a press.
local TRIGGER_THRESHOLD = 0.5
-- Release once the trigger springs back below this (hysteresis band).
local TRIGGER_RELEASE = 0.2

local state = {
    is_down = {},
    pressed = {},
    released = {},
    sources = {},
    action_counts = {},
    axis = {
        leftx = 0,
        lefty = 0,
        rightx = 0,
        righty = 0
    },
    trigger = {
        left = 0,
        right = 0
    }
}

local DEADZONE = 0.2

function input.update()
    -- Clear single-frame transition states
    state.pressed = {}
    state.released = {}
end

function input.is_down(action)
    return state.is_down[action] == true
end

function input.pressed(action)
    return state.pressed[action] == true
end

function input.released(action)
    return state.released[action] == true
end

-- Any action currently held down? Used by the frame pacer to stay at full speed
-- while the player is interacting.
function input.any_down()
    return next(state.is_down) ~= nil
end

-- Any action that registered a fresh press this frame?
function input.any_pressed()
    return next(state.pressed) ~= nil
end

-- Swallow a single-frame press/release transition so downstream views never see
-- it. Used by the global long-press quit combo to suppress the individual
-- Start/Select actions while both are held together.
function input.consume(action)
    if not action then return end
    state.pressed[action] = nil
    state.released[action] = nil
end

function input.get_axis(axis_name)
    return state.axis[axis_name] or 0
end

local function set_source_down(action, source_id)
    if not action or not source_id then return end
    if not state.sources[source_id] then
        state.sources[source_id] = true
        local count = (state.action_counts[action] or 0) + 1
        state.action_counts[action] = count
        if count == 1 then
            state.is_down[action] = true
            state.pressed[action] = true
        end
    end
end

local function set_source_up(action, source_id)
    if not action or not source_id then return end
    if state.sources[source_id] then
        state.sources[source_id] = nil
        local count = math.max(0, (state.action_counts[action] or 1) - 1)
        state.action_counts[action] = count
        if count == 0 then
            state.is_down[action] = nil
            state.released[action] = true
        end
    end
end

function input.on_keypressed(key)
    if text_input_mode and #key == 1 and key:match("%a") then
        return
    end

    local action = key_mappings[key]
    if action then
        set_source_down(action, "key:" .. tostring(key))
    end

    -- Keyboard right stick simulation
    if not text_input_mode then
        if key == "j" then state.axis.rightx = -1.0
        elseif key == "l" then state.axis.rightx = 1.0
        elseif key == "i" then state.axis.righty = -1.0
        elseif key == "k" then state.axis.righty = 1.0
        end
    end
end

function input.on_keyreleased(key)
    local action = key_mappings[key]
    if action then
        set_source_up(action, "key:" .. tostring(key))
    end

    -- Keyboard right stick release
    if key == "j" and state.axis.rightx < 0 then state.axis.rightx = 0
    elseif key == "l" and state.axis.rightx > 0 then state.axis.rightx = 0
    elseif key == "i" and state.axis.righty < 0 then state.axis.righty = 0
    elseif key == "k" and state.axis.righty > 0 then state.axis.righty = 0
    end
end

function input.on_gamepadpressed(joystick, button)
    local action = gamepad_mappings[button]
    if action then
        set_source_down(action, "btn:" .. tostring(button))
    end
end

function input.on_gamepadreleased(joystick, button)
    local action = gamepad_mappings[button]
    if action then
        set_source_up(action, "btn:" .. tostring(button))
    end
end

function input.on_gamepadaxis(joystick, axis, value)
    -- Analog triggers (L2/R2) arrive as axes named triggerleft/triggerright.
    -- They are not exposed as buttons by LÖVE 11, so we normalise them into the
    -- l2 / r2 actions here. Cross the threshold to press, drop back near zero to
    -- release (hysteresis avoids flicker at the boundary).
    if axis == "triggerleft" or axis == "triggerright" then
        local is_left = (axis == "triggerleft")
        local action = is_left and "l2" or "r2"
        local source_id = is_left and "axis:triggerleft" or "axis:triggerright"
        if is_left then state.trigger.left = value else state.trigger.right = value end
        if value >= TRIGGER_THRESHOLD then
            set_source_down(action, source_id)
        elseif value < TRIGGER_RELEASE then
            set_source_up(action, source_id)
        end
        -- between TRIGGER_RELEASE and TRIGGER_THRESHOLD: keep the current state
        -- (hysteresis, so a trigger resting just below the press point does not
        --  chatter on and off)
        return
    end

    if not state.axis[axis] then
        return
    end

    if math.abs(value) < DEADZONE then
        state.axis[axis] = 0
    else
        local sign = value > 0 and 1 or -1
        local normalized = (math.abs(value) - DEADZONE) / (1 - DEADZONE)
        state.axis[axis] = sign * normalized
    end

    -- Map primary analog stick to D-Pad actions with clean enter/exit thresholds
    if axis == "leftx" then
        if state.axis.leftx > 0.5 then
            set_source_down("right", "axis:leftx_pos")
            set_source_up("left", "axis:leftx_neg")
        elseif state.axis.leftx < -0.5 then
            set_source_down("left", "axis:leftx_neg")
            set_source_up("right", "axis:leftx_pos")
        else
            set_source_up("left", "axis:leftx_neg")
            set_source_up("right", "axis:leftx_pos")
        end
    elseif axis == "lefty" then
        if state.axis.lefty > 0.5 then
            set_source_down("down", "axis:lefty_pos")
            set_source_up("up", "axis:lefty_neg")
        elseif state.axis.lefty < -0.5 then
            set_source_down("up", "axis:lefty_neg")
            set_source_up("down", "axis:lefty_pos")
        else
            set_source_up("up", "axis:lefty_neg")
            set_source_up("down", "axis:lefty_pos")
        end
    end
end

return input
