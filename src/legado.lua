--[[
    Legado (开源阅读) 3.0 Engine Binding for Love2D / LuaJIT
    Powered by QuickJS & C Native Bridge
]]

local ffi = require("ffi")

ffi.cdef[[
    int legado_init(void);
    void legado_free(void);
    char* legado_eval(const char* js_code);
    char* legado_parse_sources(const char* json_str);
    char* legado_build_search_req(const char* source_json, const char* keyword, int page);
    char* legado_parse_search(const char* source_json, const char* html_or_json, const char* base_url);
    char* legado_parse_book_info(const char* source_json, const char* html_or_json, const char* base_url);
    char* legado_parse_explore_categories(const char* explore_url);
    char* legado_parse_toc(const char* source_json, const char* html_or_json, const char* base_url);
    char* legado_parse_content(const char* source_json, const char* html_or_json, const char* base_url);
    void legado_free_string(char* ptr);
    void legado_set_ajax_callback(void* fn);
    void legado_set_crypto_callback(void* fn);
    char* strdup(const char* s);
]]

local M = {}
local lib = nil

local function decode_json(str)
    if not str or str == "" then return nil end
    local ok_cjson, cjson = pcall(require, "cjson")
    if ok_cjson then return cjson.decode(str) end

    local ok_j, j = pcall(require, "src.json")
    if not ok_j then ok_j, j = pcall(require, "json") end
    if ok_j and j and j.decode then
        return j.decode(str)
    end
    return nil
end

function M.load_library(path)
    if lib then return lib end
    local candidates = {}
    if path then table.insert(candidates, path) end
    if not path then
        table.insert(candidates, "src/liblegado_qjs.so")
        table.insert(candidates, "./liblegado_qjs.so")
    end

    local errs = {}
    for _, p in ipairs(candidates) do
        local ok, loaded = pcall(ffi.load, p)
        if ok then
            lib = loaded
            break
        else
            table.insert(errs, "[" .. p .. "]: " .. tostring(loaded))
        end
    end

    if not lib then
        error("Failed to load liblegado_qjs.so:\n" .. table.concat(errs, "\n"))
    end

    if lib.legado_init() ~= 1 then
        lib = nil
        error("liblegado_qjs.so loaded but legado_init() failed")
    end
    return lib
end

function M.init(path)
    M.load_library(path)
    M.register_callbacks()
    return true
end

local _callbacks_registered = false
local _ajax_cb_anchor = nil
local _crypto_cb_anchor = nil

-- Disable JIT compilation for functions invoking FFI callbacks.
-- When LuaJIT executes JIT-compiled mcode that invokes a C function, which in turn
-- calls back into Lua via an FFI callback, LuaJIT encounters `tvref(g->jit_base)`
-- and raises an unrecoverable VM panic: `PANIC: unprotected error in call to Lua API (bad callback)`.
local ok_jit, jit_mod = pcall(require, "jit")
local function protect_from_jit(fn)
    if ok_jit and jit_mod and jit_mod.off then
        pcall(jit_mod.off, fn)
    end
    return fn
end

function M.register_callbacks()
    if _callbacks_registered then return true end
    M.load_library()

    local http = require("src.http")
    local aes = require("src.aes")
    local json = require("src.json")

    local ajax_cb_fn = function(url_ptr, opts_ptr, timeout)
        local url = url_ptr ~= nil and ffi.string(url_ptr) or ""
        local opts = opts_ptr ~= nil and ffi.string(opts_ptr) or ""
        local decoded = nil
        if opts ~= "" then
            local decoded_ok, value = pcall(json.decode, opts)
            if decoded_ok and type(value) == "table" then decoded = value end
        end
        local ok, res
        if decoded and decoded._legado_response_meta == true then
            decoded._legado_response_meta = nil
            ok, res = pcall(http.request_sync_result, url, decoded, timeout)
            if ok and type(res) == "table" then
                local encoded_ok, encoded = pcall(json.encode, res)
                res = encoded_ok and encoded or ""
            else
                res = ""
            end
        else
            ok, res = pcall(http.request_sync, url, opts, timeout)
        end
        if not ok or not res then res = "" end
        return ffi.C.strdup(res)
    end
    protect_from_jit(ajax_cb_fn)
    _ajax_cb_anchor = ffi.cast("char* (*)(const char*, const char*, int)", ajax_cb_fn)

    local crypto_cb_fn = function(algo_ptr, key_ptr, iv_ptr, data_ptr, mode)
        local algo = algo_ptr ~= nil and ffi.string(algo_ptr) or ""
        local key = key_ptr ~= nil and ffi.string(key_ptr) or ""
        local iv = iv_ptr ~= nil and ffi.string(iv_ptr) or ""
        local data = data_ptr ~= nil and ffi.string(data_ptr) or ""

        local out = ""
        local ok, err = pcall(function()
            if mode == 0 then
                local ct = aes.cbc_encrypt(data, key, iv)
                if ct and #ct > 0 then
                    out = aes.base64_encode(ct)
                end
            else
                local raw = aes.base64_decode(data)
                if raw and #raw > 0 then
                    out = aes.cbc_decrypt(raw, key, iv)
                end
            end
        end)
        return ffi.C.strdup(out or "")
    end
    protect_from_jit(crypto_cb_fn)
    _crypto_cb_anchor = ffi.cast("char* (*)(const char*, const char*, const char*, const char*, int)", crypto_cb_fn)

    lib.legado_set_ajax_callback(ffi.cast("void*", _ajax_cb_anchor))
    lib.legado_set_crypto_callback(ffi.cast("void*", _crypto_cb_anchor))
    _callbacks_registered = true
    return true
end

function M.eval(js_code)
    M.load_library()
    local ptr = lib.legado_eval(js_code)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    return str
end
protect_from_jit(M.eval)

function M.parseSources(json_str)
    M.load_library()
    local ptr = lib.legado_parse_sources(json_str)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    return str
end
protect_from_jit(M.parseSources)

function M.buildSearchRequest(source_json, keyword, page)
    M.load_library()
    page = page or 1
    local ptr = lib.legado_build_search_req(source_json, keyword, page)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    return str
end
protect_from_jit(M.buildSearchRequest)

function M.parseSearch(source_json, html_or_json, base_url)
    M.load_library()
    base_url = base_url or ""
    local ptr = lib.legado_parse_search(source_json, html_or_json, base_url)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    return str
end
M.parseSearchResult = M.parseSearch
protect_from_jit(M.parseSearch)

function M.parseBookInfo(source_json, html_or_json, base_url)
    M.load_library()
    base_url = base_url or ""
    local ptr = lib.legado_parse_book_info(source_json, html_or_json, base_url)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    return str
end
protect_from_jit(M.parseBookInfo)

function M.parseExploreCategories(explore_url)
    M.load_library()
    local ptr = lib.legado_parse_explore_categories(explore_url)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    return str
end
protect_from_jit(M.parseExploreCategories)

function M.parseToc(source_json, html_or_json, base_url)
    M.load_library()
    base_url = base_url or ""
    local ptr = lib.legado_parse_toc(source_json, html_or_json, base_url)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    local obj = decode_json(str)
    if type(obj) == "table" then
        return obj
    end
    return { chapters = {}, nextTocUrl = nil }
end
protect_from_jit(M.parseToc)

function M.parseContent(source_json, html_or_json, base_url)
    M.load_library()
    base_url = base_url or ""
    local ptr = lib.legado_parse_content(source_json, html_or_json, base_url)
    local str = ffi.string(ptr)
    lib.legado_free_string(ptr)
    local obj = decode_json(str)
    if type(obj) == "table" then
        return obj
    end
    return { content = str or "", nextContentUrl = nil }
end
protect_from_jit(M.parseContent)

function M.free()
    if lib then
        lib.legado_free()
        lib = nil
    end
end

return M
