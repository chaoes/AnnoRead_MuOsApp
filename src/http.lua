local http = {}
local json = require("src.json")
local transport = require("src.http_transport")

function http.request(options)
    options = options or {}
    local result = transport.perform(options)
    if result.error then return nil, result.error end
    if not result.body or #result.body == 0 then return nil, "Empty response or network timeout" end
    return result.body
end

-- Synchronous HTTP helper used by Legado java.ajax() host callbacks.
-- opts can be a JSON string or nil. timeout is in seconds (or ms if > 100).
local function decode_options(opts_json)
    if type(opts_json) == "table" then return opts_json end
    if type(opts_json) ~= "string" or opts_json == "" then return {} end
    local ok, decoded = pcall(json.decode, opts_json)
    if ok and type(decoded) == "table" then return decoded end
    return {}
end

local function make_sync_options(url, opts_json, timeout)
    local decoded = decode_options(opts_json)
    local options = { url = url }
    local to = tonumber(timeout) or 10
    if to > 100 then to = math.max(1, math.floor(to / 1000)) end
    options.timeout = tonumber(decoded.timeout) or to
    options.method = decoded.method or "GET"
    options.method_explicit = decoded.method ~= nil
    options.headers = decoded.headers or decoded.header
    options.body = decoded.body
    options.charset = decoded.charset
    options.type = decoded.type
    return options
end

-- Metadata API for java.connect style callers. `request_sync` retains its string ABI.
function http.request_sync_result(url, opts_json, timeout)
    if not url or url == "" then return { body = "", headers = {}, error = "empty URL" } end
    local options = transport.resolve_options(make_sync_options(url, opts_json, timeout))
    local result = transport.perform(options)
    if options.charset then
        result.charset_requested = options.charset
        result.charset_applied = false
        result.charset_error = "response charset conversion is unavailable in the bundled runtime"
    end
    return result
end

function http.request_sync(url, opts_json, timeout)
    if not url or url == "" then return "" end
    local result = http.request_sync_result(url, opts_json, timeout)
    if result.error then return "" end
    return result.body or ""
end

-- Threaded asynchronous HTTP queue for 60 FPS non-blocking fetching
local thread_code = [[
local thread_in = love.thread.getChannel("http_req_channel")
local thread_out = love.thread.getChannel("http_res_channel")
local transport = require("src.http_transport")

while true do
    local req = thread_in:demand()
    if req == "STOP" then break end

    local result = transport.perform(req)

    thread_out:push({
        id = req.id,
        tag = req.tag,
        payload = req.payload,
        response = result.error and "" or (result.body or "")
    })
end
]]

local worker_thread = nil
local req_channel = nil
local res_channel = nil
local next_req_id = 1
local callbacks = {}

function http.init_async()
    if not (love and love.thread) then return end
    req_channel = love.thread.getChannel("http_req_channel")
    res_channel = love.thread.getChannel("http_res_channel")
    worker_thread = love.thread.newThread(thread_code)
    worker_thread:start()
end

function http.request_async(options, callback)
    if not req_channel then
        http.init_async()
    end
    local req_id = next_req_id
    next_req_id = next_req_id + 1

    callbacks[req_id] = callback
    req_channel:push({
        id = req_id,
        url = options.url,
        method = options.method,
        method_explicit = options.method ~= nil,
        headers = options.headers,
        body = options.body,
        type = options.type,
        charset = options.charset,
        timeout = options.timeout or 8,
        tag = options.tag,
        payload = options.payload
    })
    return req_id
end

function http.update()
    if not res_channel then return end
    while true do
        local res = res_channel:pop()
        if not res then break end
        local cb = callbacks[res.id]
        if cb then
            callbacks[res.id] = nil
            cb(res.response, res.tag, res.payload)
        end
    end
end

-- Number of in-flight async requests. Views use this to show spinners; the
-- frame pacer uses it to avoid dropping to the idle rate while work is pending.
function http.pending_count()
    local n = 0
    for _ in pairs(callbacks) do n = n + 1 end
    return n
end

function http.has_pending()
    return next(callbacks) ~= nil
end

return http
