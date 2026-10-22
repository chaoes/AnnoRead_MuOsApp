-- book_download.lua
--
-- Whole-book offline caching shared by the Bookshelf (L3) and, when convenient,
-- the Reader. It resolves the book's source, walks the full table-of-contents
-- (recursively, up to a sane depth) and then downloads every uncached chapter.
--
-- Usage:
--   book_download.start(book, {
--     on_status  = function(msg) end,          -- human-readable progress text
--     on_progress= function(done,total,failed)end,
--     on_done    = function(ok, msg) end,       -- ok=false on failure
--   })

local http = require("src.http")
local legado = require("src.legado")
local json = require("src.json")
local storage = require("src.storage")
local cache = require("src.cache")

local book_download = {}

local MAX_TOC_PAGES = 10

local function resolve_source(book)
    if book and book.origin then
        for _, s in ipairs(storage.get_sources()) do
            if s.bookSourceUrl == book.origin then
                return s
            end
        end
        return nil
    end
    return storage.get_active_source()
end

-- Recursively fetch the full TOC for a book/source.
local function fetch_all_chapters(source, book, on_done)
    local src_json = json.encode(source)
    local target_toc_url = book.tocUrl or book.bookUrl
    local all = {}
    local visited = {}

    local function fetch_page(page_url, depth, toc_url)
        if not page_url or page_url == "" or visited[page_url] or depth > MAX_TOC_PAGES then
            on_done(#all > 0 and all or nil, toc_url)
            return
        end
        visited[page_url] = true
        http.request_async({ url = page_url, method = "GET", timeout = 8 }, function(resp)
            if not resp or #resp == 0 then on_done(nil); return end
            local parsed = legado.parseToc(src_json, resp, page_url)
            local chs = type(parsed) == "table" and (parsed.chapters or parsed) or json.decode(parsed)
            if type(chs) ~= "table" or #chs == 0 then on_done(nil); return end
            for _, ch in ipairs(chs) do table.insert(all, ch) end
            local next_url = type(parsed) == "table" and parsed.nextTocUrl
            if next_url and #next_url > 0 then
                if next_url == page_url or visited[next_url] or depth >= MAX_TOC_PAGES then on_done(nil); return end
                fetch_page(next_url, depth + 1, toc_url)
                return
            end
            on_done(all, toc_url)
        end)
    end

    -- First hop: resolve the real tocUrl from the book page.
    http.request_async({ url = target_toc_url, method = "GET", timeout = 8 }, function(resp)
        local real_toc_url = target_toc_url
        if not resp or #resp == 0 then on_done(nil); return end
        if resp and #resp > 0 then
            local detail_json = legado.parseBookInfo(src_json, resp, target_toc_url)
            local detail_obj = json.decode(detail_json)
            if detail_obj and detail_obj.tocUrl and #detail_obj.tocUrl > 0 then
                real_toc_url = detail_obj.tocUrl
            end
        end
        fetch_page(real_toc_url, 1, real_toc_url)
    end)
end

-- Public entry point.
function book_download.start(book, cbs)
    cbs = cbs or {}
    book = {
        bookUrl = book and book.bookUrl,
        origin = book and book.origin,
        tocUrl = book and book.tocUrl,
        name = book and book.name,
        currentChapterIndex = book and book.currentChapterIndex,
        currentChapterTitle = book and book.currentChapterTitle,
    }
    local source = resolve_source(book)
    local source_json = source and json.encode(source)
    local cache_origin = (book and book.origin) or (source and source.bookSourceUrl) or ""
    local cached, cached_toc, toc_state, legacy_map = cache.load_toc(book.bookUrl, cache_origin)
    if not source then
        if cached and #cached > 0 then
            local found = 0
            for i, ch in ipairs(cached) do
                local has_body = ch.url and cache.is_cached_url(book.bookUrl, ch.url)
                if not has_body and ch.url and legacy_map and legacy_map[tostring(i)] == ch.url then
                    has_body = cache.is_cached(book.bookUrl, i)
                end
                if has_body then found = found + 1 end
            end
            local missing = found < #cached
            local msg = missing and "书源已删除；离线目录可读，仍有章节未缓存" or "书源已删除；目录与正文均已缓存"
            if cbs.on_status then cbs.on_status(msg) end
            if cbs.on_done then cbs.on_done(not missing, msg, found, #cached, #cached - found) end
        elseif cbs.on_done then
            cbs.on_done(false, "未找到可用书源")
        end
        return
    end

    local function download_chapters(chapters, toc_url, save_toc_after_success)
        if not chapters or #chapters == 0 then
            if cbs.on_done then cbs.on_done(false, "目录获取失败") end
            return
        end

        if cbs.on_status then
            cbs.on_status(string.format("共 %d 章，开始下载...", #chapters))
        end

        cache.cache_book({ bookUrl = book.bookUrl }, source_json, chapters,
            function(done, total, failed)
                if cbs.on_status then
                    cbs.on_status(string.format("缓存全书中… %d/%d（失败 %d）", done, total, failed))
                end
                if cbs.on_progress then cbs.on_progress(done, total, failed) end
            end,
            function(done, total, failed)
                if failed == 0 and save_toc_after_success then
                    local legacy_map = {}
                    local old_idx = tonumber(book.currentChapterIndex)
                    local old_title = book.currentChapterTitle
                    if old_idx and old_idx > 0 and type(old_title) == "string" and old_title ~= ""
                        and chapters[old_idx] and chapters[old_idx].title == old_title
                        and cache.is_cached(book.bookUrl, old_idx) then
                        legacy_map[tostring(old_idx)] = chapters[old_idx].url
                    end
                    if not cache.save_toc(book.bookUrl, book.origin or source.bookSourceUrl, chapters, toc_url or cached_toc, legacy_map) then
                        if cbs.on_done then cbs.on_done(false, "正文已缓存，但目录写入失败", done, total, failed) end
                        return
                    end
                end
                local msg = string.format("全书缓存完成：%d/%d 章，失败 %d", done - failed, total, failed)
                if save_toc_after_success and failed > 0 then msg = "全书缓存未完成，旧目录保持不变" end
                if cbs.on_status then cbs.on_status(msg) end
                if cbs.on_done then cbs.on_done(failed == 0, msg, done, total, failed) end
            end)
    end

    if cached and #cached > 0 then
        if Game_Can_Online == false then
            local found = 0
            for i, ch in ipairs(cached) do
                local has_body = ch.url and cache.is_cached_url(book.bookUrl, ch.url)
                if not has_body and ch.url and legacy_map and legacy_map[tostring(i)] == ch.url then
                    has_body = cache.is_cached(book.bookUrl, i)
                end
                if has_body then found = found + 1 end
            end
            local missing = found < #cached
            local msg = missing and "目录已缓存；当前未联网，尚有章节未缓存" or "全书目录与章节均已缓存"
            if cbs.on_status then cbs.on_status(msg) end
            if cbs.on_done then cbs.on_done(not missing, msg, found, #cached, #cached - found) end
            return
        end
        if cbs.on_status then cbs.on_status("使用已缓存目录...") end
        download_chapters(cached, cached_toc, false)
        return
    end

    if Game_Can_Online == false then
        if cbs.on_done then cbs.on_done(false, "离线：尚无缓存目录") end
        return
    end
    if cbs.on_status then cbs.on_status("正在获取目录...") end
    fetch_all_chapters(source, book, function(chapters, toc_url)
        if not chapters or #chapters == 0 then
            if cbs.on_done then cbs.on_done(false, "目录获取失败，未改动已有缓存") end
            return
        end
        -- New URL-keyed caches can use the valid catalog immediately, including
        -- chapters that have downloaded so far. Legacy ch_N files have no URL
        -- identity, so keep their placeholder catalog until every chapter has
        -- been downloaded and the new mapping can be committed safely.
        local legacy = toc_state ~= "origin_mismatch" and cache.load_legacy_toc(book.bookUrl)
        if legacy then
            download_chapters(chapters, toc_url or cached_toc, true)
        else
            if not cache.save_toc(book.bookUrl, book.origin or source.bookSourceUrl, chapters, toc_url or cached_toc) then
                if cbs.on_done then cbs.on_done(false, "目录缓存保存失败") end
                return
            end
            download_chapters(chapters, toc_url or cached_toc, false)
        end
    end)
end

return book_download
