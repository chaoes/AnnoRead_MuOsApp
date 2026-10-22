-- Read the MiMo credential from a local JSON file. The save directory takes
-- precedence so a handheld installation can keep its key across app updates.
local json = require("src.json")

local M = {}
M.DEFAULT_VOICE = "茉莉"
M.DEFAULT_VOICE_STYLE = "清冷、干净的青年女声，音色清透，略带柔和的磁性；咬字轻盈清晰，情绪含蓄却有层次，像在静夜里从容讲述故事"
M.DEFAULT_SPEED = 1.12
M.DEFAULT_PITCH = -1

local function read_file(path)
    if love and love.filesystem and love.filesystem.read then
        local ok, contents = pcall(love.filesystem.read, path)
        if ok and type(contents) == "string" then return contents end
        return nil
    end

    local file = io.open(path, "rb")
    if not file then return nil end
    local contents = file:read("*a")
    file:close()
    return contents
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function M.normalize(raw)
    raw = type(raw) == "table" and raw or {}
    local speed = type(raw.speed) == "number" and raw.speed or M.DEFAULT_SPEED
    if speed < 0.5 or speed > 2.0 then speed = M.DEFAULT_SPEED end
    local pitch = type(raw.pitch) == "number" and raw.pitch or M.DEFAULT_PITCH
    if pitch < -2 or pitch > 2 or pitch ~= math.floor(pitch) then pitch = M.DEFAULT_PITCH end

    local voice = trim(raw.voice)
    return {
        api_key = trim(raw.api_key),
        voice = voice ~= "" and voice or M.DEFAULT_VOICE,
        voice_style = raw.voice_style == nil and M.DEFAULT_VOICE_STYLE or trim(raw.voice_style),
        speed = speed,
        pitch = pitch,
    }
end

function M.load()
    local merged = {}
    -- Apply bundled defaults first, then the persistent user override.
    for _, path in ipairs({ "config/mimo_tts.json", "mimo_tts.json" }) do
        local contents = read_file(path)
        if contents then
            local ok, config = pcall(json.decode, contents)
            if ok and type(config) == "table" then
                for key, value in pairs(config) do
                    if key ~= "api_key" or trim(value) ~= "" then
                        merged[key] = value
                    end
                end
            end
        end
    end

    local env_key = trim(os.getenv("MIMO_TTS_API_KEY"))
    if env_key ~= "" then merged.api_key = env_key end
    return M.normalize(merged)
end

return M
