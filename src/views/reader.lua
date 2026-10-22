local theme = require("src.theme")
local storage = require("src.storage")
local cache = require("src.cache")
local http = require("src.http")
local legado = require("src.legado")
local json = require("src.json")
local change_source = require("src.views.change_source")
local book_download = require("src.book_download")
local tts = require("src.tts")
local tts_cache = require("src.tts_cache")
local reader = {}

local current_book = nil
local active_source = nil
local chapters = {}
local chapter_idx = 1
local current_chapter_title = ""
local current_content = ""
local is_loading = false
local loading_status = ""

-- Text layout & Pagination
local pages = {}
local current_page = 1

-- Reader Settings & Modal State
local settings = nil
local show_settings = false
local settings_selected_row = 1
local settings_action_idx = 2 -- 1: Reset, 2: Close

-- Catalog Drawer
local show_catalog = false
local catalog_selected_idx = 1
local catalog_scroll = 0

-- Reader action menu (Select button): 语音朗读 / 换源 / 重新加载本章 / 缓存全书 / 排版设置
local show_menu = false
local menu_idx = 1
local MENU_ITEMS = { "tts", "change_source", "reload", "cache_book", "layout", "close" }

-- Raw text paragraphs for TTS playback
local current_raw_paras = {}
local tts_active_para = 0
local tts_status_text = ""
local tts_auto_advancing = false

-- Whole-book caching progress
local caching_book = false
local cache_done, cache_total, cache_failed = 0, 0, 0
local toast_msg = ""
local toast_timer = 0
local reader_session = 0
local chapter_request = 0
local toc_request = 0
local using_legacy_toc = false
local legacy_chapter_map = {}

local function can_use_network()
    return Game_Can_Online ~= false
end

local function source_matches_book()
    return current_book and current_book.origin and active_source
        and active_source.bookSourceUrl == current_book.origin
end

local function same_chapter_urls(left, right)
    if #left > #right then return false end
    for i = 1, #left do
        if not left[i].url or not right[i] or left[i].url ~= right[i].url then return false end
    end
    return true
end

local function get_settings()
    if not settings then
        settings = storage.get_reader_settings()
    end
    return settings
end

local function relayout(w, h)
    local s = get_settings()
    w = w or 720
    h = h or 720
    local font = theme.get_reader_font(s.font_size)
    local pad_x = s.margin_horiz
    local top_y = s.margin_vert
    local bot_y = h - s.margin_vert
    local max_w = w - pad_x * 2
    local page_h = bot_y - top_y

    local wrapped_paras, raw_paras = reader.wrap_chinese_text(current_content, font, max_w)
    current_raw_paras = raw_paras or {}
    pages = reader.paginate_paragraphs(wrapped_paras, font, page_h, s.line_spacing, s.para_spacing)
    current_page = math.max(1, math.min(current_page, #pages))
end

local function apply_settings()
    local s = get_settings()
    storage.save_reader_settings(s)
    theme.set_theme(s.theme)
    if s.tts_volume then
        tts.set_volume(s.tts_volume / 100)
    end
    relayout(720, 720)
end

function reader.is_loading()
    return is_loading
end

function reader.is_catalog_open()
    return show_catalog
end

function reader.close_catalog()
    show_catalog = false
end

function reader.open_catalog()
    show_catalog = true
    show_settings = false
    show_menu = false
    catalog_selected_idx = chapter_idx
end

function reader.is_settings_open()
    return show_settings
end

function reader.open_settings()
    show_settings = true
    show_catalog = false
    show_menu = false
    settings_selected_row = 1
    settings_action_idx = 2
end

function reader.close_settings()
    show_settings = false
end

function reader.is_menu_open()
    return show_menu
end

function reader.open_menu()
    show_menu = true
    show_catalog = false
    show_settings = false
    menu_idx = 1
end

function reader.close_menu()
    show_menu = false
end

function reader.is_caching()
    return caching_book
end

-- Start caching every chapter of the current book (offline whole-book download).
function reader.start_cache_book()
    if not current_book or caching_book then return end
    local session = reader_session
    local book_url, origin = current_book.bookUrl, current_book.origin
    local function current_download_ui()
        return session == reader_session and current_book and current_book.bookUrl == book_url and current_book.origin == origin
    end
    caching_book = true
    cache_done, cache_total, cache_failed = 0, #chapters, 0
    toast_msg = "开始缓存全书..."
    toast_timer = 3
    book_download.start(current_book, {
        on_status = function(msg)
            if not current_download_ui() then return end
            toast_msg = msg
            toast_timer = 3
        end,
        on_progress = function(done, total, failed)
            if not current_download_ui() then return end
            cache_done, cache_total, cache_failed = done, total, failed
        end,
        on_done = function(ok, msg, done, total, failed)
            if not current_download_ui() then return end
            caching_book = false
            if done and total then
                cache_done, cache_total, cache_failed = done, total, failed or 0
            end
            toast_msg = msg
            toast_timer = 4
        end,
    })
end

function reader.is_tts_playing()
    return tts.is_active()
end

function reader.get_book_key()
    if not current_book then return "default_book" end
    return tts_cache.get_book_key(current_book.name or current_book.title, current_book.bookUrl)
end

local function trigger_tts_next_chapter_prefetch()
    if not tts.is_active() or not current_book or chapter_idx >= #chapters then return end
    local next_idx = chapter_idx + 1
    local next_chap = chapters[next_idx]
    if not next_chap then return end

    local book_url = current_book.bookUrl
    local next_content = nil
    if next_chap.url and cache.is_cached_url(book_url, next_chap.url) then
        next_content = cache.get_chapter_url(book_url, next_chap.url)
    elseif cache.is_cached(book_url, next_idx) then
        next_content = cache.get_chapter(book_url, next_idx)
    end

    if next_content and #next_content > 0 then
        local s = get_settings()
        local font = theme.get_reader_font(s.font_size)
        local pad_x = s.margin_horiz
        local max_w = 720 - pad_x * 2
        local _, raw = reader.wrap_chinese_text(next_content, font, max_w)
        if raw and #raw > 0 then
            tts.set_next_chapter_prefetch(next_idx, raw)
        end
    end
end

local function start_tts_internal(start_para)
    local bk = reader.get_book_key()
    tts_active_para = start_para or 1
    tts_status_text = "准备朗读..."
    tts.start(chapters, chapter_idx, current_raw_paras, start_para, {
        on_para_change = function(idx)
            tts_active_para = idx
            -- Auto page turn: find which page contains idx
            if pages then
                for p_num, page_lines in ipairs(pages) do
                    for _, line in ipairs(page_lines) do
                        if line.para_idx == idx then
                            if current_page ~= p_num then
                                current_page = p_num
                                if current_book then
                                    local prog = (#chapters > 0) and (chapter_idx / #chapters) or 0.0
                                    storage.update_book_progress(current_book.bookUrl, chapter_idx, current_chapter_title, prog, current_page)
                                    current_book.currentChapterIndex = chapter_idx
                                    current_book.currentChapterTitle = current_chapter_title
                                    current_book.currentPage = current_page
                                    current_book.progress = prog
                                end
                            end
                            return
                        end
                    end
                end
            end
        end,
        on_chapter_complete = function()
            -- Read next chapter if available
            if chapter_idx < #chapters then
                tts_auto_advancing = true
                tts_status_text = "正在进入下一章..."
                reader.load_chapter(chapter_idx + 1, 1)
            else
                tts_status_text = "全书朗读完毕"
                tts_active_para = 0
            end
        end,
        on_status = function(msg)
            tts_status_text = msg
        end
    }, bk)

    -- Trigger next chapter synthesis prefetch if next chapter text is available
    trigger_tts_next_chapter_prefetch()
end

function reader.toggle_tts()
    if tts.is_active() then
        tts.stop()
        tts_active_para = 0
        tts_status_text = "朗读已停止"
    else
        if #current_raw_paras == 0 then
            toast_msg = "暂无可朗读内容"
            toast_timer = 2
            return
        end
        local s = get_settings()
        if s.tts_volume then
            tts.set_volume(s.tts_volume / 100)
        end
        local start_para = 1
        -- Find the first paragraph on current page
        if pages and pages[current_page] and #pages[current_page] > 0 then
            local first_line = pages[current_page][1]
            if first_line and first_line.para_idx then
                start_para = first_line.para_idx
            end
        end
        start_tts_internal(start_para)
    end
end

function reader.save_and_exit()
    tts.stop()
    tts_active_para = 0
    tts_status_text = ""
    tts_auto_advancing = false
    if current_book then
        local prog = (#chapters > 0) and (chapter_idx / #chapters) or 0.0
        local saved_page = math.max(1, current_page or 1)
        storage.update_book_progress(current_book.bookUrl, chapter_idx, current_chapter_title, prog, saved_page)
        current_book.currentChapterIndex = chapter_idx
        current_book.currentChapterTitle = current_chapter_title
        current_book.currentPage = saved_page
        current_book.progress = prog
    end
    reader_session = reader_session + 1
    chapter_request = chapter_request + 1
    toc_request = toc_request + 1
end

function reader.keypressed(key)
    -- Only raw keys that have NO action mapping in src/input.lua are handled here.
    -- All navigation/action keys (Escape/Backspace/Select/X/Start/...) are handled
    -- exclusively by reader.update() via the de-bounced action abstraction, so a
    -- single keypress is never processed twice in the same frame.
    --
    -- NOTE: keyboard 'c' is mapped to action 'x' (排版) in src/input.lua, so it is
    -- intentionally NOT handled here. Use 'P' (action 'start') to change source.
    if key == "r" then
        if not show_settings and not show_catalog and not reader.is_loading() then
            reader.reload_chapter()
        end
    end
    return nil
end

-- Text wrapping helper for Chinese text
local NO_START_CHARS = {
    ["，"] = true, ["。"] = true, ["！"] = true, ["？"] = true,
    ["、"] = true, ["；"] = true, ["："] = true, ["”"] = true,
    ["’"] = true, ["）"] = true, ["》"] = true, ["】"] = true,
    [","] = true, ["."] = true, ["!"] = true, ["?"] = true,
    [";"] = true, [":"] = true, [")"] = true, ["]"] = true
}

function reader.wrap_chinese_text(text, font, max_width)
    local paragraphs = {}
    local raw_paras = {}
    for p in text:gmatch("[^\r\n]+") do
        local trimmed = p:match("^%s*(.-)%s*$")
        if #trimmed > 0 then
            table.insert(raw_paras, trimmed)
        end
    end

    for p_idx, para in ipairs(raw_paras) do
        local para_lines = {}
        local line = "　　" -- indent 2 fullwidth spaces
        local i = 1
        local len = #para

        while i <= len do
            -- Parse next UTF-8 character
            local b = para:byte(i)
            local char_len = 1
            if b >= 240 then char_len = 4
            elseif b >= 224 then char_len = 3
            elseif b >= 192 then char_len = 2
            end

            local ch = para:sub(i, i + char_len - 1)
            local test_line = line .. ch

            if font:getWidth(test_line) > max_width then
                if NO_START_CHARS[ch] then
                    table.insert(para_lines, { text = test_line, para_idx = p_idx })
                    line = ""
                else
                    table.insert(para_lines, { text = line, para_idx = p_idx })
                    line = ch
                end
            else
                line = test_line
            end
            i = i + char_len
        end

        if #line > 0 then
            table.insert(para_lines, { text = line, para_idx = p_idx })
        end
        if #para_lines > 0 then
            table.insert(paragraphs, para_lines)
        end
    end

    return paragraphs, raw_paras
end

function reader.paginate_paragraphs(paragraphs, font, page_height, line_spacing, para_spacing)
    local line_h = math.floor(font:getHeight() * (line_spacing or 1.6))
    local p_gap = para_spacing or 10
    local pgs = {}
    local curr_lines = {}
    local curr_y = 0

    for _, para in ipairs(paragraphs) do
        for l_idx, line_item in ipairs(para) do
            local is_last = (l_idx == #para)
            local item_h = line_h + (is_last and p_gap or 0)

            if curr_y + line_h > page_height and #curr_lines > 0 then
                table.insert(pgs, curr_lines)
                curr_lines = {}
                curr_y = 0
            end

            local text_str = type(line_item) == "table" and line_item.text or line_item
            local p_idx = type(line_item) == "table" and line_item.para_idx or 1
            table.insert(curr_lines, { text = text_str, y = curr_y, para_idx = p_idx })
            curr_y = curr_y + item_h
        end
    end

    if #curr_lines > 0 then
        table.insert(pgs, curr_lines)
    end

    if #pgs == 0 then
        table.insert(pgs, { { text = "（本章暂无内容）", y = 0, para_idx = 1 } })
    end

    return pgs
end

function reader.open_change_source()
    if not current_book then return end
    change_source.open(current_book, current_chapter_title, chapter_idx - 1, function(targetBook, targetSource, alignedIdx, newChapters, isRollback)
        if isRollback then
            reader.load_toc()
            return
        end
        if targetSource then
            reader.change_source_to(targetBook, targetSource, alignedIdx, newChapters)
        end
    end)
end

function reader.change_source_to(targetBook, targetSource, alignedIdx, newChapters)
    reader_session = reader_session + 1
    chapter_request = chapter_request + 1
    toc_request = toc_request + 1
    active_source = targetSource
    legacy_chapter_map = {}
    using_legacy_toc = false
    chapters = {}
    pages = {}
    current_content = ""
    is_loading = false
    loading_status = ""
    caching_book = false
    if current_book and targetSource then
        local old_url = current_book.bookUrl
        local new_url = (targetBook and targetBook.bookUrl) or current_book.bookUrl
        local new_toc = (targetBook and (targetBook.tocUrl or targetBook.bookUrl)) or current_book.tocUrl
        current_book.origin = targetSource.bookSourceUrl
        current_book.originName = targetSource.bookSourceName
        current_book.bookUrl = new_url
        current_book.tocUrl = new_toc
        current_book.status = "normal"
        storage.update_book_origin(old_url, targetSource.bookSourceUrl, targetSource.bookSourceName, new_url, new_toc)
    end
    if newChapters and #newChapters > 0 then
        if not cache.save_toc(current_book.bookUrl, current_book.origin, newChapters, current_book.tocUrl) then
            toast_msg = "目录缓存保存失败，换源目录未应用"
            toast_timer = 4
            chapters = {}
            reader.load_toc(false)
            return
        end
        chapters = newChapters
        using_legacy_toc = false
        chapter_idx = math.max(1, math.min(alignedIdx or 1, #chapters))
        reader.load_chapter(chapter_idx)
    else
        reader.load_toc()
    end
end

function reader.get_active_source()
    return active_source
end

function reader.reload_chapter()
    if not current_book then return end
    cache.delete_chapter(current_book.bookUrl, chapter_idx)
    local chap = chapters[chapter_idx]
    if chap and chap.url then cache.delete_chapter_url(current_book.bookUrl, chap.url) end
    current_content = ""
    loading_status = "正在重新抓取本章正文..."
    reader.load_chapter(chapter_idx)
end

function reader.open_book(book)
    tts.stop()
    tts_active_para = 0
    tts_status_text = ""
    tts_auto_advancing = false
    reader_session = reader_session + 1
    chapter_request = chapter_request + 1
    toc_request = toc_request + 1
    current_book = book
    caching_book = false
    local resolved_src = nil
    if book and book.origin then
        for _, s in ipairs(storage.get_sources()) do
            if s.bookSourceUrl == book.origin then
                resolved_src = s
                break
            end
        end
    end
    active_source = resolved_src or (not (book and book.origin) and storage.get_active_source() or nil)
    if book and not book.origin and active_source then book.origin = active_source.bookSourceUrl end
    chapter_idx = book.currentChapterIndex or 1
    current_chapter_title = book.currentChapterTitle or ""
    local initial_page = book.currentPage or 1
    current_page = initial_page
    show_catalog = false
    show_settings = false
    show_menu = false
    current_content = ""
    pages = {}
    is_loading = false
    loading_status = ""

    -- Load saved settings and apply theme
    settings = storage.get_reader_settings()
    theme.set_theme(settings.theme)

    -- Show a durable catalog immediately. Old installs can still expose the
    -- cached chapter slots while the first real TOC is fetched in the background.
    local cached, _, cache_kind, saved_legacy_map = cache.load_toc(current_book.bookUrl, current_book.origin or "")
    if cached then
        using_legacy_toc = false
        legacy_chapter_map = saved_legacy_map or {}
        chapters = cached
        chapter_idx = math.max(1, math.min(chapter_idx, #chapters))
        catalog_selected_idx = chapter_idx
        reader.load_chapter(chapter_idx, initial_page)
        if can_use_network() and source_matches_book() then reader.load_toc(true) end
    else
        local legacy
        if cache_kind ~= "origin_mismatch" then
            legacy = cache.load_legacy_toc(current_book.bookUrl, current_chapter_title, chapter_idx)
        end
        chapters = legacy or {}
        using_legacy_toc = #chapters > 0
        legacy_chapter_map = {}
        if #chapters > 0 then
            chapter_idx = math.max(1, math.min(chapter_idx, #chapters))
            catalog_selected_idx = chapter_idx
            reader.load_chapter(chapter_idx, initial_page)
            if can_use_network() and source_matches_book() then reader.load_toc(true) end
        elseif can_use_network() and source_matches_book() then
            reader.load_toc(false)
        else
            is_loading = false
            loading_status = cache_kind == "origin_mismatch" and "目录来源与当前书源不符，已忽略旧目录"
                or (active_source and "离线：目录尚未缓存" or "书源不可用，无法联网更新目录")
        end
    end
end

function reader.set_content_for_test(text)
    current_content = text or ""
    current_raw_paras = {}
    for p in (current_content .. "\n"):gmatch("(.-)\r?\n") do
        local trimmed = p:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
            table.insert(current_raw_paras, trimmed)
        end
    end
    relayout(720, 720)
end

function reader.get_tts_active_para()
    return tts_active_para
end

function reader.get_chapters()
    return chapters
end

function reader.get_current_content()
    return current_content
end

function reader.get_current_page()
    return current_page
end

function reader.get_total_pages()
    return #pages
end

function reader.get_chapter_index()
    return chapter_idx
end

function reader.get_catalog_selected_idx()
    return catalog_selected_idx
end

function reader.load_toc(background)
    if not current_book or not can_use_network() or not source_matches_book() then return false end
    toc_request = toc_request + 1
    local request_id, session = toc_request, reader_session
    local book_url, origin = current_book.bookUrl, current_book.origin
    local src_json = json.encode(active_source)
    local target_toc_url = current_book.tocUrl or current_book.bookUrl
    local already_has_catalog = #chapters > 0
    local owns_loading_state = not background and not already_has_catalog
    if owns_loading_state then
        is_loading = true
        loading_status = "正在获取目录列表..."
    end

    local function still_current()
        return session == reader_session and request_id == toc_request and current_book
            and current_book.bookUrl == book_url and current_book.origin == origin
    end
    local function fail(msg)
        if not still_current() then return end
        if owns_loading_state then
            is_loading = false
            loading_status = msg
        else
            toast_msg = "目录更新失败，继续使用本地目录"
            toast_timer = 3
        end
    end
    local function accept_toc(updated, toc_url)
        if not still_current() then return end
        if type(updated) ~= "table" or #updated == 0 then fail("目录解析失败"); return end
        for _, ch in ipairs(updated) do
            if type(ch) ~= "table" or type(ch.url) ~= "string" or ch.url == "" then
                fail("目录解析失败，保留本地目录")
                return
            end
        end
        local adopt = not already_has_catalog or using_legacy_toc or same_chapter_urls(chapters, updated)
        if using_legacy_toc then
            toast_msg = "已获取真实目录；旧缓存缺少章节地址，请用“缓存全书”安全建立新目录"
            toast_timer = 5
            return
        end
        if not adopt then
            toast_msg = "目录有变动，已保留当前目录以保护离线章节"
            toast_timer = 4
            return
        end
        -- A snapshot is made durable before changing the live index mapping.
        local updated_legacy_map = legacy_chapter_map or {}
        if not cache.save_toc(book_url, origin, updated, toc_url, updated_legacy_map) then
            fail("目录缓存保存失败，保留当前目录")
            return
        end
        chapters = updated
        using_legacy_toc = false
        legacy_chapter_map = updated_legacy_map
        if not already_has_catalog then catalog_selected_idx = math.min(chapter_idx, #chapters) end
        if owns_loading_state then is_loading = false end
        if not already_has_catalog then reader.load_chapter(chapter_idx) end
    end

    http.request_async({ url = target_toc_url, method = "GET", timeout = 8 }, function(resp)
        if not still_current() then return end
        if not resp or #resp == 0 then fail("目录更新失败，继续使用本地目录"); return end
        local detail_obj = json.decode(legado.parseBookInfo(src_json, resp, target_toc_url))
        local real_toc_url = detail_obj and detail_obj.tocUrl and #detail_obj.tocUrl > 0
            and detail_obj.tocUrl or target_toc_url
        local all_chapters, visited, pages_seen = {}, {}, 0
        local function fetch_page(page_url)
            if not still_current() then return end
            if not page_url or page_url == "" or visited[page_url] or pages_seen >= 10 then
                if #all_chapters > 0 then accept_toc(all_chapters, real_toc_url)
                else fail("目录解析失败，继续使用本地目录") end
                return
            end
            visited[page_url] = true
            pages_seen = pages_seen + 1
            http.request_async({ url = page_url, method = "GET", timeout = 8 }, function(toc_resp)
                if not still_current() then return end
                if not toc_resp or #toc_resp == 0 then fail("目录分页失败，保留旧目录"); return end
                local parsed = legado.parseToc(src_json, toc_resp, page_url)
                local list = type(parsed) == "table" and (parsed.chapters or parsed)
                    or json.decode(parsed)
                if type(list) ~= "table" or #list == 0 then
                    fail("目录解析失败，保留旧目录")
                    return
                end
                for _, ch in ipairs(list) do all_chapters[#all_chapters + 1] = ch end
                local next_url = type(parsed) == "table" and parsed.nextTocUrl
                if next_url and next_url ~= "" then
                    if visited[next_url] or pages_seen >= 10 then fail("目录分页不完整，保留旧目录")
                    else fetch_page(next_url) end
                else
                    accept_toc(all_chapters, real_toc_url)
                end
            end)
        end
        fetch_page(real_toc_url)
    end)
    return true
end

function reader.load_chapter(idx, target_page)
    chapter_idx = math.max(1, math.min(idx, #chapters))
    local chap = chapters[chapter_idx]
    if not chap then return end

    pages = {}
    current_content = ""
    is_loading = false

    chapter_request = chapter_request + 1
    local request_id, session = chapter_request, reader_session
    local book_url, origin = current_book.bookUrl, current_book.origin
    local source_json = active_source and json.encode(active_source) or nil
    local chapter_url = chap.url

    local function still_current()
        return request_id == chapter_request and session == reader_session and current_book
            and current_book.bookUrl == book_url and current_book.origin == origin
            and chapter_idx == idx and chapters[chapter_idx] and chapters[chapter_idx].url == chapter_url
    end

    current_chapter_title = chap.title or string.format("第 %d 章", chapter_idx)
    current_page = 1
    show_catalog = false

    local function apply_target_page()
        if target_page == "last" then
            current_page = math.max(1, #pages)
        elseif type(target_page) == "number" then
            current_page = math.max(1, math.min(target_page, #pages))
        else
            current_page = 1
        end

        if current_book then
            local prog = (#chapters > 0) and (chapter_idx / #chapters) or 0.0
            storage.update_book_progress(current_book.bookUrl, chapter_idx, current_chapter_title, prog, current_page)
            current_book.currentChapterIndex = chapter_idx
            current_book.currentChapterTitle = current_chapter_title
            current_book.currentPage = current_page
            current_book.progress = prog
        end

        -- If TTS is active and we just auto-advanced or changed chapters:
        if tts.is_active() then
            local start_p = 1
            if target_page == "last" and pages and #pages > 0 then
                local last_p_lines = pages[#pages]
                if last_p_lines and last_p_lines[1] and last_p_lines[1].para_idx then
                    start_p = last_p_lines[1].para_idx
                end
            elseif type(target_page) == "number" and pages and pages[current_page] and #pages[current_page] > 0 then
                local first_line = pages[current_page][1]
                if first_line and first_line.para_idx then
                    start_p = first_line.para_idx
                end
            end
            tts_active_para = start_p
            tts.set_chapter_content(chapter_idx, current_raw_paras, start_p, reader.get_book_key())
            trigger_tts_next_chapter_prefetch()
        end
    end

    -- Check offline cache first!
    if cache.is_cached(current_book.bookUrl, chapter_idx) then
        -- Legacy cache slots have no URL identity. Use one only while the visible
        -- catalog is still the placeholder legacy list, or when its title matched
        -- this exact URL during the one-time migration.
        if chap.url then
            current_content = cache.is_cached_url(book_url, chap.url) and cache.get_chapter_url(book_url, chap.url) or nil
            if not current_content and legacy_chapter_map[tostring(chapter_idx)] == chap.url then
                current_content = cache.get_chapter(book_url, chapter_idx)
            end
        else
            current_content = cache.get_chapter(book_url, chapter_idx)
        end
        if current_content then
            is_loading = false
            loading_status = ""
            relayout(720, 720)
            apply_target_page()
            -- Trigger background prefetch for upcoming chapters!
            if can_use_network() and source_matches_book() and chapter_url then
                cache.prefetch_chapters({ bookUrl = book_url }, source_json, chapters, chapter_idx + 1, 5)
            end
            return
        end
    end
    if chap.url and cache.is_cached_url(book_url, chap.url) then
        current_content = cache.get_chapter_url(book_url, chap.url)
        is_loading = false
        loading_status = ""
        relayout(720, 720)
        apply_target_page()
        if can_use_network() and source_matches_book() then cache.prefetch_chapters({ bookUrl = book_url }, source_json, chapters, chapter_idx + 1, 5) end
        return
    end

    if not chapter_url then
        is_loading = false
        loading_status = using_legacy_toc and "此章没有本地缓存，联网更新目录后才能读取" or "此章没有可用地址"
        return
    end
    if not can_use_network() or not source_matches_book() then
        is_loading = false
        loading_status = not source_matches_book() and "书源不可用，无法联网抓取本章" or "离线：本章尚未缓存"
        return
    end

    is_loading = true
    loading_status = string.format("正在加载 《%s》...", current_chapter_title)

    local src_json = source_json
    local full_content_parts = {}
    local visited_content_urls = {}

    local function fetch_content_page(page_url, depth)
        if not page_url or page_url == "" or visited_content_urls[page_url] or depth > 5 then
            if not still_current() then return end
            is_loading = false
            if #full_content_parts > 0 then
                current_content = table.concat(full_content_parts, "\n\n")
                cache.save_chapter_url(book_url, chapter_url, current_content)
                relayout(720, 720)
                apply_target_page()
                if can_use_network() and source_matches_book() then cache.prefetch_chapters({ bookUrl = book_url }, src_json, chapters, chapter_idx + 1, 5) end
            else
                loading_status = "正文抓取失败，按 [A] 重试"
            end
            return
        end

        visited_content_urls[page_url] = true
        http.request_async({
            url = page_url,
            method = "GET",
            timeout = 8
        }, function(resp)
            if not still_current() then return end
            if resp and #resp > 0 then
                local clean_res = legado.parseContent(src_json, resp, page_url)
                local clean_text = type(clean_res) == "table" and clean_res.content or clean_res
                if clean_text and #clean_text > 0 then
                    table.insert(full_content_parts, clean_text)
                end

                local next_url = type(clean_res) == "table" and clean_res.nextContentUrl
                if next_url and #next_url > 0 and next_url ~= page_url and not visited_content_urls[next_url] then
                    fetch_content_page(next_url, depth + 1)
                    return
                end
            end

            is_loading = false
            if #full_content_parts > 0 then
                current_content = table.concat(full_content_parts, "\n\n")
                cache.save_chapter_url(book_url, chapter_url, current_content)
                relayout(720, 720)
                apply_target_page()
                if can_use_network() and source_matches_book() then cache.prefetch_chapters({ bookUrl = book_url }, src_json, chapters, chapter_idx + 1, 5) end
            else
                loading_status = "正文抓取失败，按 [A] 重试"
            end
        end)
    end

    fetch_content_page(chap.url, 1)
end

function reader.update(dt, input)
    local s = get_settings()

    -- 0. Update TTS subsystem
    tts.update(dt)

    -- 0. Handle Change Source Modal
    if change_source.is_open() then
        change_source.update(dt, input)
        return nil
    end
    if show_settings then
        if input.pressed("up") then
            settings_selected_row = settings_selected_row - 1
            if settings_selected_row < 1 then settings_selected_row = 8 end
        elseif input.pressed("down") then
            settings_selected_row = settings_selected_row + 1
            if settings_selected_row > 8 then settings_selected_row = 1 end
        elseif input.pressed("left") then
            if settings_selected_row == 1 then
                local order = { "dark", "sepia", "light", "jirai" }
                for i, th in ipairs(order) do
                    if th == s.theme then
                        local prev_idx = (i == 1) and #order or (i - 1)
                        s.theme = order[prev_idx]
                        break
                    end
                end
            elseif settings_selected_row == 2 then
                s.font_size = math.max(14, s.font_size - 2)
            elseif settings_selected_row == 3 then
                s.line_spacing = math.max(1.2, math.floor((s.line_spacing - 0.1) * 10 + 0.5) / 10)
            elseif settings_selected_row == 4 then
                s.para_spacing = math.max(0, s.para_spacing - 2)
            elseif settings_selected_row == 5 then
                s.margin_horiz = math.max(16, s.margin_horiz - 4)
            elseif settings_selected_row == 6 then
                s.margin_vert = math.max(20, s.margin_vert - 5)
            elseif settings_selected_row == 7 then
                s.tts_volume = math.max(50, (s.tts_volume or 100) - 10)
            elseif settings_selected_row == 8 then
                settings_action_idx = 1
            end
            apply_settings()
        elseif input.pressed("right") then
            if settings_selected_row == 1 then
                local order = { "dark", "sepia", "light", "jirai" }
                for i, th in ipairs(order) do
                    if th == s.theme then
                        local next_idx = (i % #order) + 1
                        s.theme = order[next_idx]
                        break
                    end
                end
            elseif settings_selected_row == 2 then
                s.font_size = math.min(32, s.font_size + 2)
            elseif settings_selected_row == 3 then
                s.line_spacing = math.min(2.4, math.floor((s.line_spacing + 0.1) * 10 + 0.5) / 10)
            elseif settings_selected_row == 4 then
                s.para_spacing = math.min(30, s.para_spacing + 2)
            elseif settings_selected_row == 5 then
                s.margin_horiz = math.min(64, s.margin_horiz + 4)
            elseif settings_selected_row == 6 then
                s.margin_vert = math.min(70, s.margin_vert + 5)
            elseif settings_selected_row == 7 then
                s.tts_volume = math.min(200, (s.tts_volume or 100) + 10)
            elseif settings_selected_row == 8 then
                settings_action_idx = 2
            end
            apply_settings()
        elseif input.pressed("a") then
            if settings_selected_row == 1 then
                local order = { "dark", "sepia", "light", "jirai" }
                for i, th in ipairs(order) do
                    if th == s.theme then
                        local next_idx = (i % #order) + 1
                        s.theme = order[next_idx]
                        break
                    end
                end
                apply_settings()
            elseif settings_selected_row >= 2 and settings_selected_row <= 7 then
                if settings_selected_row == 2 then
                    s.font_size = (s.font_size >= 32) and 14 or (s.font_size + 2)
                elseif settings_selected_row == 3 then
                    s.line_spacing = (s.line_spacing >= 2.4) and 1.2 or (math.floor((s.line_spacing + 0.1) * 10 + 0.5) / 10)
                elseif settings_selected_row == 4 then
                    s.para_spacing = (s.para_spacing >= 30) and 0 or (s.para_spacing + 4)
                elseif settings_selected_row == 5 then
                    s.margin_horiz = (s.margin_horiz >= 64) and 16 or (s.margin_horiz + 8)
                elseif settings_selected_row == 6 then
                    s.margin_vert = (s.margin_vert >= 70) and 20 or (s.margin_vert + 10)
                elseif settings_selected_row == 7 then
                    s.tts_volume = ((s.tts_volume or 100) >= 200) and 50 or ((s.tts_volume or 100) + 20)
                end
                apply_settings()
            elseif settings_selected_row == 8 then
                if settings_action_idx == 1 then
                    settings = storage.get_default_reader_settings()
                    apply_settings()
                else
                    show_settings = false
                end
            end
        elseif input.pressed("b") or input.pressed("x") or input.pressed("select") then
            show_settings = false
        end
        return nil
    end

    -- 2. Handle Catalog Drawer Navigation
    if show_catalog then
        if input.pressed("up") then
            catalog_selected_idx = math.max(1, catalog_selected_idx - 1)
        elseif input.pressed("down") then
            catalog_selected_idx = math.min(#chapters, catalog_selected_idx + 1)
        elseif input.pressed("left") or input.pressed("l1") then
            catalog_selected_idx = math.max(1, catalog_selected_idx - 10)
        elseif input.pressed("right") or input.pressed("r1") then
            catalog_selected_idx = math.min(#chapters, catalog_selected_idx + 10)
        end

        local target_scroll = math.max(0, (catalog_selected_idx - 6) * 44)
        catalog_scroll = catalog_scroll + (target_scroll - catalog_scroll) * math.min(1.0, dt * 15)

        if input.pressed("a") then
            reader.load_chapter(catalog_selected_idx)
        elseif input.pressed("b") or input.pressed("select") then
            show_catalog = false
        end
        return nil
    end

    -- 2.5 Handle Reader Action Menu (Select button)
    if show_menu then
        if input.pressed("up") then
            menu_idx = menu_idx - 1
            if menu_idx < 1 then menu_idx = #MENU_ITEMS end
        elseif input.pressed("down") then
            menu_idx = menu_idx + 1
            if menu_idx > #MENU_ITEMS then menu_idx = 1 end
        elseif input.pressed("a") then
            local item = MENU_ITEMS[menu_idx]
            show_menu = false
            if item == "tts" then
                reader.toggle_tts()
            elseif item == "change_source" then
                reader.open_change_source()
            elseif item == "reload" then
                reader.reload_chapter()
            elseif item == "cache_book" then
                reader.start_cache_book()
            elseif item == "layout" then
                reader.open_settings()
            end
        elseif input.pressed("b") or input.pressed("select") then
            show_menu = false
        end
        return nil
    end

    -- Toast timer
    if toast_timer > 0 then
        toast_timer = toast_timer - dt
        if toast_timer <= 0 then toast_msg = "" end
    end

    -- 3. Normal Reading Page Turning
    if input.pressed("right") or input.pressed("down") then
        if current_page < #pages then
            current_page = current_page + 1
        else
            -- Advance to next chapter
            if chapter_idx < #chapters then
                reader.load_chapter(chapter_idx + 1)
            end
        end
    elseif input.pressed("left") or input.pressed("up") then
        if current_page > 1 then
            current_page = current_page - 1
        else
            -- Backtrack to previous chapter (jump to its last page)
            if chapter_idx > 1 then
                reader.load_chapter(chapter_idx - 1, "last")
            end
        end
    -- Skip chapters with L1 / R1
    elseif input.pressed("l1") then
        if chapter_idx > 1 then
            reader.load_chapter(chapter_idx - 1)
        end
    elseif input.pressed("r1") then
        if chapter_idx < #chapters then
            reader.load_chapter(chapter_idx + 1)
        end
    -- [Select] opens the action menu (换源 / 重载 / 缓存全书 / 排版)
    elseif input.pressed("select") then
        reader.open_menu()
    -- [A] opens the chapter catalog
    elseif input.pressed("a") then
        reader.open_catalog()
    -- Toggle Settings Modal
    elseif input.pressed("x") then
        reader.open_settings()
    -- Change Source Modal
    elseif input.pressed("start") then
        reader.open_change_source()
    -- Toggle Bookshelf membership
    elseif input.pressed("y") then
        if current_book then
            local in_shelf = storage.is_in_bookshelf(current_book)
            if in_shelf then
                storage.remove_book_by_url(current_book.bookUrl)
            else
                storage.add_book(current_book)
            end
        end
    -- Exit Reader & Auto-Save
    elseif input.pressed("b") then
        reader.save_and_exit()
        return { action = "close_reader" }
    end

    return nil
end

function reader.mousepressed(vx, vy, button)
    local vw, vh = 720, 720
    local s = get_settings()

    if change_source.is_open() then
        return change_source.mousepressed(vx, vy, button)
    end

    -- Right click is always back / exit
    if button == 2 then
        if show_settings then
            show_settings = false
            return nil
        elseif show_catalog then
            show_catalog = false
            return nil
        else
            reader.save_and_exit()
            return { action = "close_reader" }
        end
    end

    -- If Settings Modal is open
    if show_settings then
        local mw = math.min(vw - 48, 540)
        local mh = 480
        local mx = math.floor((vw - mw) / 2)
        local my = math.floor((vh - mh) / 2)

        -- If clicked outside modal card -> close
        if vx < mx or vx > mx + mw or vy < my or vy > my + mh then
            show_settings = false
            return nil
        end

        local start_ry = my + 78
        local row_h = 48
        local row_gap = 6
        local rx = mx + 16
        local rw = mw - 32

        for i = 1, 7 do
            local ry = start_ry + (i - 1) * (row_h + row_gap)
            if vy >= ry and vy <= ry + row_h and vx >= rx and vx <= rx + rw then
                settings_selected_row = i
                if i == 1 then
                    -- Theme Pills
                    local themes = { "dark", "sepia", "light", "jirai" }
                    local pill_w = 56
                    local pill_gap = 6
                    local total_pills_w = #themes * pill_w + (#themes - 1) * pill_gap
                    local px = rx + rw - total_pills_w - 12
                    for _, th in ipairs(themes) do
                        if vx >= px and vx <= px + pill_w then
                            s.theme = th
                            apply_settings()
                            return nil
                        end
                        px = px + pill_w + pill_gap
                    end
                elseif i >= 2 and i <= 6 then
                    -- Numeric Steppers
                    local btn_w = 34
                    local val_w = 80
                    local st_w = btn_w * 2 + val_w + 12
                    local st_x = rx + rw - st_w - 12
                    local plus_x = st_x + btn_w + 6 + val_w + 6

                    -- Clicked [-]
                    if vx >= st_x and vx <= st_x + btn_w then
                        if i == 2 then s.font_size = math.max(14, s.font_size - 2)
                        elseif i == 3 then s.line_spacing = math.max(1.2, math.floor((s.line_spacing - 0.1) * 10 + 0.5) / 10)
                        elseif i == 4 then s.para_spacing = math.max(0, s.para_spacing - 2)
                        elseif i == 5 then s.margin_horiz = math.max(16, s.margin_horiz - 4)
                        elseif i == 6 then s.margin_vert = math.max(20, s.margin_vert - 5)
                        end
                        apply_settings()
                        return nil
                    -- Clicked [+]
                    elseif vx >= plus_x and vx <= plus_x + btn_w then
                        if i == 2 then s.font_size = math.min(32, s.font_size + 2)
                        elseif i == 3 then s.line_spacing = math.min(2.4, math.floor((s.line_spacing + 0.1) * 10 + 0.5) / 10)
                        elseif i == 4 then s.para_spacing = math.min(30, s.para_spacing + 2)
                        elseif i == 5 then s.margin_horiz = math.min(64, s.margin_horiz + 4)
                        elseif i == 6 then s.margin_vert = math.min(70, s.margin_vert + 5)
                        end
                        apply_settings()
                        return nil
                    end
                elseif i == 7 then
                    -- Reset vs Close
                    local btn_w = math.floor((rw - 12) / 2)
                    local close_x = rx + btn_w + 12
                    if vx <= rx + btn_w then
                        settings = storage.get_default_reader_settings()
                        apply_settings()
                        return nil
                    elseif vx >= close_x then
                        show_settings = false
                        return nil
                    end
                end
                break
            end
        end
        return nil
    end

    -- If Reader Action Menu is open
    if show_menu then
        local mw = 340
        local item_h = 52
        local mh = item_h * #MENU_ITEMS + 72
        local mx = math.floor((vw - mw) / 2)
        local my = math.floor((vh - mh) / 2)

        if vx < mx or vx > mx + mw or vy < my or vy > my + mh then
            show_menu = false
            return nil
        end
        local start_y = my + 62
        for i, item in ipairs(MENU_ITEMS) do
            local iy = start_y + (i - 1) * item_h
            if vy >= iy + 4 and vy <= iy + item_h - 4 then
                menu_idx = i
                show_menu = false
                if item == "tts" then
                    reader.toggle_tts()
                elseif item == "change_source" then
                    reader.open_change_source()
                elseif item == "reload" then
                    reader.reload_chapter()
                elseif item == "cache_book" then
                    reader.start_cache_book()
                elseif item == "layout" then
                    reader.open_settings()
                end
                return nil
            end
        end
        return nil
    end

    -- If Catalog Drawer is open
    if show_catalog then
        local dw = math.min(vw * 0.85, 520)
        if vx > dw then
            show_catalog = false
            return nil
        end
        -- Check chapter clicked
        local item_h = 42
        for i, chap in ipairs(chapters) do
            local iy = 60 + (i - 1) * item_h - catalog_scroll
            if vy >= iy and vy <= iy + item_h then
                reader.load_chapter(i)
                return nil
            end
        end
        return nil
    end

    -- Check bottom footer button clicks
    if vy >= vh - 40 then
        -- Left: Catalog
        if vx >= 20 and vx <= 120 then
            reader.open_catalog()
            return nil
        -- Middle/Right: Action Menu
        elseif vx >= vw - 240 and vx <= vw - 90 then
            reader.open_menu()
            return nil
        -- Far Right: Exit
        elseif vx >= vw - 80 then
            reader.save_and_exit()
            return { action = "close_reader" }
        end
    end

    -- Top header click -> toggle catalog
    if vy <= 44 then
        reader.open_catalog()
        return nil
    end

    -- Page click areas:
    -- Left 35%: prev page / prev chapter
    if vx < vw * 0.35 then
        if current_page > 1 then
            current_page = current_page - 1
        elseif chapter_idx > 1 then
            reader.load_chapter(chapter_idx - 1, "last")
        end
    -- Right 35%: next page / next chapter
    elseif vx > vw * 0.65 then
        if current_page < #pages then
            current_page = current_page + 1
        elseif chapter_idx < #chapters then
            reader.load_chapter(chapter_idx + 1)
        end
    -- Center 30%: toggle settings modal
    else
        reader.open_settings()
    end

    return nil
end

function reader.wheelmoved(x, y)
    if show_settings then
        if y > 0 then
            settings_selected_row = math.max(1, settings_selected_row - 1)
        elseif y < 0 then
            settings_selected_row = math.min(7, settings_selected_row + 1)
        end
    elseif show_catalog then
        if y > 0 then
            catalog_selected_idx = math.max(1, catalog_selected_idx - 2)
        elseif y < 0 then
            catalog_selected_idx = math.min(#chapters, catalog_selected_idx + 2)
        end
        local target_scroll = math.max(0, (catalog_selected_idx - 6) * 44)
        catalog_scroll = target_scroll
    else
        if y < 0 then
            -- Wheel down -> next page
            if current_page < #pages then
                current_page = current_page + 1
            elseif chapter_idx < #chapters then
                reader.load_chapter(chapter_idx + 1)
            end
        elseif y > 0 then
            -- Wheel up -> prev page
            if current_page > 1 then
                current_page = current_page - 1
            elseif chapter_idx > 1 then
                reader.load_chapter(chapter_idx - 1, "last")
            end
        end
    end
end

function reader.draw(w, h)
    local c = theme.colors()
    local s = get_settings()

    -- Fill Full Reader Background
    love.graphics.setColor(c.reader_bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- 1. Dim Top Header
    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    local header_text = string.format("%s · %s", current_book and current_book.name or "", current_chapter_title)
    local header_y = math.max(12, math.floor(s.margin_vert * 0.35))
    love.graphics.print(header_text, s.margin_horiz, header_y)

    if current_book and current_book.status == "source_deleted" then
        love.graphics.setColor(c.danger)
        local warn_text = "⚠️ 书源已失效，按 [Start] 换源"
        love.graphics.print(warn_text, s.margin_horiz + theme.get_font("hint"):getWidth(header_text) + 16, header_y)
    end

    -- Offline Cache & Bookshelf Indicator Badge
    local in_shelf = storage.is_in_bookshelf(current_book)
    local badge_x = w - s.margin_horiz
    local visible_chapter = chapters[chapter_idx]
    if (visible_chapter and visible_chapter.url and cache.is_cached_url(current_book and current_book.bookUrl or "", visible_chapter.url))
        or cache.is_cached(current_book and current_book.bookUrl or "", chapter_idx) then
        love.graphics.setColor(c.success)
        local c_str = "[已缓存]"
        local cw = theme.get_font("hint"):getWidth(c_str)
        badge_x = badge_x - cw
        love.graphics.print(c_str, badge_x, header_y)
        badge_x = badge_x - 12
    end
    if not in_shelf then
        love.graphics.setColor(c.accent)
        local s_str = "[未入书架 · 按Y加书架]"
        local sw = theme.get_font("hint"):getWidth(s_str)
        badge_x = badge_x - sw
        love.graphics.print(s_str, badge_x, header_y)
    end

    -- 2. Reading Content Page
    local font = theme.get_reader_font(s.font_size)
    love.graphics.setFont(font)
    love.graphics.setColor(c.reader_text)

    local start_y = s.margin_vert

    if is_loading or #pages == 0 then
        theme.set_font("header")
        love.graphics.setColor(c.accent)
        love.graphics.printf(loading_status ~= "" and loading_status or "正在准备排版...", 0, h * 0.45, w, "center")
    elseif pages[current_page] then
        local active_p = tts.is_active() and tts_active_para or 0
        for _, item in ipairs(pages[current_page]) do
            if active_p > 0 and item.para_idx == active_p then
                love.graphics.setColor(c.accent)
            else
                love.graphics.setColor(c.reader_text)
            end
            love.graphics.print(item.text, s.margin_horiz, start_y + item.y)
        end
    else
        theme.set_font("body")
        love.graphics.printf("正在准备排版...", 0, h * 0.45, w, "center")
    end

    -- 3. Dim Bottom Footer
    theme.set_font("hint")
    love.graphics.setColor(c.text_muted)
    local footer_text = "暂无阅读进度"
    if #pages > 0 then
        footer_text = string.format("第 %d / %d 页", current_page, #pages)
        if #chapters > 0 then
            local completed_chapters = math.max(0, math.min(chapter_idx - 1, #chapters - 1))
            local page_fraction = math.max(0, math.min(current_page / #pages, 1))
            local overall_prog = (completed_chapters + page_fraction) / #chapters * 100
            footer_text = footer_text .. string.format("   |   总进度 %.1f%%", overall_prog)
        end
    end
    local footer_y = math.min(h - 24, h - math.floor(s.margin_vert * 0.45))
    love.graphics.print(footer_text, s.margin_horiz, footer_y)

    local hint_text = in_shelf and "[A] 目录   [Select] 菜单   [X] 排版   [B] 返回" or "[A] 目录   [Select] 菜单   [Y] 加书架   [X] 排版   [B] 返回"
    local hint_w = theme.get_font("hint"):getWidth(hint_text)
    love.graphics.print(hint_text, w - hint_w - s.margin_horiz, footer_y)

    -- Whole-book caching progress banner
    if caching_book then
        theme.set_font("hint")
        local txt = string.format("缓存全书中… %d/%d（失败 %d）", cache_done, cache_total, cache_failed)
        local tw = theme.get_font("hint"):getWidth(txt) + 28
        local bx = (w - tw) / 2
        local by = h - 60
        theme.draw_panel(bx, by, tw, 28, c.surface_active, c.accent, 6)
        love.graphics.setColor(c.accent)
        love.graphics.print(txt, bx + 14, by + 6)
    elseif tts.is_active() or (tts_status_text and #tts_status_text > 0 and tts_status_text ~= "朗读已停止") then
        theme.set_font("hint")
        local txt = string.format("🔊 朗读中 [段落 %d/%d] · %s", tts_active_para, #current_raw_paras, tts_status_text)
        local tw = theme.get_font("hint"):getWidth(txt) + 28
        local bx = (w - tw) / 2
        local by = h - 60
        theme.draw_panel(bx, by, tw, 28, c.surface_active, c.accent, 6)
        love.graphics.setColor(c.accent)
        love.graphics.print(txt, bx + 14, by + 6)
    end

    -- 4. Catalog Drawer Overlay
    if show_catalog then
        -- Backdrop shadow
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        -- Drawer Panel
        local dw = math.min(w * 0.85, 520)
        theme.draw_panel(0, 0, dw, h, c.surface, c.border, 0)

        theme.set_font("header")
        love.graphics.setColor(c.focus)
        love.graphics.print(string.format("目录 (%d 章)", #chapters), 24, 20)

        love.graphics.setScissor(0, 56, dw, h - 60)
        local item_h = 42
        for i, chap in ipairs(chapters) do
            local iy = 60 + (i - 1) * item_h - catalog_scroll
            if iy + item_h > 50 and iy < h then
                local is_sel = (i == catalog_selected_idx)
                local is_curr = (i == chapter_idx)

                if is_sel then
                    love.graphics.setColor(c.focus_bg)
                    love.graphics.rectangle("fill", 12, iy, dw - 24, item_h, 6, 6)
                    love.graphics.setColor(c.focus)
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle("line", 12, iy, dw - 24, item_h, 6, 6)
                    love.graphics.setLineWidth(1)
                    -- Indicator left bar
                    love.graphics.setColor(c.accent)
                    love.graphics.rectangle("fill", 12, iy + 6, 3, item_h - 12, 2, 2)
                end

                theme.set_font("body")
                love.graphics.setColor(is_curr and c.accent or (is_sel and c.text or c.text_muted))
                local prefix = is_curr and "▶ " or ""
                love.graphics.print(prefix .. (chap.title or ""), 24, iy + 10)
            end
        end
        love.graphics.setScissor()
    end

    -- 4.5 Reader Action Menu (Select button)
    if show_menu then
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", 0, 0, w, h)

        local mw = 340
        local item_h = 52
        local mh = item_h * #MENU_ITEMS + 72
        local mx = math.floor((w - mw) / 2)
        local my = math.floor((h - mh) / 2)

        theme.draw_panel(mx, my, mw, mh, c.surface, c.border, 12)
        theme.draw_focus_ring(mx, my, mw, mh, 12, 1)

        theme.set_font("header")
        love.graphics.setColor(c.focus)
        love.graphics.print("操作菜单", mx + 24, my + 18)
        theme.set_font("hint")
        love.graphics.setColor(c.text_muted)
        love.graphics.print("[A] 选择 · [B]/[Select] 关闭", mx + 24, my + 44)

        local is_tts = tts.is_active()
        local labels = {
            tts = is_tts and "停止语音朗读" or "开启语音朗读",
            change_source = "换 源",
            reload = "重新加载本章",
            cache_book = "缓存全书（离线）",
            layout = "排版设置",
            close = "关闭菜单"
        }
        local hints = {
            tts = is_tts and "正在朗读本章内容" or "使用 MiMo 模型流式朗读",
            change_source = "跨书源搜索并切换",
            reload = "丢弃缓存后重新抓取本章",
            cache_book = caching_book and "正在缓存中…" or "下载本书全部章节",
            layout = "字号 / 行距 / 边距",
            close = ""
        }

        local start_y = my + 62
        for i, item in ipairs(MENU_ITEMS) do
            local iy = start_y + (i - 1) * item_h
            local is_sel = (i == menu_idx)
            if is_sel then
                love.graphics.setColor(c.focus_bg)
                love.graphics.rectangle("fill", mx + 12, iy + 4, mw - 24, item_h - 8, 8, 8)
                love.graphics.setColor(c.focus)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", mx + 12, iy + 4, mw - 24, item_h - 8, 8, 8)
                love.graphics.setLineWidth(1)
            end
            theme.set_font("body")
            love.graphics.setColor(is_sel and c.focus or c.text)
            love.graphics.print(labels[item] or item, mx + 28, iy + 12)
            if hints[item] and #hints[item] > 0 then
                theme.set_font("hint")
                love.graphics.setColor(c.text_muted)
                love.graphics.print(hints[item], mx + 28, iy + 32)
            end
        end
    end

    -- 5. Settings Popup Modal
    if show_settings then
        -- Semi-transparent backdrop
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        local mw = math.min(w - 48, 540)
        local mh = 512
        local mx = math.floor((w - mw) / 2)
        local my = math.floor((h - mh) / 2)

        -- Modal Background Card
        theme.draw_panel(mx, my, mw, mh, c.surface, c.border, 12)
        theme.draw_focus_ring(mx, my, mw, mh, 12, 1)

        -- Modal Header
        theme.set_font("header")
        love.graphics.setColor(c.focus)
        love.graphics.print("阅读排版与朗读设置", mx + 24, my + 18)

        theme.set_font("hint")
        love.graphics.setColor(c.text_muted)
        love.graphics.print("方向键调节 · [A] 选择 · [X]/[B] 关闭", mx + 24, my + 44)

        -- Header divider line
        love.graphics.setColor(c.border)
        love.graphics.line(mx + 16, my + 68, mx + mw - 16, my + 68)

        -- Setting Rows definition
        local rows = {
            { id = "theme", label = "背景主题" },
            { id = "font_size", label = "阅读字号", val = string.format("%d pt", s.font_size) },
            { id = "line_spacing", label = "行距倍数", val = string.format("%.1fx", s.line_spacing) },
            { id = "para_spacing", label = "段落间距", val = string.format("%d px", s.para_spacing) },
            { id = "margin_horiz", label = "左右边距", val = string.format("%d px", s.margin_horiz) },
            { id = "margin_vert", label = "上下边距", val = string.format("%d px", s.margin_vert) },
            { id = "tts_volume", label = "朗读音量", val = string.format("%d%%", s.tts_volume or 100) },
            { id = "actions", label = "操作" }
        }

        local start_ry = my + 76
        local row_h = 44
        local row_gap = 5

        for i, r in ipairs(rows) do
            local ry = start_ry + (i - 1) * (row_h + row_gap)
            local rx = mx + 16
            local rw = mw - 32
            local is_row_focused = (settings_selected_row == i)

            if i <= 7 then
                -- Row container
                local row_bg = is_row_focused and c.focus_bg or c.surface_active
                local row_border = is_row_focused and c.focus or c.border
                theme.draw_panel(rx, ry, rw, row_h, row_bg, row_border, 8)
                if is_row_focused then
                    theme.draw_focus_ring(rx, ry, rw, row_h, 8, 2)
                end

                -- Row Label
                theme.set_font("body")
                love.graphics.setColor(is_row_focused and c.focus or c.text)
                love.graphics.print(r.label, rx + 16, ry + 11)

                if r.id == "theme" then
                    -- Theme Pills: Dark / Sepia / Light / Jirai
                    local themes = {
                        { id = "dark", name = "暗黑" },
                        { id = "sepia", name = "羊皮纸" },
                        { id = "light", name = "明亮" },
                        { id = "jirai", name = "地雷" }
                    }
                    local pill_w = 56
                    local pill_h = 30
                    local pill_gap = 6
                    local total_pills_w = #themes * pill_w + (#themes - 1) * pill_gap
                    local px = rx + rw - total_pills_w - 12
                    local py = ry + (row_h - pill_h) / 2

                    theme.set_font("hint")
                    for _, th in ipairs(themes) do
                        local is_th_active = (s.theme == th.id)
                        local is_th_focused = is_row_focused and is_th_active
                        local th_bg = is_th_active and c.focus or c.surface
                        local th_border = is_th_focused and c.accent or (is_th_active and c.focus or c.border)
                        theme.draw_panel(px, py, pill_w, pill_h, th_bg, th_border, 6)
                        if is_th_focused then
                            theme.draw_focus_ring(px, py, pill_w, pill_h, 6, 2)
                        end
                        love.graphics.setColor(is_th_active and { 1, 1, 1, 1 } or c.text_muted)
                        local tw = theme.get_font("hint"):getWidth(th.name)
                        love.graphics.print(th.name, px + (pill_w - tw) / 2, py + 7)
                        px = px + pill_w + pill_gap
                    end
                else
                    -- Numeric Stepper: [-]  value  [+]
                    local btn_w = 34
                    local btn_h = 30
                    local val_w = 80
                    local st_w = btn_w * 2 + val_w + 12
                    local st_x = rx + rw - st_w - 12
                    local st_y = ry + (row_h - btn_h) / 2

                    -- [-] button
                    theme.draw_panel(st_x, st_y, btn_w, btn_h, c.surface, is_row_focused and c.focus or c.border, 6)
                    theme.set_font("body")
                    love.graphics.setColor(is_row_focused and c.focus or c.text)
                    local minus_w = theme.get_font("body"):getWidth("-")
                    love.graphics.print("-", st_x + (btn_w - minus_w) / 2, st_y + 4)

                    -- Value text
                    theme.set_font("header")
                    love.graphics.setColor(is_row_focused and c.accent or c.text)
                    local vw_text = theme.get_font("header"):getWidth(r.val)
                    love.graphics.print(r.val, st_x + btn_w + 6 + (val_w - vw_text) / 2, st_y + 4)

                    -- [+] button
                    local plus_x = st_x + btn_w + 6 + val_w + 6
                    theme.draw_panel(plus_x, st_y, btn_w, btn_h, c.surface, is_row_focused and c.focus or c.border, 6)
                    theme.set_font("body")
                    love.graphics.setColor(is_row_focused and c.focus or c.text)
                    local plus_w = theme.get_font("body"):getWidth("+")
                    love.graphics.print("+", plus_x + (btn_w - plus_w) / 2, st_y + 4)
                end
            else
                -- Actions Row: Reset and Done
                local btn_w = math.floor((rw - 12) / 2)
                local btn_h = 42

                -- Reset Button
                local is_reset_focused = is_row_focused and (settings_action_idx == 1)
                local reset_bg = is_reset_focused and c.focus_bg or c.surface_active
                local reset_border = is_reset_focused and c.focus or c.border
                theme.draw_panel(rx, ry, btn_w, btn_h, reset_bg, reset_border, 8)
                if is_reset_focused then
                    theme.draw_focus_ring(rx, ry, btn_w, btn_h, 8, 2)
                end
                theme.set_font("body")
                love.graphics.setColor(is_reset_focused and c.focus or c.text_muted)
                local rlbl = "恢复默认"
                local rlw = theme.get_font("body"):getWidth(rlbl)
                love.graphics.print(rlbl, rx + (btn_w - rlw) / 2, ry + 11)

                -- Done Button
                local is_close_focused = is_row_focused and (settings_action_idx == 2)
                local close_bg = is_close_focused and c.focus or c.surface_active
                local close_border = is_close_focused and c.accent or c.border
                local close_x = rx + btn_w + 12
                theme.draw_panel(close_x, ry, btn_w, btn_h, close_bg, close_border, 8)
                if is_close_focused then
                    theme.draw_focus_ring(close_x, ry, btn_w, btn_h, 8, 2)
                end
                theme.set_font("body")
                love.graphics.setColor(is_close_focused and { 1, 1, 1, 1 } or c.accent)
                local clbl = "完成并返回"
                local clw = theme.get_font("body"):getWidth(clbl)
                love.graphics.print(clbl, close_x + (btn_w - clw) / 2, ry + 11)
            end
        end
    end

    -- 6. Change Source Modal
    if change_source.is_open() then
        change_source.draw(w, h)
    end
end

return reader
