package.path = "./?.lua;./?/init.lua;" .. package.path

local files, dirs = {}, {}
love = { filesystem = {} }
function love.filesystem.getInfo(path)
    if files[path] ~= nil then return { type = "file" } end
    if dirs[path] then return { type = "directory" } end
end
function love.filesystem.createDirectory(path) dirs[path] = true; return true end
function love.filesystem.write(path, value)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then dirs[dir] = true end
    files[path] = value
    return true
end
function love.filesystem.read(path) return files[path] end
function love.filesystem.remove(path) files[path], dirs[path] = nil, nil; return true end
function love.filesystem.getDirectoryItems(path)
    local result, prefix = {}, path .. "/"
    local found = {}
    for p in pairs(files) do
        if p:sub(1, #prefix) == prefix then
            local child = p:sub(#prefix + 1):match("^[^/]+")
            if child and not found[child] then found[child] = true; result[#result + 1] = child end
        end
    end
    return result
end
love.timer = { getTime = function() return 1 end }

local source = { bookSourceUrl = "source-A", bookSourceName = "A", enabled = true }
local requests = {}
package.loaded["src.storage"] = {
    get_sources = function() return { source } end,
    get_active_source = function() return source end,
    get_reader_settings = function() return { theme = "light", font_size = 20, margin_horiz = 30, margin_vert = 30, line_spacing = 1.6, para_spacing = 10 } end,
    save_reader_settings = function() end,
    update_book_progress = function() end,
    update_book_origin = function() end,
}
package.loaded["src.theme"] = {
    set_theme = function() end,
    get_reader_font = function() return { getWidth = function(_, s) return #s * 10 end, getHeight = function() return 20 end } end,
}
package.loaded["src.http"] = { request_async = function(opts, cb) requests[#requests + 1] = { opts = opts, cb = cb } end }
package.loaded["src.legado"] = {
    parseBookInfo = function() return require("src.json").encode({ tocUrl = "toc" }) end,
    parseToc = function(_, body)
        if body == "page1" then return { chapters = { { title = "one", url = "u1" }, { title = "two", url = "u2" } }, nextTocUrl = "page2" } end
        if body == "page2" then return { chapters = { { title = "three", url = "u3" } } } end
        if body == "reordered" then return { chapters = { { title = "two", url = "u2" }, { title = "one", url = "u1" } } } end
        return { chapters = {} }
    end,
    parseContent = function(_, body) return { content = body } end,
}
package.loaded["src.views.change_source"] = { is_open = function() return false end }
package.loaded["src.book_download"] = { start = function() end }

local json = require("src.json")
local cache = require("src.cache")
local book = { bookUrl = "book-A", tocUrl = "detail", origin = "source-A", currentChapterIndex = 2, currentChapterTitle = "two" }
local initial = { { title = "one", url = "u1" }, { title = "two", url = "u2" } }
assert(cache.save_toc(book.bookUrl, book.origin, initial, "toc"), "save initial TOC")
assert(cache.save_chapter_url(book.bookUrl, "u2", "cached two"), "save URL chapter")
local hash = 5381
for i = 1, #"collision-url" do hash = (hash * 33 + ("collision-url"):byte(i)) % 4294967296 end
local collision_path = "cache/collision-book/ch_u_" .. string.format("%08x", hash) .. ".txt"
assert(cache.save_chapter_url("collision-book", "collision-url", "safe"), "save URL-keyed content")
files[collision_path] = json.encode({ bookUrl = "collision-book", chapterUrl = "different-url", content = "wrong body" })
assert(not cache.is_cached_url("collision-book", "collision-url"), "URL hash collision is a cache miss")
-- A restart reloads the cache module while retaining only the fake on-disk files.
package.loaded["src.cache"] = nil
package.loaded["src.views.reader"] = nil
cache = require("src.cache")
Game_Can_Online = false
local reader = require("src.views.reader")
reader.open_book(book)
assert(#requests == 0, "offline open must not request TOC or prefetch")
assert(#reader.get_chapters() == 2 and reader.get_chapters()[2].url == "u2", "snapshot TOC loads offline")
assert(reader.get_current_content() == "cached two", "URL cached chapter loads offline")

-- Online refresh is asynchronous and only a safe append may replace the active list.
Game_Can_Online = true
reader.open_catalog()
reader.load_toc(true)
assert(#requests == 1, "background TOC refresh starts")
requests[1].cb("detail-response")
assert(#requests == 2 and requests[2].opts.url == "toc", "detail resolves TOC")
requests[2].cb("page1")
assert(#requests == 3 and requests[3].opts.url == "page2", "TOC page two requested")
requests[3].cb("page2")
assert(#reader.get_chapters() == 3 and reader.get_chapters()[3].url == "u3", "safe append adopted")
assert(reader.get_current_content() == "cached two", "background refresh keeps current body")
assert(reader.is_catalog_open(), "background refresh keeps catalog modal open")

-- A pending chapter response survives a background TOC table replacement by URL identity.
reader.close_catalog()
reader.load_chapter(1)
local body_request = #requests
reader.open_catalog()
reader.load_toc(true)
local refresh_detail = #requests
requests[refresh_detail].cb("detail-response")
requests[refresh_detail + 1].cb("page1")
requests[refresh_detail + 2].cb("page2")
requests[body_request].cb("delayed chapter body")
assert(reader.get_current_content() == "delayed chapter body", "current chapter callback survives safe TOC update")
assert(reader.is_catalog_open(), "chapter response leaves catalog modal open")

-- Reload explicitly bypasses an existing URL body cache.
reader.reload_chapter()
local reload_request = #requests
assert(not cache.is_cached_url(book.bookUrl, "u1"), "reload removes URL-keyed body first")
requests[reload_request].cb("reloaded body")
assert(cache.is_cached_url(book.bookUrl, "u1") and reader.get_current_content() == "reloaded body", "reload refetches and stores current URL")

-- A failed later TOC page cannot replace the complete snapshot.
reader.load_toc(true)
local failed_detail = #requests
requests[failed_detail].cb("detail-response")
requests[failed_detail + 1].cb("page1")
requests[failed_detail + 2].cb(nil)
local after_failure = cache.load_toc(book.bookUrl, book.origin)
assert(#after_failure == 3 and after_failure[3].url == "u3", "failed page preserves complete snapshot")
reader.load_toc(true)
local empty_detail = #requests
requests[empty_detail].cb("detail-response")
requests[empty_detail + 1].cb("empty")
local after_empty = cache.load_toc(book.bookUrl, book.origin)
assert(#after_empty == 3 and after_empty[3].url == "u3", "empty TOC result preserves previous snapshot")

-- Reordered TOCs never become the on-disk index mapping.
reader.load_toc(true)
local n = #requests
requests[n].cb("detail-response")
requests[n + 1].cb("reordered")
local saved = cache.load_toc(book.bookUrl, book.origin)
assert(#saved == 3 and saved[1].url == "u1", "unsafe reorder retains previous snapshot")

-- Malformed newest copy is ignored in favor of the older complete slot.
assert(cache.save_toc(book.bookUrl, book.origin, initial, "toc"), "write second snapshot")
local slot_a = "cache/book-A/toc_a.json"
local slot_b = "cache/book-A/toc_b.json"
local gen_a = files[slot_a] and json.decode(files[slot_a]).generation or -1
local gen_b = files[slot_b] and json.decode(files[slot_b]).generation or -1
local newest = gen_a >= gen_b and slot_a or slot_b
files[newest] = "{broken"
local survived = cache.load_toc(book.bookUrl, book.origin)
assert(survived and #survived == 3, "corrupt snapshot does not hide older valid copy")
local mismatch, _, reason = cache.load_toc(book.bookUrl, "source-B")
assert(mismatch == nil and reason == "origin_mismatch", "snapshot source identity is enforced")

-- Legacy sparse slots expose only bounded placeholder chapters with no guessed URLs.
files["cache/book-legacy/ch_2.txt"] = "legacy two"
files["cache/book-legacy/ch_5.txt"] = "legacy five"
files["cache/book-legacy/ch_100001.txt"] = "ignore huge sparse index"
dirs["cache/book-legacy"] = true
local legacy = cache.load_legacy_toc("book-legacy", "old title", 5)
assert(#legacy == 5 and legacy[5].title == "old title" and legacy[5].url == nil, "legacy directory preserves sparse indexes without invented URLs")
assert(legacy[4].title:find("未缓存"), "legacy holes are explicit")

-- Legacy ch_N installs remain readable offline with neutral catalog placeholders.
files["cache/book-legacy/ch_5.txt"] = "legacy five"
Game_Can_Online = false
package.loaded["src.cache"] = nil
package.loaded["src.views.reader"] = nil
cache = require("src.cache")
reader = require("src.views.reader")
local legacy_book = { bookUrl = "book-legacy", origin = "source-A", currentChapterIndex = 5, currentChapterTitle = "old title" }
local before_legacy_open = #requests
reader.open_book(legacy_book)
assert(#requests == before_legacy_open, "legacy offline open does not request network")
assert(#reader.get_chapters() == 5 and reader.get_chapters()[5].url == nil, "legacy catalog does not invent URLs")
assert(reader.get_current_content() == "legacy five", "legacy cached body opens offline")
Game_Can_Online = true
reader.open_book(legacy_book)
local legacy_refresh = #requests
requests[legacy_refresh].cb("detail-response")
requests[legacy_refresh + 1].cb("page1")
requests[legacy_refresh + 2].cb("page2")
assert(#reader.get_chapters() == 5 and reader.get_chapters()[5].url == nil, "background refresh leaves legacy placeholders intact")
assert(cache.load_toc(legacy_book.bookUrl, legacy_book.origin) == nil, "legacy refresh does not commit unverifiable URLs")
assert(files["cache/book-legacy/ch_5.txt"] == "legacy five", "legacy body survives background refresh")
Game_Can_Online = false
reader.open_book(legacy_book)
assert(reader.get_current_content() == "legacy five", "legacy body remains readable after restart")

package.loaded["src.book_download"] = nil
local book_download = require("src.book_download")
Game_Can_Online = true
local legacy_partial_done
book_download.start(legacy_book, { on_done = function(ok) legacy_partial_done = ok end })
local legacy_partial_detail = #requests
requests[legacy_partial_detail].cb("detail-response")
requests[legacy_partial_detail + 1].cb("page1")
requests[legacy_partial_detail + 2].cb("page2")
requests[#requests].cb(nil)
requests[#requests].cb("partial body two")
requests[#requests].cb("partial body three")
assert(legacy_partial_done == false and cache.load_toc(legacy_book.bookUrl, legacy_book.origin) == nil,
    "legacy partial download keeps placeholder catalog")
assert(files["cache/book-legacy/ch_2.txt"] == "legacy two" and files["cache/book-legacy/ch_5.txt"] == "legacy five",
    "legacy partial failure preserves every old indexed body")

book_download.start(legacy_book, {})
local legacy_full_detail = #requests
requests[legacy_full_detail].cb("detail-response")
requests[legacy_full_detail + 1].cb("page1")
requests[legacy_full_detail + 2].cb("page2")
local retry_body = #requests
assert(requests[retry_body].opts.url == "u1", "retry downloads only the missing URL body")
requests[retry_body].cb("completed body one")
local legacy_real_toc = cache.load_toc(legacy_book.bookUrl, legacy_book.origin)
assert(legacy_real_toc and #legacy_real_toc == 3, "legacy catalog commits after full URL download")
assert(files["cache/book-legacy/ch_5.txt"] == "legacy five", "legacy body files remain intact after safe migration")

-- A stale TOC callback from book A cannot apply after opening book B.
Game_Can_Online = true
reader.open_book(book)
local stale_request = #requests
reader.open_book({ bookUrl = "book-B", origin = "source-A", currentChapterIndex = 1 })
requests[stale_request].cb("detail-response")
assert(reader.get_chapters()[1] == nil, "stale A callback cannot replace B catalog")

-- Normal right-click exit invalidates an in-flight body callback and its cache write.
reader.open_book(book)
local current_chapter = reader.get_chapters()[1]
cache.delete_chapter_url(book.bookUrl, current_chapter.url)
reader.load_chapter(1)
local exit_body_request = #requests
local exit = reader.mousepressed(1, 1, 2)
assert(exit and exit.action == "close_reader", "right-click exits reader")
requests[exit_body_request].cb("must not be written")
assert(not cache.is_cached_url(book.bookUrl, current_chapter.url), "exit invalidates stale body cache write")

-- Ordinary new books persist a complete TOC before partial body downloads.
local download_book = { bookUrl = "book-download", tocUrl = "detail", origin = "source-A" }
local download_book_url = download_book.bookUrl
package.loaded["src.book_download"] = nil
book_download = require("src.book_download")
book_download.start(download_book, {})
download_book.bookUrl, download_book.origin = "book-mutated", "source-B"
local dl_detail = #requests
requests[dl_detail].cb("detail-response")
requests[dl_detail + 1].cb("page1")
requests[dl_detail + 2].cb("page2")
assert(cache.load_toc(download_book_url, "source-A") ~= nil, "new TOC is saved before body download")
for i = 1, 3 do
    local body_req = #requests
    assert(requests[body_req].opts.url == "u" .. i, "whole-book body requests follow TOC order")
    requests[body_req].cb("downloaded body " .. i)
end
local downloaded_toc = cache.load_toc(download_book_url, "source-A")
assert(downloaded_toc and #downloaded_toc == 3, "whole-book download persists complete TOC")
assert(cache.count_chapters(download_book_url) == 3, "URL-keyed bodies appear in cache statistics")

local failed_book = { bookUrl = "book-download-failed", tocUrl = "detail", origin = "source-A" }
local failed_done
book_download.start(failed_book, { on_done = function(ok) failed_done = ok end })
local fail_detail = #requests
requests[fail_detail].cb("detail-response")
requests[fail_detail + 1].cb("page1")
requests[fail_detail + 2].cb("page2")
for _ = 1, 3 do
    local body_req = #requests
    requests[body_req].cb(nil)
end
assert(failed_done == false and cache.load_toc(failed_book.bookUrl, failed_book.origin) ~= nil,
    "ordinary book retains its valid TOC after partial body failure")

cache.delete_book(download_book_url)
assert(cache.load_toc(download_book_url, "source-A") == nil
    and not cache.is_cached_url(download_book_url, "u1"), "book deletion removes TOC and URL bodies")

print("Reader offline TOC regression tests passed")
