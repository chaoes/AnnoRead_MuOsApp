local theme = require("src.theme")
local storage = require("src.storage")
local http = require("src.http")
local legado = require("src.legado")
local json = require("src.json")
local discover_view = {}

local categories = {}
local category_idx = 1
local category_scroll = 0
local books_list = {}
local selected_book_idx = 1
local scroll_offset = 0
local is_loading = false
local status_msg = "正在载入分类..."
local focus_subzone = "categories" -- "categories" or "books"
local card_btn_idx = 0 -- 0: 整卡(动作面板), 1: [阅读], 2: [+书架]/[已在架]

-- Multi-source state
local source_list = {}
local active_source_idx = 1

local function can_use_network()
    return Game_Can_Online ~= false
end

function discover_view.get_source_list()
    return source_list
end

function discover_view.get_active_source_index()
    return active_source_idx
end

function discover_view.get_categories()
    return categories
end

local function refresh_source_list()
    source_list = {}
    local all_sources = storage.get_sources()
    for _, s in ipairs(all_sources) do
        if s.enabled ~= false and s.exploreUrl and #s.exploreUrl > 0 then
            table.insert(source_list, s)
        end
    end
end

function discover_view.set_active_source(idx)
    refresh_source_list()
    if not can_use_network() then
        is_loading = false
        categories = {}
        books_list = {}
        status_msg = "离线：发现页需要网络连接"
        return false
    end
    if #source_list == 0 then
        status_msg = "暂无启用的可用'发现'书源"
        categories = {}
        return false
    end
    active_source_idx = math.max(1, math.min(idx or 1, #source_list))
    local active_src = source_list[active_source_idx]
    if not active_src or not active_src.exploreUrl then
        status_msg = "当前书源不支持'发现'规则"
        categories = {}
        return false
    end

    status_msg = string.format("正在解析 [%s] 探索分类...", active_src.bookSourceName or "书源")
    is_loading = true

    local cats_res = legado.parseExploreCategories(active_src.exploreUrl)
    local parsed = type(cats_res) == "table" and cats_res or json.decode(cats_res)

    if type(parsed) == "table" and #parsed > 0 then
        categories = parsed
        category_idx = 1
        category_scroll = 0
        if #categories > 0 then
            discover_view.load_category_books(1)
        end
        return true
    else
        is_loading = false
        status_msg = "该书源未发现可用分类"
        categories = {}
        return false
    end
end

-- Book Action Modal
local show_action_modal = false
local action_modal_book = nil
local action_modal_focus = 1 -- 1: 立即阅读, 2: 加入/移出书架, 3: 取消

function discover_view.set_action_book(book)
    action_modal_book = book
    show_action_modal = book ~= nil
end

function discover_view.get_action_source_line()
    if not action_modal_book then return "" end
    local src_name = action_modal_book.originName or (source_list[active_source_idx] and source_list[active_source_idx].bookSourceName) or "当前书源"
    return string.format("来源: %s · %s", src_name, action_modal_book.latestChapterTitle or "连载中")
end

function discover_view.init()
    focus_subzone = "categories"
    category_idx = 1
    selected_book_idx = 1
    card_btn_idx = 0
    scroll_offset = 0
    show_action_modal = false
    action_modal_book = nil
    categories = {}
    books_list = {}
    is_loading = false

    refresh_source_list()

    if not can_use_network() then
        status_msg = "离线：发现页需要网络连接"
        return
    end

    -- Pick the first source that parses categories successfully, or default to 1
    local target_idx = 1
    for idx, s in ipairs(source_list) do
        local ok, res = pcall(legado.parseExploreCategories, s.exploreUrl)
        if ok and res and #res > 2 then
            local parsed = json.decode(res)
            if parsed and #parsed > 0 then
                target_idx = idx
                break
            end
        end
    end
    discover_view.set_active_source(target_idx)
end

function discover_view.load_category_books(cat_idx)
    if not can_use_network() then
        is_loading = false
        status_msg = "离线：发现页需要网络连接"
        return
    end
    local cat = categories[cat_idx]
    if not cat or not cat.url then return end

    local active_src = source_list[active_source_idx] or storage.get_active_source()
    if not active_src then return end

    is_loading = true
    status_msg = string.format("正在加载 [%s] ...", cat.title or "书籍")
    books_list = {}
    selected_book_idx = 1
    card_btn_idx = 0
    scroll_offset = 0

    -- Legado 3.0: Discover book parsing uses ruleExplore (or falls back to ruleSearch)
    local src_copy = json.decode(json.encode(active_src))
    if src_copy.ruleExplore then
        src_copy.ruleSearch = src_copy.ruleExplore
    end
    local src_json = json.encode(src_copy)

    -- Resolve {{page}} and {{page+1}} dynamic macros in category URLs
    local req_url = cat.url:gsub("{{page}}", "1"):gsub("{{page%+1}}", "2")
    if not req_url:match("^https?://") then
        local base = (active_src.bookSourceUrl or ""):gsub("/+$", "")
        req_url = base .. "/" .. req_url:gsub("^/+", "")
    end

    -- Include source headers (such as Referer, User-Agent)
    local req_headers = active_src.header and json.decode(active_src.header) or {}

    http.request_async({
        url = req_url,
        method = "GET",
        headers = req_headers,
        timeout = 8
    }, function(resp)
        is_loading = false
        if not resp or #resp == 0 then
            status_msg = "分类数据加载失败，网络超时"
            return
        end

        local parsed_books_json = legado.parseSearch(src_json, resp, req_url)
        local list = json.decode(parsed_books_json)

        if type(list) == "table" and #list > 0 then
            books_list = list
            status_msg = string.format("已载入 %d 本 [%s] 热门作品", #list, cat.title or "")
        else
            status_msg = "暂无书籍数据"
        end
    end)
end

function discover_view.is_action_modal_open()
    return show_action_modal
end

-- Public busy flag so main.lua's frame pacer keeps full rate while loading.
function discover_view.is_loading()
    return is_loading
end

function discover_view.get_focus_subzone()
    return focus_subzone
end

function discover_view.get_card_button_index()
    return card_btn_idx
end

function discover_view._set_categories(cats)
    categories = cats
end

function discover_view._set_books(list)
    books_list = list
    selected_book_idx = 1
end

-- Test/debug hook: focus the books list (and optionally a card element).
function discover_view._set_card_button_index(idx)
    focus_subzone = "books"
    card_btn_idx = idx or 0
end

function discover_view.update(dt, input)
    -- 1. Handle Book Action Modal Navigation
    if show_action_modal and action_modal_book then
        if input.pressed("left") then
            action_modal_focus = (action_modal_focus == 1) and 3 or (action_modal_focus - 1)
        elseif input.pressed("right") then
            action_modal_focus = (action_modal_focus == 3) and 1 or (action_modal_focus + 1)
        elseif input.pressed("a") then
            if action_modal_focus == 1 then
                -- 立即阅读: Directly open reader WITHOUT automatically adding to bookshelf
                local book_to_read = action_modal_book
                show_action_modal = false
                return { action = "open_reader", book = book_to_read }
            elseif action_modal_focus == 2 then
                -- 加入书架 / 移出书架
                local in_shelf = storage.is_in_bookshelf(action_modal_book)
                if in_shelf then
                    storage.remove_book_by_url(action_modal_book.bookUrl)
                    status_msg = string.format("已将 《%s》 从书架移出！", action_modal_book.name or "")
                else
                    storage.add_book(action_modal_book)
                    status_msg = string.format("已将 《%s》 加入书架！", action_modal_book.name or "")
                end
            elseif action_modal_focus == 3 then
                show_action_modal = false
            end
        elseif input.pressed("b") then
            show_action_modal = false
        end
        return nil
    end

    -- L2 / R2: Switch Discover Source (Cleanly separate from global L1/R1 top tab switching)
    if (input.pressed("l2") or input.pressed("prev_source")) and #source_list > 1 then
        local new_idx = active_source_idx - 1
        if new_idx < 1 then new_idx = #source_list end
        discover_view.set_active_source(new_idx)
        return nil
    elseif (input.pressed("r2") or input.pressed("next_source")) and #source_list > 1 then
        local new_idx = active_source_idx + 1
        if new_idx > #source_list then new_idx = 1 end
        discover_view.set_active_source(new_idx)
        return nil
    end

    if #categories == 0 then
        if input.pressed("up") then
            return { action = "focus_tabs" }
        end
        return nil
    end

    if focus_subzone == "categories" then
        if input.pressed("up") then
            return { action = "focus_tabs" }
        elseif input.pressed("down") then
            if #books_list > 0 then
                focus_subzone = "books"
                card_btn_idx = 0
            end
        elseif input.pressed("left") then
            if category_idx > 1 then
                category_idx = category_idx - 1
                discover_view.load_category_books(category_idx)
            end
        elseif input.pressed("right") then
            if category_idx < #categories then
                category_idx = category_idx + 1
                discover_view.load_category_books(category_idx)
            end
        elseif input.pressed("a") then
            if #books_list > 0 then
                focus_subzone = "books"
                card_btn_idx = 0
            end
        end
    elseif focus_subzone == "books" then
        if input.pressed("up") then
            if selected_book_idx == 1 then
                focus_subzone = "categories"
            else
                selected_book_idx = selected_book_idx - 1
            end
            card_btn_idx = 0
        elseif input.pressed("down") then
            selected_book_idx = math.min(#books_list, selected_book_idx + 1)
            card_btn_idx = 0
        elseif input.pressed("left") then
            -- ◀/▶ move focus between the card's quick buttons and back to the
            -- whole card (0 = card -> Book Action Dialog, 1 = [阅读], 2 = [书架]).
            -- Wrapping means both buttons are one press away from the card.
            card_btn_idx = (card_btn_idx + 2) % 3
        elseif input.pressed("right") then
            card_btn_idx = (card_btn_idx + 1) % 3
        end

        local target_scroll = math.max(0, (selected_book_idx - 3) * 105)
        scroll_offset = scroll_offset + (target_scroll - scroll_offset) * math.min(1.0, dt * 12)

        -- A activates the focused element on the card
        if input.pressed("a") then
            local target_book = books_list[selected_book_idx]
            if target_book then
                if card_btn_idx == 1 then
                    return { action = "open_reader", book = target_book }
                elseif card_btn_idx == 2 then
                    local in_shelf = storage.is_in_bookshelf(target_book)
                    if in_shelf then
                        storage.remove_book_by_url(target_book.bookUrl)
                        status_msg = string.format("已将 《%s》 从书架移出！", target_book.name)
                    else
                        storage.add_book(target_book)
                        status_msg = string.format("已将 《%s》 加入书架！", target_book.name)
                    end
                else
                    show_action_modal = true
                    action_modal_book = target_book
                    action_modal_focus = 1
                end
            end
        -- Shortcut: Toggle Bookshelf directly
        elseif input.pressed("x") then
            local target_book = books_list[selected_book_idx]
            if target_book then
                local in_shelf = storage.is_in_bookshelf(target_book)
                if in_shelf then
                    storage.remove_book_by_url(target_book.bookUrl)
                    status_msg = string.format("已将 《%s》 从书架移出！", target_book.name)
                else
                    storage.add_book(target_book)
                    status_msg = string.format("已将 《%s》 加入书架！", target_book.name)
                end
            end
        end
    end

    return nil
end

function discover_view.mousepressed(vx, vy, button)
    -- Handle modal click
    if show_action_modal and action_modal_book then
        local mw = 460
        local mh = 240
        local mx = math.floor((720 - mw) / 2)
        local my = math.floor((720 - mh) / 2)

        if vx < mx or vx > mx + mw or vy < my or vy > my + mh then
            show_action_modal = false
            return nil
        end

        local btn_w = 120
        local btn_h = 38
        local btn_y = my + 175
        local b1_x = mx + 24
        local b2_x = mx + 24 + btn_w + 16
        local b3_x = mx + 24 + (btn_w + 16) * 2

        if vy >= btn_y and vy <= btn_y + btn_h then
            if vx >= b1_x and vx <= b1_x + btn_w then
                local book_to_read = action_modal_book
                show_action_modal = false
                return { action = "open_reader", book = book_to_read }
            elseif vx >= b2_x and vx <= b2_x + btn_w then
                local in_shelf = storage.is_in_bookshelf(action_modal_book)
                if in_shelf then
                    storage.remove_book_by_url(action_modal_book.bookUrl)
                    status_msg = string.format("已将 《%s》 从书架移出！", action_modal_book.name or "")
                else
                    storage.add_book(action_modal_book)
                    status_msg = string.format("已将 《%s》 加入书架！", action_modal_book.name or "")
                end
                return nil
            elseif vx >= b3_x and vx <= b3_x + btn_w then
                show_action_modal = false
                return nil
            end
        end
        return nil
    end

    if #categories == 0 then return nil end

    -- 0. Click Source Switcher
    if vy >= 58 and vy <= 86 and #source_list > 1 then
        if vx >= 20 and vx <= 120 then
            local new_idx = active_source_idx - 1
            if new_idx < 1 then new_idx = #source_list end
            discover_view.set_active_source(new_idx)
            return nil
        elseif vx >= 240 and vx <= 380 then
            local new_idx = active_source_idx + 1
            if new_idx > #source_list then new_idx = 1 end
            discover_view.set_active_source(new_idx)
            return nil
        end
    end

    -- 1. Click Category Tabs
    local tab_y = 90
    local tab_x = 24
    local f_hint = theme.get_font("hint")
    if vy >= tab_y and vy <= tab_y + 36 then
        for i, cat in ipairs(categories) do
            local pw = f_hint:getWidth(cat.title) + 24
            local px = tab_x - category_scroll
            if vx >= px and vx <= px + pw then
                focus_subzone = "categories"
                category_idx = i
                discover_view.load_category_books(category_idx)
                return nil
            end
            tab_x = tab_x + pw + 8
        end
    end

    -- 2. Click Book Cards
    local card_x = 24
    local card_w = 720 - 48
    local status_y = tab_y + 38
    local start_y = status_y + 24
    local card_h = 92
    local card_gap = 12

    if #books_list > 0 and vx >= card_x and vx <= card_x + card_w then
        for i, book in ipairs(books_list) do
            local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
            if vy >= cy and vy <= cy + card_h then
                focus_subzone = "books"
                selected_book_idx = i

                local btn_w = 75
                local btn_h = 28
                local btn_y = cy + 14
                local shelf_btn_x = card_x + card_w - 85
                local read_btn_x = card_x + card_w - 170

                -- Click quick "阅读" button
                if vx >= read_btn_x and vx <= read_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h then
                    card_btn_idx = 1
                    return { action = "open_reader", book = book }
                -- Click quick "+书架" / "已在架" button
                elseif vx >= shelf_btn_x and vx <= shelf_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h then
                    card_btn_idx = 2
                    local in_shelf = storage.is_in_bookshelf(book)
                    if in_shelf then
                        storage.remove_book_by_url(book.bookUrl)
                        status_msg = string.format("已将 《%s》 从书架移出！", book.name)
                    else
                        storage.add_book(book)
                        status_msg = string.format("已将 《%s》 加入书架！", book.name)
                    end
                    return nil
                else
                    -- Clicking anywhere else on card opens Book Action Dialog
                    card_btn_idx = 0
                    show_action_modal = true
                    action_modal_book = book
                    action_modal_focus = 1
                end
                break
            end
        end
    end
    return nil
end

function discover_view.wheelmoved(x, y)
    if #books_list == 0 or show_action_modal then return end
    focus_subzone = "books"
    if y > 0 then
        selected_book_idx = math.max(1, selected_book_idx - 1)
    elseif y < 0 then
        selected_book_idx = math.min(#books_list, selected_book_idx + 1)
    end
end

function discover_view.draw(w, h, is_view_focused)
    if is_view_focused == nil then is_view_focused = true end
    local c = theme.colors()

    if not can_use_network() then
        theme.set_font("hint")
        love.graphics.setColor(c.accent)
        love.graphics.print("离线模式", 24, 66)
        theme.set_font("header")
        love.graphics.setColor(c.text_muted)
        love.graphics.printf(status_msg, 0, h * 0.4, w, "center")
        theme.set_font("hint")
        love.graphics.printf("联网后重新启动应用，按 [方向键上] 返回顶部标签", 0, h * 0.4 + 40, w, "center")
        return
    end

    -- 0. Source Indicator Bar (Always visible so users can switch sources even without categories)
    local src_bar_y = 66
    theme.set_font("hint")
    local cur_src = source_list[active_source_idx]
    local src_name = cur_src and (cur_src.bookSourceName or "未知书源") or "默认书源"
    local src_indicator = string.format("[◀ L2] 书源: %s (%d/%d) [R2 ▶]", src_name, active_source_idx, math.max(1, #source_list))
    love.graphics.setColor(c.accent)
    love.graphics.print(src_indicator, 24, src_bar_y)

    if #categories == 0 then
        local tab_y = 90
        local status_y = tab_y + 38
        theme.set_font("hint")
        love.graphics.setColor(is_loading and c.accent or c.text_muted)
        love.graphics.print(status_msg, 24, status_y)

        theme.set_font("header")
        love.graphics.setColor(c.text_muted)
        love.graphics.printf(status_msg, 0, h * 0.4, w, "center")

        theme.set_font("hint")
        love.graphics.setColor(c.text_muted)
        love.graphics.printf("按 [L2 / R2] 切换其他书源，或按 [方向键上] 返回顶部标签", 0, h * 0.4 + 40, w, "center")
        return
    end

    -- 1. Horizontal Category Tabs Row
    local tab_y = 90
    local tab_x = 24
    theme.set_font("hint")

    local active_tab_offset = (category_idx - 1) * 90
    local target_cat_scroll = math.max(0, active_tab_offset - (w / 2 - 60))
    category_scroll = category_scroll + (target_cat_scroll - category_scroll) * 0.2

    love.graphics.setScissor(20, tab_y - 2, w - 40, 38)
    for i, cat in ipairs(categories) do
        local is_sel = (i == category_idx)
        local is_pill_focused = is_view_focused and (focus_subzone == "categories") and is_sel and not show_action_modal
        local pill_w, pill_h = theme.draw_pill(cat.title, tab_x - category_scroll, tab_y, is_sel, is_pill_focused)
        tab_x = tab_x + pill_w + 8
    end
    love.graphics.setScissor()

    -- Status Hint
    local status_y = tab_y + 38
    theme.set_font("hint")
    love.graphics.setColor(is_loading and c.accent or c.text_muted)
    love.graphics.print(status_msg, 24, status_y)

    -- 2. Books List
    local start_y = status_y + 24
    local card_x = 24
    local card_w = w - 48
    local card_h = 92
    local card_gap = 12

    love.graphics.setScissor(0, start_y, w, h - start_y - 45)

    if #books_list > 0 then
        for i, book in ipairs(books_list) do
            local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
            if cy + card_h > start_y - 20 and cy < h - 40 then
                local is_focused = is_view_focused and (focus_subzone == "books") and (i == selected_book_idx) and not show_action_modal
                theme.draw_card(card_x, cy, card_w, card_h, is_focused)

                theme.set_font("title")
                love.graphics.setColor(is_focused and c.focus or c.text)
                love.graphics.print(book.name or "未命名", card_x + 16, cy + 12)

                local title_w = theme.get_font("title"):getWidth(book.name or "")
                local clean_kind = (book.kind or "综合"):gsub("[\r\n]+", " "):gsub("%s+", " ")
                theme.draw_pill(clean_kind, card_x + 24 + title_w, cy + 12, false)

                theme.set_font("hint")
                love.graphics.setColor(c.text_muted)
                love.graphics.print(string.format("作者: %s", book.author or "未知"), card_x + 16, cy + 42)

                love.graphics.setColor(c.accent)
                love.graphics.print(string.format("最新: %s", book.latestChapterTitle or "连载中"), card_x + 16, cy + 64)

                -- Quick Buttons on Card: [阅读] & [+书架]/[已在架]
                local btn_w = 75
                local btn_h = 28
                local btn_y = cy + 14
                local shelf_btn_x = card_x + card_w - 85
                local read_btn_x = card_x + card_w - 170

                -- [阅读] Pill
                local read_focused = is_focused and (card_btn_idx == 1)
                theme.draw_panel(read_btn_x, btn_y, btn_w, btn_h,
                    read_focused and c.focus_bg or c.surface_active,
                    read_focused and c.focus or c.border, 6)
                if read_focused then theme.draw_focus_ring(read_btn_x, btn_y, btn_w, btn_h, 6, 2) end
                theme.set_font("hint")
                love.graphics.setColor(read_focused and c.focus or c.text)
                local r_tw = theme.get_font("hint"):getWidth("阅读")
                love.graphics.print("阅读", read_btn_x + (btn_w - r_tw) / 2, btn_y + 6)

                -- [+书架] / [已在架] Pill
                local in_shelf = storage.is_in_bookshelf(book)
                local s_label = in_shelf and "已在架" or "+书架"
                local shelf_focused = is_focused and (card_btn_idx == 2)
                local s_bg = shelf_focused and c.focus_bg or (in_shelf and c.focus_bg or c.surface)
                local s_border = shelf_focused and c.accent or (in_shelf and c.focus or c.border)
                theme.draw_panel(shelf_btn_x, btn_y, btn_w, btn_h, s_bg, s_border, 6)
                if shelf_focused then theme.draw_focus_ring(shelf_btn_x, btn_y, btn_w, btn_h, 6, 2) end
                love.graphics.setColor(shelf_focused and c.accent or (in_shelf and c.focus or c.text_muted))
                local s_tw = theme.get_font("hint"):getWidth(s_label)
                love.graphics.print(s_label, shelf_btn_x + (btn_w - s_tw) / 2, btn_y + 6)
            end
        end
    end

    love.graphics.setScissor()

    -- 3. Book Action Dialog
    if show_action_modal and action_modal_book then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        local mw = 460
        local mh = 240
        local mx = math.floor((w - mw) / 2)
        local my = math.floor((h - mh) / 2)

        theme.draw_panel(mx, my, mw, mh, c.surface, c.border, 12)
        theme.draw_focus_ring(mx, my, mw, mh, 12, 1)

        -- Title
        theme.set_font("title")
        love.graphics.setColor(c.focus)
        love.graphics.print(action_modal_book.name or "书籍详情", mx + 24, my + 18)

        local in_shelf = storage.is_in_bookshelf(action_modal_book)
        theme.draw_pill(in_shelf and "已在书架" or "未入书架", mx + mw - 110, my + 18, in_shelf)

        -- Details
        theme.set_font("body")
        love.graphics.setColor(c.text)
        love.graphics.print(string.format("作者: %s  |  分类: %s", action_modal_book.author or "未知", action_modal_book.kind or "综合"), mx + 24, my + 58)

        theme.set_font("hint")
        love.graphics.setColor(c.accent)
        love.graphics.print(discover_view.get_action_source_line(), mx + 24, my + 90)

        theme.set_font("hint")
        love.graphics.setColor(c.text_muted)
        love.graphics.print("支持直接阅读或存入书架，不会自动入库", mx + 24, my + 120)

        -- Action Buttons
        local btn_w = 120
        local btn_h = 38
        local btn_y = my + 175
        local b1_x = mx + 24
        local b2_x = mx + 24 + btn_w + 16
        local b3_x = mx + 24 + (btn_w + 16) * 2

        -- Button 1: 立即阅读
        local is_b1_f = (action_modal_focus == 1)
        theme.draw_panel(b1_x, btn_y, btn_w, btn_h, is_b1_f and c.focus_bg or c.surface_active, is_b1_f and c.focus or c.border, 8)
        if is_b1_f then theme.draw_focus_ring(b1_x, btn_y, btn_w, btn_h, 8, 2) end
        theme.set_font("body")
        love.graphics.setColor(is_b1_f and c.focus or c.text)
        local t1 = "立即阅读"
        love.graphics.print(t1, b1_x + (btn_w - theme.get_font("body"):getWidth(t1)) / 2, btn_y + 9)

        -- Button 2: 加入书架 / 移出书架
        local is_b2_f = (action_modal_focus == 2)
        local t2 = in_shelf and "移出书架" or "加入书架"
        theme.draw_panel(b2_x, btn_y, btn_w, btn_h, is_b2_f and c.focus_bg or c.surface_active, is_b2_f and c.accent or c.border, 8)
        if is_b2_f then theme.draw_focus_ring(b2_x, btn_y, btn_w, btn_h, 8, 2) end
        theme.set_font("body")
        love.graphics.setColor(is_b2_f and c.accent or c.text)
        love.graphics.print(t2, b2_x + (btn_w - theme.get_font("body"):getWidth(t2)) / 2, btn_y + 9)

        -- Button 3: 取消
        local is_b3_f = (action_modal_focus == 3)
        theme.draw_panel(b3_x, btn_y, btn_w, btn_h, is_b3_f and c.focus_bg or c.surface_active, is_b3_f and c.focus or c.border, 8)
        if is_b3_f then theme.draw_focus_ring(b3_x, btn_y, btn_w, btn_h, 8, 2) end
        theme.set_font("body")
        love.graphics.setColor(is_b3_f and c.focus or c.text_muted)
        local t3 = "取消"
        love.graphics.print(t3, b3_x + (btn_w - theme.get_font("body"):getWidth(t3)) / 2, btn_y + 9)
    end
end

return discover_view
