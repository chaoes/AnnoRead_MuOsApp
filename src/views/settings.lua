local theme = require("src.theme")
local storage = require("src.storage")
local cache = require("src.cache")
local tts_cache = require("src.tts_cache")
local settings_view = {}

local ROW_THEME = 1
local ROW_CACHE = 2
local ROW_QUIT = 3
local ROW_ABOUT = 4
local ROW_COUNT = 4

local APP_NAME = "AnnoRead 阿诺阅读"
local APP_VERSION = "v3.0"

local selected_idx = 1

-- Row layout. The first three rows are two-line cards; the 关于 row carries
-- three lines, so it gets a taller card -- otherwise its last line collides
-- with the card's bottom edge on the 720x720 layout.
local ROW_H = 72
local ROW_GAP = 12
local ROW_START_Y = 84
local ABOUT_ROW_H = 94

local function row_height(i)
    return (i == ROW_ABOUT) and ABOUT_ROW_H or ROW_H
end

-- Vertical position of row i (1-based).
local function row_y(i)
    local y = ROW_START_Y
    for k = 1, i - 1 do
        y = y + row_height(k) + ROW_GAP
    end
    return y
end

-- Test/debug hook: expose computed row rectangles (x, y, w, h) so a regression
-- test can assert nothing overflows the 720x720 playfield / overlaps.
function settings_view._row_layout()
    local out = {}
    for i = 1, ROW_COUNT do
        out[i] = { x = 24, y = row_y(i), w = 720 - 48, h = row_height(i) }
    end
    return out
end

-- Generic confirmation dialog state.
-- confirm_kind: "quit" | "clear_off_shelf" | "clear_all" | nil
local show_confirm = false
local confirm_kind = nil
local confirm_focus = 2 -- 1: 确认, 2: 取消

-- Transient toast message (e.g. cache cleared result).
local toast_msg = ""
local toast_timer = 0

local THEME_ORDER = { "dark", "sepia", "light", "jirai" }
local THEME_NAMES = { dark = "暗黑", sepia = "羊皮纸", light = "明亮", jirai = "地雷" }

local function get_settings()
    return storage.get_reader_settings()
end

local function shelf_url_set()
    local set = {}
    for _, b in ipairs(storage.get_books()) do
        if b.bookUrl then set[b.bookUrl] = true end
    end
    return set
end

local function apply_theme(name)
    local s = get_settings()
    s.theme = name
    storage.save_reader_settings(s)
    theme.set_theme(name)
end

local function cycle_theme(dir)
    local s = get_settings()
    local idx = 1
    for i, t in ipairs(THEME_ORDER) do
        if t == s.theme then
            idx = i
            break
        end
    end
    idx = ((idx - 1 + dir) % #THEME_ORDER) + 1
    apply_theme(THEME_ORDER[idx])
end

local function set_toast(msg)
    toast_msg = msg or ""
    toast_timer = 3
end

-- Delete cached chapters for books that are NOT on the shelf.
local function clear_off_shelf_cache()
    local keep = {}
    for url in pairs(shelf_url_set()) do
        table.insert(keep, url)
    end
    local removed = cache.clear_except(keep)
    set_toast(string.format("已清理 %d 本书的缓存（不在书架）", removed))
end

local function clear_all_cache()
    local removed = cache.clear_all()
    pcall(tts_cache.clear_all)
    set_toast(string.format("已清空全部文本与语音缓存（%d 本书）", removed))
end

function settings_view.init()
    selected_idx = 1
    show_confirm = false
    confirm_kind = nil
    confirm_focus = 2
    toast_msg = ""
    toast_timer = 0
end

function settings_view.is_confirm_open()
    return show_confirm
end

function settings_view.close_confirm()
    show_confirm = false
    confirm_kind = nil
end

function settings_view.open_confirm()
    selected_idx = ROW_QUIT
    show_confirm = true
    confirm_kind = "quit"
    confirm_focus = 2
end

function settings_view.update(dt, input)
    if toast_timer > 0 then
        toast_timer = toast_timer - dt
        if toast_timer <= 0 then toast_msg = "" end
    end

    -- 1. Confirmation dialog takes over input
    if show_confirm then
        if input.pressed("left") or input.pressed("right") then
            confirm_focus = (confirm_focus == 1) and 2 or 1
        elseif input.pressed("a") then
            local kind = confirm_kind
            show_confirm = false
            confirm_kind = nil
            if confirm_focus == 1 then
                if kind == "quit" then
                    return { action = "quit" }
                elseif kind == "clear_off_shelf" then
                    clear_off_shelf_cache()
                elseif kind == "clear_all" then
                    clear_all_cache()
                end
            end
        elseif input.pressed("b") then
            show_confirm = false
            confirm_kind = nil
        end
        return nil
    end

    -- 2. Vertical navigation over the setting rows
    if input.pressed("up") then
        if selected_idx == 1 then
            return { action = "focus_tabs" }
        else
            selected_idx = selected_idx - 1
        end
    elseif input.pressed("down") then
        selected_idx = math.min(ROW_COUNT, selected_idx + 1)
    end

    -- 3. Row actions
    if selected_idx == ROW_THEME then
        if input.pressed("left") then
            cycle_theme(-1)
        elseif input.pressed("right") or input.pressed("a") then
            cycle_theme(1)
        end
    elseif selected_idx == ROW_CACHE then
        -- ◀: clear off-shelf cache only; ▶/A: prompt to clear ALL cache
        if input.pressed("left") then
            show_confirm = true
            confirm_kind = "clear_off_shelf"
            confirm_focus = 2
        elseif input.pressed("right") or input.pressed("a") then
            show_confirm = true
            confirm_kind = "clear_all"
            confirm_focus = 2
        end
    elseif selected_idx == ROW_QUIT then
        if input.pressed("a") then
            show_confirm = true
            confirm_kind = "quit"
            confirm_focus = 2
        end
    end

    return nil
end

function settings_view.mousepressed(vx, vy, button)
    local card_x = 24
    local card_w = 720 - 48

    if show_confirm then
        local mw = 480
        local mh = 210
        local mx = math.floor((720 - mw) / 2)
        local my = math.floor((720 - mh) / 2)

        if vx < mx or vx > mx + mw or vy < my or vy > my + mh then
            show_confirm = false
            confirm_kind = nil
            return nil
        end

        local btn_w = 150
        local btn_h = 40
        local btn_y = my + 140
        local ok_x = mx + 55
        local cancel_x = mx + mw - 55 - btn_w

        if vy >= btn_y and vy <= btn_y + btn_h then
            if vx >= ok_x and vx <= ok_x + btn_w then
                local kind = confirm_kind
                show_confirm = false
                confirm_kind = nil
                if kind == "quit" then
                    return { action = "quit" }
                elseif kind == "clear_off_shelf" then
                    clear_off_shelf_cache()
                elseif kind == "clear_all" then
                    clear_all_cache()
                end
                return nil
            elseif vx >= cancel_x and vx <= cancel_x + btn_w then
                show_confirm = false
                confirm_kind = nil
                return nil
            end
        end
        return nil
    end

    if vx >= card_x and vx <= card_x + card_w then
        for i = 1, ROW_COUNT do
            local cy = row_y(i)
            local rh = row_height(i)
            if vy >= cy and vy <= cy + rh then
                if i == ROW_THEME then
                    local pill_w = 68
                    local pill_gap = 8
                    local total_w = #THEME_ORDER * pill_w + (#THEME_ORDER - 1) * pill_gap
                    local px = card_x + card_w - total_w - 16
                    for j, t in ipairs(THEME_ORDER) do
                        local tx = px + (j - 1) * (pill_w + pill_gap)
                        if vx >= tx and vx <= tx + pill_w then
                            selected_idx = i
                            apply_theme(t)
                            return nil
                        end
                    end
                elseif i == ROW_CACHE then
                    selected_idx = i
                    -- Two buttons on the right: [清理书架外] and [清空全部]
                    local btn_off_w = 130
                    local btn_all_w = 96
                    local gap = 8
                    local all_x = card_x + card_w - btn_all_w - 16
                    local off_x = all_x - btn_off_w - gap
                    if vx >= off_x and vx <= off_x + btn_off_w then
                        show_confirm = true
                        confirm_kind = "clear_off_shelf"
                        confirm_focus = 2
                    elseif vx >= all_x and vx <= all_x + btn_all_w then
                        show_confirm = true
                        confirm_kind = "clear_all"
                        confirm_focus = 2
                    end
                    return nil
                elseif i == ROW_QUIT then
                    if vx >= card_x + card_w - 190 then
                        selected_idx = i
                        show_confirm = true
                        confirm_kind = "quit"
                        confirm_focus = 2
                    end
                    return nil
                else
                    selected_idx = i
                    return nil
                end
            end
        end
    end
    return nil
end

local function draw_theme_row(card_x, cy, card_w, card_h, is_focused)
    local c = theme.colors()
    local s = get_settings()

    theme.set_font("body")
    love.graphics.setColor(is_focused and c.focus or c.text)
    love.graphics.print("背景主题", card_x + 16, cy + 24)

    local pill_w = 68
    local pill_h = 34
    local pill_gap = 8
    local total_w = #THEME_ORDER * pill_w + (#THEME_ORDER - 1) * pill_gap
    local px = card_x + card_w - total_w - 16
    local py = cy + (card_h - pill_h) / 2

    theme.set_font("hint")
    for _, t in ipairs(THEME_ORDER) do
        local is_active = (s.theme == t)
        local is_pill_focused = is_focused and is_active
        theme.draw_panel(px, py, pill_w, pill_h,
            is_active and c.focus or c.surface,
            is_pill_focused and c.accent or (is_active and c.focus or c.border), 6)
        if is_pill_focused then
            theme.draw_focus_ring(px, py, pill_w, pill_h, 6, 2)
        end
        love.graphics.setColor(is_active and { 1, 1, 1, 1 } or c.text_muted)
        local tw = theme.get_font("hint"):getWidth(THEME_NAMES[t] or t)
        love.graphics.print(THEME_NAMES[t] or t, px + (pill_w - tw) / 2, py + 8)
        px = px + pill_w + pill_gap
    end
end

local function draw_cache_row(card_x, cy, card_w, card_h, is_focused)
    local c = theme.colors()

    theme.set_font("body")
    love.graphics.setColor(is_focused and c.focus or c.text)
    love.graphics.print("缓存管理", card_x + 16, cy + 14)

    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    local chapters = cache.count_chapters()
    local books = #cache.list_books()
    love.graphics.print(string.format("已缓存 %d 章 / %d 本书", chapters, books), card_x + 16, cy + 42)

    -- Two buttons on the right
    local btn_w = 96
    local btn_h = 36
    local gap = 8
    local all_x = card_x + card_w - btn_w - 16
    local off_w = 130
    local off_x = all_x - off_w - gap
    local btn_y = cy + (card_h - btn_h) / 2

    -- [清理书架外] (danger-lite)
    theme.draw_panel(off_x, btn_y, off_w, btn_h,
        is_focused and c.surface_active or c.surface, is_focused and c.accent or c.border, 8)
    theme.set_font("hint")
    love.graphics.setColor(is_focused and c.accent or c.text_muted)
    local t1 = "清理书架外"
    love.graphics.print(t1, off_x + (off_w - theme.get_font("hint"):getWidth(t1)) / 2, btn_y + 10)

    -- [清空全部] (danger)
    theme.draw_panel(all_x, btn_y, btn_w, btn_h,
        is_focused and c.surface_active or c.surface, is_focused and c.danger or c.border, 8)
    love.graphics.setColor(is_focused and c.danger or c.text_muted)
    local t2 = "清空全部"
    love.graphics.print(t2, all_x + (btn_w - theme.get_font("hint"):getWidth(t2)) / 2, btn_y + 10)
end

local function draw_quit_row(card_x, cy, card_w, card_h, is_focused)
    local c = theme.colors()

    theme.set_font("body")
    love.graphics.setColor(is_focused and c.focus or c.text)
    love.graphics.print("退出应用", card_x + 16, cy + 16)

    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    love.graphics.print("关闭 AnnoRead 并返回 muOS 系统界面", card_x + 16, cy + 42)

    local btn_w = 120
    local btn_h = 36
    local btn_x = card_x + card_w - btn_w - 16
    local btn_y = cy + (card_h - btn_h) / 2
    theme.draw_panel(btn_x, btn_y, btn_w, btn_h,
        is_focused and c.danger or c.surface_active,
        is_focused and c.danger or c.border, 8)
    theme.set_font("body")
    love.graphics.setColor(is_focused and { 1, 1, 1, 1 } or c.danger)
    local tw = theme.get_font("body"):getWidth("退 出")
    love.graphics.print("退 出", btn_x + (btn_w - tw) / 2, btn_y + 8)
end

local function draw_about_row(card_x, cy, card_w, card_h, is_focused)
    local c = theme.colors()

    theme.set_font("body")
    love.graphics.setColor(is_focused and c.focus or c.text)
    love.graphics.print("关于", card_x + 16, cy + 16)

    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    love.graphics.print(APP_NAME .. "  " .. APP_VERSION, card_x + 16, cy + 46)
    love.graphics.print("Legado 3.0 规则引擎 · 多书源阅读器", card_x + 16, cy + 68)
end

local CONFIRM_TITLES = {
    quit = "退出确认",
    clear_off_shelf = "清理缓存确认",
    clear_all = "清空缓存确认",
}
local CONFIRM_PROMPTS = {
    quit = "确定要退出 AnnoRead 吗？",
    clear_off_shelf = "清理【不在书架】的书籍缓存？",
    clear_all = "清空【全部】章节缓存？",
}
local CONFIRM_NOTES = {
    quit = "当前阅读进度与书架已自动保存",
    clear_off_shelf = "书架内书籍的缓存会保留",
    clear_all = "所有离线缓存都会被删除",
}

function settings_view.draw(w, h, is_view_focused)
    if is_view_focused == nil then is_view_focused = true end
    local c = theme.colors()

    local card_x = 24
    local card_w = w - 48

    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    love.graphics.print("系统设置   [▲] 返回顶部标签", card_x, 58)

    local rows = {
        { draw = draw_theme_row },
        { draw = draw_cache_row },
        { draw = draw_quit_row },
        { draw = draw_about_row }
    }

    for i, r in ipairs(rows) do
        local cy = row_y(i)
        local rh = row_height(i)
        local is_focused = is_view_focused and (i == selected_idx) and not show_confirm
        theme.draw_card(card_x, cy, card_w, rh, is_focused)
        r.draw(card_x, cy, card_w, rh, is_focused)
    end

    -- Toast message
    if toast_msg ~= "" then
        theme.set_font("hint")
        local tw = theme.get_font("hint"):getWidth(toast_msg) + 32
        local tx = (w - tw) / 2
        local ty = h - 78
        theme.draw_panel(tx, ty, tw, 30, c.surface_active, c.focus, 8)
        love.graphics.setColor(c.focus)
        love.graphics.print(toast_msg, tx + 16, ty + 7)
    end

    -- Confirmation dialog
    if show_confirm then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        local mw = 480
        local mh = 210
        local mx = math.floor((w - mw) / 2)
        local my = math.floor((h - mh) / 2)

        theme.draw_panel(mx, my, mw, mh, c.surface, c.border, 12)
        theme.draw_focus_ring(mx, my, mw, mh, 12, 1)

        local is_danger = (confirm_kind == "clear_all" or confirm_kind == "clear_off_shelf")
        theme.set_font("header")
        love.graphics.setColor(is_danger and c.danger or c.focus)
        love.graphics.print(CONFIRM_TITLES[confirm_kind] or "确认", mx + 24, my + 20)

        theme.set_font("body")
        love.graphics.setColor(c.text)
        love.graphics.print(CONFIRM_PROMPTS[confirm_kind] or "确定继续吗？", mx + 24, my + 62)

        theme.set_font("hint")
        love.graphics.setColor(c.text_muted)
        love.graphics.print(CONFIRM_NOTES[confirm_kind] or "", mx + 24, my + 92)

        local btn_w = 150
        local btn_h = 40
        local btn_y = my + 140
        local ok_x = mx + 55
        local cancel_x = mx + mw - 55 - btn_w

        -- Confirm button
        local is_ok_focused = (confirm_focus == 1)
        local ok_color = is_danger and c.danger or c.focus
        theme.draw_panel(ok_x, btn_y, btn_w, btn_h,
            is_ok_focused and (is_danger and c.danger or c.focus_bg) or c.surface_active,
            is_ok_focused and ok_color or c.border, 8)
        if is_ok_focused then
            theme.draw_focus_ring(ok_x, btn_y, btn_w, btn_h, 8, 2)
        end
        theme.set_font("body")
        love.graphics.setColor(is_ok_focused and { 1, 1, 1, 1 } or c.text)
        local ok_label = (confirm_kind == "quit") and "退出应用" or "确定清理"
        local ok_w = theme.get_font("body"):getWidth(ok_label)
        love.graphics.print(ok_label, ok_x + (btn_w - ok_w) / 2, btn_y + 9)

        -- Cancel button
        local is_cancel_focused = (confirm_focus == 2)
        theme.draw_panel(cancel_x, btn_y, btn_w, btn_h,
            is_cancel_focused and c.focus_bg or c.surface_active,
            is_cancel_focused and c.focus or c.border, 8)
        if is_cancel_focused then
            theme.draw_focus_ring(cancel_x, btn_y, btn_w, btn_h, 8, 2)
        end
        theme.set_font("body")
        love.graphics.setColor(is_cancel_focused and c.focus or c.text_muted)
        local cw = theme.get_font("body"):getWidth("取消")
        love.graphics.print("取消", cancel_x + (btn_w - cw) / 2, btn_y + 9)
    end
end

return settings_view
