package.path = "./?.lua;./?/init.lua;" .. package.path
local json = require("src.json")

local source = {
    enabled = true,
    searchUrl = "https://fixture.invalid/search",
    bookSourceUrl = "fixture-source",
    checkKeyWord = "自定义检测词",
}
local requests = {}
local callbacks = {}
local diagnosis_keyword = nil
package.loaded["src.storage"] = { get_sources = function() return { source } end }
package.loaded["src.http"] = { request_async = function(options, callback)
    requests[#requests + 1] = options
    callbacks[#callbacks + 1] = callback
end }
local parsed_search = "[]"
package.loaded["src.legado"] = {
    buildSearchRequest = function(_, keyword)
        diagnosis_keyword = keyword
        return json.encode({
            url = "https://fixture.invalid/search",
            method = "POST",
            headers = json.encode({ ["Content-Type"] = "application/octet-stream" }),
            body = "raw\nbody",
            type = "application/octet-stream",
            charset = "gb18030",
        })
    end,
    parseSearch = function() return parsed_search end,
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
assert(diagnosis_keyword == source.checkKeyWord, "source diagnosis should use the source's check keyword")
callbacks[2]("<html>error</html>", nil, nil, { status = 403 })
assert(sources.get_diagnosis(1).ok == false and sources.get_diagnosis(1).text:find("HTTP 403", 1, true),
    "HTTP error page must not be marked as a healthy source")

sources.update(0.016, { pressed = function(action) return action == "a" end })
callbacks[3]("<html>no results</html>", nil, nil, { status = 200 })
assert(sources.get_diagnosis(1).ok == nil, "empty search result should be inconclusive")

parsed_search = json.encode({ { name = "测试书", bookUrl = "https://fixture.invalid/book" } })
sources.update(0.016, { pressed = function(action) return action == "a" end })
callbacks[4]("<html>book</html>", nil, nil, { status = 200 })
assert(sources.get_diagnosis(1).ok == true, "parsed book should pass search-stage diagnosis")

parsed_search = "invalid JSON"
sources.update(0.016, { pressed = function(action) return action == "a" end })
callbacks[5]("<html>book</html>", nil, nil, { status = 200 })
assert(sources.get_diagnosis(1).ok == false, "invalid parser output should fail diagnosis")

sources.update(0.016, { pressed = function(action) return action == "a" end })
callbacks[6]("", nil, nil, { error = "connection failed" })
assert(sources.get_diagnosis(1).ok == false, "transport error should fail diagnosis")

parsed_search = json.encode({ { name = "测试书", bookUrl = "https://fixture.invalid/book" } })
sources.update(0.016, { pressed = function(action) return action == "a" end })
sources.update(0.016, { pressed = function(action) return action == "a" end })
callbacks[7]("", nil, nil, { error = "late failure" })
assert(sources.get_diagnosis(1).text == "正在检查搜索请求...", "stale diagnosis must not replace a newer request")
callbacks[8]("<html>book</html>", nil, nil, { status = 200 })
assert(sources.get_diagnosis(1).ok == true, "newer diagnosis should finish normally")

local change_source = require("src.views.change_source")
change_source.open({ name = "book", origin = "other" }, "chapter", 0, function() end)
assert_request(9, "change-source view")

print("HTTP view request field tests passed")
