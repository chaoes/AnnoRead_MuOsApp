local legado = require("src.legado")
local json = require("src.json")
local storage = {}

local SOURCES_FILE = "legado_sources.json"
local SHELF_FILE = "legado_bookshelf.json"
local SETTINGS_FILE = "reader_settings.json"

-- Absolute path of the directory where user data (sources/bookshelf/settings/
-- cache) actually lives on this platform. On the handheld, mux_launch.sh sets
-- XDG_DATA_HOME=<app>/conf, so this resolves to <app>/conf/love/<identity>/.
function storage.get_user_data_dir()
    if love and love.filesystem and love.filesystem.getSaveDirectory then
        return love.filesystem.getSaveDirectory()
    end
    return nil
end

local default_reader_settings = {
    theme = "dark",
    font_size = 20,
    line_spacing = 1.6,
    para_spacing = 10,
    margin_horiz = 28,
    margin_vert = 40,
    tts_volume = 100, -- TTS volume percentage (50% - 200%, default 100%)
}

local state = {
    sources = {},
    books = {},
    reader_settings = nil
}

function storage.json_decode(str)
    return json.decode(str)
end

function storage.json_encode(val)
    return json.encode(val)
end

-- Book sources now live as one-or-more JSON files inside dedicated folders so
-- users can drop additional source files directly into sources/ or next to bundled defaults.
--
--   sources/*.json          user-added source files (save directory and app directory)
--   assets/sources/*.json   optional locally bundled sources
--
-- All *.json files found in these folders are parsed and merged. Legacy single-file
-- locations are still honoured as a fallback for older installs.
local SOURCES_DIR = "assets/sources"
local USER_SOURCES_DIR = "sources"

storage.SOURCES_DIR = SOURCES_DIR
storage.USER_SOURCES_DIR = USER_SOURCES_DIR

function storage.get_user_sources_dir()
    -- On handheld/device, sources/ is directly in the app directory next to main.lua
    -- and love.filesystem also maps sources/ in both save dir and app base dir.
    return "sources/"
end

local function list_source_files_in_dir(dir_path)
    local files = {}
    local seen = {}

    -- Running under LÖVE: use love.filesystem so it checks virtual filesystem (save dir + app root)
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        local ok, items = pcall(love.filesystem.getDirectoryItems, dir_path)
        if ok and type(items) == "table" then
            for _, name in ipairs(items) do
                if name:lower():match("%.json$") then
                    local p = dir_path:gsub("/+$", "") .. "/" .. name
                    if not seen[p] then
                        seen[p] = true
                        table.insert(files, p)
                    end
                end
            end
        end
    end

    -- Real filesystem scan (for plain Lua / tests or absolute paths)
    local p = io.popen("ls " .. dir_path .. "/*.json 2>/dev/null")
    if p then
        for line in p:lines() do
            if #line > 0 and not seen[line] then
                seen[line] = true
                table.insert(files, line)
            end
        end
        p:close()
    end

    return files
end

local function read_file_content(path)
    if love and love.filesystem and love.filesystem.read then
        local ok, content = pcall(love.filesystem.read, path)
        if ok and content and #content > 0 then
            return content
        end
    end

    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and #content > 0 then
            return content
        end
    end
    return nil
end

local function parse_source_file(path)
    local content = read_file_content(path)
    if not content or #content == 0 then return nil end

    local list = nil
    if legado and legado.parseSources then
        local ok, parsed_json = pcall(legado.parseSources, content)
        if ok and parsed_json and #parsed_json > 0 then
            local dec_ok, dec = pcall(json.decode, parsed_json)
            if dec_ok and type(dec) == "table" and #dec > 0 then
                list = dec
            end
        end
    end

    -- Fallback: direct decode if legado was unavailable or returned empty
    if not list or type(list) ~= "table" or #list == 0 then
        local ok, raw = pcall(json.decode, content)
        if ok and type(raw) == "table" then
            if raw[1] and type(raw[1]) == "table" and raw[1].bookSourceUrl then
                list = raw
            elseif raw.bookSourceUrl then
                list = { raw }
            elseif raw.data and type(raw.data) == "table" then
                list = raw.data
            elseif raw.list and type(raw.list) == "table" then
                list = raw.list
            end
        end
    end

    if type(list) == "table" and #list > 0 then
        return list
    end
    return nil
end

local function load_all_sources_from_disk()
    local merged = {}
    local seen_urls = {}

    local function add_file(path)
        local list = parse_source_file(path)
        if list then
            for _, s in ipairs(list) do
                if s.bookSourceUrl and not seen_urls[s.bookSourceUrl] then
                    seen_urls[s.bookSourceUrl] = true
                    table.insert(merged, s)
                end
            end
        end
    end

    -- 1. User sources directories (priority over bundled defaults)
    for _, path in ipairs(list_source_files_in_dir(USER_SOURCES_DIR)) do
        add_file(path)
    end

    local abs_user_dir = storage.get_user_sources_dir()
    if abs_user_dir and abs_user_dir ~= USER_SOURCES_DIR then
        for _, path in ipairs(list_source_files_in_dir(abs_user_dir)) do
            add_file(path)
        end
    end

    -- 2. Bundled defaults
    for _, path in ipairs(list_source_files_in_dir(SOURCES_DIR)) do
        add_file(path)
    end

    -- 3. Legacy single-file fallbacks
    if #merged == 0 then
        local legacy = { "assets/sources.json", "/tmp/real_source.json", "assets/real_source.json" }
        for _, p in ipairs(legacy) do
            add_file(p)
        end
    end

    return merged
end

local function load_default_sources()
    return load_all_sources_from_disk()
end

storage.load_default_sources = load_default_sources

function storage.reload_sources()
    local disk_sources = load_all_sources_from_disk()
    if #disk_sources > 0 then
        local saved_prefs = {}
        for _, s in ipairs(state.sources) do
            if s.bookSourceUrl then
                saved_prefs[s.bookSourceUrl] = {
                    enabled = s.enabled,
                    customOrder = s.customOrder,
                    weight = s.weight
                }
            end
        end
        for _, s in ipairs(disk_sources) do
            local pref = saved_prefs[s.bookSourceUrl]
            if pref then
                if pref.enabled ~= nil then s.enabled = pref.enabled end
                if pref.customOrder ~= nil then s.customOrder = pref.customOrder end
                if pref.weight ~= nil then s.weight = pref.weight end
            end
        end
        state.sources = disk_sources
        storage.save_sources()
        return true
    end
    return false
end

function storage.init()
    legado.init()

    -- Ensure user sources directory exists
    if love and love.filesystem and love.filesystem.createDirectory then
        pcall(love.filesystem.createDirectory, USER_SOURCES_DIR)
    end

    -- 1. Load Sources
    local saved_prefs = {}
    local saved_sources = nil
    if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(SOURCES_FILE) then
        local content = love.filesystem.read(SOURCES_FILE)
        if content and #content > 0 then
            local ok, list = pcall(json.decode, content)
            if ok and type(list) == "table" and #list > 0 then
                saved_sources = list
                for _, s in ipairs(list) do
                    if s.bookSourceUrl then
                        saved_prefs[s.bookSourceUrl] = {
                            enabled = s.enabled,
                            customOrder = s.customOrder,
                            weight = s.weight
                        }
                    end
                end
            end
        end
    end

    local disk_sources = load_all_sources_from_disk()
    if #disk_sources > 0 then
        for _, s in ipairs(disk_sources) do
            local pref = saved_prefs[s.bookSourceUrl]
            if pref then
                if pref.enabled ~= nil then s.enabled = pref.enabled end
                if pref.customOrder ~= nil then s.customOrder = pref.customOrder end
                if pref.weight ~= nil then s.weight = pref.weight end
            end
        end
        state.sources = disk_sources
    elseif saved_sources and #saved_sources > 0 then
        state.sources = saved_sources
    else
        state.sources = {}
    end
    storage.save_sources()

    -- 2. Load Bookshelf
    if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(SHELF_FILE) then
        local content = love.filesystem.read(SHELF_FILE)
        if content and #content > 0 then
            local list = json.decode(content)
            if type(list) == "table" then
                state.books = list
            end
        end
    end

end

function storage.save_sources()
    if love and love.filesystem and love.filesystem.write then
        love.filesystem.write(SOURCES_FILE, json.encode(state.sources))
    end
end

function storage.save_books()
    if love and love.filesystem and love.filesystem.write then
        love.filesystem.write(SHELF_FILE, json.encode(state.books))
    end
end

function storage.get_sources()
    return state.sources
end

function storage.get_active_source()
    for _, src in ipairs(state.sources) do
        if src.enabled ~= false then return src end
    end
    return state.sources[1]
end

function storage.toggle_source(index)
    local src = state.sources[index]
    if src then
        src.enabled = not (src.enabled ~= false)
        storage.save_sources()
        return src.enabled
    end
    return false
end

function storage.enable_all_sources(enabled)
    local target = (enabled == true)
    for _, src in ipairs(state.sources) do
        src.enabled = target
    end
    storage.save_sources()
    return true
end

function storage.delete_source(index)
    local src = state.sources[index]
    if src then
        local removed = table.remove(state.sources, index)
        storage.save_sources()
        return removed
    end
    return nil
end

function storage.get_books()
    return state.books
end

function storage.get_books_by_origin(origin)
    local res = {}
    if not origin or origin == "" then return res end
    for _, b in ipairs(state.books) do
        if b.origin == origin then
            table.insert(res, b)
        end
    end
    return res
end

function storage.update_book_origin(bookUrl, origin, originName, newBookUrl, tocUrl)
    for _, b in ipairs(state.books) do
        if b.bookUrl == bookUrl then
            b.origin = origin
            b.originName = originName
            b.bookUrl = newBookUrl or b.bookUrl
            b.tocUrl = tocUrl or b.tocUrl
            b.status = "normal"
            storage.save_books()
            return true
        end
    end
    return false
end

function storage.mark_book_source_deleted(bookUrl)
    for _, b in ipairs(state.books) do
        if b.bookUrl == bookUrl then
            b.status = "source_deleted"
            storage.save_books()
            return true
        end
    end
    return false
end

function storage.is_in_bookshelf(book)
    if not book then return false, nil end
    local url = type(book) == "string" and book or book.bookUrl
    local name = type(book) == "table" and book.name or nil
    local author = type(book) == "table" and book.author or nil

    for i, b in ipairs(state.books) do
        if (url and b.bookUrl == url) or (name and author and b.name == name and b.author == author) then
            return true, i
        end
    end
    return false, nil
end

function storage.remove_book_by_url(bookUrl)
    for i, b in ipairs(state.books) do
        if b.bookUrl == bookUrl then
            return storage.remove_book(i)
        end
    end
    return nil
end

function storage.add_book(book)
    for i, b in ipairs(state.books) do
        if b.bookUrl == book.bookUrl or (b.name == book.name and b.author == book.author) then
            b.lastReadTime = os.time()
            storage.save_books()
            return b, i
        end
    end
    book.lastReadTime = os.time()
    book.currentChapterIndex = book.currentChapterIndex or 1
    book.progress = book.progress or 0.0
    book.status = book.status or "normal"
    table.insert(state.books, 1, book)
    storage.save_books()
    return book, 1
end

function storage.remove_book(index)
    if state.books[index] then
        local removed = table.remove(state.books, index)
        storage.save_books()
        return removed
    end
    return nil
end

function storage.update_book_progress(bookUrl, chapterIndex, chapterTitle, progress, pageIndex)
    for _, b in ipairs(state.books) do
        if b.bookUrl == bookUrl then
            b.currentChapterIndex = chapterIndex
            b.currentChapterTitle = chapterTitle
            b.currentPage = pageIndex or b.currentPage or 1
            b.progress = progress
            b.lastReadTime = os.time()
            storage.save_books()
            break
        end
    end
end

function storage.get_default_reader_settings()
    local copy = {}
    for k, v in pairs(default_reader_settings) do copy[k] = v end
    return copy
end

function storage.get_reader_settings()
    if state.reader_settings then
        return state.reader_settings
    end
    if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(SETTINGS_FILE) then
        local content = love.filesystem.read(SETTINGS_FILE)
        if content and #content > 0 then
            local obj = json.decode(content)
            if type(obj) == "table" then
                state.reader_settings = obj
                return state.reader_settings
            end
        end
    end
    state.reader_settings = storage.get_default_reader_settings()
    return state.reader_settings
end

function storage.save_reader_settings(settings)
    state.reader_settings = settings
    local s = json.encode(settings)
    if love and love.filesystem and love.filesystem.write then
        love.filesystem.write(SETTINGS_FILE, s)
    end
end

return storage
