--[[
    change_source.lua: Smart Change Source Panel ported from legado-windows.
    Searches across all enabled sources in parallel, sorts by latency,
    and aligns reading chapter index using ChapterAlignmentEngine.
]]

local theme = require("src.theme")
local storage = require("src.storage")
local http = require("src.http")
local legado = require("src.legado")
local json = require("src.json")
local ca = require("src.chapter_alignment")

local change_source = {}

local is_active = false
local current_book = nil
local cur_chapter_title = ""
local cur_chapter_idx = 0
local on_select_cb = nil

local previous_source = nil
local candidates = {}
local selected_idx = 1
local scroll_offset = 0
local is_searching = false
local completed_count = 0
local total_sources = 0

-- Concurrency and lifecycle state
local change_source_session = 0
local search_queue = {}
local search_queue_idx = 1
local active_requests = 0
local MAX_CONCURRENT = 3

function change_source.is_open()
    return is_active
end

function change_source.get_candidates()
    return candidates
end

function change_source.get_previous()
    return previous_source
end

function change_source.close()
    is_active = false
    change_source_session = change_source_session + 1
    search_queue = {}
    search_queue_idx = 1
    active_requests = 0
    is_searching = false
end

function change_source._inject_candidate(cand)
    local insert_idx = #candidates + 1
    for i, c in ipairs(candidates) do
        if (cand.latencyMs or 9999) < (c.latencyMs or 9999) then
            insert_idx = i
            break
        end
    end
    table.insert(candidates, insert_idx, cand)
end

local function pump_search_queue()
    if not is_active then return end
    local my_session = change_source_session

    while active_requests < MAX_CONCURRENT and search_queue_idx <= #search_queue do
        local item = search_queue[search_queue_idx]
        search_queue_idx = search_queue_idx + 1
        active_requests = active_requests + 1

        local src = item.src
        local src_json = item.src_json
        local req_obj = item.req_obj
        local clean_name = item.clean_name
        local book = current_book

        local t0 = love and love.timer and love.timer.getTime() or os.clock()
        http.request_async({
            url = req_obj.url,
            method = req_obj.method,
            headers = req_obj.headers,
            type = req_obj.type,
            charset = req_obj.charset,
            body = req_obj.body,
            timeout = 5
        }, function(resp)
            if change_source_session ~= my_session or not is_active then return end
            active_requests = math.max(0, active_requests - 1)
            completed_count = completed_count + 1
            if completed_count >= total_sources then
                is_searching = false
            end

            local t1 = love and love.timer and love.timer.getTime() or os.clock()
            local latency = math.floor((t1 - t0) * 1000)

            if resp and #resp > 0 then
                local parsed_json = legado.parseSearch(src_json, resp, req_obj.url)
                local list = json.decode(parsed_json)
                if type(list) == "table" then
                    for _, res_item in ipairs(list) do
                        local item_name = (res_item.name or ""):gsub("[《》【】%[%]%s]+", "")
                        if item_name == clean_name then
                            local cand = {
                                book = res_item,
                                source = src,
                                origin = src.bookSourceUrl,
                                originName = src.bookSourceName or "未知源",
                                latencyMs = latency,
                                latestChapterTitle = res_item.latestChapterTitle,
                                chapters = nil,
                                alignment = nil,
                                is_current = (src.bookSourceUrl == (book and book.origin))
                            }
                            change_source._inject_candidate(cand)
                            break
                        end
                    end
                end
            end

            pump_search_queue()
        end)
    end
end

function change_source.open(book, currentChapterTitle, currentChapterIndex, on_select)
    is_active = true
    change_source_session = change_source_session + 1
    local my_session = change_source_session

    current_book = book
    cur_chapter_title = currentChapterTitle or ""
    cur_chapter_idx = currentChapterIndex or 0
    on_select_cb = on_select

    if book then
        previous_source = {
            origin = book.origin or "",
            originName = book.originName or "原书源",
            chapterIndex = currentChapterIndex or 0,
            chapterTitle = currentChapterTitle or ""
        }
    end

    candidates = {}
    selected_idx = 1
    scroll_offset = 0
    is_searching = true
    completed_count = 0
    search_queue = {}
    search_queue_idx = 1
    active_requests = 0

    local sources = storage.get_sources()
    local enabled_sources = {}
    for _, s in ipairs(sources) do
        if s.enabled ~= false and s.searchUrl and #s.searchUrl > 0 then
            table.insert(enabled_sources, s)
        end
    end
    total_sources = #enabled_sources

    if total_sources == 0 then
        is_searching = false
        return
    end

    local book_name = book and book.name or ""
    local clean_name = book_name:gsub("[《》【】%[%]%s]+", "")

    for _, src in ipairs(enabled_sources) do
        local src_json = json.encode(src)
        local req_json = legado.buildSearchRequest(src_json, book_name, 1)
        local req_obj = json.decode(req_json)

        if req_obj and req_obj.url then
            table.insert(search_queue, {
                src = src,
                src_json = src_json,
                req_obj = req_obj,
                clean_name = clean_name
            })
        else
            completed_count = completed_count + 1
            if completed_count >= total_sources then
                is_searching = false
            end
        end
    end

    pump_search_queue()
end

-- Asynchronously fetch TOC and compute alignment for candidate if missing
local function ensure_candidate_alignment(cand)
    if not cand or cand.chapters or cand.is_fetching_toc then return end
    cand.is_fetching_toc = true
    local my_session = change_source_session

    local src_json = json.encode(cand.source)
    local toc_url = cand.book.tocUrl or cand.book.bookUrl

    http.request_async({
        url = toc_url,
        timeout = 6
    }, function(resp)
        cand.is_fetching_toc = false
        if change_source_session ~= my_session or not is_active then return end
        if resp and #resp > 0 then
            local parsed_toc = legado.parseToc(src_json, resp, toc_url)
            local chs = type(parsed_toc) == "table" and (parsed_toc.chapters or parsed_toc) or json.decode(parsed_toc)
            if type(chs) == "table" and #chs > 0 then
                cand.chapters = chs
                cand.alignment = ca.align(cur_chapter_title, cur_chapter_idx, chs)
            end
        end
    end)
end

function change_source.update(dt, input)
    if not is_active then return end

    -- Trigger alignment for currently focused candidate
    local current_cand = candidates[selected_idx]
    if current_cand then
        ensure_candidate_alignment(current_cand)
    end

    if input.pressed("up") then
        selected_idx = math.max(1, selected_idx - 1)
    elseif input.pressed("down") then
        selected_idx = math.min(#candidates, selected_idx + 1)
    elseif input.pressed("b") then
        change_source.close()
    elseif input.pressed("x") then
        -- Quick rollback to previous source
        if previous_source and on_select_cb then
            on_select_cb(nil, nil, previous_source.chapterIndex, nil, true)
            change_source.close()
        end
    elseif input.pressed("a") then
        local chosen = candidates[selected_idx]
        if chosen and on_select_cb then
            local aligned_idx = chosen.alignment and (chosen.alignment.index + 1) or (cur_chapter_idx + 1)
            local cb = on_select_cb
            local c_book = chosen.book
            local c_src = chosen.source
            local c_chaps = chosen.chapters
            change_source.close()
            cb(c_book, c_src, aligned_idx, c_chaps, false)
        end
    end

    local target_scroll = math.max(0, (selected_idx - 3) * 110)
    scroll_offset = scroll_offset + (target_scroll - scroll_offset) * math.min(1.0, (dt or 0.016) * 12)
end

function change_source.draw(w, h)
    if not is_active then return end
    local c = theme.colors()

    -- 1. Dim background overlay
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local mw = math.min(w - 32, 540)
    local mh = math.min(h - 40, 620)
    local mx = math.floor((w - mw) / 2)
    local my = math.floor((h - mh) / 2)

    theme.draw_panel(mx, my, mw, mh, c.surface, c.border, 12)
    theme.draw_focus_ring(mx, my, mw, mh, 12, 1)

    -- Header
    theme.set_font("title")
    love.graphics.setColor(c.focus)
    love.graphics.print("🔄 智能换源与对齐", mx + 20, my + 16)

    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    love.graphics.print(string.format("当前阅读: %s", cur_chapter_title or "第 1 章"), mx + 20, my + 44)

    -- Rollback hint if previous source exists
    if previous_source and previous_source.origin ~= "" then
        love.graphics.setColor(c.accent)
        love.graphics.print(string.format("[X] 切回上个书源: %s", previous_source.originName or ""), mx + mw - 220, my + 18)
    end

    -- Status Line
    local status_line_y = my + 68
    local status_txt = is_searching and string.format("正在跨源检索... (%d/%d)", completed_count, total_sources)
                       or string.format("检索完成，共发现 %d 个可用书源 (按延迟升序)", #candidates)
    love.graphics.setColor(is_searching and c.accent or c.text_muted)
    love.graphics.print(status_txt, mx + 20, status_line_y)

    -- Candidate list view
    local list_y = status_line_y + 24
    local list_h = my + mh - list_y - 20
    love.graphics.setScissor(mx + 10, list_y, mw - 20, list_h)

    local item_h = 96
    local gap = 10

    for i, cand in ipairs(candidates) do
        local cy = list_y + (i - 1) * (item_h + gap) - scroll_offset
        if cy + item_h > list_y - 20 and cy < list_y + list_h + 20 then
            local is_focused = (i == selected_idx)
            local bg = is_focused and c.focus_bg or c.surface_active
            local bcol = is_focused and c.focus or (cand.is_current and c.accent or c.border)

            theme.draw_panel(mx + 16, cy, mw - 32, item_h, bg, bcol, 8)
            if is_focused then
                theme.draw_focus_ring(mx + 16, cy, mw - 32, item_h, 8, 2)
            end

            -- Source Name & Current Badge
            theme.set_font("body")
            love.graphics.setColor(is_focused and c.focus or c.text)
            love.graphics.print(cand.originName or "书源", mx + 28, cy + 10)

            if cand.is_current then
                theme.draw_pill("当前源", mx + 160, cy + 10, true)
            end

            -- Latency badge
            local lat = cand.latencyMs or 999
            local lat_str = string.format("%d ms", lat)
            local lat_col = lat < 600 and c.success or (lat < 1500 and c.accent or c.danger)
            theme.set_font("hint")
            love.graphics.setColor(lat_col)
            local lw = theme.get_font("hint"):getWidth(lat_str)
            love.graphics.print(lat_str, mx + mw - 32 - lw - 12, cy + 12)

            -- Latest Chapter
            love.graphics.setColor(c.text_muted)
            local lat_chap = string.format("最新: %s", cand.latestChapterTitle or "连载中")
            love.graphics.print(lat_chap, mx + 28, cy + 38)

            -- Alignment Info
            local align_y = cy + 62
            if cand.alignment then
                local al = cand.alignment
                local conf_pct = math.floor((al.confidence or 0) * 100)
                local al_col = (al.confidence and al.confidence >= 0.8) and c.success or c.accent
                love.graphics.setColor(al_col)
                local al_str = string.format("✅ 对齐第 %d 章 (%d%%): %s", (al.index or 0) + 1, conf_pct, al.strategy or "")
                love.graphics.print(al_str, mx + 28, align_y)
            elseif cand.is_fetching_toc then
                love.graphics.setColor(c.accent)
                love.graphics.print("正在对齐目录章节...", mx + 28, align_y)
            else
                love.graphics.setColor(c.text_muted)
                love.graphics.print("移动光标到此处自动对齐目录", mx + 28, align_y)
            end
        end
    end

    love.graphics.setScissor()
end

function change_source.mousepressed(vx, vy, button)
    if not is_active then return nil end

    local w, h = 720, 720
    local mw = math.min(w - 32, 540)
    local mh = math.min(h - 40, 620)
    local mx = math.floor((w - mw) / 2)
    local my = math.floor((h - mh) / 2)

    -- Click outside -> close
    if vx < mx or vx > mx + mw or vy < my or vy > my + mh then
        change_source.close()
        return nil
    end

    local list_y = my + 92
    local item_h = 96
    local gap = 10

    for i, cand in ipairs(candidates) do
        local cy = list_y + (i - 1) * (item_h + gap) - scroll_offset
        if vx >= mx + 16 and vx <= mx + mw - 16 and vy >= cy and vy <= cy + item_h then
            selected_idx = i
            if on_select_cb then
                local aligned_idx = cand.alignment and (cand.alignment.index + 1) or (cur_chapter_idx + 1)
                local cb = on_select_cb
                local c_book = cand.book
                local c_src = cand.source
                local c_chaps = cand.chapters
                change_source.close()
                cb(c_book, c_src, aligned_idx, c_chaps, false)
            end
            return nil
        end
    end

    return nil
end

return change_source
