-- Convert legacy source response encodings to UTF-8 before rule parsing.
local M = {}
local ok, ffi = pcall(require, "ffi")
if ok then
    ffi.cdef[[
        void *iconv_open(const char *tocode, const char *fromcode);
        size_t iconv(void *cd, char **inbuf, size_t *inbytesleft,
                     char **outbuf, size_t *outbytesleft);
        int iconv_close(void *cd);
    ]]
end

function M.convert(body, charset)
    charset = tostring(charset or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if charset == "" or charset == "utf-8" or charset == "utf8" then return body end
    if charset == "gb2312" or charset == "gbk" or charset == "gb-2312" then charset = "GB18030" end
    if not ok then return nil, "iconv requires LuaJIT FFI" end
    local cd = ffi.C.iconv_open("UTF-8", charset)
    if cd == ffi.cast("void *", -1) then return nil, "unsupported charset: " .. charset end
    local input = ffi.new("char[?]", #body + 1)
    ffi.copy(input, body, #body)
    local input_ptr = ffi.new("char *[1]", input)
    local input_left = ffi.new("size_t[1]", #body)
    local capacity = #body * 4 + 32
    local output = ffi.new("char[?]", capacity)
    local output_ptr = ffi.new("char *[1]", output)
    local output_left = ffi.new("size_t[1]", capacity)
    local result = ffi.C.iconv(cd, input_ptr, input_left, output_ptr, output_left)
    ffi.C.iconv_close(cd)
    if result == ffi.cast("size_t", -1) or input_left[0] ~= 0 then
        return nil, "invalid " .. charset .. " response bytes"
    end
    return ffi.string(output, capacity - tonumber(output_left[0]))
end

return M
