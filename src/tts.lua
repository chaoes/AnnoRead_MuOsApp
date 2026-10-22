-- src/tts.lua
-- MiMo-V2.5-TTS voice synthesis and paragraph reading engine for AnnoRead.
-- Features:
--   - Integrates Xiaomi MiMo-V2.5-TTS via Token Plan OpenAI-compatible endpoint.
--   - Configurable preset voice, voice style, speed, and relative pitch.
--   - Paragraph-by-paragraph pipelined synthesis with persistent disk caching.
--   - Chapter prefetch: synthesizes current paragraphs and pre-fetches next chapter.
--   - Obsolete cache cleanup & old request cancellation on chapter jump / stop.
--   - Real-time progress tracking for automatic page turning and paragraph highlight.

local M = {}
local json = require("src.json")
local http = require("src.http")
local aes = require("src.aes")
local tts_cache = require("src.tts_cache")

local tts_config = require("src.tts_config")
local DEFAULT_API_URL = "https://token-plan-cn.xiaomimimo.com/v1/chat/completions"
local DEFAULT_MODEL = "mimo-v2.5-tts"
local DEFAULT_PROMPT = "请用自然流畅的普通话朗读小说，保持叙事连贯，停顿得体。"

local PREFETCH_AHEAD = 2

local state = "idle" -- "idle" | "loading" | "playing" | "paused"
local config = tts_config.load()
local api_key = config.api_key
local api_url = DEFAULT_API_URL
local model = DEFAULT_MODEL
local voice = config.voice
local voice_style = config.voice_style
local speed = config.speed
local pitch = config.pitch
local tone_prompt = DEFAULT_PROMPT
local volume = 1.0 -- Software playback volume (0.1 - 2.0, default 1.0)
local HARDWARE_PCM_BOOST = 3.2 -- Hardware pre-amplification boost for MiMo TTS output (boost low master volume on device)

local current_book_key = "default_book"
local chapters = {}
local chapter_idx = 1
local paragraphs = {}
local current_para_idx = 1
local current_source = nil
local current_duration = 0
local session_id = 0

-- Audio memory cache: para_idx -> { source = Source, duration = number }
local audio_cache = {}
-- In-flight request IDs: para_idx -> req_id
local pending_requests = {}

-- Next chapter background prefetch state
local next_ch_prefetch = {
    book_key = nil,
    chapter_idx = 0,
    paragraphs = {},
    ptr = 1,
    active_req = nil,
    session = 0
}

local callbacks = {
    on_para_change = nil,
    on_progress = nil,
    on_chapter_complete = nil,
    on_error = nil,
    on_status = nil,
}

local function style_prompt()
    local parts = { tone_prompt }
    if voice_style ~= "" then
        parts[#parts + 1] = "音色风格：" .. voice_style .. "。"
    end

    local pace = "自然适中"
    if speed < 0.75 then pace = "明显放慢"
    elseif speed < 0.95 then pace = "稍慢"
    elseif speed > 1.4 then pace = "明显加快"
    elseif speed > 1.05 then pace = "稍快" end
    parts[#parts + 1] = string.format("语速%s，目标约为正常语速的 %.2f 倍，停顿自然。", pace, speed)

    local pitch_text = ({
        [-2] = "整体音高明显偏低。",
        [-1] = "整体音高略低。",
        [0] = "整体音高自然。",
        [1] = "整体音高略高。",
        [2] = "整体音高明显偏高。",
    })[pitch]
    parts[#parts + 1] = pitch_text
    return table.concat(parts, " ")
end

local function cache_variant()
    return model .. "\0" .. voice .. "\0" .. style_prompt()
end

local function request_payload(text)
    return {
        model = model,
        messages = {
            { role = "user", content = style_prompt() },
            { role = "assistant", content = text }
        },
        audio = { format = "wav", voice = voice }
    }
end

function M.decode_base64(b64_str)
    if not b64_str or b64_str == "" then return "" end
    if love and love.data and love.data.decode then
        local ok, raw = pcall(love.data.decode, "string", "base64", b64_str)
        if ok and raw then return raw end
    end
    return aes.base64_decode(b64_str)
end

--- Boost 16-bit PCM WAV audio data by multiplying sample amplitudes.
-- Uses an analog soft-knee limiter above 30000 to eliminate digital clipping distortion
-- while raising perceived loudness significantly on small handheld speakers.
function M.amplify_wav(wav_bytes, gain)
    if not wav_bytes or #wav_bytes < 44 then return wav_bytes end
    if string.sub(wav_bytes, 1, 4) ~= "RIFF" or string.sub(wav_bytes, 9, 12) ~= "WAVE" then
        return wav_bytes
    end
    if not gain or (gain <= 1.01 and gain >= 0.99) then return wav_bytes end

    local len = #wav_bytes
    local data_start = nil
    local data_len = 0
    local pos = 12
    while pos + 8 <= len do
        local id = string.sub(wav_bytes, pos + 1, pos + 4)
        local b1, b2, b3, b4 = string.byte(wav_bytes, pos + 5, pos + 8)
        if not (b1 and b2 and b3 and b4) then break end
        local sz = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        if id == "data" then
            data_start = pos + 8
            data_len = sz
            break
        end
        pos = pos + 8 + sz
    end

    if not data_start or data_len <= 0 then return wav_bytes end

    local ffi_ok, ffi = pcall(require, "ffi")
    if ffi_ok and ffi then
        local buf = ffi.new("uint8_t[?]", len)
        ffi.copy(buf, wav_bytes, len)
        local samples = ffi.cast("int16_t*", buf + data_start)
        local n_samples = math.floor(data_len / 2)
        for i = 0, n_samples - 1 do
            local s = samples[i] * gain
            if s > 30000 then
                local excess = s - 30000
                s = 30000 + 2767 * (excess / (excess + 2767))
            elseif s < -30000 then
                local excess = -s - 30000
                s = -(30000 + 2767 * (excess / (excess + 2767)))
            end
            if s > 32767 then s = 32767
            elseif s < -32768 then s = -32768 end
            samples[i] = s
        end
        return ffi.string(buf, len)
    end
    return wav_bytes
end

function M.create_audio_source(raw_wav_bytes)
    if not raw_wav_bytes or #raw_wav_bytes == 0 then return nil, 0 end

    -- Ensure master audio output is at maximum gain
    if love and love.audio and love.audio.setVolume then
        pcall(love.audio.setVolume, 1.0)
    end

    -- Apply PCM hardware pre-amplification boost + software volume scale
    local final_wav = raw_wav_bytes
    local total_gain = (HARDWARE_PCM_BOOST or 1.0) * math.max(1.0, volume)
    if total_gain > 1.05 then
        final_wav = M.amplify_wav(raw_wav_bytes, total_gain)
    end

    local norm_vol = math.min(1.0, volume)

    if not (love and love.filesystem and love.audio) then
        -- Return a mock structure in headless environments
        local mock = {
            _playing = false,
            _pos = 0,
            _dur = 2.0,
            _vol = norm_vol,
            play = function(self) self._playing = true end,
            stop = function(self) self._playing = false; self._pos = 0 end,
            pause = function(self) self._playing = false end,
            isPlaying = function(self) return self._playing end,
            tell = function(self) return self._pos end,
            getDuration = function(self) return self._dur end,
            setVolume = function(self, v) self._vol = v end,
            getVolume = function(self) return self._vol end,
        }
        return mock, 2.0
    end

    local ok_fd, fileData = pcall(love.filesystem.newFileData, final_wav, "tts_para.wav")
    if not ok_fd or not fileData then return nil, 0 end

    local ok_src, source = pcall(love.audio.newSource, fileData, "static")
    if ok_src and source then
        if source.setVolume then
            source:setVolume(norm_vol)
        end
        local dur = 0
        if source.getDuration then
            dur = source:getDuration()
        end
        return source, dur
    end
    return nil, 0
end

local function cancel_all_in_flight()
    -- Clear pending requests map and abort waiting callbacks
    pending_requests = {}
    next_ch_prefetch.active_req = nil
    next_ch_prefetch.paragraphs = {}
end

local function step_next_chapter_prefetch()
    if state == "idle" then return end
    if next_ch_prefetch.session ~= session_id then return end
    if next_ch_prefetch.active_req then return end
    local paras = next_ch_prefetch.paragraphs
    if not paras or #paras == 0 then return end
    if next_ch_prefetch.ptr > #paras then return end

    local p_idx = next_ch_prefetch.ptr
    local text = paras[p_idx]
    if not text or #text == 0 then
        next_ch_prefetch.ptr = p_idx + 1
        step_next_chapter_prefetch()
        return
    end

    local b_key = next_ch_prefetch.book_key
    local c_idx = next_ch_prefetch.chapter_idx
    local variant = cache_variant()

    if api_key == "" then return end

    -- If already cached on disk, skip to next paragraph
    if tts_cache.is_cached(b_key, c_idx, p_idx, text, variant) then
        next_ch_prefetch.ptr = p_idx + 1
        step_next_chapter_prefetch()
        return
    end

    local req_body = json.encode(request_payload(text))
    local headers = {
        ["api-key"] = api_key,
        ["Content-Type"] = "application/json"
    }

    local cur_session = session_id
    local req_id = http.request_async({
        url = api_url,
        method = "POST",
        headers = headers,
        body = req_body,
        timeout = 25
    }, function(resp, tag, req_payload)
        if next_ch_prefetch.session ~= cur_session or cur_session ~= session_id or state == "idle" then
            return
        end
        next_ch_prefetch.active_req = nil

        if resp and #resp > 0 then
            local ok, data = pcall(json.decode, resp)
            if ok and data and data.choices and data.choices[1] then
                local audio_obj = data.choices[1].message and data.choices[1].message.audio
                if audio_obj and audio_obj.data then
                    local wav_bytes = M.decode_base64(audio_obj.data)
                    if wav_bytes and #wav_bytes > 0 then
                        tts_cache.save_audio(b_key, c_idx, p_idx, text, wav_bytes, variant)
                    end
                end
            end
        end

        next_ch_prefetch.ptr = p_idx + 1
        step_next_chapter_prefetch()
    end)

    next_ch_prefetch.active_req = req_id
end

function M.set_next_chapter_prefetch(ch_idx, paras)
    if state == "idle" then return end
    next_ch_prefetch.book_key = current_book_key
    next_ch_prefetch.chapter_idx = ch_idx
    next_ch_prefetch.paragraphs = paras or {}
    next_ch_prefetch.ptr = 1
    next_ch_prefetch.session = session_id
    if not next_ch_prefetch.active_req then
        step_next_chapter_prefetch()
    end
end

local function prefetch_paragraph(p_idx, req_session)
    if p_idx > #paragraphs then return end
    if audio_cache[p_idx] or pending_requests[p_idx] then return end

    local text = paragraphs[p_idx]
    if not text or #text == 0 then return end
    local variant = cache_variant()

    -- 1. Check disk storage cache first!
    if tts_cache.is_cached(current_book_key, chapter_idx, p_idx, text, variant) then
        local raw_wav = tts_cache.get_audio(current_book_key, chapter_idx, p_idx, text, variant)
        if raw_wav and #raw_wav > 0 then
            local src, dur = M.create_audio_source(raw_wav)
            if src then
                audio_cache[p_idx] = { source = src, duration = dur }
                if state == "loading" and current_para_idx == p_idx then
                    M.play_current_paragraph()
                end
                return
            end
        end
    end

    -- 2. Request synthesis via HTTP
    if api_key == "" then
        if p_idx == current_para_idx and state == "loading" then
            M.handle_error("未配置 MiMo TTS API Key，请填写 mimo_tts.json")
        end
        return
    end

    local req_body = json.encode(request_payload(text))
    local headers = {
        ["api-key"] = api_key,
        ["Content-Type"] = "application/json"
    }

    local req_id = http.request_async({
        url = api_url,
        method = "POST",
        headers = headers,
        body = req_body,
        timeout = 25
    }, function(resp, tag, req_payload)
        pending_requests[p_idx] = nil
        if req_session ~= session_id or state == "idle" then
            return -- Request cancelled or superseded
        end

        if not resp or #resp == 0 then
            if p_idx == current_para_idx and state == "loading" then
                M.handle_error("语音合成请求超时或网络异常")
            end
            return
        end

        local ok, data = pcall(json.decode, resp)
        if not ok or not data or not data.choices or not data.choices[1] then
            if p_idx == current_para_idx and state == "loading" then
                local err_msg = "语音数据解析失败"
                if type(data) == "table" and data.error and data.error.message then
                    err_msg = tostring(data.error.message)
                end
                M.handle_error("语音合成错误: " .. err_msg)
            end
            return
        end

        local audio_obj = data.choices[1].message and data.choices[1].message.audio
        if not audio_obj or not audio_obj.data then
            if p_idx == current_para_idx and state == "loading" then
                M.handle_error("未返回有效语音数据")
            end
            return
        end

        local wav_bytes = M.decode_base64(audio_obj.data)
        if not wav_bytes or #wav_bytes == 0 then
            if p_idx == current_para_idx and state == "loading" then
                M.handle_error("语音Base64解码失败")
            end
            return
        end

        -- Save to persistent storage cache immediately
        tts_cache.save_audio(current_book_key, chapter_idx, p_idx, text, wav_bytes, variant)

        local src, dur = M.create_audio_source(wav_bytes)
        if not src then
            if p_idx == current_para_idx and state == "loading" then
                M.handle_error("初始化音频播放失败")
            end
            return
        end

        audio_cache[p_idx] = { source = src, duration = dur }

        if state == "loading" and current_para_idx == p_idx then
            M.play_current_paragraph()
        end
    end)

    pending_requests[p_idx] = req_id
end

function M.handle_error(err_msg)
    state = "idle"
    M.stop_playback_only()
    if callbacks.on_error then
        callbacks.on_error(err_msg)
    end
end

function M.play_current_paragraph()
    if state == "idle" then return end

    local cached = audio_cache[current_para_idx]
    if not cached then
        state = "loading"
        prefetch_paragraph(current_para_idx, session_id)
        return
    end

    if current_source then
        pcall(function() current_source:stop() end)
        current_source = nil
    end

    current_source = cached.source
    if current_source and current_source.setVolume then
        current_source:setVolume(volume)
    end
    current_duration = cached.duration or (current_source.getDuration and current_source:getDuration() or 1.0)
    state = "playing"

    if current_source.play then
        current_source:play()
    end

    if callbacks.on_para_change then
        callbacks.on_para_change(current_para_idx, #paragraphs)
    end

    -- Trigger prefetch for upcoming paragraphs
    for i = 1, PREFETCH_AHEAD do
        prefetch_paragraph(current_para_idx + i, session_id)
    end

    -- Evict older paragraphs from memory
    for idx, item in pairs(audio_cache) do
        if idx < current_para_idx - 1 then
            if item.source and item.source.stop then
                pcall(function() item.source:stop() end)
            end
            audio_cache[idx] = nil
        end
    end
end

function M.stop_playback_only()
    if current_source then
        pcall(function() current_source:stop() end)
        current_source = nil
    end
    if love and love.audio and love.audio.stop then
        pcall(love.audio.stop)
    end
end

function M.init(cbs)
    cbs = cbs or {}
    callbacks.on_para_change = cbs.on_para_change
    callbacks.on_progress = cbs.on_progress
    callbacks.on_chapter_complete = cbs.on_chapter_complete
    callbacks.on_error = cbs.on_error
    callbacks.on_status = cbs.on_status
    tts_cache.init()
end

function M.set_callbacks(cbs)
    M.init(cbs)
end

function M.set_book_key(bk)
    current_book_key = bk or current_book_key
end

function M.get_book_key()
    return current_book_key
end

function M.start(chaps, ch_idx, paras, start_para, cbs, bk_param)
    -- Flexible signature handling:
    -- Form 1: M.start(chapters, chapter_idx, paragraphs, start_para, callbacks, book_key)
    -- Form 2: M.start(paragraphs, start_para, callbacks, book_key)
    local bk = bk_param
    if type(chaps) == "table" and (chaps[1] == nil or type(chaps[1]) == "string") and type(ch_idx) == "number" and (type(paras) == "table" or paras == nil) then
        if type(paras) == "table" and (paras.on_para_change or paras.on_status or paras.on_chapter_complete or paras.on_error) then
            -- Form 2: M.start(paragraphs, start_para, callbacks, book_key)
            bk = start_para
            cbs = paras
            paras = chaps
            start_para = ch_idx
            chaps = {}
            ch_idx = 1
        end
    end
    if cbs then
        M.set_callbacks(cbs)
    end

    if type(bk) == "string" and #bk > 0 then
        current_book_key = bk
    end

    session_id = session_id + 1
    M.stop_playback_only()
    cancel_all_in_flight()
    audio_cache = {}

    chapters = chaps or {}
    chapter_idx = ch_idx or 1
    paragraphs = paras or {}
    current_para_idx = math.max(1, math.min(start_para or 1, math.max(1, #paragraphs)))

    -- Clean up obsolete audio files: keep only current and next chapter
    tts_cache.cleanup_obsolete(current_book_key, chapter_idx, chapter_idx + 1)

    if #paragraphs == 0 then
        state = "idle"
        if callbacks.on_error then
            callbacks.on_error("当前章节无段落内容可供朗读")
        end
        return
    end

    state = "loading"
    M.play_current_paragraph()
end

function M.set_chapter_content(ch_idx, paras, start_para, bk)
    session_id = session_id + 1
    M.stop_playback_only()
    cancel_all_in_flight()
    audio_cache = {}

    if bk then current_book_key = bk end
    chapter_idx = ch_idx or chapter_idx
    paragraphs = paras or {}
    current_para_idx = math.max(1, math.min(start_para or 1, math.max(1, #paragraphs)))

    -- Clean up obsolete audio files for previous chapters
    tts_cache.cleanup_obsolete(current_book_key, chapter_idx, chapter_idx + 1)

    if #paragraphs == 0 then
        state = "idle"
        return
    end

    if state ~= "idle" then
        state = "loading"
        M.play_current_paragraph()
    end
end

function M.stop()
    session_id = session_id + 1
    state = "idle"
    M.stop_playback_only()
    cancel_all_in_flight()
    for idx, item in pairs(audio_cache) do
        if item.source and item.source.stop then
            pcall(function() item.source:stop() end)
        end
    end
    if love and love.audio and love.audio.stop then
        pcall(love.audio.stop)
    end
    audio_cache = {}
end

function M.pause()
    if state == "playing" and current_source then
        if current_source.pause then
            current_source:pause()
        end
        state = "paused"
    end
end

function M.resume()
    if state == "paused" and current_source then
        if current_source.play then
            current_source:play()
        end
        state = "playing"
    elseif state == "idle" and #paragraphs > 0 then
        M.start(chapters, chapter_idx, paragraphs, current_para_idx)
    end
end

function M.update(dt)
    if state == "loading" then
        return
    end

    if state ~= "playing" or not current_source then
        return
    end

    local is_playing = false
    if current_source.isPlaying then
        is_playing = current_source:isPlaying()
    end

    if is_playing then
        if callbacks.on_progress and current_source.tell and current_duration > 0 then
            local pos = current_source:tell()
            local prog = math.max(0, math.min(1, pos / current_duration))
            callbacks.on_progress(current_para_idx, prog)
        end
    else
        -- Current paragraph finished!
        if current_para_idx < #paragraphs then
            current_para_idx = current_para_idx + 1
            M.play_current_paragraph()
        else
            -- Chapter completed!
            M.stop_playback_only()
            if callbacks.on_chapter_complete then
                callbacks.on_chapter_complete(chapter_idx + 1)
            end
        end
    end
end

-- State inspections
function M.is_active()
    return state == "playing" or state == "loading" or state == "paused"
end

function M.is_playing()
    return state == "playing"
end

function M.is_loading()
    return state == "loading"
end

function M.is_paused()
    return state == "paused"
end

function M.get_state()
    return state
end

function M.get_current_para()
    return current_para_idx
end

function M.get_total_paras()
    return #paragraphs
end

function M.get_current_chapter()
    return chapter_idx
end

function M.get_progress()
    if state == "playing" and current_source and current_source.tell and current_duration > 0 then
        return math.max(0, math.min(1, current_source:tell() / current_duration))
    end
    return 0
end

-- Configuration getters & setters
function M.set_api_key(k) api_key = type(k) == "string" and k:gsub("^%s+", ""):gsub("%s+$", "") or "" end
function M.get_api_key() return api_key end
function M.set_voice(v) voice = tts_config.normalize({ voice = v }).voice end
function M.get_voice() return voice end
function M.set_model(m) if type(m) == "string" and m ~= "" then model = m end end
function M.get_model() return model end
function M.set_tone_prompt(p) tone_prompt = type(p) == "string" and p ~= "" and p or DEFAULT_PROMPT end
function M.get_tone_prompt() return tone_prompt end
function M.set_voice_style(v) voice_style = tts_config.normalize({ voice_style = v }).voice_style end
function M.get_voice_style() return voice_style end
function M.set_speed(v) speed = tts_config.normalize({ speed = v }).speed end
function M.get_speed() return speed end
function M.set_pitch(v) pitch = tts_config.normalize({ pitch = v }).pitch end
function M.get_pitch() return pitch end
function M.get_style_prompt() return style_prompt() end
function M.get_cache_variant() return cache_variant() end
function M.set_volume(v)
    volume = math.max(0.1, math.min(2.0, tonumber(v) or 1.0))
    if current_source and current_source.setVolume then
        current_source:setVolume(math.min(1.0, volume))
    end
end
function M.get_volume() return volume end

return M
