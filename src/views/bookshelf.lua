local theme = require("src.theme")
local storage = require("src.storage")
local cache = require("src.cache")
local book_download = require("src.book_download")
local bookshelf = {}

-- On-card button slots (left to right): [阅读] [缓存] [移出].
-- Ordering puts 阅读 first so the default focus is "open", not "cache".
local BUTTON_READ = 1
local BUTTON_CACHE = 2
local BUTTON_REMOVE = 3

local selected_idx = 1
local scroll_offset = 0
-- 1: [阅读], 2: [缓存], 3: [移出] (◀/▶ 切换焦点).
-- [阅读] is the *first* button so the default focus lands on "open the book"
-- instead of "cache it" -- the old order made A-on-card accidentally start a
-- whole-book download far too easily.
local card_btn_idx = 1

-- Remove confirmation dialog state
local show_remove_modal = false
local remove_modal_book = nil
local remove_modal_focus = 1 -- 1: 确定移出, 2: 取消
local toast_msg = ""
local toast_timer = 0

-- Whole-book caching state
local caching_url = nil
local cache_status = ""

function bookshelf.init()
    selected_idx = 1
    scroll_offset = 0
    card_btn_idx = 1
    show_remove_modal = false
    remove_modal_book = nil
    caching_url = nil
    cache_status = ""
end

function bookshelf.is_caching()
    return caching_url ~= nil
end

function bookshelf.is_remove_dialog_open()
    return show_remove_modal
end

-- Alias so main.lua's overlay guard can suppress global hotkeys (L1/R1 tab
-- switching) while the removal dialog owns the input.
function bookshelf.is_action_modal_open()
    return show_remove_modal
end

function bookshelf.get_card_button_index()
    return card_btn_idx
end

-- Test/debug hook: focus a specific on-card button (1 = [阅读], 2 = [移出]).
function bookshelf._set_card_button_index(idx)
    card_btn_idx = idx
end

function bookshelf.update(dt, input)
    if toast_timer > 0 then
        toast_timer = toast_timer - dt
        if toast_timer <= 0 then toast_msg = "" end
    end

    local books = storage.get_books()
    -- 1. Handle Remove Confirmation Modal
    if show_remove_modal then
        if input.pressed("left") or input.pressed("right") then
            remove_modal_focus = (remove_modal_focus == 1) and 2 or 1
        elseif input.pressed("a") then
            if remove_modal_focus == 1 and remove_modal_book then
                storage.remove_book_by_url(remove_modal_book.bookUrl)
                selected_idx = math.min(selected_idx, math.max(1, #storage.get_books()))
                toast_msg = string.format("已将 《%s》 移出书架", remove_modal_book.name or "")
                toast_timer = 2.5
            end
            show_remove_modal = false
        elseif input.pressed("b") then
            show_remove_modal = false
        end
        return nil
    end

    if #books == 0 then
        if input.pressed("up") then
            return { action = "focus_tabs" }
        end
        return nil
    end

    if input.pressed("up") then
        if selected_idx == 1 then
            return { action = "focus_tabs" }
        else
            selected_idx = selected_idx - 1
            card_btn_idx = BUTTON_READ
        end
    elseif input.pressed("down") then
        selected_idx = math.min(#books, selected_idx + 1)
        card_btn_idx = BUTTON_READ
    elseif input.pressed("left") then
        -- ◀/▶ move focus between the card's [阅读] / [缓存] / [移出] buttons
        card_btn_idx = math.max(BUTTON_READ, card_btn_idx - 1)
    elseif input.pressed("right") then
        card_btn_idx = math.min(BUTTON_REMOVE, card_btn_idx + 1)
    end

    -- Smooth scroll tracking selected index
    local target_scroll = math.max(0, (selected_idx - 3) * 110)
    scroll_offset = scroll_offset + (target_scroll - scroll_offset) * math.min(1.0, dt * 12)

    -- Actions (A activates the focused on-card button)
    if input.pressed("a") then
        local book = books[selected_idx]
        if book then
            if card_btn_idx == BUTTON_READ then
                return { action = "open_reader", book = book }
            elseif card_btn_idx == BUTTON_CACHE then
                if not caching_url then
                    caching_url = book.bookUrl
                    bookshelf.cache_whole_book(book)
                end
            else -- BUTTON_REMOVE
                show_remove_modal = true
                remove_modal_book = book
                remove_modal_focus = 1
            end
        end
    elseif input.pressed("x") then
        if #books > 0 and books[selected_idx] then
            show_remove_modal = true
            remove_modal_book = books[selected_idx]
            remove_modal_focus = 1
        end
    -- L3: quick shortcut to cache the whole selected book offline
    elseif input.pressed("l3") then
        local book = books[selected_idx]
        if book and not caching_url then
            caching_url = book.bookUrl
            bookshelf.cache_whole_book(book)
        end
    end

    return nil
end

-- Download every chapter of a book into the offline cache.
function bookshelf.cache_whole_book(book)
    book_download.start(book, {
        on_status = function(msg)
            cache_status = msg
            toast_msg = msg
            toast_timer = 3
        end,
        on_done = function(ok, msg)
            caching_url = nil
            cache_status = ""
            toast_msg = msg
            toast_timer = 4
        end,
    })
end

function bookshelf.mousepressed(vx, vy, button)
    local books = storage.get_books()

    -- If remove modal is active
    if show_remove_modal then
        local mw = 440
        local mh = 200
        local mx = math.floor((720 - mw) / 2)
        local my = math.floor((720 - mh) / 2)

        if vx < mx or vx > mx + mw or vy < my or vy > my + mh then
            show_remove_modal = false
            return nil
        end

        local btn_w = 140
        local btn_h = 38
        local btn_y = my + 135
        local confirm_x = mx + 50
        local cancel_x = mx + mw - 50 - btn_w

        if vy >= btn_y and vy <= btn_y + btn_h then
            if vx >= confirm_x and vx <= confirm_x + btn_w then
                if remove_modal_book then
                    storage.remove_book_by_url(remove_modal_book.bookUrl)
                    selected_idx = math.min(selected_idx, math.max(1, #storage.get_books()))
                    toast_msg = string.format("已将 《%s》 移出书架", remove_modal_book.name or "")
                    toast_timer = 2.5
                end
                show_remove_modal = false
                return nil
            elseif vx >= cancel_x and vx <= cancel_x + btn_w then
                show_remove_modal = false
                return nil
            end
        end
        return nil
    end

    if #books == 0 then return nil end

    local card_x = 24
    local card_w = 720 - 48
    local card_h = 96
    local card_gap = 14
    local start_y = 65

    if vx >= card_x and vx <= card_x + card_w then
        for i, book in ipairs(books) do
            local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
            if vy >= cy and vy <= cy + card_h then
                selected_idx = i
                local btn_w = 66
                local btn_h = 28
                local btn_y = cy + 14
                local remove_btn_x = card_x + card_w - 76
                local cache_btn_x = remove_btn_x - btn_w - 6
                local read_btn_x = cache_btn_x - btn_w - 6

                -- Click [阅读] button -> open the reader
                if button == 1 and vx >= read_btn_x and vx <= read_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h then
                    card_btn_idx = BUTTON_READ
                    return { action = "open_reader", book = book }
                -- Click [缓存] button -> cache whole book
                elseif button == 1 and vx >= cache_btn_x and vx <= cache_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h then
                    card_btn_idx = BUTTON_CACHE
                    if not caching_url then
                        caching_url = book.bookUrl
                        bookshelf.cache_whole_book(book)
                    end
                    return nil
                -- Click [移出] button or right-click
                elseif (button == 1 and vx >= remove_btn_x and vx <= remove_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h) or (button == 2) then
                    card_btn_idx = BUTTON_REMOVE
                    show_remove_modal = true
                    remove_modal_book = book
                    remove_modal_focus = 1
                    return nil
                else
                    card_btn_idx = BUTTON_READ
                    return { action = "open_reader", book = book }
                end
            end
        end
    end
    return nil
end

function bookshelf.wheelmoved(x, y)
    local books = storage.get_books()
    if #books == 0 or show_remove_modal then return end
    if y > 0 then
        selected_idx = math.max(1, selected_idx - 1)
    elseif y < 0 then
        selected_idx = math.min(#books, selected_idx + 1)
    end
end

function bookshelf.draw(w, h, is_view_focused)
    if is_view_focused == nil then is_view_focused = true end
    local c = theme.colors()
    local books = storage.get_books()

    if #books == 0 then
        theme.set_font("header")
        love.graphics.setColor(c.text_muted)
        love.graphics.printf("书架空空如也\n\n按 [方向键上] 选择顶部导航，或按 [R1] 发现新书", 0, h * 0.4, w, "center")
        return
    end

    local card_x = 24
    local card_w = w - 48
    local card_h = 96
    local card_gap = 14
    local start_y = 65

    -- Scissor clipping for smooth list scrolling
    love.graphics.setScissor(0, start_y - 5, w, h - start_y - 45)

    for i, book in ipairs(books) do
        local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
        if cy + card_h > start_y - 20 and cy < h - 40 then
            local is_focused = is_view_focused and (i == selected_idx) and not show_remove_modal
            theme.draw_card(card_x, cy, card_w, card_h, is_focused)

            -- Book Title & Origin Badge
            theme.set_font("title")
            love.graphics.setColor(is_focused and c.focus or c.text)
            love.graphics.print(book.name or "未命名", card_x + 16, cy + 12)

            local title_w = theme.get_font("title"):getWidth(book.name or "")
            theme.draw_pill(book.originName or "本地", card_x + 24 + title_w, cy + 12, false)

            -- Author & Latest Chapter
            theme.set_font("hint")
            love.graphics.setColor(c.text_muted)
            local author_str = string.format("作者: %s  |  最新: %s", book.author or "未知", book.latestChapterTitle or "连载中")
            love.graphics.print(author_str, card_x + 16, cy + 42)

            -- Reading Progress Bar & Chapter Name
            local curr_ch = book.currentChapterTitle or "未开始阅读"
            local prog = math.min(1.0, math.max(0.0, book.progress or 0.0))
            love.graphics.setColor(c.accent)
            love.graphics.print(string.format("已读: %s (%.0f%%)", curr_ch, prog * 100), card_x + 16, cy + 68)

            -- Action Buttons: [阅读] & [缓存] & [移出] (left to right)
            local btn_w = 66
            local btn_h = 28
            local btn_y = cy + 14
            local remove_btn_x = card_x + card_w - 76
            local cache_btn_x = remove_btn_x - btn_w - 6
            local read_btn_x = cache_btn_x - btn_w - 6

            -- [阅读] Pill (open the book -- now the FIRST/default button)
            local read_focused = is_focused and (card_btn_idx == BUTTON_READ)
            theme.draw_panel(read_btn_x, btn_y, btn_w, btn_h,
                read_focused and c.focus_bg or c.surface_active,
                read_focused and c.focus or (is_focused and c.focus or c.border), 6)
            if read_focused then theme.draw_focus_ring(read_btn_x, btn_y, btn_w, btn_h, 6, 2) end
            theme.set_font("hint")
            love.graphics.setColor(read_focused and c.focus or (is_focused and c.focus or c.text))
            local r_tw = theme.get_font("hint"):getWidth("阅读")
            love.graphics.print("阅读", read_btn_x + (btn_w - r_tw) / 2, btn_y + 6)

            -- [缓存] Pill (whole-book offline download)
            local cache_focused = is_focused and (card_btn_idx == BUTTON_CACHE)
            local is_caching_this = (caching_url == book.bookUrl)
            theme.draw_panel(cache_btn_x, btn_y, btn_w, btn_h,
                cache_focused and c.focus_bg or c.surface,
                cache_focused and c.accent or c.border, 6)
            if cache_focused then theme.draw_focus_ring(cache_btn_x, btn_y, btn_w, btn_h, 6, 2) end
            theme.set_font("hint")
            love.graphics.setColor(cache_focused and c.accent or c.text_muted)
            local ca_label = is_caching_this and "缓存中" or "缓存"
            local ca_tw = theme.get_font("hint"):getWidth(ca_label)
            love.graphics.print(ca_label, cache_btn_x + (btn_w - ca_tw) / 2, btn_y + 6)

            -- [移出] Pill
            local remove_focused = is_focused and (card_btn_idx == BUTTON_REMOVE)
            theme.draw_panel(remove_btn_x, btn_y, btn_w, btn_h,
                remove_focused and c.surface_active or c.surface,
                remove_focused and c.danger or c.border, 6)
            if remove_focused then
                love.graphics.setColor(c.danger)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", remove_btn_x, btn_y, btn_w, btn_h, 6, 6)
                love.graphics.setLineWidth(1)
            end
            love.graphics.setColor(remove_focused and c.danger or c.text_muted)
            local rm_tw = theme.get_font("hint"):getWidth("移出")
            love.graphics.print("移出", remove_btn_x + (btn_w - rm_tw) / 2, btn_y + 6)

            -- Mini Progress Line
            local bar_x = card_x + card_w - 170
            local bar_y = cy + 74
            local bar_w = 160
            local bar_h = 4
            love.graphics.setColor(c.surface_active)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 2, 2)
            love.graphics.setColor(c.focus)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_w * prog, bar_h, 2, 2)
        end
    end

    love.graphics.setScissor()

    -- Toast Message
    if toast_msg ~= "" then
        theme.set_font("hint")
        local tw = theme.get_font("hint"):getWidth(toast_msg) + 32
        local tx = (w - tw) / 2
        local ty = h - 75
        theme.draw_panel(tx, ty, tw, 30, c.surface_active, c.focus, 8)
        love.graphics.setColor(c.focus)
        love.graphics.print(toast_msg, tx + 16, ty + 7)
    end

    -- Removal Confirmation Modal
    if show_remove_modal and remove_modal_book then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        local mw = 440
        local mh = 200
        local mx = math.floor((w - mw) / 2)
        local my = math.floor((h - mh) / 2)

        theme.draw_panel(mx, my, mw, mh, c.surface, c.border, 12)
        theme.draw_focus_ring(mx, my, mw, mh, 12, 1)

        -- Title
        theme.set_font("header")
        love.graphics.setColor(c.focus)
        love.graphics.print("移出书架确认", mx + 24, my + 18)

        -- Prompt text
        theme.set_font("body")
        love.graphics.setColor(c.text)
        local q_text = string.format("确定将 《%s》 移出书架吗？", remove_modal_book.name or "")
        love.graphics.print(q_text, mx + 24, my + 56)

        theme.set_font("hint")
        love.graphics.setColor(c.text_muted)
        love.graphics.print("移出后将清除本地阅读进度记录", mx + 24, my + 86)

        -- Action Buttons
        local btn_w = 140
        local btn_h = 38
        local btn_y = my + 135
        local confirm_x = mx + 50
        local cancel_x = mx + mw - 50 - btn_w

        -- Confirm Button
        local is_conf_f = (remove_modal_focus == 1)
        theme.draw_panel(confirm_x, btn_y, btn_w, btn_h, is_conf_f and c.focus_bg or c.surface_active, is_conf_f and c.focus or c.border, 8)
        if is_conf_f then
            theme.draw_focus_ring(confirm_x, btn_y, btn_w, btn_h, 8, 2)
        end
        theme.set_font("body")
        love.graphics.setColor(is_conf_f and c.focus or c.text)
        local c_tw = theme.get_font("body"):getWidth("确定移出")
        love.graphics.print("确定移出", confirm_x + (btn_w - c_tw) / 2, btn_y + 9)

        -- Cancel Button
        local is_canc_f = (remove_modal_focus == 2)
        theme.draw_panel(cancel_x, btn_y, btn_w, btn_h, is_canc_f and c.focus_bg or c.surface_active, is_canc_f and c.focus or c.border, 8)
        if is_canc_f then
            theme.draw_focus_ring(cancel_x, btn_y, btn_w, btn_h, 8, 2)
        end
        theme.set_font("body")
        love.graphics.setColor(is_canc_f and c.focus or c.text_muted)
        local can_tw = theme.get_font("body"):getWidth("取消")
        love.graphics.print("取消", cancel_x + (btn_w - can_tw) / 2, btn_y + 9)
    end
end

return bookshelf
