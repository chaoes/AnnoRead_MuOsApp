local theme = require("src.theme")
local storage = require("src.storage")
local http = require("src.http")
local legado = require("src.legado")
local json = require("src.json")
local input_mgr = require("src.input")
local keyboard = require("src.keyboard")
local search_view = {}

local keyword = "仙逆"
local PRESETS = { "仙逆", "诡秘之主", "三体", "道诡异仙", "凡人修仙", "剑来" }
local preset_idx = 1
local is_searching = false
local search_results = {}
local selected_idx = 1
local scroll_offset = 0
local focus_subzone = "presets" -- "input", "search_btn", "presets", "results"
local status_msg = "按 [A] 执行搜索，或使用 [◀/▶] 选择推荐词"

-- Book Action Modal
local show_action_modal = false
local action_modal_book = nil
local action_modal_focus = 1 -- 1: 立即阅读, 2: 加入/移出书架, 3: 取消

-- Set by search_view.keypressed when physical Enter performs a search while the
-- text input box is focused. Enter maps to action 'a', which in the input box would
-- otherwise pop the on-screen virtual keyboard in the same frame; this flag makes
-- update() skip all 'a' handling for that one frame.
local suppress_a_frame = false

function search_view.set_action_book(book)
    action_modal_book = book
    show_action_modal = book ~= nil
end

function search_view.get_action_source_line()
    if not action_modal_book then return "" end
    local src_name = action_modal_book.originName or "默认书源"
    return string.format("来源: %s · %s", src_name, action_modal_book.latestChapterTitle or "连载中")
end

function search_view.init()
    selected_idx = 1
    scroll_offset = 0
    focus_subzone = "presets"
    show_action_modal = false
    action_modal_book = nil
    -- Do not trigger automatic search on init to avoid blocking GUI on tab switch
end

function search_view.is_busy()
    return is_searching
end

function search_view.is_searching()
    return is_searching
end

function search_view.is_action_modal_open()
    return show_action_modal or keyboard.is_open()
end

function search_view.is_keyboard_open()
    return keyboard.is_open()
end

-- Aggregation Helper: Normalizes book name and author into duplicate key
local function normalize_str(s)
    return (s or ""):gsub("[《》【】%[%]%s%p]+", ""):lower()
end

function search_view.aggregate_book_item(results_list, new_book)
    results_list = results_list or {}
    if not new_book or not new_book.name then return results_list end

    local key = normalize_str(new_book.name) .. "_" .. normalize_str(new_book.author)
    local existing = nil

    for _, b in ipairs(results_list) do
        local b_key = normalize_str(b.name) .. "_" .. normalize_str(b.author)
        if b_key == key then
            existing = b
            break
        end
    end

    if existing then
        -- Add to candidates list
        existing.candidates = existing.candidates or { {
            bookUrl = existing.bookUrl,
            origin = existing.origin,
            originName = existing.originName,
            latestChapterTitle = existing.latestChapterTitle,
            latencyMs = existing.latencyMs or 9999
        } }

        table.insert(existing.candidates, {
            bookUrl = new_book.bookUrl,
            origin = new_book.origin,
            originName = new_book.originName,
            latestChapterTitle = new_book.latestChapterTitle,
            latencyMs = new_book.latencyMs or 9999
        })

        -- If new book has lower latency or better latest chapter, promote to primary card view
        local cur_lat = existing.latencyMs or 9999
        local new_lat = new_book.latencyMs or 9999
        if new_lat < cur_lat then
            existing.origin = new_book.origin
            existing.originName = new_book.originName
            existing.bookUrl = new_book.bookUrl
            existing.tocUrl = new_book.tocUrl or new_book.bookUrl
            existing.coverUrl = new_book.coverUrl or existing.coverUrl
            existing.intro = new_book.intro or existing.intro
            existing.kind = new_book.kind or existing.kind
            existing.wordCount = new_book.wordCount or existing.wordCount
            existing.latestChapterTitle = new_book.latestChapterTitle or existing.latestChapterTitle
            existing.latencyMs = new_lat
        end
    else
        local card = {}
        for k, v in pairs(new_book) do card[k] = v end
        card.candidates = { {
            bookUrl = new_book.bookUrl,
            origin = new_book.origin,
            originName = new_book.originName,
            latestChapterTitle = new_book.latestChapterTitle,
            latencyMs = new_book.latencyMs or 9999
        } }
        table.insert(results_list, card)
    end

    return results_list
end

function search_view.perform_search()
    local sources = storage.get_sources()
    local enabled_sources = {}
    for _, s in ipairs(sources) do
        if s.enabled ~= false and s.searchUrl and #s.searchUrl > 0 then
            table.insert(enabled_sources, s)
        end
    end

    if #enabled_sources == 0 then
        status_msg = "未找到已启用的可用书源，请先在 [书源] 界面启用书源"
        return
    end

    is_searching = true
    search_results = {}
    selected_idx = 1
    scroll_offset = 0

    local total_to_search = #enabled_sources
    local completed_cnt = 0
    local next_source_idx = 1
    local MAX_CONCURRENT = 4
    local active_workers = 0

    status_msg = string.format("受控并发检索中 (0/%d 个书源)...", total_to_search)

    local function spawn_worker()
        while active_workers < MAX_CONCURRENT and next_source_idx <= total_to_search do
            local src = enabled_sources[next_source_idx]
            next_source_idx = next_source_idx + 1
            active_workers = active_workers + 1

            local src_json = json.encode(src)
            local req_json = legado.buildSearchRequest(src_json, keyword, 1)
            local req_obj = json.decode(req_json)

            if req_obj and req_obj.url then
                local t0 = love and love.timer and love.timer.getTime() or os.clock()
                http.request_async({
                    url = req_obj.url,
                    method = req_obj.method,
                    headers = req_obj.headers,
                    type = req_obj.type,
                    charset = req_obj.charset,
                    body = req_obj.body,
                    timeout = 6
                }, function(resp)
                    local t1 = love and love.timer and love.timer.getTime() or os.clock()
                    local latency = math.floor((t1 - t0) * 1000)

                    active_workers = active_workers - 1
                    completed_cnt = completed_cnt + 1

                    if resp and #resp > 0 then
                        local parsed_books_json = legado.parseSearch(src_json, resp, req_obj.url)
                        local list = json.decode(parsed_books_json)
                        if type(list) == "table" and #list > 0 then
                            for _, book in ipairs(list) do
                                book.latencyMs = latency
                                search_view.aggregate_book_item(search_results, book)
                            end
                        end
                    end

                    if completed_cnt >= total_to_search then
                        is_searching = false
                        status_msg = string.format("检索完成，聚合发现 %d 部作品 (%d 个书源响应)", #search_results, total_to_search)
                    else
                        status_msg = string.format("受控并发检索中 (%d/%d)... 已聚合 %d 部作品", completed_cnt, total_to_search, #search_results)
                        spawn_worker()
                    end
                end)
            else
                active_workers = active_workers - 1
                completed_cnt = completed_cnt + 1
                if completed_cnt >= total_to_search then
                    is_searching = false
                    status_msg = string.format("检索完成，聚合发现 %d 部作品", #search_results)
                end
            end
        end
    end

    spawn_worker()
end

function search_view.textinput(t)
    keyword = keyword .. t
end

function search_view.keypressed(key)
    if key == "backspace" then
        if #keyword > 0 then
            -- UTF-8 safe backspace
            local byteoffset = utf8.offset(keyword, -1)
            if byteoffset then
                keyword = string.sub(keyword, 1, byteoffset - 1)
            else
                keyword = string.sub(keyword, 1, -2)
            end
        end
    elseif key == "return" then
        -- Physical Enter only has meaning inside the text input box, and only when the
        -- on-screen virtual keyboard is NOT open (while it is open, keys are typed via
        -- the keyboard view). Everywhere else the action layer ('a') already submits.
        if focus_subzone == "input" and not keyboard.is_open() then
            search_view.perform_search()
            -- Enter maps to action 'a', whose input-box handler would otherwise pop the
            -- on-screen virtual keyboard in this same frame. Suppress it for one frame.
            suppress_a_frame = true
            if #search_results > 0 then
                focus_subzone = "results"
            end
        end
    end
end

function search_view.is_a_suppressed()
    return suppress_a_frame
end

function search_view.update(dt, input)
    -- Consume the one-frame 'a' suppression set by search_view.keypressed (Enter).
    local skip_a = suppress_a_frame
    suppress_a_frame = false

    -- Handle Virtual Keyboard when active
    if keyboard.is_open() then
        keyboard.update(dt, input)
        return nil
    end

    -- Handle Book Action Modal Navigation
    if show_action_modal and action_modal_book then
        -- L1 / R1 / L2 / R2: Switch candidate sources directly within the action modal
        if (input.pressed("l1") or input.pressed("l2")) and action_modal_book.candidates and #action_modal_book.candidates > 1 then
            local cands = action_modal_book.candidates
            local cur_idx = 1
            for idx, c in ipairs(cands) do
                if c.origin == action_modal_book.origin then cur_idx = idx break end
            end
            local next_idx = (cur_idx > 1) and (cur_idx - 1) or #cands
            local pick = cands[next_idx]
            action_modal_book.origin = pick.origin
            action_modal_book.originName = pick.originName
            action_modal_book.bookUrl = pick.bookUrl
            action_modal_book.latestChapterTitle = pick.latestChapterTitle or action_modal_book.latestChapterTitle
            action_modal_book.latencyMs = pick.latencyMs
        elseif (input.pressed("r1") or input.pressed("r2")) and action_modal_book.candidates and #action_modal_book.candidates > 1 then
            local cands = action_modal_book.candidates
            local cur_idx = 1
            for idx, c in ipairs(cands) do
                if c.origin == action_modal_book.origin then cur_idx = idx break end
            end
            local next_idx = (cur_idx < #cands) and (cur_idx + 1) or 1
            local pick = cands[next_idx]
            action_modal_book.origin = pick.origin
            action_modal_book.originName = pick.originName
            action_modal_book.bookUrl = pick.bookUrl
            action_modal_book.latestChapterTitle = pick.latestChapterTitle or action_modal_book.latestChapterTitle
            action_modal_book.latencyMs = pick.latencyMs
        elseif input.pressed("left") then
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

    if focus_subzone == "input" then
        input_mgr.set_text_input_mode(true)
        if input.pressed("up") then
            input_mgr.set_text_input_mode(false)
            return { action = "focus_tabs" }
        elseif input.pressed("down") then
            input_mgr.set_text_input_mode(false)
            focus_subzone = "presets"
        elseif input.pressed("right") then
            input_mgr.set_text_input_mode(false)
            focus_subzone = "search_btn"
        elseif input.pressed("a") and not skip_a then
            -- Open on-screen virtual keyboard for handheld input
            input_mgr.set_text_input_mode(false)
            keyboard.open(keyword, function(committed_text)
                keyword = committed_text
                search_view.perform_search()
                if #search_results > 0 then
                    focus_subzone = "results"
                end
            end, function()
                focus_subzone = "input"
            end, function(live_text)
                keyword = live_text
            end)
        end
    elseif focus_subzone == "search_btn" then
        input_mgr.set_text_input_mode(false)
        if input.pressed("up") then
            return { action = "focus_tabs" }
        elseif input.pressed("down") then
            focus_subzone = "presets"
        elseif input.pressed("left") then
            focus_subzone = "input"
        elseif input.pressed("a") then
            search_view.perform_search()
            if #search_results > 0 then
                focus_subzone = "results"
            end
        end
    elseif focus_subzone == "presets" then
        input_mgr.set_text_input_mode(false)
        if input.pressed("up") then
            focus_subzone = "input"
        elseif input.pressed("down") then
            if #search_results > 0 then
                focus_subzone = "results"
            end
        elseif input.pressed("left") then
            preset_idx = math.max(1, preset_idx - 1)
            keyword = PRESETS[preset_idx]
        elseif input.pressed("right") then
            preset_idx = math.min(#PRESETS, preset_idx + 1)
            keyword = PRESETS[preset_idx]
        elseif input.pressed("a") then
            search_view.perform_search()
            if #search_results > 0 then
                focus_subzone = "results"
            end
        end
    elseif focus_subzone == "results" then
        input_mgr.set_text_input_mode(false)
        if input.pressed("up") then
            if selected_idx == 1 then
                focus_subzone = "presets"
            else
                selected_idx = selected_idx - 1
            end
        elseif input.pressed("down") then
            selected_idx = math.min(#search_results, selected_idx + 1)
        end

        local target_scroll = math.max(0, (selected_idx - 3) * 105)
        scroll_offset = scroll_offset + (target_scroll - scroll_offset) * math.min(1.0, dt * 12)

        -- Action: Open Book Action Dialog
        if input.pressed("a") and not skip_a then
            local target_book = search_results[selected_idx]
            if target_book then
                show_action_modal = true
                action_modal_book = target_book
                action_modal_focus = 1
            end
        -- Shortcut: Toggle Bookshelf directly
        elseif input.pressed("x") then
            local target_book = search_results[selected_idx]
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

function search_view.mousepressed(vx, vy, button)
    -- Handle virtual keyboard click
    if keyboard.is_open() then
        keyboard.mousepressed(vx, vy, button)
        return nil
    end

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

    local bar_x = 24
    local bar_y = 65
    local bar_w = 720 - 48
    local bar_h = 44
    local btn_w = 90
    local btn_gap = 10
    local input_w = bar_w - btn_w - btn_gap
    local btn_x = bar_x + input_w + btn_gap

    -- Click search input box
    if vx >= bar_x and vx <= bar_x + input_w and vy >= bar_y and vy <= bar_y + bar_h then
        focus_subzone = "input"
        keyboard.open(keyword, function(committed_text)
            keyword = committed_text
            search_view.perform_search()
            if #search_results > 0 then
                focus_subzone = "results"
            end
        end, function()
            focus_subzone = "input"
        end, function(live_text)
            keyword = live_text
        end)
        return nil
    end

    -- Click dedicated search button
    if vx >= btn_x and vx <= btn_x + btn_w and vy >= bar_y and vy <= bar_y + bar_h then
        focus_subzone = "search_btn"
        search_view.perform_search()
        return nil
    end

    -- Click preset pills
    local pill_x = bar_x
    local pill_y = bar_y + 54
    local f_hint = theme.get_font("hint")
    for i, kw in ipairs(PRESETS) do
        local pw = f_hint:getWidth(kw) + 24
        if vx >= pill_x and vx <= pill_x + pw and vy >= pill_y and vy <= pill_y + 28 then
            focus_subzone = "presets"
            preset_idx = i
            keyword = PRESETS[preset_idx]
            search_view.perform_search()
            return nil
        end
        pill_x = pill_x + pw + 8
    end

    -- Click results card
    local status_y = pill_y + 36
    local start_y = status_y + 24
    local card_h = 92
    local card_gap = 12

    if #search_results > 0 and vx >= bar_x and vx <= bar_x + bar_w then
        for i, book in ipairs(search_results) do
            local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
            if vy >= cy and vy <= cy + card_h then
                focus_subzone = "results"
                selected_idx = i

                local btn_w = 75
                local btn_h = 28
                local btn_y = cy + 14
                local shelf_btn_x = bar_x + bar_w - 85
                local read_btn_x = bar_x + bar_w - 170

                -- Click quick "阅读" button
                if vx >= read_btn_x and vx <= read_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h then
                    return { action = "open_reader", book = book }
                -- Click quick "+书架" / "已在架" button
                elseif vx >= shelf_btn_x and vx <= shelf_btn_x + btn_w and vy >= btn_y and vy <= btn_y + btn_h then
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

function search_view.wheelmoved(x, y)
    if #search_results == 0 or show_action_modal then return end
    focus_subzone = "results"
    if y > 0 then
        selected_idx = math.max(1, selected_idx - 1)
    elseif y < 0 then
        selected_idx = math.min(#search_results, selected_idx + 1)
    end
end

function search_view.draw(w, h, is_view_focused)
    if is_view_focused == nil then is_view_focused = true end
    local c = theme.colors()

    -- 1. Search Bar Header & Dedicated Search Button
    local bar_x = 24
    local bar_y = 65
    local bar_w = w - 48
    local bar_h = 44
    local btn_w = 90
    local btn_gap = 10
    local input_w = bar_w - btn_w - btn_gap
    local btn_x = bar_x + input_w + btn_gap

    -- A. Search Input Box
    local is_input_focused = is_view_focused and (focus_subzone == "input")
    local border_c = is_input_focused and c.focus or c.border
    local bg_c = is_input_focused and c.surface_active or c.surface
    theme.draw_panel(bar_x, bar_y, input_w, bar_h, bg_c, border_c, 8)
    if is_input_focused then
        theme.draw_focus_ring(bar_x, bar_y, input_w, bar_h, 8, 2)
    end

    theme.set_font("header")
    love.graphics.setColor(is_input_focused and c.focus or c.text)
    local cursor_char = (is_input_focused and math.floor(love.timer.getTime() * 2) % 2 == 0) and " |" or ""
    love.graphics.print("[搜] " .. (keyword == "" and "输入书名/作者..." or keyword) .. cursor_char, bar_x + 14, bar_y + 11)

    -- B. Dedicated Search Button
    local is_btn_focused = is_view_focused and (focus_subzone == "search_btn")
    local btn_bg = is_btn_focused and c.focus or c.surface_active
    local btn_border = is_btn_focused and c.accent or c.border
    theme.draw_panel(btn_x, bar_y, btn_w, bar_h, btn_bg, btn_border, 8)
    if is_btn_focused then
        theme.draw_focus_ring(btn_x, bar_y, btn_w, bar_h, 8, 2)
    end
    theme.set_font("header")
    local btn_label = is_searching and "搜索中..." or "搜索"
    local blw = theme.get_font("header"):getWidth(btn_label)
    love.graphics.setColor(is_btn_focused and { 1, 1, 1, 1 } or c.accent)
    love.graphics.print(btn_label, btn_x + (btn_w - blw) / 2, bar_y + 11)

    -- Preset Pills Row
    local pill_x = bar_x
    local pill_y = bar_y + 54
    theme.set_font("hint")
    for i, kw in ipairs(PRESETS) do
        local is_sel = (i == preset_idx)
        local is_pill_focused = is_view_focused and (focus_subzone == "presets") and is_sel
        local pw = theme.draw_pill(kw, pill_x, pill_y, is_sel, is_pill_focused)
        pill_x = pill_x + pw + 8
    end

    -- Status Text
    local status_y = pill_y + 36
    theme.set_font("hint")
    love.graphics.setColor(is_searching and c.accent or c.text_muted)
    love.graphics.print(status_msg, bar_x, status_y)

    -- 2. Results List
    local start_y = status_y + 24
    local card_h = 92
    local card_gap = 12

    love.graphics.setScissor(0, start_y, w, h - start_y - 45)

    if #search_results > 0 then
        for i, book in ipairs(search_results) do
            local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
            if cy + card_h > start_y - 20 and cy < h - 40 then
                local is_focused = is_view_focused and (focus_subzone == "results") and (i == selected_idx) and not show_action_modal
                theme.draw_card(bar_x, cy, bar_w, card_h, is_focused)

                theme.set_font("title")
                love.graphics.setColor(is_focused and c.focus or c.text)
                love.graphics.print(book.name or "未命名", bar_x + 16, cy + 12)

                local title_w = theme.get_font("title"):getWidth(book.name or "")
                local clean_kind = (book.kind or "综合"):gsub("[\r\n]+", " "):gsub("%s+", " ")
                local pw1 = theme.draw_pill(clean_kind, bar_x + 24 + title_w, cy + 12, false)

                -- Aggregated Sources Count & Best Source Badge
                local cand_cnt = (book.candidates and #book.candidates) or 1
                local agg_label = string.format("%d个源·%s %dms", cand_cnt, book.originName or "源", book.latencyMs or 0)
                theme.draw_pill(agg_label, bar_x + 32 + title_w + pw1, cy + 12, cand_cnt > 1)

                theme.set_font("hint")
                love.graphics.setColor(c.text_muted)
                love.graphics.print(string.format("作者: %s  |  类型: %s", book.author or "未知", book.kind or "综合"), bar_x + 16, cy + 42)

                love.graphics.setColor(c.accent)
                love.graphics.print(string.format("最新: %s", book.latestChapterTitle or "连载中"), bar_x + 16, cy + 64)

                -- Quick Buttons on Card: [阅读] & [+书架]/[已在架]
                local btn_w = 75
                local btn_h = 28
                local btn_y = cy + 14
                local shelf_btn_x = bar_x + bar_w - 85
                local read_btn_x = bar_x + bar_w - 170

                -- [阅读] Pill
                theme.draw_panel(read_btn_x, btn_y, btn_w, btn_h, c.surface_active, is_focused and c.focus or c.border, 6)
                theme.set_font("hint")
                love.graphics.setColor(is_focused and c.focus or c.text)
                local r_tw = theme.get_font("hint"):getWidth("阅读")
                love.graphics.print("阅读", read_btn_x + (btn_w - r_tw) / 2, btn_y + 6)

                -- [+书架] / [已在架] Pill
                local in_shelf = storage.is_in_bookshelf(book)
                local s_label = in_shelf and "已在架" or "+书架"
                local s_bg = in_shelf and c.focus_bg or c.surface
                local s_border = in_shelf and c.focus or c.border
                theme.draw_panel(shelf_btn_x, btn_y, btn_w, btn_h, s_bg, s_border, 6)
                love.graphics.setColor(in_shelf and c.focus or c.text_muted)
                local s_tw = theme.get_font("hint"):getWidth(s_label)
                love.graphics.print(s_label, shelf_btn_x + (btn_w - s_tw) / 2, btn_y + 6)
            end
        end
    elseif not is_searching then
        theme.set_font("body")
        love.graphics.setColor(c.text_muted)
        local empty_tip = "输入书名搜索，或按 [A] 搜索推荐词"
        local tip_w = theme.get_font("body"):getWidth(empty_tip)
        love.graphics.print(empty_tip, math.floor((w - tip_w) / 2), start_y + 80)
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
        love.graphics.print(string.format("作者: %s  |  类型: %s", action_modal_book.author or "未知", action_modal_book.kind or "综合"), mx + 24, my + 58)

        theme.set_font("hint")
        love.graphics.setColor(c.accent)
        local s_line = search_view.get_action_source_line()
        if action_modal_book.candidates and #action_modal_book.candidates > 1 then
            s_line = s_line .. string.format("   [L1/R1 切换书源 (%d个可用)]", #action_modal_book.candidates)
        end
        love.graphics.print(s_line, mx + 24, my + 90)

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

    love.graphics.setScissor()

    -- 4. Virtual Keyboard Overlay
    if keyboard.is_open() then
        keyboard.draw(w, h)
    end
end

return search_view
