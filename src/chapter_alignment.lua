--[[
    ChapterAlignmentEngine: Smart Chapter Alignment ported from legado-windows.
    Aligns chapter indices across different book sources using chapter numbers,
    cleaned subtitles, and UTF-8 Levenshtein distance similarity.
]]

local ca = {}

local digit_map = {
    ["零"] = 0, ["一"] = 1, ["二"] = 2, ["两"] = 2, ["三"] = 3,
    ["四"] = 4, ["五"] = 5, ["六"] = 6, ["七"] = 7, ["八"] = 8, ["九"] = 9
}

local unit_map = {
    ["十"] = 10, ["百"] = 100, ["千"] = 1000, ["万"] = 10000
}

-- UTF-8 characters iterator
local function utf8_chars(s)
    local t = {}
    local p = 1
    local len = #s
    while p <= len do
        local b = s:byte(p)
        local w = 1
        if b >= 240 then w = 4
        elseif b >= 224 then w = 3
        elseif b >= 192 then w = 2
        end
        table.insert(t, s:sub(p, p + w - 1))
        p = p + w
    end
    return t
end

function ca.parse_chinese_number(str)
    if not str or str == "" then return nil end
    local clean = str:gsub("^%s+", ""):gsub("%s+$", ""):gsub("两", "二")
    if clean == "零" then return 0 end

    local chars = utf8_chars(clean)
    local total = 0
    local currentSection = 0
    local currentDigit = 0
    local hasDigit = false

    for _, ch in ipairs(chars) do
        if digit_map[ch] then
            currentDigit = digit_map[ch]
            hasDigit = true
        elseif unit_map[ch] then
            local unit = unit_map[ch]
            if unit == 10000 then
                currentSection = (currentSection + (hasDigit and currentDigit or 1)) * unit
                total = total + currentSection
                currentSection = 0
                currentDigit = 0
                hasDigit = false
            else
                currentSection = currentSection + (hasDigit and currentDigit or 1) * unit
                currentDigit = 0
                hasDigit = false
            end
        else
            return nil
        end
    end
    total = total + currentSection + currentDigit
    return total > 0 and total or nil
end

local CHAPTER_SUFFIXES = { "章", "回", "集", "卷", "部", "篇" }

function ca.extract_chapter_number(title)
    if not title or title == "" then return nil end
    local t = title:gsub("^%s+", ""):gsub("%s+$", "")

    -- 1. "第 105 章/回/集/卷/部/篇"
    for _, suf in ipairs(CHAPTER_SUFFIXES) do
        local num = t:match("^%s*第%s*(%d+)%s*" .. suf)
        if num then return tonumber(num) end
    end

    -- 2. "第 一百零五 章/回/集/卷/部/篇"
    for _, suf in ipairs(CHAPTER_SUFFIXES) do
        local zh_num = t:match("^%s*第%s*(.-)%s*" .. suf)
        if zh_num and #zh_num > 0 then
            local val = ca.parse_chinese_number(zh_num)
            if val then return val end
        end
    end

    -- 3. Leading number "105. 决战" or "105 决战" or "105、决战"
    local lead_num = t:match("^%s*(%d+)%s*[%._%s%-%:：]")
    if lead_num then return tonumber(lead_num) end

    return nil
end

function ca.clean_subtitle(title)
    if not title then return "" end
    local s = title:gsub("^%s+", ""):gsub("%s+$", "")

    -- Remove parenthetical content
    s = s:gsub("%b()", ""):gsub("（[^）]*）", ""):gsub("%b[]", ""):gsub("【[^】]*】", ""):gsub("%b{}", "")

    -- Remove volume prefix e.g. "第一卷", "卷一", "正文卷", "VIP卷"
    s = s:gsub("^第?%d+卷%s*", "")
    for _, suf in ipairs(CHAPTER_SUFFIXES) do
        local pre = s:match("^第%s*(.-)%s*" .. suf .. "%s*")
        if pre and #pre > 0 then
            s = s:gsub("^第%s*.-%s*" .. suf .. "%s*", "")
            break
        end
    end
    s = s:gsub("^[正外番]文卷%s*", "")
    s = s:gsub("^VIP卷%s*", "")
    s = s:gsub("^%s*%d+%s*[%._%s%-%:：%s]*", "")

    -- Remove non-word noise and punctuation
    s = s:gsub("[·•_—%-%s\r\n\t]+", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

function ca.similarity(s1, s2)
    if s1 == s2 then return 1.0 end
    if not s1 or not s2 or #s1 == 0 or #s2 == 0 then return 0.0 end

    local c1 = utf8_chars(s1)
    local c2 = utf8_chars(s2)
    local len1, len2 = #c1, #c2
    if len1 == 0 or len2 == 0 then return 0.0 end
    if len1 > 40 then len1 = 40 end
    if len2 > 40 then len2 = 40 end

    local dp = {}
    for i = 0, len1 do
        dp[i] = {}
        dp[i][0] = i
    end
    for j = 0, len2 do
        dp[0][j] = j
    end

    for i = 1, len1 do
        for j = 1, len2 do
            local cost = (c1[i] == c2[j]) and 0 or 1
            dp[i][j] = math.min(
                dp[i - 1][j] + 1,
                dp[i][j - 1] + 1,
                dp[i - 1][j - 1] + cost
            )
        end
    end

    local dist = dp[len1][len2]
    local maxLen = math.max(len1, len2)
    return math.max(0.0, math.min(1.0, 1.0 - (dist / maxLen)))
end

function ca.align(currentTitle, currentIndex, candidates)
    if not candidates or #candidates == 0 then
        return {
            index = 0,
            chapter = { url = "", title = currentTitle or "", index = 0 },
            confidence = 0.0,
            strategy = "候选章节列表为空"
        }
    end

    local cleanCurrent = ca.clean_subtitle(currentTitle or "")
    local currentNum = ca.extract_chapter_number(currentTitle or "")

    -- 1. Exact raw title match
    for idx = 1, #candidates do
        local ch = candidates[idx]
        if ch.title and currentTitle and ch.title:gsub("%s+", "") == currentTitle:gsub("%s+", "") then
            return {
                index = idx - 1, -- 0-based
                chapter = ch,
                confidence = 1.0,
                strategy = "精确标题完全匹配"
            }
        end
    end

    -- 2. Clean subtitle match + Chapter Number match
    local bestIdx = -1
    local bestScore = -1.0
    local bestStrategy = ""

    for idx = 1, #candidates do
        local ch = candidates[idx]
        local candTitle = ch.title or ""
        local candClean = ca.clean_subtitle(candTitle)
        local candNum = ca.extract_chapter_number(candTitle)

        local score = 0.0
        local strategy = ""

        if currentNum and candNum and currentNum == candNum then
            if cleanCurrent == candClean or #cleanCurrent == 0 or #candClean == 0 then
                score = 0.98
                strategy = string.format("章节序号一致 (%d) 且标题高度契合", currentNum)
            else
                local sim = ca.similarity(cleanCurrent, candClean)
                if sim >= 0.7 then
                    score = 0.98
                    strategy = string.format("章节序号一致 (%d) 且标题高度契合", currentNum)
                else
                    score = 0.92 + (sim * 0.05)
                    strategy = string.format("章节序号一致 (%d)", currentNum)
                end
            end
        elseif #cleanCurrent > 0 and #candClean > 0 then
            if cleanCurrent == candClean then
                score = 0.95
                strategy = string.format("核心章节标题完全一致 (%s)", cleanCurrent)
            elseif cleanCurrent:find(candClean, 1, true) or candClean:find(cleanCurrent, 1, true) then
                score = 0.82
                strategy = "章节标题包含匹配"
            else
                local sim = ca.similarity(cleanCurrent, candClean)
                if sim >= 0.8 then
                    score = 0.80 + (sim * 0.15)
                    strategy = string.format("标题相似度极高 (%d%%)", math.floor(sim * 100))
                end
            end
        end

        -- Proximity bonus if candidate index is close to currentIndex (0-based)
        local diff = math.abs((idx - 1) - currentIndex)
        if diff <= 3 and score > 0.7 then
            score = math.min(1.0, score + 0.03)
        end

        if score > bestScore then
            bestScore = score
            bestIdx = idx - 1
            bestStrategy = strategy
            if bestScore >= 0.98 then
                break -- Fast break on very high confidence match
            end
        end
    end

    if bestIdx >= 0 and bestScore >= 0.7 then
        return {
            index = bestIdx,
            chapter = candidates[bestIdx + 1],
            confidence = bestScore,
            strategy = bestStrategy
        }
    end

    -- 3. Fallback: Proximity by current index
    local fallbackIdx = math.max(0, math.min(currentIndex, #candidates - 1))
    local fallbackCh = candidates[fallbackIdx + 1]
    local fallbackClean = ca.clean_subtitle(fallbackCh.title or "")
    local fallbackSim = ca.similarity(cleanCurrent, fallbackClean)

    return {
        index = fallbackIdx,
        chapter = fallbackCh,
        confidence = math.max(0.3, math.min(0.65, 0.4 + fallbackSim * 0.2)),
        strategy = string.format("序号位置保底推荐 (第 %d 章)", fallbackIdx + 1)
    }
end

return ca
