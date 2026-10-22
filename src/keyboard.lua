local theme = require("src.theme")
local pinyin = require("src.pinyin_dict")
local keyboard = {}

local is_active = false
local current_text = ""
local pinyin_buffer = ""
local input_mode = "zh" -- "zh" or "en"
local is_symbols = false -- false = letter/number keyboard, true = dedicated symbols keyboard
local on_commit_cb = nil
local on_close_cb = nil
local on_change_cb = nil

-- Candidate management
local candidates = {}
local cand_page = 1
local CANDS_PER_PAGE = 7

-- Cursor navigation on QWERTY / Symbol grid
-- cursor_row == 0 is the candidate bar; 1..5 are the key rows.
local cursor_row = 2
local cursor_col = 1
-- Focused candidate index within the current candidate page (row 0 only)
local cand_cursor = 1

-- QWERTY Keyboards
local KEYS_ROW1 = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "退格" }
local KEYS_ROW2 = { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" }
local KEYS_ROW3 = { "a", "s", "d", "f", "g", "h", "j", "k", "l" }
local KEYS_ROW4 = { "中/英", "z", "x", "c", "v", "b", "n", "m", "符号", "清空" }
local KEYS_ROW5 = { "关闭键盘", "空格", "确定/搜索" }

-- Dedicated Symbols Keyboards
-- Chinese Full-Width Symbols
local SYM_ZH_ROW1 = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "退格" }
local SYM_ZH_ROW2 = { "，", "。", "、", "？", "！", "：", "；", "“", "”", "…" }
local SYM_ZH_ROW3 = { "（", "）", "《", "》", "【", "】", "—", "～", "·", "’" }
local SYM_ZH_ROW4 = { "中/英", "￥", "/", "@", "#", "%", "+", "-", "返回字母", "清空" }

-- English Half-Width Symbols
local SYM_EN_ROW1 = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "退格" }
local SYM_EN_ROW2 = { ",", ".", "/", "?", "!", ":", ";", "\"", "'", "`" }
local SYM_EN_ROW3 = { "(", ")", "<", ">", "[", "]", "_", "~", "-", "=" }
local SYM_EN_ROW4 = { "中/英", "$", "\\", "@", "#", "%", "*", "&", "返回字母", "清空" }

local function utf8_pop(str)
    if not str or #str == 0 then return "" end
    local p = #str
    while p > 1 do
        local b = string.byte(str, p)
        if b < 128 or b >= 192 then break end
        p = p - 1
    end
    return string.sub(str, 1, p - 1)
end

local function notify_change()
    if on_change_cb then
        on_change_cb(current_text)
    end
end

function keyboard.open(initial_text, on_commit, on_close, on_change)
    is_active = true
    current_text = initial_text or ""
    pinyin_buffer = ""
    input_mode = "zh"
    is_symbols = false
    candidates = {}
    cand_page = 1
    cursor_row = 2
    cursor_col = 1
    cand_cursor = 1
    on_commit_cb = on_commit
    on_close_cb = on_close
    on_change_cb = on_change
end

function keyboard.close()
    if not is_active then return end
    is_active = false
    if on_close_cb then
        on_close_cb()
    end
end

function keyboard.is_open()
    return is_active
end

function keyboard.get_text()
    return current_text
end

function keyboard.get_buffer()
    return pinyin_buffer
end

function keyboard.get_input_mode()
    return input_mode
end

function keyboard.is_symbol_mode()
    return is_symbols
end

function keyboard.toggle_symbol_mode()
    is_symbols = not is_symbols
    pinyin_buffer = ""
    keyboard.refresh_candidates()
    local keys = keyboard.get_active_row_keys(cursor_row)
    cursor_col = math.min(cursor_col, #keys)
end

function keyboard.toggle_input_mode()
    input_mode = (input_mode == "zh") and "en" or "zh"
    pinyin_buffer = ""
    keyboard.refresh_candidates()
end

function keyboard.get_current_page()
    return cand_page
end

function keyboard.get_cursor()
    return cursor_row, cursor_col, cand_cursor
end

function keyboard._set_cursor(row, col, cc)
    cursor_row = row
    cursor_col = col or cursor_col
    cand_cursor = cc or cand_cursor
end

function keyboard.get_total_pages()
    return math.max(1, math.ceil(#candidates / CANDS_PER_PAGE))
end

function keyboard.get_current_candidates()
    return candidates
end

function keyboard.get_paged_candidates()
    local res = {}
    local start_idx = (cand_page - 1) * CANDS_PER_PAGE + 1
    local end_idx = math.min(#candidates, start_idx + CANDS_PER_PAGE - 1)
    for i = start_idx, end_idx do
        table.insert(res, candidates[i])
    end
    return res, start_idx
end

function keyboard.refresh_candidates()
    if input_mode == "zh" and not is_symbols and #pinyin_buffer > 0 then
        candidates = pinyin.get_candidates(pinyin_buffer)
        cand_page = 1
    else
        candidates = {}
        cand_page = 1
    end
    cand_cursor = 1
end

function keyboard.handle_key(ch)
    if input_mode == "zh" and not is_symbols then
        if ch >= "a" and ch <= "z" then
            pinyin_buffer = pinyin_buffer .. ch
            keyboard.refresh_candidates()
            return
        end
    end
    -- English, digits, or direct symbols
    current_text = current_text .. ch
    notify_change()
end

function keyboard.handle_backspace()
    if #pinyin_buffer > 0 then
        pinyin_buffer = string.sub(pinyin_buffer, 1, #pinyin_buffer - 1)
        keyboard.refresh_candidates()
    else
        current_text = utf8_pop(current_text)
        notify_change()
    end
end

function keyboard.handle_clear()
    if #pinyin_buffer > 0 then
        pinyin_buffer = ""
        keyboard.refresh_candidates()
    else
        current_text = ""
        notify_change()
    end
end

function keyboard.select_candidate(idx_on_page)
    local paged = keyboard.get_paged_candidates()
    local word = paged[idx_on_page]
    if word then
        current_text = current_text .. word
        pinyin_buffer = ""
        keyboard.refresh_candidates()
        notify_change()
    end
end

function keyboard.prev_candidate_page()
    if cand_page > 1 then
        cand_page = cand_page - 1
    end
end

function keyboard.next_candidate_page()
    local total_pages = math.ceil(#candidates / CANDS_PER_PAGE)
    if cand_page < total_pages then
        cand_page = cand_page + 1
    end
end

function keyboard.get_active_row_keys(row)
    if is_symbols then
        local is_zh = (input_mode == "zh")
        if row == 1 then return is_zh and SYM_ZH_ROW1 or SYM_EN_ROW1
        elseif row == 2 then return is_zh and SYM_ZH_ROW2 or SYM_EN_ROW2
        elseif row == 3 then return is_zh and SYM_ZH_ROW3 or SYM_EN_ROW3
        elseif row == 4 then return is_zh and SYM_ZH_ROW4 or SYM_EN_ROW4
        elseif row == 5 then return KEYS_ROW5
        end
    else
        if row == 1 then return KEYS_ROW1
        elseif row == 2 then return KEYS_ROW2
        elseif row == 3 then return KEYS_ROW3
        elseif row == 4 then return KEYS_ROW4
        elseif row == 5 then return KEYS_ROW5
        end
    end
    return KEYS_ROW2
end

function keyboard.trigger_current_key()
    local row_keys = keyboard.get_active_row_keys(cursor_row)
    local key = row_keys[cursor_col]
    if not key then return end

    if key == "退格" then
        keyboard.handle_backspace()
    elseif key == "中/英" then
        keyboard.toggle_input_mode()
    elseif key == "符号" or key == "返回字母" then
        keyboard.toggle_symbol_mode()
    elseif key == "清空" then
        keyboard.handle_clear()
    elseif key == "关闭键盘" then
        keyboard.close()
    elseif key == "空格" then
        if #pinyin_buffer > 0 then
            local paged = keyboard.get_paged_candidates()
            if #paged > 0 then
                keyboard.select_candidate(1)
            else
                current_text = current_text .. pinyin_buffer
                pinyin_buffer = ""
                keyboard.refresh_candidates()
                notify_change()
            end
        else
            current_text = current_text .. " "
            notify_change()
        end
    elseif key == "确定/搜索" then
        if #pinyin_buffer > 0 then
            local paged = keyboard.get_paged_candidates()
            if #paged > 0 then
                keyboard.select_candidate(1)
            else
                current_text = current_text .. pinyin_buffer
                pinyin_buffer = ""
                keyboard.refresh_candidates()
                notify_change()
            end
        end
        local committed = current_text
        is_active = false
        if on_commit_cb then
            on_commit_cb(committed)
        end
    else
        -- Regular key: letter, digit, or symbol
        if #pinyin_buffer > 0 and key >= "1" and key <= "7" then
            local num = tonumber(key)
            keyboard.select_candidate(num)
        else
            keyboard.handle_key(key)
        end
    end
end

function keyboard.update(dt, input)
    if not is_active then return end

    local total_pages = keyboard.get_total_pages()

    -- 0. Candidate-bar focus (cursor_row == 0)
    if cursor_row == 0 then
        local paged = keyboard.get_paged_candidates()

        if input.pressed("left") then
            if cand_cursor > 1 then
                cand_cursor = cand_cursor - 1
            else
                -- At the left edge, jump to the previous page (wrap to its end)
                if cand_page > 1 then
                    cand_page = cand_page - 1
                    local prev = keyboard.get_paged_candidates()
                    cand_cursor = math.max(1, #prev)
                end
            end
        elseif input.pressed("right") then
            if cand_cursor < #paged then
                cand_cursor = cand_cursor + 1
            else
                -- At the right edge, jump to the next page (wrap to its start)
                if cand_page < total_pages then
                    cand_page = cand_page + 1
                    cand_cursor = 1
                end
            end
        elseif input.pressed("l1") then
            -- Page candidates left/right; never falls through to tab switching
            if cand_page > 1 then cand_page = cand_page - 1; cand_cursor = 1 end
        elseif input.pressed("r1") then
            if cand_page < total_pages then cand_page = cand_page + 1; cand_cursor = 1 end
        elseif input.pressed("a") then
            if #paged > 0 then keyboard.select_candidate(cand_cursor) end
        elseif input.pressed("down") then
            cursor_row = 1
            cursor_col = 1
        elseif input.pressed("b") then
            keyboard.handle_backspace()
        end
        return
    end

    -- 1. LR Shoulder candidate paging (letter rows keep the classic behavior)
    if input.pressed("l1") then
        keyboard.prev_candidate_page()
        cand_cursor = 1
    elseif input.pressed("r1") then
        keyboard.next_candidate_page()
        cand_cursor = 1
    elseif input.pressed("l2") then
        keyboard.select_candidate(1)
    elseif input.pressed("r2") then
        keyboard.select_candidate(2)
    end

    -- 2. D-Pad cursor navigation
    if input.pressed("up") then
        if #candidates > 0 and cursor_row > 0 then
            -- Jump straight into the candidate bar (most useful target while
            -- pinyin candidates are showing).
            cursor_row = 0
            cand_cursor = math.min(math.max(1, cand_cursor), #keyboard.get_paged_candidates())
        elseif cursor_row > 1 then
            cursor_row = cursor_row - 1
            local keys = keyboard.get_active_row_keys(cursor_row)
            cursor_col = math.min(cursor_col, #keys)
        end
    elseif input.pressed("down") then
        if cursor_row < 5 then
            cursor_row = cursor_row + 1
            local keys = keyboard.get_active_row_keys(cursor_row)
            cursor_col = math.min(cursor_col, #keys)
        end
    elseif input.pressed("left") then
        if cursor_col > 1 then
            cursor_col = cursor_col - 1
        end
    elseif input.pressed("right") then
        local keys = keyboard.get_active_row_keys(cursor_row)
        if cursor_col < #keys then
            cursor_col = cursor_col + 1
        end
    end

    -- 3. Face buttons
    if input.pressed("a") then
        keyboard.trigger_current_key()
    elseif input.pressed("b") then
        keyboard.handle_backspace()
    elseif input.pressed("x") or input.pressed("start") then
        if #pinyin_buffer > 0 then
            local paged = keyboard.get_paged_candidates()
            if #paged > 0 then keyboard.select_candidate(1) end
        end
        local committed = current_text
        is_active = false
        if on_commit_cb then on_commit_cb(committed) end
    end
end

-- Precise Candidate Hitboxes & Paging Buttons Calculation
function keyboard.get_candidate_hitboxes(vw, vh)
    local kb_h = 325
    local kb_y = vh - kb_h
    local cand_bar_y = kb_y - 45
    local cand_bar_h = 42

    local btn_prev = {
        x = 18,
        y = cand_bar_y + 5,
        w = 54,
        h = 32,
        label = "◀ L1"
    }

    local btn_next = {
        x = vw - 18 - 54,
        y = cand_bar_y + 5,
        w = 54,
        h = 32,
        label = "R1 ▶"
    }

    local hitboxes = {}
    local paged_cands = keyboard.get_paged_candidates()

    local cand_x = btn_prev.x + btn_prev.w + 10
    -- If there's a pinyin buffer, show pinyin prefix badge
    if pinyin_buffer ~= "" then
        local f_hint = theme.get_font("hint")
        local py_w = f_hint:getWidth(pinyin_buffer) + 16
        cand_x = cand_x + py_w + 8
    end

    local f_body = theme.get_font("body")
    for i, word in ipairs(paged_cands) do
        local label = string.format("%d.%s", i, word)
        local cw = f_body:getWidth(label) + 14
        table.insert(hitboxes, {
            idx = i,
            word = word,
            label = label,
            x = cand_x,
            y = cand_bar_y + 6,
            w = cw,
            h = 30
        })
        cand_x = cand_x + cw + 6
    end
    return hitboxes, btn_prev, btn_next
end

function keyboard.mousepressed(vx, vy, button)
    if not is_active then return end

    local vw, vh = 720, 720
    local kb_h = 325
    local kb_y = vh - kb_h

    -- Check if clicked outside keyboard panel
    if vy < kb_y - 45 then
        keyboard.close()
        return
    end

    -- Candidate bar area: kb_y - 45 to kb_y
    if vy >= kb_y - 45 and vy <= kb_y then
        local hitboxes, btn_prev, btn_next = keyboard.get_candidate_hitboxes(vw, vh)
        if btn_prev and vx >= btn_prev.x and vx <= btn_prev.x + btn_prev.w and vy >= btn_prev.y and vy <= btn_prev.y + btn_prev.h then
            keyboard.prev_candidate_page()
            return
        end
        if btn_next and vx >= btn_next.x and vx <= btn_next.x + btn_next.w and vy >= btn_next.y and vy <= btn_next.y + btn_next.h then
            keyboard.next_candidate_page()
            return
        end
        for _, box in ipairs(hitboxes) do
            if vx >= box.x and vx <= box.x + box.w and vy >= box.y and vy <= box.y + box.h then
                keyboard.select_candidate(box.idx)
                return
            end
        end
        return
    end

    -- Click keys
    local start_row_y = kb_y + 12
    local row_h = 40
    local row_gap = 8

    for r = 1, 5 do
        local ry = start_row_y + (r - 1) * (row_h + row_gap)
        if vy >= ry and vy <= ry + row_h then
            local keys = keyboard.get_active_row_keys(r)
            local total_w = vw - 32
            local gap = 6
            if r == 5 then
                local w1 = math.floor(total_w * 0.28)
                local w2 = math.floor(total_w * 0.42)
                local w3 = total_w - w1 - w2 - gap * 2
                local x1 = 16
                local x2 = x1 + w1 + gap
                local x3 = x2 + w2 + gap
                if vx >= x1 and vx <= x1 + w1 then
                    cursor_row = 5; cursor_col = 1
                    keyboard.trigger_current_key()
                elseif vx >= x2 and vx <= x2 + w2 then
                    cursor_row = 5; cursor_col = 2
                    keyboard.trigger_current_key()
                elseif vx >= x3 and vx <= x3 + w3 then
                    cursor_row = 5; cursor_col = 3
                    keyboard.trigger_current_key()
                end
                return
            else
                local key_w = (total_w - (#keys - 1) * gap) / #keys
                for c_idx, key in ipairs(keys) do
                    local kx = 16 + (c_idx - 1) * (key_w + gap)
                    if vx >= kx and vx <= kx + key_w then
                        cursor_row = r
                        cursor_col = c_idx
                        keyboard.trigger_current_key()
                        return
                    end
                end
            end
            break
        end
    end
end

function keyboard.draw(w, h)
    if not is_active then return end
    local c = theme.colors()

    -- 1. Dim background
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local kb_h = 325
    local kb_y = h - kb_h

    -- 2. Candidate Bar (Above Keyboard Panel)
    local cand_bar_y = kb_y - 45
    local cand_bar_h = 42
    theme.draw_panel(12, cand_bar_y, w - 24, cand_bar_h, c.surface_active, c.border, 8)

    -- Draw dual paging buttons & candidate pills
    local hitboxes, btn_prev, btn_next = keyboard.get_candidate_hitboxes(w, h)

    -- Prev Page Button [◀ L1]
    local total_pages = keyboard.get_total_pages()
    local can_prev = (cand_page > 1)
    theme.draw_panel(btn_prev.x, btn_prev.y, btn_prev.w, btn_prev.h, can_prev and c.surface or c.surface_active, can_prev and c.focus or c.border, 6)
    theme.set_font("hint")
    love.graphics.setColor(can_prev and c.focus or c.text_muted)
    local p_lw = theme.get_font("hint"):getWidth(btn_prev.label)
    love.graphics.print(btn_prev.label, btn_prev.x + (btn_prev.w - p_lw) / 2, btn_prev.y + 7)

    -- Next Page Button [R1 ▶]
    local can_next = (cand_page < total_pages)
    theme.draw_panel(btn_next.x, btn_next.y, btn_next.w, btn_next.h, can_next and c.surface or c.surface_active, can_next and c.focus or c.border, 6)
    theme.set_font("hint")
    love.graphics.setColor(can_next and c.focus or c.text_muted)
    local n_lw = theme.get_font("hint"):getWidth(btn_next.label)
    love.graphics.print(btn_next.label, btn_next.x + (btn_next.w - n_lw) / 2, btn_next.y + 7)

    -- If pinyin buffer exists, show only pinyin letters cleanly
    if pinyin_buffer ~= "" then
        theme.set_font("hint")
        local py_str = pinyin_buffer
        local py_w = theme.get_font("hint"):getWidth(py_str) + 16
        local py_x = btn_prev.x + btn_prev.w + 6
        theme.draw_panel(py_x, cand_bar_y + 7, py_w, 28, c.focus_bg, c.focus, 6)
        love.graphics.setColor(c.focus)
        love.graphics.print(py_str, py_x + 8, cand_bar_y + 11)
    end

    -- Draw candidates using exact hitboxes
    theme.set_font("body")
    local cand_bar_focused = (cursor_row == 0)
    for i, box in ipairs(hitboxes) do
        local is_focused = cand_bar_focused and (i == cand_cursor)
        theme.draw_panel(box.x, box.y, box.w, box.h,
            is_focused and c.focus_bg or c.surface,
            is_focused and c.focus or c.border, 6)
        if is_focused then
            theme.draw_focus_ring(box.x, box.y, box.w, box.h, 6, 2)
        end
        love.graphics.setColor(is_focused and c.focus or c.focus)
        love.graphics.print(box.label, box.x + 7, box.y + 2)
    end

    -- Candidate-bar focus indicator hint
    if cand_bar_focused and #candidates > 0 then
        theme.set_font("hint")
        love.graphics.setColor(c.accent)
        local tip = "[A] 选词  [◀/▶/L1/R1] 翻选"
        local tw = theme.get_font("hint"):getWidth(tip)
        love.graphics.print(tip, (w - tw) / 2, cand_bar_y - 20)
    end

    -- Page indicator next to R1 button if there are candidates
    if #candidates > 0 then
        local page_str = string.format("%d/%d", cand_page, total_pages)
        theme.set_font("hint")
        local p_tw = theme.get_font("hint"):getWidth(page_str)
        love.graphics.setColor(c.text_muted)
        love.graphics.print(page_str, btn_next.x - p_tw - 8, cand_bar_y + 13)
    end

    -- 3. Keyboard Frame Panel
    theme.draw_panel(0, kb_y, w, kb_h, c.surface, c.border, 0)
    love.graphics.setColor(c.focus)
    love.graphics.line(0, kb_y, w, kb_y)

    -- 4. Key Grid Rows
    local start_row_y = kb_y + 12
    local row_h = 40
    local row_gap = 8
    local total_w = w - 32
    local gap = 6

    for r = 1, 5 do
        local ry = start_row_y + (r - 1) * (row_h + row_gap)
        local keys = keyboard.get_active_row_keys(r)

        if r == 5 then
            -- Special Row 5: 关闭键盘, 空格, 确定/搜索
            local w1 = math.floor(total_w * 0.28)
            local w2 = math.floor(total_w * 0.42)
            local w3 = total_w - w1 - w2 - gap * 2
            local widths = { w1, w2, w3 }
            local cur_x = 16

            for c_idx, key in ipairs(keys) do
                local kw = widths[c_idx]
                local is_focused = (cursor_row == 5 and cursor_col == c_idx)
                local bg = is_focused and c.focus_bg or c.surface_active
                local b_col = is_focused and c.focus or c.border

                if key == "关闭键盘" then
                    bg = is_focused and c.focus_bg or c.surface
                elseif key == "确定/搜索" then
                    bg = is_focused and c.focus or c.surface_active
                end

                theme.draw_panel(cur_x, ry, kw, row_h, bg, b_col, 8)
                if is_focused then
                    theme.draw_focus_ring(cur_x, ry, kw, row_h, 8, 2)
                end

                theme.set_font("body")
                love.graphics.setColor(is_focused and ((key == "确定/搜索") and {1, 1, 1, 1} or c.focus) or c.text)
                local klw = theme.get_font("body"):getWidth(key)
                love.graphics.print(key, cur_x + (kw - klw) / 2, ry + 10)

                cur_x = cur_x + kw + gap
            end
        else
            local key_w = (total_w - (#keys - 1) * gap) / #keys
            for c_idx, key in ipairs(keys) do
                local kx = 16 + (c_idx - 1) * (key_w + gap)
                local is_focused = (cursor_row == r and cursor_col == c_idx)
                local bg = is_focused and c.focus_bg or c.surface_active
                local b_col = is_focused and c.focus or c.border

                -- Special highlight for "符号" / "返回字母"
                if key == "符号" or key == "返回字母" then
                    bg = is_focused and c.focus_bg or c.surface
                    b_col = is_focused and c.focus or c.accent
                end

                theme.draw_panel(kx, ry, key_w, row_h, bg, b_col, 6)
                if is_focused then
                    theme.draw_focus_ring(kx, ry, key_w, row_h, 6, 2)
                end

                if key == "中/英" then
                    local f_body = theme.get_font("body")
                    local f_hint = theme.get_font("hint")
                    local slash_w = f_hint:getWidth("/")

                    local zh_active = (input_mode == "zh")
                    local zh_w = (zh_active and f_body or f_hint):getWidth("中")
                    local en_w = (not zh_active and f_body or f_hint):getWidth("英")
                    local total_kw = zh_w + slash_w + en_w + 4
                    local bx = kx + (key_w - total_kw) / 2

                    if zh_active then
                        theme.set_font("body")
                        love.graphics.setColor(is_focused and c.focus or c.accent)
                        love.graphics.print("中", bx, ry + 10)
                    else
                        theme.set_font("hint")
                        love.graphics.setColor(c.text_muted)
                        love.graphics.print("中", bx, ry + 12)
                    end
                    bx = bx + zh_w + 2

                    theme.set_font("hint")
                    love.graphics.setColor(c.text_muted)
                    love.graphics.print("/", bx, ry + 12)
                    bx = bx + slash_w + 2

                    if not zh_active then
                        theme.set_font("body")
                        love.graphics.setColor(is_focused and c.focus or c.accent)
                        love.graphics.print("英", bx, ry + 10)
                    else
                        theme.set_font("hint")
                        love.graphics.setColor(c.text_muted)
                        love.graphics.print("英", bx, ry + 12)
                    end
                else
                    theme.set_font("body")
                    love.graphics.setColor(is_focused and c.focus or ((key == "符号" or key == "返回字母") and c.accent or c.text))
                    local klw = theme.get_font("body"):getWidth(key)
                    love.graphics.print(key, kx + (key_w - klw) / 2, ry + 10)
                end
            end
        end
    end

    -- 5. Bottom Hint Guide Line
    local hint_y = h - 28
    love.graphics.setColor(c.tab_bg)
    love.graphics.rectangle("fill", 0, hint_y - 4, w, 32)
    love.graphics.setColor(c.border)
    love.graphics.line(0, hint_y - 4, w, hint_y - 4)

    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    local hint_txt = "[D-Pad] 移动   [A] 输入   [▲] 候选词   [L1/R1] 翻页   [L2/R2] 选词   [B] 退格   [Start] 完成"
    local hw = theme.get_font("hint"):getWidth(hint_txt)
    love.graphics.print(hint_txt, (w - hw) / 2, hint_y + 3)
end

return keyboard
