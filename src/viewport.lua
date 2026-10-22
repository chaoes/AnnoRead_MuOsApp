local viewport = {}

local modes = {
    native = { width = 720, height = 720, filter = "linear" },
    pixel_360 = { width = 360, height = 360, filter = "nearest" },
    pixel_240 = { width = 240, height = 240, filter = "nearest" }
}

local current_mode = "native"
local current_w = 720
local current_h = 720
local canvas = nil

function viewport.init(virtual_w, virtual_h)
    virtual_w = virtual_w or 720
    virtual_h = virtual_h or 720
    modes.native.width = virtual_w
    modes.native.height = virtual_h
    viewport.set_mode("native")
end

local function recreate_canvas()
    if not (love and love.graphics and love.graphics.newCanvas) then
        return
    end

    local cfg = modes[current_mode] or modes.native
    canvas = love.graphics.newCanvas(cfg.width, cfg.height)
    canvas:setFilter(cfg.filter, cfg.filter)
end

function viewport.set_mode(mode_name)
    if not modes[mode_name] then
        mode_name = "native"
    end
    current_mode = mode_name
    current_w = modes[mode_name].width
    current_h = modes[mode_name].height
    recreate_canvas()
end

function viewport.get_mode()
    return current_mode
end

function viewport.get_dimensions()
    return current_w, current_h
end

local function calculate_transform(win_w, win_h)
    if not win_w or not win_h then
        if love and love.graphics and love.graphics.getDimensions then
            win_w, win_h = love.graphics.getDimensions()
        else
            win_w, win_h = current_w, current_h
        end
    end

    local scale = math.min(win_w / current_w, win_h / current_h)
    local offset_x = math.floor((win_w - current_w * scale) / 2)
    local offset_y = math.floor((win_h - current_h * scale) / 2)

    return scale, offset_x, offset_y, win_w, win_h
end

function viewport.get_transform(win_w, win_h)
    return calculate_transform(win_w, win_h)
end

function viewport.to_virtual(screen_x, screen_y, win_w, win_h)
    local scale, offset_x, offset_y = calculate_transform(win_w, win_h)
    local vx = (screen_x - offset_x) / scale
    local vy = (screen_y - offset_y) / scale
    return math.floor(vx + 0.5), math.floor(vy + 0.5)
end

function viewport.to_screen(virt_x, virt_y, win_w, win_h)
    local scale, offset_x, offset_y = calculate_transform(win_w, win_h)
    local sx = math.floor(offset_x + virt_x * scale + 0.5)
    local sy = math.floor(offset_y + virt_y * scale + 0.5)
    return sx, sy
end

function viewport.begin_draw()
    if not (love and love.graphics) then return end

    if not canvas then
        recreate_canvas()
    end

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.08, 0.08, 0.1, 1.0)
    love.graphics.push("all")
    love.graphics.origin()
end

function viewport.end_draw()
    if not (love and love.graphics and canvas) then return end

    love.graphics.pop()
    love.graphics.setCanvas()

    local scale, offset_x, offset_y = calculate_transform()

    -- Clear screen border area (letterbox)
    love.graphics.clear(0.02, 0.02, 0.03, 1.0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, offset_x, offset_y, 0, scale, scale)
end

return viewport
