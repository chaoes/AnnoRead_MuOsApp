local theme = {}

local current_theme = "dark"
local fonts = {}

local PALETTES = {
    dark = {
        bg = { 0.08, 0.09, 0.11, 1.0 },          -- #14171c
        surface = { 0.13, 0.15, 0.18, 1.0 },     -- #21262d
        surface_active = { 0.18, 0.22, 0.28, 1.0 },
        border = { 0.22, 0.25, 0.30, 1.0 },
        focus = { 0.23, 0.54, 0.98, 1.0 },       -- vibrant blue
        focus_bg = { 0.15, 0.25, 0.40, 0.6 },
        text = { 0.92, 0.94, 0.96, 1.0 },
        text_muted = { 0.55, 0.60, 0.66, 1.0 },
        accent = { 0.98, 0.55, 0.20, 1.0 },      -- orange accent
        success = { 0.24, 0.76, 0.45, 1.0 },     -- green
        danger = { 0.95, 0.32, 0.32, 1.0 },      -- red
        tab_bg = { 0.10, 0.11, 0.14, 1.0 },
        reader_bg = { 0.07, 0.07, 0.08, 1.0 },
        reader_text = { 0.82, 0.84, 0.86, 1.0 }
    },
    sepia = {
        bg = { 0.95, 0.92, 0.84, 1.0 },          -- parchment warm
        surface = { 0.90, 0.86, 0.77, 1.0 },
        surface_active = { 0.85, 0.80, 0.70, 1.0 },
        border = { 0.78, 0.72, 0.62, 1.0 },
        focus = { 0.65, 0.42, 0.20, 1.0 },       -- leather brown
        focus_bg = { 0.82, 0.75, 0.62, 0.6 },
        text = { 0.22, 0.18, 0.14, 1.0 },
        text_muted = { 0.50, 0.45, 0.38, 1.0 },
        accent = { 0.75, 0.38, 0.15, 1.0 },
        success = { 0.25, 0.55, 0.25, 1.0 },
        danger = { 0.80, 0.25, 0.20, 1.0 },
        tab_bg = { 0.88, 0.84, 0.75, 1.0 },
        reader_bg = { 0.96, 0.93, 0.86, 1.0 },
        reader_text = { 0.20, 0.16, 0.12, 1.0 }
    },
    light = {
        bg = { 0.96, 0.97, 0.98, 1.0 },
        surface = { 1.0, 1.0, 1.0, 1.0 },
        surface_active = { 0.92, 0.94, 0.96, 1.0 },
        border = { 0.82, 0.85, 0.88, 1.0 },
        focus = { 0.08, 0.45, 0.88, 1.0 },
        focus_bg = { 0.88, 0.93, 0.99, 0.8 },
        text = { 0.12, 0.14, 0.16, 1.0 },
        text_muted = { 0.45, 0.48, 0.52, 1.0 },
        accent = { 0.95, 0.45, 0.15, 1.0 },
        success = { 0.15, 0.65, 0.35, 1.0 },
        danger = { 0.88, 0.25, 0.25, 1.0 },
        tab_bg = { 0.91, 0.93, 0.95, 1.0 },
        reader_bg = { 0.98, 0.98, 0.98, 1.0 },
        reader_text = { 0.12, 0.14, 0.16, 1.0 }
    },
    jirai = {
        -- 地雷妹 (Jirai Kei) 风格：深邃哥特黑夜黑 + 甜酷病娇樱花/莓果粉 (#ff69b4 / #f77fbe) + 熏衣草/深黑紫细节
        bg = { 0.07, 0.05, 0.08, 1.0 },              -- 极深黑紫夜色 #120d14
        surface = { 0.14, 0.10, 0.16, 1.0 },         -- 深夜哥特暗层 #241a29
        surface_active = { 0.22, 0.15, 0.26, 1.0 },  -- 略明亮暗紫层 #382642
        border = { 0.38, 0.22, 0.36, 1.0 },          -- 暗粉紫勾线边框 #61385c
        focus = { 1.0, 0.41, 0.71, 1.0 },            -- 地雷高亮粉 / Hot Pink #ff69b4
        focus_bg = { 0.35, 0.10, 0.25, 0.65 },       -- 沉浸半透粉紫对焦底色
        text = { 0.96, 0.90, 0.95, 1.0 },            -- 粉白文本 #f5e6f2
        text_muted = { 0.68, 0.52, 0.66, 1.0 },      -- 烟粉灰弱化文本 #ad84a8
        accent = { 1.0, 0.55, 0.80, 1.0 },           -- 亮樱花粉重点色 #ff8ccc
        success = { 0.30, 0.85, 0.60, 1.0 },         -- 甜酷绿薄荷
        danger = { 0.95, 0.25, 0.45, 1.0 },          -- 莓果赤红 #f24073
        tab_bg = { 0.09, 0.06, 0.11, 1.0 },          -- 顶部 Tab 深黑紫底色 #170f1c
        reader_bg = { 0.06, 0.04, 0.07, 1.0 },       -- 阅读器舒适暗黑背景 #0f0a12
        reader_text = { 0.94, 0.88, 0.93, 1.0 }       -- 阅读器护眼柔和粉白 #f0e0ed
    }
}

-- Embedded CJK font search.
--
-- The bundled font is "Maple Mono NF CN" (Regular) -- a Nerd Font (patched with
-- ~10k icon glyphs) that also ships full Simplified Chinese coverage, licensed
-- under the SIL Open Font License 1.1 (see assets/fonts/OFL-MapleMono.txt).
-- It supersedes the previous WenQuanYi Zen Hei (.ttc).
--
-- The reader must render arbitrary novel text, so the FULL CJK font is shipped
-- (no glyph subsetting); only the Regular weight is bundled to keep the
-- download small.
local FONT_CANDIDATES = {
    "assets/fonts/MapleMono-NF-CN-Regular.ttf",
    "assets/font.ttf",
    "assets/font.ttc"
}

local function load_font_candidates(candidates)
    for _, path in ipairs(candidates) do
        local f = io.open(path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data and #data > 0 then
                local ok, fd = pcall(love.filesystem.newFileData, data, "cjk_font.ttf")
                if ok and fd then return fd end
            end
        end
    end
    return nil
end

local function find_font_file()
    local fd = load_font_candidates(FONT_CANDIDATES)
    if fd then return fd end
    -- Last-resort system fonts (host dev machines only).
    for _, p in ipairs({
        "/usr/share/fonts/wenquanyi/wqy-zenhei/wqy-zenhei.ttc",
        "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
    }) do
        local f = io.open(p, "rb")
        if f then
            local data = f:read("*a"); f:close()
            if data and #data > 0 then
                local ok, fd = pcall(love.filesystem.newFileData, data, "cjk_font.ttf")
                if ok and fd then return fd end
            end
        end
    end
    return nil
end

local cached_file_data = nil
local font_cache = {}

function theme.init()
    local file_data = find_font_file()
    cached_file_data = file_data
    local sizes = {
        title = 20,
        header = 17,
        body = 15,
        hint = 13,
        reader_large = 22,
        reader_medium = 18,
        reader_small = 15
    }

    for name, sz in pairs(sizes) do
        if file_data then
            local ok, f = pcall(love.graphics.newFont, file_data, sz)
            if ok and f then
                fonts[name] = f
            end
        end
        if not fonts[name] then
            fonts[name] = love.graphics.newFont(sz)
        end
    end
end

function theme.get_reader_font(size)
    size = math.max(12, math.min(36, math.floor(size + 0.5)))
    if not font_cache[size] then
        if cached_file_data and love and love.graphics and love.graphics.newFont then
            local ok, f = pcall(love.graphics.newFont, cached_file_data, size)
            if ok and f then font_cache[size] = f end
        end
        if not font_cache[size] and love and love.graphics and love.graphics.newFont then
            local ok, f = pcall(love.graphics.newFont, size)
            if ok and f then font_cache[size] = f end
        end
        if not font_cache[size] then
            font_cache[size] = {
                getWidth = function(_, str) return #str * (size * 0.5) end,
                getHeight = function(_) return size end
            }
        end
    end
    return font_cache[size]
end

local fallback_font = {
    getWidth = function(_, str) return #str * 8 end,
    getHeight = function(_) return 16 end
}

function theme.get_font(name)
    if fonts[name] then return fonts[name] end
    if fonts.body then return fonts.body end
    if love and love.graphics and love.graphics.getFont then
        return love.graphics.getFont() or fallback_font
    end
    return fallback_font
end

function theme.set_font(name)
    local f = theme.get_font(name)
    if f and love and love.graphics and love.graphics.setFont then
        love.graphics.setFont(f)
    end
end

function theme.colors()
    return PALETTES[current_theme] or PALETTES.dark
end

function theme.set_theme(name)
    if PALETTES[name] then
        current_theme = name
    end
end

function theme.cycle_theme()
    local order = { "dark", "sepia", "light", "jirai" }
    local next_idx = 1
    for i, t in ipairs(order) do
        if t == current_theme then
            next_idx = (i % #order) + 1
            break
        end
    end
    current_theme = order[next_idx]
    return current_theme
end

function theme.get_theme_name()
    return current_theme
end

-- Handheld-optimized UI drawing helpers
function theme.draw_panel(x, y, w, h, bg_color, border_color, radius)
    radius = radius or 6
    if bg_color then
        love.graphics.setColor(bg_color)
        love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    end
    if border_color then
        love.graphics.setColor(border_color)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h, radius, radius)
    end
end

function theme.draw_card(x, y, w, h, is_focused, is_active)
    local c = theme.colors()
    local radius = 8

    if is_focused then
        -- Focus highlight fill
        love.graphics.setColor(c.focus_bg)
        love.graphics.rectangle("fill", x, y, w, h, radius, radius)
        -- Glowing focus border
        love.graphics.setColor(c.focus)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h, radius, radius)
        -- Indicator badge on the left edge
        love.graphics.setColor(c.focus)
        love.graphics.rectangle("fill", x - 3, y + 6, 4, h - 12, 2, 2)
    else
        love.graphics.setColor(c.surface)
        love.graphics.rectangle("fill", x, y, w, h, radius, radius)
        love.graphics.setColor(c.border)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h, radius, radius)
    end
end

function theme.draw_focus_ring(x, y, w, h, radius, line_width)
    local c = theme.colors()
    radius = radius or 6
    line_width = line_width or 2
    love.graphics.setColor(c.focus)
    love.graphics.setLineWidth(line_width)
    love.graphics.rectangle("line", x, y, w, h, radius, radius)
    love.graphics.setLineWidth(1)
end

function theme.draw_pill(label, x, y, is_selected, is_focused, custom_font)
    local c = theme.colors()
    local font = custom_font or theme.get_font("hint")
    local text_w = font:getWidth(label)
    local text_h = font:getHeight()
    local pad_x = 12
    local pad_y = 6
    local w = text_w + pad_x * 2
    local h = text_h + pad_y * 2

    love.graphics.setFont(font)
    if is_selected then
        love.graphics.setColor(c.focus)
        love.graphics.rectangle("fill", x, y, w, h, h / 2, h / 2)
        love.graphics.setColor(1, 1, 1, 1)
    else
        love.graphics.setColor(c.surface)
        love.graphics.rectangle("fill", x, y, w, h, h / 2, h / 2)
        love.graphics.setColor(c.border)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h, h / 2, h / 2)
        love.graphics.setColor(c.text_muted)
    end

    love.graphics.print(label, x + pad_x, y + pad_y)

    if is_focused then
        love.graphics.setColor(c.accent)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4, (h + 4) / 2, (h + 4) / 2)
        love.graphics.setLineWidth(1)
    end

    return w, h
end

function theme.draw_key_badge(key_name, label, x, y)
    local c = theme.colors()
    local f_hint = theme.get_font("hint")
    love.graphics.setFont(f_hint)

    local kw = f_hint:getWidth(key_name) + 8
    local kh = f_hint:getHeight() + 4

    -- Key button pill
    love.graphics.setColor(c.surface_active)
    love.graphics.rectangle("fill", x, y, kw, kh, 4, 4)
    love.graphics.setColor(c.border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, kw, kh, 4, 4)

    love.graphics.setColor(c.accent)
    love.graphics.print(key_name, x + 4, y + 2)

    -- Label text
    love.graphics.setColor(c.text_muted)
    love.graphics.print(label, x + kw + 5, y + 2)

    return kw + 5 + f_hint:getWidth(label) + 12
end

return theme
