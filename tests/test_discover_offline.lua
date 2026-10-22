package.path = "?.lua;./src/?.lua;" .. package.path

local discover = require("src.views.discover")
local storage = require("src.storage")
local legado = require("src.legado")
local http = require("src.http")

local old_online = Game_Can_Online
local old_sources = storage.get_sources
local old_parse = legado.parseExploreCategories
local old_request = http.request_async
local parse_calls, request_calls = 0, 0

Game_Can_Online = false
storage.get_sources = function()
    return { { enabled = true, exploreUrl = "https://example.test/explore", bookSourceName = "测试源" } }
end
legado.parseExploreCategories = function()
    parse_calls = parse_calls + 1
    return "[]"
end
http.request_async = function()
    request_calls = request_calls + 1
end

discover.init()
assert(#discover.get_categories() == 0 and not discover.is_loading())
assert(discover.set_active_source(1) == false)
discover._set_categories({ { title = "测试分类", url = "https://example.test/books" } })
discover.load_category_books(1)
assert(parse_calls == 0 and request_calls == 0, "offline discover must not access the network")

Game_Can_Online = old_online
storage.get_sources = old_sources
legado.parseExploreCategories = old_parse
http.request_async = old_request
print("Offline discover avoids network requests")
