local http = require("src.http")
local legado = require("src.legado")
local cache = {}
local mem_cache = {}

local function sanitize_name(name)
    return (name:gsub("[^%w_%-]", "_"))
end

local function get_cache_path(bookUrl, chapterIdx)
    local book_dir = "cache/" .. sanitize_name(bookUrl)
    return book_dir .. "/ch_" .. tostring(chapterIdx) .. ".txt"
end

local function url_cache_path(bookUrl, chapterUrl)
    local hash = 5381
    for i = 1, #chapterUrl do hash = (hash * 33 + chapterUrl:byte(i)) % 4294967296 end
    return "cache/" .. sanitize_name(bookUrl) .. string.format("/ch_u_%08x.txt", hash)
end

function cache.is_cached_url(bookUrl, chapterUrl)
    local p = url_cache_path(bookUrl, chapterUrl)
    local raw
    if love and love.filesystem and love.filesystem.getInfo then
        if not love.filesystem.getInfo(p) then return false end
        raw = love.filesystem.read(p)
    else
        raw = mem_cache[p]
    end
    local entry = type(raw) == "string" and require("src.json").decode(raw) or nil
    return type(entry) == "table" and entry.bookUrl == bookUrl and entry.chapterUrl == chapterUrl
        and type(entry.content) == "string"
end

function cache.get_chapter_url(bookUrl, chapterUrl)
    local p = url_cache_path(bookUrl, chapterUrl)
    local raw
    if love and love.filesystem and love.filesystem.getInfo then
        raw = love.filesystem.getInfo(p) and love.filesystem.read(p) or nil
    else
        raw = mem_cache[p]
    end
    local entry = type(raw) == "string" and require("src.json").decode(raw) or nil
    if type(entry) == "table" and entry.bookUrl == bookUrl and entry.chapterUrl == chapterUrl then
        return entry.content
    end
    return nil
end

function cache.save_chapter_url(bookUrl, chapterUrl, content)
    if type(content) ~= "string" or content == "" then return false end
    local p = url_cache_path(bookUrl, chapterUrl)
    local encoded = require("src.json").encode({ bookUrl = bookUrl, chapterUrl = chapterUrl, content = content })
    if love and love.filesystem and love.filesystem.write then
        local dir = "cache/" .. sanitize_name(bookUrl)
        if love.filesystem.getInfo and not love.filesystem.getInfo(dir) then love.filesystem.createDirectory(dir) end
        return love.filesystem.write(p, encoded)
    end
    mem_cache[p] = encoded
    return true
end

function cache.delete_chapter_url(bookUrl, chapterUrl)
    local p = url_cache_path(bookUrl, chapterUrl)
    mem_cache[p] = nil
    if love and love.filesystem and love.filesystem.remove and love.filesystem.getInfo and love.filesystem.getInfo(p) then
        return love.filesystem.remove(p)
    end
    return true
end

local MAX_LEGACY_CHAPTER = 100000
local TOC_VERSION = 1

local function toc_slot_path(bookUrl, slot)
    return "cache/" .. sanitize_name(bookUrl) .. "/toc_" .. slot .. ".json"
end

local function read_toc_slot(bookUrl, origin, slot)
    local path = toc_slot_path(bookUrl, slot)
    local raw
    if love and love.filesystem and love.filesystem.read then
        if love.filesystem.getInfo and not love.filesystem.getInfo(path) then return nil end
        raw = love.filesystem.read(path)
    else
        raw = mem_cache[path]
    end
    local obj = type(raw) == "string" and require("src.json").decode(raw) or nil
    if type(obj) ~= "table" or obj.version ~= TOC_VERSION or obj.bookUrl ~= bookUrl
        or obj.origin ~= origin or type(obj.generation) ~= "number" or obj.slot ~= slot
        or type(obj.chapters) ~= "table" or #obj.chapters == 0 then
        return nil
    end
    for _, ch in ipairs(obj.chapters) do
        if type(ch) ~= "table" or type(ch.title) ~= "string" or type(ch.url) ~= "string" or ch.url == "" then
            return nil
        end
    end
    return obj
end

-- Persist two alternating copies. A torn write can invalidate only the older slot;
-- the previous complete snapshot remains readable until the new copy validates.
function cache.save_toc(bookUrl, origin, chapters, tocUrl, legacy_map)
    if type(bookUrl) ~= "string" or type(origin) ~= "string" or type(chapters) ~= "table" or #chapters == 0 then
        return false
    end
    for _, ch in ipairs(chapters) do
        if type(ch) ~= "table" or type(ch.url) ~= "string" or ch.url == "" then return false end
    end
    local a = read_toc_slot(bookUrl, origin, "a")
    local b = read_toc_slot(bookUrl, origin, "b")
    local current = (a and b) and (a.generation >= b.generation and a or b) or a or b
    local generation = (current and current.generation or 0) + 1
    local slot = current and current.slot == "a" and "b" or "a"
    local snapshot = {
        version = TOC_VERSION, bookUrl = bookUrl, origin = origin,
        tocUrl = tocUrl, generation = generation, slot = slot, chapters = chapters,
        legacyMap = legacy_map,
    }
    local json = require("src.json")
    local encoded = json.encode(snapshot)
    local path = toc_slot_path(bookUrl, slot)
    if love and love.filesystem and love.filesystem.write then
        local dir = "cache/" .. sanitize_name(bookUrl)
        if love.filesystem.getInfo and not love.filesystem.getInfo(dir) then love.filesystem.createDirectory(dir) end
        local ok = love.filesystem.write(path, encoded)
        if not ok then return false end
        local verified = read_toc_slot(bookUrl, origin, slot)
        return verified ~= nil and verified.generation == generation
    end
    mem_cache[path] = encoded
    local verified = read_toc_slot(bookUrl, origin, slot)
    return verified ~= nil and verified.generation == generation
end

function cache.load_toc(bookUrl, origin)
    local a = read_toc_slot(bookUrl, origin, "a")
    local b = read_toc_slot(bookUrl, origin, "b")
    local result = (a and b) and (a.generation >= b.generation and a or b) or a or b
    if result then return result.chapters, result.tocUrl, "snapshot", result.legacyMap end
    local mismatch = false
    if love and love.filesystem and love.filesystem.getInfo then
        for _, slot in ipairs({ "a", "b" }) do
            local path = toc_slot_path(bookUrl, slot)
            if love.filesystem.getInfo(path) then
                local raw = love.filesystem.read(path)
                local obj = type(raw) == "string" and require("src.json").decode(raw) or nil
                if type(obj) == "table" and (obj.bookUrl ~= bookUrl or obj.origin ~= origin) then mismatch = true end
            end
        end
    else
        for _, slot in ipairs({ "a", "b" }) do
            local raw = mem_cache[toc_slot_path(bookUrl, slot)]
            local obj = raw and require("src.json").decode(raw)
            if type(obj) == "table" and (obj.bookUrl ~= bookUrl or obj.origin ~= origin) then mismatch = true end
        end
    end
    return nil, nil, mismatch and "origin_mismatch" or "missing"
end

-- Legacy installations have only ch_N.txt. Expose bounded placeholder slots so
-- offline users can still open cached chapters without inventing chapter URLs.
function cache.load_legacy_toc(bookUrl, currentTitle, currentIndex)
    local dir = "cache/" .. sanitize_name(bookUrl)
    local max_idx = 0
    if love and love.filesystem and love.filesystem.getDirectoryItems and love.filesystem.getInfo
        and love.filesystem.getInfo(dir) then
        for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
            local n = tonumber(name:match("^ch_(%d+)%.txt$"))
            if n and n >= 1 and n <= MAX_LEGACY_CHAPTER and n > max_idx then max_idx = n end
        end
    else
        local prefix = dir .. "/ch_"
        for path in pairs(mem_cache) do
            if path:sub(1, #prefix) == prefix then
                local n = tonumber(path:match("ch_(%d+)%.txt$"))
                if n and n >= 1 and n <= MAX_LEGACY_CHAPTER and n > max_idx then max_idx = n end
            end
        end
    end
    if max_idx == 0 then return nil end
    local chapters = {}
    for i = 1, max_idx do
        local title = (i == currentIndex and currentTitle and currentTitle ~= "") and currentTitle
            or (cache.is_cached(bookUrl, i) and "本地缓存第 " .. i .. " 章" or "第 " .. i .. " 章（未缓存）")
        chapters[i] = { title = title }
    end
    return chapters, "legacy"
end

function cache.init()
    if love and love.filesystem and love.filesystem.getInfo then
        if not love.filesystem.getInfo("cache") then
            love.filesystem.createDirectory("cache")
        end
    end
end

function cache.is_cached(bookUrl, chapterIdx)
    local p = get_cache_path(bookUrl, chapterIdx)
    if love and love.filesystem and love.filesystem.getInfo then
        return love.filesystem.getInfo(p) ~= nil
    end
    return mem_cache[p] ~= nil
end

function cache.get_chapter(bookUrl, chapterIdx)
    local p = get_cache_path(bookUrl, chapterIdx)
    if love and love.filesystem and love.filesystem.getInfo then
        if love.filesystem.getInfo(p) then
            return love.filesystem.read(p)
        end
        return nil
    end
    return mem_cache[p]
end

function cache.save_chapter(bookUrl, chapterIdx, content)
    if not content or #content == 0 then return false end
    local p = get_cache_path(bookUrl, chapterIdx)
    if love and love.filesystem and love.filesystem.write then
        local book_dir = "cache/" .. sanitize_name(bookUrl)
        if not love.filesystem.getInfo(book_dir) then
            love.filesystem.createDirectory(book_dir)
        end
        return love.filesystem.write(p, content)
    end
    mem_cache[p] = content
    return true
end

function cache.delete_chapter(bookUrl, chapterIdx)
    local p = get_cache_path(bookUrl, chapterIdx)
    mem_cache[p] = nil
    if love and love.filesystem and love.filesystem.remove then
        if love.filesystem.getInfo(p) then
            return love.filesystem.remove(p)
        end
    end
    return true
end

-- Asynchronous background pre-caching for smooth offline reading
local prefetch_queue = {}
local is_prefetching = false

function cache.prefetch_chapters(book, source_json, chapters, start_idx, count)
    local book_url = book and book.bookUrl
    local source_snapshot = source_json
    local chapter_snapshot = {}
    for i, ch in ipairs(chapters or {}) do chapter_snapshot[i] = ch and { title = ch.title, url = ch.url } end
    count = count or 3
    local total = #chapter_snapshot
    local pending_indices = {}
    for i = start_idx, math.min(start_idx + count - 1, total) do
        local chap = chapter_snapshot[i]
        if chap and chap.url and not cache.is_cached_url(book_url, chap.url) then
            table.insert(pending_indices, i)
        end
    end

    if #pending_indices == 0 then return end

    -- Serialize prefetch requests sequentially with a queue to avoid freezing UI
    local function fetch_next(idx_ptr)
        if idx_ptr > #pending_indices then return end
        local i = pending_indices[idx_ptr]
        local chap = chapter_snapshot[i]
        if not chap or not chap.url or cache.is_cached_url(book_url, chap.url) then
            fetch_next(idx_ptr + 1)
            return
        end

        http.request_async({
            url = chap.url,
            method = "GET",
            tag = "prefetch",
            timeout = 5,
            payload = {
                bookUrl = book_url,
                chapterIdx = i,
                source_json = source_snapshot,
                url = chap.url
            }
        }, function(resp, tag, payload)
            if resp and #resp > 0 then
                local clean_res = legado.parseContent(payload.source_json, resp, payload.url)
                local clean_text = type(clean_res) == "table" and clean_res.content or clean_res
                if clean_text and #clean_text > 0 then
                    cache.save_chapter_url(payload.bookUrl, payload.url, clean_text)
                end
            end
            -- Fetch the next prefetch chapter sequentially after previous one finishes
            fetch_next(idx_ptr + 1)
        end)
    end

    fetch_next(1)
end

-- Download every chapter of a book into the offline cache (whole-book caching).
-- Chapters already cached are skipped. Fetches sequentially to avoid flooding the
-- network stack. `on_progress(done, total, failed)` is invoked after each chapter;
-- `on_done(done, total, failed)` fires once when the whole book is processed.
function cache.cache_book(book, source_json, chapters, on_progress, on_done)
    local book_url = book and book.bookUrl
    local source_snapshot = source_json
    local chapter_snapshot = {}
    for i, ch in ipairs(chapters or {}) do chapter_snapshot[i] = ch and { title = ch.title, url = ch.url } end
    local total = #chapter_snapshot
    if total == 0 then
        if on_done then on_done(0, 0, 0) end
        return
    end

    -- Build the work list of uncached chapters.
    local pending = {}
    local already, failed = 0, 0
    for i = 1, total do
        local chapter = chapter_snapshot[i]
        if not chapter or not chapter.url or chapter.url == "" then
            failed = failed + 1
        elseif cache.is_cached_url(book_url, chapter.url) then
            already = already + 1
        else
            table.insert(pending, i)
        end
    end
    local done = already + failed

    if on_progress then on_progress(done, total, failed) end

    local function step(ptr)
        if ptr > #pending then
            if on_done then on_done(done, total, failed) end
            return
        end
        local i = pending[ptr]
        local chap = chapter_snapshot[i]
        if not chap or not chap.url then
            failed = failed + 1
            done = done + 1
            if on_progress then on_progress(done, total, failed) end
            step(ptr + 1)
            return
        end

        http.request_async({
            url = chap.url,
            method = "GET",
            tag = "cache_book",
            timeout = 8,
            payload = { bookUrl = book_url, chapterIdx = i, source_json = source_snapshot, url = chap.url }
        }, function(resp)
            if resp and #resp > 0 then
                local clean_res = legado.parseContent(source_json, resp, chap.url)
                local clean_text = type(clean_res) == "table" and clean_res.content or clean_res
                if clean_text and #clean_text > 0 then
                    local saved = cache.save_chapter_url(book_url, chap.url, clean_text)
                    if not saved or not cache.is_cached_url(book_url, chap.url) then failed = failed + 1 end
                else
                    failed = failed + 1
                end
            else
                failed = failed + 1
            end
            done = done + 1
            if on_progress then on_progress(done, total, failed) end
            step(ptr + 1)
        end)
    end

    step(1)
end

-- ---------------------------------------------------------------------------
-- Cache maintenance (used by the Settings tab)
-- ---------------------------------------------------------------------------

local function cache_root()
    return "cache"
end

-- List the per-book cache directory names (sanitized book URLs).
function cache.list_books()
    if not (love and love.filesystem and love.filesystem.getDirectoryItems) then return {} end
    if not love.filesystem.getInfo(cache_root()) then return {} end
    local items = love.filesystem.getDirectoryItems(cache_root())
    local dirs = {}
    for _, name in ipairs(items) do
        if love.filesystem.getInfo(cache_root() .. "/" .. name) then
            table.insert(dirs, name)
        end
    end
    return dirs
end

-- Count cached chapters across all books (or a single book when bookUrl given).
function cache.count_chapters(bookUrl)
    if not (love and love.filesystem and love.filesystem.getDirectoryItems) then return 0 end
    local dirs = bookUrl and { sanitize_name(bookUrl) } or cache.list_books()
    local n = 0
    for _, d in ipairs(dirs) do
        local p = cache_root() .. "/" .. d
        if love.filesystem.getInfo(p) then
            for _, f in ipairs(love.filesystem.getDirectoryItems(p)) do
                if f:match("^ch_%d+%.txt$") then
                    n = n + 1
                elseif f:match("^ch_u_[%da-f]+%.txt$") then
                    local entry = require("src.json").decode(love.filesystem.read(p .. "/" .. f) or "")
                    if type(entry) == "table" and entry.bookUrl and sanitize_name(entry.bookUrl) == d
                        and (not bookUrl or entry.bookUrl == bookUrl) and type(entry.chapterUrl) == "string"
                        and type(entry.content) == "string" then n = n + 1 end
                end
            end
        end
    end
    return n
end

function cache.delete_book(bookUrl)
    local dir = cache_root() .. "/" .. sanitize_name(bookUrl)
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        if love.filesystem.getInfo(dir) then
            for _, f in ipairs(love.filesystem.getDirectoryItems(dir)) do
                love.filesystem.remove(dir .. "/" .. f)
            end
            love.filesystem.remove(dir)
            return true
        end
    end
    return false
end

-- Remove cached chapters for every book whose URL is NOT in `keep_urls`.
-- Returns the number of book caches deleted.
function cache.clear_except(keep_urls)
    keep_urls = keep_urls or {}
    local keep = {}
    for _, u in ipairs(keep_urls) do keep[sanitize_name(u)] = true end

    local removed = 0
    for _, dir in ipairs(cache.list_books()) do
        if not keep[dir] then
            local p = cache_root() .. "/" .. dir
            for _, f in ipairs(love.filesystem.getDirectoryItems(p)) do
                love.filesystem.remove(p .. "/" .. f)
            end
            love.filesystem.remove(p)
            removed = removed + 1
        end
    end
    return removed
end

-- Wipe the entire cache.
function cache.clear_all()
    local removed = 0
    for _, dir in ipairs(cache.list_books()) do
        local p = cache_root() .. "/" .. dir
        for _, f in ipairs(love.filesystem.getDirectoryItems(p)) do
            love.filesystem.remove(p .. "/" .. f)
        end
        love.filesystem.remove(p)
        removed = removed + 1
    end
    return removed
end

return cache
