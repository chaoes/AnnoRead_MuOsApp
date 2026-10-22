package.path = package.path .. ";./src/?.lua"
local ca = require("chapter_alignment")

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)))
    end
end

print("=== Running Chapter Alignment Unit Tests ===")

assertEq(ca.parse_chinese_number("一百零五"), 105, "中文数字")
assertEq(ca.extract_chapter_number("第105章 决战天门山"), 105, "阿拉伯章节号")
assertEq(ca.extract_chapter_number("第一百零五章 决战"), 105, "中文章节号")
assertEq(ca.clean_subtitle("第105章 决战天门山 (求月票)"), "决战天门山", "净化副标题")
assert(ca.similarity("决战天门山", "决战天门山") == 1.0, "完全相似")

-- 对齐：序号一致应高置信度命中 (0-based index 1 for 2nd candidate)
local cands = {
    { title = "第1章 起", url = "u1" },
    { title = "第105章 决战天门山", url = "u2" },
    { title = "第106章 承", url = "u3" }
}
local r = ca.align("第105章 决战天门山", 104, cands)
assertEq(r.index, 1, "应对齐到第105章")
assert(r.confidence >= 0.9, "置信度应高")

-- 纯中文标题（无编号）应回退位置就近且低置信度
local r2 = ca.align("终章", 2, cands)
assert(r2.confidence < 0.7, "无编号应低置信度")

print("✔ Chapter Alignment Unit Tests passed successfully!")
