local pinyin = require("src.pinyin_dict")

print("--- Testing Pinyin Dictionary Comprehensive ---")
local cands_ni = pinyin.get_candidates("ni")
assert(cands_ni and #cands_ni > 0, "Candidates for 'ni' should exist")
assert(cands_ni[1] == "你", "Top candidate for 'ni' should be '你'")

-- Test 'zai' should have '在' and '再' in top 3
local cands_zai = pinyin.get_candidates("zai")
assert(cands_zai and #cands_zai >= 2, "Candidates for 'zai' should exist")
assert(cands_zai[1] == "在", "Top 1 for 'zai' should be '在'")
assert(cands_zai[2] == "再", "Top 2 for 'zai' should be '再'")

-- Test other essential common words
local cands_de = pinyin.get_candidates("de")
assert(cands_de[1] == "的", "Top candidate for 'de' should be '的'")

local cands_shi = pinyin.get_candidates("shi")
assert(cands_shi[1] == "是", "Top candidate for 'shi' should be '是'")

local cands_xian = pinyin.get_candidates("xian")
assert(cands_xian and #cands_xian > 0, "Candidates for 'xian' should exist")
assert(cands_xian[1] == "先" or cands_xian[1] == "现" or cands_xian[1] == "仙", "Top for 'xian' should be valid common char")

local cands_empty = pinyin.get_candidates("xyz123")
assert(#cands_empty == 0, "Invalid syllable should return empty list")

print("Pinyin comprehensive tests passed!")
