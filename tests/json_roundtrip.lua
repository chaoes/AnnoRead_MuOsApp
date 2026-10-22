package.path = "./?.lua;./?/init.lua;" .. package.path
local json = require("src.json")

local input_path, output_path = arg[1], arg[2]
assert(input_path and output_path, "usage: json_roundtrip.lua INPUT OUTPUT")
local input = assert(io.open(input_path, "rb")):read("*a")
local value, decode_error = json.decode(input)
if arg[3] == "expect-error" then
    assert(value == nil and decode_error and decode_error:find("invalid string escape", 1, true),
        "invalid JSON escape did not produce a useful error")
    return
end
assert(value ~= nil, "JSON decode failed: " .. tostring(decode_error))
local output = assert(io.open(output_path, "wb"))
assert(output:write(json.encode(value)))
assert(output:close())
