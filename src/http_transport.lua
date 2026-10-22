-- Shared curl transport for the main Lua state and Love worker threads.
local M = {}
local json = require("src.json")
local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function hex_bytes(bytes)
    local out = {}
    for i = 1, #bytes do
        out[i] = string.format("%02x", bytes:byte(i))
    end
    return table.concat(out)
end

local function apply_response_type(result, req)
    -- Legado's non-null request type asks the HTTP layer to expose raw response
    -- bytes as lowercase hex, including embedded NULs and line breaks.
    if req.type ~= nil and not result.error and result.body ~= nil then
        result.body = hex_bytes(result.body)
    end
    return result
end

local function shell_escape(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end
M.shell_escape = shell_escape

local function header_blocks(raw)
    local blocks, current = {}, nil
    for line in (raw .. "\n"):gmatch("(.-)\r?\n") do
        if line:match("^HTTP/%d") then
            current = {}
            blocks[#blocks + 1] = current
        elseif current and line == "" then
            current = nil
        elseif current then
            local k, v = line:match("^([^:]+):%s*(.*)$")
            if k then current[k:lower()] = v end
        end
    end
    return blocks[#blocks] or {}
end

function M.command(req, header_path)
    local cmd = { "curl", "-sS", "-L", "--compressed", "-m", shell_escape(req.timeout or 10) }
    local method = (req.method or "GET"):upper()
    local has_body = req.body ~= nil and (type(req.body) == "table" or tostring(req.body) ~= "")
    if method ~= "GET" and not (method == "POST" and has_body) then
        cmd[#cmd + 1] = "-X"; cmd[#cmd + 1] = shell_escape(method)
    end
    local has_ua = false
    for k, v in pairs(req.headers or {}) do
        if tostring(k):lower() == "user-agent" then has_ua = true end
        cmd[#cmd + 1] = "-H"; cmd[#cmd + 1] = shell_escape(tostring(k) .. ": " .. tostring(v))
    end
    if not has_ua then
        cmd[#cmd + 1] = "-H"
        cmd[#cmd + 1] = shell_escape("User-Agent: Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36")
    end
    if has_body then
        local body = type(req.body) == "table" and json.encode(req.body) or tostring(req.body)
        cmd[#cmd + 1] = "--data-raw"; cmd[#cmd + 1] = shell_escape(body)
    end
    if header_path then cmd[#cmd + 1] = "-D"; cmd[#cmd + 1] = shell_escape(header_path) end
    cmd[#cmd + 1] = "-w"; cmd[#cmd + 1] = shell_escape("\n__ANNO_HTTP_META__%{http_code}\n%{url_effective}\n%{exitcode}\n%{errormsg}")
    cmd[#cmd + 1] = shell_escape(req.url or "")
    return table.concat(cmd, " ")
end

local function merge_headers(inline, explicit)
    local function as_table(value)
        if type(value) == "table" then return value end
        if type(value) == "string" then
            local ok, decoded = pcall(json.decode, value)
            if ok and type(decoded) == "table" then return decoded end
        end
        return {}
    end
    local merged = {}
    for k, v in pairs(as_table(inline)) do merged[k] = v end
    for k, v in pairs(as_table(explicit)) do
        local lower = tostring(k):lower()
        for old in pairs(merged) do
            if tostring(old):lower() == lower then merged[old] = nil end
        end
        merged[k] = v
    end
    return merged
end

local function with_inline_options(req)
    local url = tostring(req.url or "")
    local base_url, options_json = url:match("^(.-),%s*(%{.*%})%s*$")
    local resolved = {}
    for k, v in pairs(req) do resolved[k] = v end
    if not base_url then
        resolved.headers = merge_headers(nil, req.headers or req.header)
        return resolved
    end
    local ok, inline = pcall(json.decode, options_json)
    if not ok or type(inline) ~= "table" then
        resolved.headers = merge_headers(nil, req.headers or req.header)
        return resolved
    end
    resolved.url = base_url
    local explicit_headers = req.headers or req.header
    local inline_headers = inline.headers or inline.header
    resolved.headers = merge_headers(inline_headers, explicit_headers)
    for _, key in ipairs({ "body", "type", "charset" }) do
        if req[key] == nil then resolved[key] = inline[key] end
    end
    if inline.method and (req.method == nil or
        (req.method == "GET" and req.method_explicit ~= true)) then
        resolved.method = inline.method
    end
    return resolved
end
M.resolve_options = with_inline_options

function M.parse_output(output, headers_raw, exit_ok, exit_code)
    local body, status, final_url, curl_exit, curl_error = (output or ""):match("^(.*)\n__ANNO_HTTP_META__(%d%d%d)\n([^\n]*)\n(%d+)\n([^\n]*)$")
    if not body then
        return { body = "", status = nil, final_url = nil, headers = {}, error = "curl failed (exit " .. tostring(exit_code or "unknown") .. "); response metadata missing" }
    end
    local result = { body = body, status = tonumber(status), final_url = final_url, headers = header_blocks(headers_raw or "") }
    result.curl_exit_code = tonumber(curl_exit)
    if result.curl_exit_code ~= 0 then
        result.error = "curl failed (exit " .. tostring(result.curl_exit_code) .. ")"
        if curl_error and curl_error ~= "" then result.error = result.error .. ": " .. curl_error end
    elseif not exit_ok then
        result.error = "curl process did not close successfully"
    end
    return result
end

local function base64_decode(input)
    local clean = input:gsub("%s", "")
    if #clean % 4 ~= 0 then return nil, "invalid base64 length" end
    local out = {}
    for i = 1, #clean, 4 do
        local a, b = clean:sub(i, i), clean:sub(i + 1, i + 1)
        local c, d = clean:sub(i + 2, i + 2), clean:sub(i + 3, i + 3)
        local va = BASE64:find(a, 1, true)
        local vb = BASE64:find(b, 1, true)
        if not va or not vb then return nil, "invalid base64 character" end
        va, vb = va - 1, vb - 1
        local vc = c == "=" and nil or BASE64:find(c, 1, true)
        local vd = d == "=" and nil or BASE64:find(d, 1, true)
        if c ~= "=" and not vc then return nil, "invalid base64 character" end
        if d ~= "=" and not vd then return nil, "invalid base64 character" end
        if c == "=" and d ~= "=" then return nil, "invalid base64 padding" end
        if (c == "=" or d == "=") and i + 3 ~= #clean then return nil, "base64 padding before end" end
        vc = vc and vc - 1 or 0
        vd = vd and vd - 1 or 0
        out[#out + 1] = string.char(va * 4 + math.floor(vb / 16))
        if c ~= "=" then out[#out + 1] = string.char((vb % 16) * 16 + math.floor(vc / 4)) end
        if d ~= "=" then out[#out + 1] = string.char((vc % 4) * 64 + vd) end
    end
    return table.concat(out)
end

local function data_uri_result(req)
    local metadata, payload = tostring(req.url or ""):match("^data:([^,]*),(.*)$")
    if not metadata then return nil end
    local bytes, err
    if metadata:lower():match(";base64") then
        bytes, err = base64_decode(payload)
    else
        local offset = 1
        while offset <= #payload do
            if payload:sub(offset, offset) == "%" then
                local hex = payload:sub(offset + 1, offset + 2)
                if #hex ~= 2 or not hex:match("^[0-9a-fA-F][0-9a-fA-F]$") then
                    return { body = "", headers = {}, error = "invalid percent escape in data URI" }
                end
                offset = offset + 3
            else
                offset = offset + 1
            end
        end
        bytes = payload:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    end
    if not bytes then return { body = "", headers = {}, error = "invalid data URI: " .. tostring(err) } end
    local body = req.type ~= nil and hex_bytes(bytes) or bytes
    return { body = body, status = 200, final_url = req.url, headers = {}, curl_exit_code = 0 }
end

function M.perform(req)
    req = with_inline_options(req or {})
    if tostring(req.url or ""):match("^data:") then
        return data_uri_result(req)
    end
    local header_path = os.tmpname()
    local handle = io.popen(M.command(req, header_path), "r")
    if not handle then os.remove(header_path); return { body = "", headers = {}, error = "Failed to spawn curl command" } end
    local output = handle:read("*a") or ""
    local ok, _, code = handle:close()
    local hf = io.open(header_path, "rb")
    local headers_raw = hf and hf:read("*a") or ""
    if hf then hf:close() end
    os.remove(header_path)
    return apply_response_type(M.parse_output(output, headers_raw, ok, code), req)
end

return M
