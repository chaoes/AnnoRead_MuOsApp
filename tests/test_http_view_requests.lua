package.path = "./?.lua;./?/init.lua;" .. package.path
local json = require("src.json")

local source = {
    enabled = true,
    searchUrl = "https://fixture.invalid/search",
    bookSourceUrl = "fixture-source",
}
local requests = {}
package.loaded["src.storage"] = { get_sources = function() return { source } end }
package.loaded["src.http"] = { request_async = function(options, callback)
    requests[#requests + 1] = options
end }
package.loaded["src.legado"] = {
    buildSearchRequest = function()
        return json.encode({
            url = "https://fixture.invalid/search",
            method = "POST",
            headers = json.encode({ ["Content-Type"] = "application/octet-stream" }),
            body = "raw\nbody",
            type = "application/octet-stream",
            charset = "gb18030",
        })
    end,
    parseSearch = function() return "[]" end,
}
package.loaded["src.theme"] = {}
package.loaded["src.input"] = {}
package.loaded["src.keyboard"] = { is_open = function() return false end }
package.loaded["src.chapter_alignment"] = {}
love = { timer = { getTime = function() return 1 end } }

local function assert_request(index, caller)
    local req = requests[index]
    assert(req, caller .. " did not issue HTTP request")
    assert(req.type == "application/octet-stream", caller .. " dropped opts.type")
    assert(req.charset == "gb18030", caller .. " dropped opts.charset")
    assert(req.body == "raw\nbody", caller .. " changed/dropped opts.body")
    assert(req.method == "POST", caller .. " dropped method")
    local headers = type(req.headers) == "string" and json.decode(req.headers) or req.headers
    assert(headers["Content-Type"] == "application/octet-stream", caller .. " changed/dropped stringified headers")
end

local search = require("src.views.search")
search.perform_search()
assert_request(1, "search view")

local sources = require("src.views.sources")
sources.init()
sources.update(0.016, { pressed = function(action) return action == "a" end })
assert_request(2, "source diagnosis")

local change_source = require("src.views.change_source")
change_source.open({ name = "book", origin = "other" }, "chapter", 0, function() end)
assert_request(3, "change-source view")

print("HTTP view request field tests passed")
