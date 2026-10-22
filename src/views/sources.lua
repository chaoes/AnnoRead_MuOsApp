local theme = require("src.theme")
local storage = require("src.storage")
local http = require("src.http")
local legado = require("src.legado")
local json = require("src.json")
local sources_view = {}

local selected_idx = 1
local scroll_offset = 0
local diag_status = {} -- [idx] = { text = "...", latency = 120, ok = true }

function sources_view.init()
    if storage.reload_sources then
        storage.reload_sources()
    end
    selected_idx = 1
    scroll_offset = 0
    diag_status = {}
end

function sources_view.get_enabled_counts()
    local sources = storage.get_sources()
    local enabled_cnt = 0
    for _, s in ipairs(sources) do
        if s.enabled ~= false then enabled_cnt = enabled_cnt + 1 end
    end
    return enabled_cnt, #sources
end

function sources_view.batch_toggle_all(enabled)
    storage.enable_all_sources(enabled)
end

local function run_source_diagnosis(idx)
    local sources = storage.get_sources()
    local src = sources[idx]
    if not src then return end

    diag_status[idx] = { text = "正在测速诊断中...", ok = nil }
    local t0 = love.timer.getTime()

    local src_json = json.encode(src)
    local req_json = legado.buildSearchRequest(src_json, "测试", 1)
    if not req_json or #req_json == 0 then
        diag_status[idx] = { text = "诊断失败: searchUrl 规则无效", ok = false }
        return
    end

    local req_obj = json.decode(req_json)
    if not req_obj or not req_obj.url then
        diag_status[idx] = { text = "诊断失败: URL 生成异常", ok = false }
        return
    end

    http.request_async({
        url = req_obj.url,
        method = req_obj.method,
        headers = req_obj.headers,
        body = req_obj.body,
        type = req_obj.type,
        charset = req_obj.charset,
        timeout = 5
    }, function(resp)
        local elapsed = math.floor((love.timer.getTime() - t0) * 1000)
        if resp and #resp > 10 then
            diag_status[idx] = {
                text = string.format("正常 (响应 %d ms, 数据 %d 字节)", elapsed, #resp),
                latency = elapsed,
                ok = true
            }
        else
            diag_status[idx] = {
                text = string.format("超时/请求失败 (%d ms)", elapsed),
                latency = elapsed,
                ok = false
            }
        end
    end)
end

function sources_view._test_apply_migration(bookUrl, target, alignedIndex)
    local books = storage.get_books()
    local target_book = nil
    for _, b in ipairs(books) do
        if b.bookUrl == bookUrl then
            target_book = b
            break
        end
    end
    if not target_book then return false end

    -- Guard against progress regression:
    -- If verified total chapters is less than current progress, mark deleted instead of regressing.
    local cur_prog_idx = target_book.currentChapterIndex or 1
    if target.totalChapters and target.totalChapters > 0 and target.totalChapters < cur_prog_idx then
        storage.mark_book_source_deleted(bookUrl)
        return false
    end

    if target.origin and target.origin ~= "" then
        storage.update_book_origin(bookUrl, target.origin, target.originName, target.bookUrl, target.tocUrl)
        return true
    else
        storage.mark_book_source_deleted(bookUrl)
        return false
    end
end

function sources_view.migrate_books_from_source(origin, on_done)
    local affected_books = storage.get_books_by_origin(origin)
    if #affected_books == 0 then
        if on_done then on_done() end
        return
    end

    local remaining_sources = {}
    for _, s in ipairs(storage.get_sources()) do
        if s.enabled ~= false and s.bookSourceUrl ~= origin and s.searchUrl and #s.searchUrl > 0 then
            table.insert(remaining_sources, s)
        end
    end

    if #remaining_sources == 0 then
        for _, b in ipairs(affected_books) do
            storage.mark_book_source_deleted(b.bookUrl)
        end
        if on_done then on_done() end
        return
    end

    -- For each affected book, search remaining sources concurrently
    local pending = #affected_books
    for _, b in ipairs(affected_books) do
        local b_url = b.bookUrl
        local b_name = b.name
        local clean_name = (b_name or ""):gsub("[《》【】%[%]%s]+", "")

        local book_migrated = false
        local sources_tried = 0
        local total_to_try = #remaining_sources

        for _, s in ipairs(remaining_sources) do
            local src_json = json.encode(s)
            local req_json = legado.buildSearchRequest(src_json, b_name, 1)
            local req_obj = json.decode(req_json)

            if req_obj and req_obj.url then
                http.request_async({
                    url = req_obj.url,
                    method = req_obj.method,
                    headers = req_obj.headers,
                    type = req_obj.type,
                    charset = req_obj.charset,
                    body = req_obj.body,
                    timeout = 5
                }, function(resp)
                    sources_tried = sources_tried + 1
                    if not book_migrated and resp and #resp > 0 then
                        local parsed_json = legado.parseSearch(src_json, resp, req_obj.url)
                        local list = json.decode(parsed_json)
                        if type(list) == "table" then
                            for _, item in ipairs(list) do
                                local item_name = (item.name or ""):gsub("[《》【】%[%]%s]+", "")
                                if item_name == clean_name then
                                    book_migrated = true
                                    sources_view._test_apply_migration(b_url, {
                                        origin = s.bookSourceUrl,
                                        originName = s.bookSourceName,
                                        bookUrl = item.bookUrl,
                                        tocUrl = item.tocUrl or item.bookUrl,
                                        totalChapters = 0 -- unverified, safe migration
                                    }, 0)
                                    break
                                end
                            end
                        end
                    end

                    if sources_tried >= total_to_try then
                        if not book_migrated then
                            storage.mark_book_source_deleted(b_url)
                        end
                        pending = pending - 1
                        if pending <= 0 and on_done then on_done() end
                    end
                end)
            else
                sources_tried = sources_tried + 1
                if sources_tried >= total_to_try then
                    if not book_migrated then
                        storage.mark_book_source_deleted(b_url)
                    end
                    pending = pending - 1
                    if pending <= 0 and on_done then on_done() end
                end
            end
        end
    end
end

function sources_view.update(dt, input)
    local sources = storage.get_sources()
    if #sources == 0 then
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
        end
    elseif input.pressed("down") then
        selected_idx = math.min(#sources, selected_idx + 1)
    end

    local target_scroll = math.max(0, (selected_idx - 3) * 105)
    scroll_offset = scroll_offset + (target_scroll - scroll_offset) * math.min(1.0, dt * 12)

    -- Toggle Enable / Disable (停用 / 启用)
    if input.pressed("x") then
        storage.toggle_source(selected_idx)
    -- Batch Disable All (L2) / Batch Enable All (R2)
    elseif input.pressed("l2") then
        sources_view.batch_toggle_all(false)
    elseif input.pressed("r2") then
        sources_view.batch_toggle_all(true)
    -- Test Diagnosis Speed
    elseif input.pressed("a") then
        run_source_diagnosis(selected_idx)
    end

    return nil
end

function sources_view.mousepressed(vx, vy, button)
    local sources = storage.get_sources()
    if #sources == 0 then return nil end

    local card_x = 24
    local card_w = 720 - 48
    local card_h = 92
    local card_gap = 12
    local start_y = 108

    if vx >= card_x and vx <= card_x + card_w then
        for i, src in ipairs(sources) do
            local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
            if vy >= cy and vy <= cy + card_h then
                selected_idx = i
                if vx >= card_x + card_w - 120 and vx <= card_x + card_w - 10 and vy >= cy + 10 and vy <= cy + 40 then
                    storage.toggle_source(i)
                elseif button == 1 then
                    run_source_diagnosis(i)
                end
                break
            end
        end
    end
    return nil
end

function sources_view.wheelmoved(x, y)
    local sources = storage.get_sources()
    if #sources == 0 then return end
    if y > 0 then
        selected_idx = math.max(1, selected_idx - 1)
    elseif y < 0 then
        selected_idx = math.min(#sources, selected_idx + 1)
    end
end

function sources_view.draw(w, h, is_view_focused)
    if is_view_focused == nil then is_view_focused = true end
    local c = theme.colors()
    local sources = storage.get_sources()

    if #sources == 0 then
        theme.set_font("header")
        love.graphics.setColor(c.text_muted)
        local empty_tip = "当前无可用书源\n\n请将 Legado 书源 .json 文件放入 sources/ 目录\n按 [方向键上] 选择顶部导航"
        love.graphics.printf(empty_tip, 0, h * 0.4, w, "center")
        return
    end

    local card_x = 24
    local card_w = w - 48
    local card_h = 92
    local card_gap = 12
    local start_y = 108

    -- Top Summary Pill
    local enabled_cnt, total_cnt = sources_view.get_enabled_counts()
    theme.set_font("hint")
    love.graphics.setColor(enabled_cnt > 0 and c.focus or c.danger)
    local summary_txt = string.format("已启用 %d / %d 个书源   [X单关 / L2全关 / R2全开]", enabled_cnt, total_cnt)
    love.graphics.print(summary_txt, card_x, 64)

    -- Where user can drop sources
    love.graphics.setColor(c.text_muted)
    local dir_hint = "书源目录: sources/ (放入.json书源文件直接生效)"
    love.graphics.print(dir_hint, card_x, 84)

    love.graphics.setScissor(0, start_y - 5, w, h - start_y - 45)

    for i, src in ipairs(sources) do
        local cy = start_y + (i - 1) * (card_h + card_gap) - scroll_offset
        if cy + card_h > start_y - 20 and cy < h - 40 then
            local is_focused = is_view_focused and (i == selected_idx)
            local is_enabled = (src.enabled ~= false)
            theme.draw_card(card_x, cy, card_w, card_h, is_focused)

            -- Source Name & Group Tag
            theme.set_font("title")
            love.graphics.setColor(is_focused and c.focus or c.text)
            love.graphics.print(src.bookSourceName or "未命名书源", card_x + 16, cy + 12)

            local name_w = theme.get_font("title"):getWidth(src.bookSourceName or "")
            theme.draw_pill(src.bookSourceGroup or "小说", card_x + 24 + name_w, cy + 12, false)

            -- Enable / Disable Badge on Right
            local status_text = is_enabled and "已启用" or "已停用"
            local status_w = theme.get_font("hint"):getWidth(status_text) + 20
            local status_x = card_x + card_w - status_w - 16
            local status_bg = is_enabled and c.success or c.surface_active
            local status_fg = is_enabled and { 1, 1, 1, 1 } or c.text_muted

            love.graphics.setColor(status_bg)
            love.graphics.rectangle("fill", status_x, cy + 12, status_w, 24, 12, 12)
            theme.set_font("hint")
            love.graphics.setColor(status_fg)
            love.graphics.print(status_text, status_x + 10, cy + 16)

            -- Source Base URL
            love.graphics.setColor(c.text_muted)
            love.graphics.print(src.bookSourceUrl or "", card_x + 16, cy + 42)

            -- Diagnosis / Speed Result
            local diag = diag_status[i]
            if diag then
                love.graphics.setColor(diag.ok and c.success or (diag.ok == false and c.danger or c.accent))
                love.graphics.print("测速诊断: " .. diag.text, card_x + 16, cy + 64)
            else
                love.graphics.setColor(c.text_muted)
                local toggle_action = is_enabled and "按 [X] 停用此源" or "按 [X] 启用此源"
                love.graphics.print("按 [A] 测速诊断  ·  " .. toggle_action, card_x + 16, cy + 64)
            end
        end
    end

    love.graphics.setScissor()
end

return sources_view
