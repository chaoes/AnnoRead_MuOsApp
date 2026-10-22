-- src/tts_cache.lua
-- Persistent disk storage cache for MiMo TTS synthesized paragraph audio.
-- Indexing:
--   Folder structure: cache/tts/<sanitized_book_key>/ch_<chapter_idx>/p_<para_idx>_<hash>.wav
--   where book_key is constructed from book title or bookUrl. The hash also
--   includes the optional synthesis profile so voice changes cannot reuse audio.
-- Features:
--   - Persistent storage to reduce network latency and API calls.
--   - Invalidation & cleanup: remove obsolete chapters / non-target chapters.
--   - Count & total cache size queries.

local tts_cache = {}

local function sanitize_name(name)
    if not name or name == "" then return "unknown" end
    local clean = name:gsub("[^%w_%-]", "_")
    if #clean > 64 then
        -- Keep prefix and add hash
        local h = 5381
        for i = 1, #name do h = (h * 33 + name:byte(i)) % 4294967296 end
        clean = clean:sub(1, 32) .. string.format("_%08x", h)
    end
    return clean
end

function tts_cache.hash_str(str)
    if not str or str == "" then return 0 end
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return h
end

function tts_cache.get_book_key(book_title, book_url)
    local raw = (book_title and book_title ~= "") and book_title or (book_url or "default_book")
    return sanitize_name(raw)
end

function tts_cache.get_chapter_dir(book_key, chapter_idx)
    return string.format("cache/tts/%s/ch_%d", sanitize_name(book_key), tonumber(chapter_idx) or 1)
end

function tts_cache.get_para_path(book_key, chapter_idx, para_idx, para_text, variant)
    local dir = tts_cache.get_chapter_dir(book_key, chapter_idx)
    local hash_input = para_text or ""
    if variant and variant ~= "" then hash_input = hash_input .. "\0" .. variant end
    local thash = tts_cache.hash_str(hash_input)
    return string.format("%s/p_%d_%08x.wav", dir, tonumber(para_idx) or 1, thash)
end

local function ensure_dir(path)
    if love and love.filesystem then
        if not love.filesystem.getInfo(path) then
            pcall(love.filesystem.createDirectory, path)
        end
    else
        pcall(os.execute, "mkdir -p '" .. path .. "'")
    end
end

function tts_cache.init()
    if love and love.filesystem then
        ensure_dir("cache")
        ensure_dir("cache/tts")
    end
end

function tts_cache.is_cached(book_key, chapter_idx, para_idx, para_text, variant)
    local path = tts_cache.get_para_path(book_key, chapter_idx, para_idx, para_text, variant)
    if love and love.filesystem and love.filesystem.getInfo then
        local info = love.filesystem.getInfo(path)
        return info ~= nil and (info.size or 0) > 0
    end
    -- Fallback for non-Love2D environment (e.g. CLI tests)
    local f = io.open(path, "rb")
    if f then
        local sz = f:seek("end")
        f:close()
        return sz and sz > 0
    end
    return false
end

function tts_cache.get_audio(book_key, chapter_idx, para_idx, para_text, variant)
    local path = tts_cache.get_para_path(book_key, chapter_idx, para_idx, para_text, variant)
    if love and love.filesystem and love.filesystem.read then
        if not love.filesystem.getInfo(path) then return nil end
        local content, err = love.filesystem.read(path)
        if content and #content > 0 then return content end
        return nil
    end
    local f = io.open(path, "rb")
    if f then
        local content = f:read("*a")
        f:close()
        if content and #content > 0 then return content end
    end
    return nil
end

function tts_cache.save_audio(book_key, chapter_idx, para_idx, para_text, raw_wav_bytes, variant)
    if not raw_wav_bytes or #raw_wav_bytes == 0 then return false end
    tts_cache.init()
    local b_dir = "cache/tts/" .. sanitize_name(book_key)
    ensure_dir(b_dir)
    local ch_dir = tts_cache.get_chapter_dir(book_key, chapter_idx)
    ensure_dir(ch_dir)

    local path = tts_cache.get_para_path(book_key, chapter_idx, para_idx, para_text, variant)
    if love and love.filesystem and love.filesystem.write then
        local ok, err = love.filesystem.write(path, raw_wav_bytes)
        return ok == true
    end
    local f = io.open(path, "wb")
    if f then
        f:write(raw_wav_bytes)
        f:close()
        return true
    end
    return false
end

--- Clean invalid/obsolete TTS audio cache for a book, retaining only current and next chapter.
-- @param book_key string The unique book identifier
-- @param keep_chapter_min number Lowest chapter to keep (usually current_chapter)
-- @param keep_chapter_max number Highest chapter to keep (usually current_chapter + 1)
function tts_cache.cleanup_obsolete(book_key, keep_chapter_min, keep_chapter_max)
    if not book_key or book_key == "" then return 0 end
    local b_dir = "cache/tts/" .. sanitize_name(book_key)
    local removed_count = 0

    if love and love.filesystem and love.filesystem.getDirectoryItems then
        if not love.filesystem.getInfo(b_dir) then return 0 end
        local items = love.filesystem.getDirectoryItems(b_dir)
        for _, item in ipairs(items) do
            local ch_num = item:match("^ch_(%d+)$")
            if ch_num then
                local num = tonumber(ch_num)
                if num < keep_chapter_min or num > keep_chapter_max then
                    local ch_dir = b_dir .. "/" .. item
                    local files = love.filesystem.getDirectoryItems(ch_dir)
                    for _, fn in ipairs(files) do
                        pcall(love.filesystem.remove, ch_dir .. "/" .. fn)
                        removed_count = removed_count + 1
                    end
                    pcall(love.filesystem.remove, ch_dir)
                end
            end
        end
    else
        -- Fallback using shell commands in CLI test environment
        local p = io.popen("ls -d " .. b_dir .. "/ch_* 2>/dev/null")
        if p then
            for line in p:lines() do
                local ch_num = line:match("ch_(%d+)$")
                if ch_num then
                    local num = tonumber(ch_num)
                    if num < keep_chapter_min or num > keep_chapter_max then
                        os.execute("rm -rf '" .. line .. "'")
                        removed_count = removed_count + 1
                    end
                end
            end
            p:close()
        end
    end
    return removed_count
end

--- Wipe all TTS cache across all books or for a specific book.
function tts_cache.clear_all(book_key)
    local target_dir = book_key and ("cache/tts/" .. sanitize_name(book_key)) or "cache/tts"
    local count = 0
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        local function remove_recursive(dir)
            if not love.filesystem.getInfo(dir) then return end
            local items = love.filesystem.getDirectoryItems(dir)
            for _, it in ipairs(items) do
                local sub = dir .. "/" .. it
                local info = love.filesystem.getInfo(sub)
                if info and info.type == "directory" then
                    remove_recursive(sub)
                    pcall(love.filesystem.remove, sub)
                else
                    pcall(love.filesystem.remove, sub)
                    count = count + 1
                end
            end
            pcall(love.filesystem.remove, dir)
        end
        remove_recursive(target_dir)
    else
        os.execute("rm -rf '" .. target_dir .. "'")
    end
    return count
end

--- Get TTS audio file count and size stats
function tts_cache.get_stats(book_key)
    local target_dir = book_key and ("cache/tts/" .. sanitize_name(book_key)) or "cache/tts"
    local count, total_size = 0, 0
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        local function scan_recursive(dir)
            if not love.filesystem.getInfo(dir) then return end
            local items = love.filesystem.getDirectoryItems(dir)
            for _, it in ipairs(items) do
                local sub = dir .. "/" .. it
                local info = love.filesystem.getInfo(sub)
                if info and info.type == "directory" then
                    scan_recursive(sub)
                elseif info then
                    count = count + 1
                    total_size = total_size + (info.size or 0)
                end
            end
        end
        scan_recursive(target_dir)
    end
    return count, total_size
end

return tts_cache
