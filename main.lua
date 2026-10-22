local viewport = require("src.viewport")
local input = require("src.input")
local theme = require("src.theme")
local storage = require("src.storage")
local cache = require("src.cache")
local http = require("src.http")
local frame_pacer = require("src.frame_pacer")
local safety_quit = require("src.safety_quit")

-- Sub-views
local bookshelf_view = require("src.views.bookshelf")
local discover_view = require("src.views.discover")
local search_view = require("src.views.search")
local sources_view = require("src.views.sources")
local settings_view = require("src.views.settings")
local reader_view = require("src.views.reader")

local TABS = {
    { id = "bookshelf", title = "书架", view = bookshelf_view },
    { id = "discover",  title = "发现", view = discover_view },
    { id = "search",    title = "搜索", view = search_view },
    { id = "sources",   title = "书源", view = sources_view },
    { id = "settings",  title = "设置", view = settings_view }
}

local current_tab_idx = 1
local in_reader = false
Game_Can_Online = true -- set from GAME_NETWORK_AVAILABLE in love.load()
local auto_screenshot = false
local show_catalog_test = false
local catalog_opened = false
local show_settings_test = false
local settings_opened = false
local show_holdquit_test = false
local frame_count = 0
local focus_zone = "content" -- "tabs" or "content"

-- Forward declaration: defined below, used by the event handlers above it.
local perform_safe_quit

function love.load(arg, unfilteredArg)
    viewport.init(720, 720)
    love.graphics.setDefaultFilter("linear", "linear")
    love.keyboard.setKeyRepeat(true)

    -- muOS launch script probes connectivity and exports GAME_NETWORK_AVAILABLE.
    -- On PC (env unset) we assume online so development is unaffected.
    local net_flag = os.getenv("GAME_NETWORK_AVAILABLE")
    Game_Can_Online = (net_flag == nil) or (net_flag == "1")

    theme.init()
    storage.init()
    cache.init()
    http.init_async()

    -- Power saving: start at full frame rate; the pacer drops it once idle.
    frame_pacer.init()

    -- Global safety exit (hold Start + Select). Save progress, then quit.
    safety_quit.init()
    safety_quit.set_handlers({})

    -- Initialize views
    bookshelf_view.init()
    search_view.init()
    sources_view.init()
    settings_view.init()

    -- Apply the user's saved theme preference app-wide at startup.
    theme.set_theme(storage.get_reader_settings().theme)

    local all_args = {}
    if _G.arg then
        for i = -10, 20 do
            if _G.arg[i] then table.insert(all_args, _G.arg[i]) end
        end
    end
    for _, a in ipairs(unfilteredArg or arg or {}) do
        table.insert(all_args, a)
    end
    for _, a in ipairs(all_args) do
        if a == "--screenshot" then
            auto_screenshot = true
        elseif a:match("^%-%-tab=(%d+)$") then
            current_tab_idx = tonumber(a:match("^%-%-tab=(%d+)$"))
            if TABS[current_tab_idx] and TABS[current_tab_idx].view.init then
                TABS[current_tab_idx].view.init()
            end
        elseif a == "--reader" then
            local books = storage.get_books()
            if #books > 0 then
                in_reader = true
                reader_view.open_book(books[1])
            end
        elseif a == "--catalog" then
            local books = storage.get_books()
            if #books > 0 then
                in_reader = true
                show_catalog_test = true
                reader_view.open_book(books[1])
            end
        elseif a == "--settings" then
            local books = storage.get_books()
            if #books > 0 then
                in_reader = true
                show_settings_test = true
                reader_view.open_book(books[1])
            end
        elseif a == "--quit" then
            current_tab_idx = 5
            if TABS[current_tab_idx] and TABS[current_tab_idx].view.init then
                TABS[current_tab_idx].view.init()
            end
            settings_view.open_confirm()
        elseif a == "--btn2" then
            -- Screenshot helper: show the second card button focused on 书架.
            current_tab_idx = 1
            if TABS[1] and TABS[1].view.init then TABS[1].view.init() end
            bookshelf_view._set_card_button_index(2)
        elseif a == "--discbtn" then
            -- Screenshot helper: show the discover list with a card button focused.
            current_tab_idx = 2
            local dv = TABS[2].view
            if dv.init then dv.init() end
            dv._set_categories({ { title = "玄幻奇幻", url = "http://x" }, { title = "都市", url = "http://y" } })
            dv._set_books({
                { name = "斗破苍穹", author = "天蚕土豆", kind = "玄幻", bookUrl = "http://fix/1", latestChapterTitle = "第1634章 大结局" },
                { name = "凡人修仙传", author = "忘语", kind = "仙侠", bookUrl = "http://fix/2", latestChapterTitle = "第2355章 再临仙界" }
            })
            dv._set_card_button_index(2)
        elseif a == "--menu" then
            -- Screenshot helper: reader action menu (Select).
            local books = storage.get_books()
            if #books > 0 then
                in_reader = true
                reader_view.open_book(books[1])
            end
            reader_view.open_menu()
        elseif a == "--keyboard" then
            current_tab_idx = 3
            if TABS[current_tab_idx] and TABS[current_tab_idx].view.init then
                TABS[current_tab_idx].view.init()
            end
            local keyboard = require("src.keyboard")
            keyboard.open("仙逆", function() end, function() end)
            -- simulate typing 'n' and 'i' to show candidates
            keyboard.handle_key("n")
            keyboard.handle_key("i")
            -- focus the candidate bar (row 0) so the highlight is visible
            keyboard._set_cursor(0, 1, 1)
        elseif a == "--holdquit" then
            -- Screenshot helper: show the Start+Select hold-to-quit indicator.
            show_holdquit_test = true
        end
    end
end

function love.textinput(t)
    if not in_reader and TABS[current_tab_idx].id == "search" then
        search_view.textinput(t)
    end
end

function love.keypressed(key)
    frame_pacer.note_activity()
    input.on_keypressed(key)

    if in_reader then
        if reader_view.keypressed then
            local res = reader_view.keypressed(key)
            if res and res.action == "close_reader" then
                in_reader = false
            end
        end
        return
    end

    if TABS[current_tab_idx].id == "search" then
        search_view.keypressed(key)
    end

    -- Direct numeric tab switching on keyboard. Initialize the destination
    -- just as the mouse and shoulder-button paths do.
    local tab_idx = tonumber(key)
    if tab_idx and TABS[tab_idx] then
        local mapped_actions = { "l2", "r2", "l3", "r3" }
        if mapped_actions[tab_idx] then input.consume(mapped_actions[tab_idx]) end
        current_tab_idx = tab_idx
        focus_zone = "content"
        local view = TABS[tab_idx].view
        if view.init then view.init() end
    end
end

function love.keyreleased(key)
    input.on_keyreleased(key)
end

function love.gamepadpressed(joystick, button)
    frame_pacer.note_activity()
    input.on_gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
    input.on_gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
    if math.abs(value or 0) > 0.3 then frame_pacer.note_activity() end
    input.on_gamepadaxis(joystick, axis, value)
end

function love.mousemoved(x, y, dx, dy)
    if (dx or 0) ~= 0 or (dy or 0) ~= 0 then frame_pacer.note_activity() end
end

function love.wheelmoved(x, y)
    if in_reader then
        if reader_view.wheelmoved then
            reader_view.wheelmoved(x, y)
        end
    else
        local current_view = TABS[current_tab_idx].view
        if current_view and current_view.wheelmoved then
            current_view.wheelmoved(x, y)
        end
    end
end

function love.mousepressed(x, y, button)
    local vw, vh = viewport.get_dimensions()
    local vx, vy = viewport.to_virtual(x, y)
    if not vx or not vy then return end

    if in_reader then
        if reader_view.mousepressed then
            local res = reader_view.mousepressed(vx, vy, button)
            if res and res.action == "close_reader" then
                in_reader = false
            end
        end
        return
    end

    -- 1. Top Bar Clicks (Tabs and L1/R1 arrows)
    if vy <= 54 then
        -- L1 Arrow
        if vx <= 70 then
            current_tab_idx = current_tab_idx - 1
            if current_tab_idx < 1 then current_tab_idx = #TABS end
            focus_zone = "content"
            local v = TABS[current_tab_idx].view
            if v and v.init then v.init() end
            return
        -- R1 Arrow
        elseif vx >= vw - 70 then
            current_tab_idx = current_tab_idx + 1
            if current_tab_idx > #TABS then current_tab_idx = 1 end
            focus_zone = "content"
            local v = TABS[current_tab_idx].view
            if v and v.init then v.init() end
            return
        end

        -- Tab Pills
        local tab_w = 90
        local gap = 8
        local total_w = #TABS * tab_w + (#TABS - 1) * gap
        local start_x = (vw - total_w) / 2
        for i = 1, #TABS do
            local tx = start_x + (i - 1) * (tab_w + gap)
            if vx >= tx and vx <= tx + tab_w and vy >= 10 and vy <= 46 then
                current_tab_idx = i
                focus_zone = "content"
                local v = TABS[current_tab_idx].view
                if v and v.init then v.init() end
                return
            end
        end
        return
    end

    -- 2. Bottom Bar Clicks
    if vy >= vh - 36 then
        local active_tab_id = TABS[current_tab_idx].id
        if active_tab_id == "bookshelf" then
            if button == 1 then
                input.on_keypressed("return")
                input.on_keyreleased("return")
            end
        elseif active_tab_id == "sources" then
            local sources = storage.get_sources()
            if #sources > 0 then
                storage.toggle_source(1)
            end
        end
        return
    end

    -- 3. Pass to Active Tab View
    focus_zone = "content"
    local current_view = TABS[current_tab_idx].view
    if current_view and current_view.mousepressed then
        local res = current_view.mousepressed(vx, vy, button)
        if res and res.action == "open_reader" and res.book then
            in_reader = true
            reader_view.open_book(res.book)
        elseif res and res.action == "quit" then
            perform_safe_quit()
        end
    end
end

-- Perform a clean, safe shutdown: persist the current reading position first so
-- nothing is lost, then hand control back to muOS.
function perform_safe_quit()
    if in_reader and reader_view.save_and_exit then
        reader_view.save_and_exit()
    end
    love.event.quit()
end
-- Decide how fast this frame should run, based on user activity and view state.
local function update_frame_pacer(dt)
    -- The headless screenshot harness must not be throttled (it counts frames).
    if auto_screenshot then
        frame_pacer.note_activity()
        frame_pacer.update(dt, { busy = true })
        return
    end

    -- Any freshly pressed action counts as activity.
    if input.any_pressed() then frame_pacer.note_activity() end

    local busy = false
    if in_reader then
        busy = reader_view.is_loading() or (reader_view.is_caching and reader_view.is_caching()) or (reader_view.is_tts_playing and reader_view.is_tts_playing())
    else
        local v = TABS[current_tab_idx] and TABS[current_tab_idx].view
        if v then
            if v.is_caching and v.is_caching() then busy = true end
            if v.is_busy and v.is_busy() then busy = true end
            if v.is_loading and v.is_loading() then busy = true end
        end
    end
    -- Keep full rate while any network request is in flight.
    if http.has_pending and http.has_pending() then busy = true end

    frame_pacer.update(dt, {
        busy = busy,
        context = in_reader and "reader" or "ui",
    })
end

function love.update(dt)
    http.update()

    -- Global hardware escape hatch: hold Start + Select to save & exit cleanly.
    -- Runs before any view logic and swallows the two buttons while held, so the
    -- half-second overlap never triggers Select's menu / Start's 换源 actions.
    if safety_quit.update(dt, input) then
        perform_safe_quit()
        input.update()
        return
    end

    -- Handle screenshot testing
    if auto_screenshot then
        frame_count = frame_count + 1
        if show_holdquit_test then safety_quit._test_hold(0.6) end
        if show_catalog_test and not reader_view.is_loading() and not catalog_opened then
            reader_view.open_catalog()
            catalog_opened = true
            frame_count = 0 -- give it 30 frames to render
        end
        if show_settings_test and not reader_view.is_loading() and not settings_opened then
            reader_view.open_settings()
            settings_opened = true
            frame_count = 0
        end
        local ready = (not in_reader and frame_count > 100) or (in_reader and not reader_view.is_loading() and (not show_catalog_test or catalog_opened) and (not show_settings_test or settings_opened) and frame_count > 30)
        if ready or frame_count > 800 then
            love.graphics.captureScreenshot("preview.png")
            love.event.quit()
        end
    end

    -- Check Reader State
    if in_reader then
        local res = reader_view.update(dt, input)
        if res and res.action == "close_reader" then
            in_reader = false
        end
        update_frame_pacer(dt)
        input.update()
        return
    end

    -- Global L1 / R1 Tab Switching
    -- Suppressed while an overlay (virtual keyboard / modal) owns the input, so
    -- shoulder presses can never leak out to the tab bar (e.g. the IME uses
    -- L1/R1 to page candidates).
    local overlay_open = false
    local active = TABS[current_tab_idx]
    if active and active.view and active.view.is_action_modal_open then
        overlay_open = active.view.is_action_modal_open()
    end

    if not overlay_open then
        if input.pressed("l1") then
            current_tab_idx = current_tab_idx > 1 and current_tab_idx - 1 or #TABS
            local v = TABS[current_tab_idx].view
            if v and v.init then v.init() end
        elseif input.pressed("r1") then
            current_tab_idx = current_tab_idx < #TABS and current_tab_idx + 1 or 1
            local v = TABS[current_tab_idx].view
            if v and v.init then v.init() end
        end
    end

    -- D-Pad Navigation between Top Tabs and View Content
    if focus_zone == "tabs" then
        if input.pressed("left") then
            current_tab_idx = current_tab_idx > 1 and current_tab_idx - 1 or #TABS
            local v = TABS[current_tab_idx].view
            if v and v.init then v.init() end
        elseif input.pressed("right") then
            current_tab_idx = current_tab_idx < #TABS and current_tab_idx + 1 or 1
            local v = TABS[current_tab_idx].view
            if v and v.init then v.init() end
        elseif input.pressed("down") or input.pressed("a") then
            focus_zone = "content"
        end
    else
        -- focus_zone == "content"
        local current_view = TABS[current_tab_idx].view
        if current_view and current_view.update then
            local res = current_view.update(dt, input)
            if res then
                if res.action == "open_reader" and res.book then
                    in_reader = true
                    reader_view.open_book(res.book)
                elseif res.action == "focus_tabs" then
                    focus_zone = "tabs"
                elseif res.action == "quit" then
                    perform_safe_quit()
                end
            end
        end
    end

    update_frame_pacer(dt)
    input.update()
end

local function draw_top_nav(vw, vh, is_tabs_focused)
    local c = theme.colors()

    -- Header Bar Background
    love.graphics.setColor(c.tab_bg)
    love.graphics.rectangle("fill", 0, 0, vw, 54)
    love.graphics.setColor(c.border)
    love.graphics.line(0, 54, vw, 54)

    -- L1 / R1 indicators
    theme.set_font("hint")
    love.graphics.setColor(c.accent)
    love.graphics.print("◀ L1", 24, 18)
    love.graphics.print("R1 ▶", vw - 56, 18)

    -- Centered Tabs Row
    local tab_w = 90
    local tab_h = 32
    local gap = 8
    local total_w = #TABS * tab_w + (#TABS - 1) * gap
    local start_x = (vw - total_w) / 2
    local ty = 12

    for i, tab in ipairs(TABS) do
        local tx = start_x + (i - 1) * (tab_w + gap)
        local is_active = (i == current_tab_idx)
        local is_selected_tab = is_tabs_focused and is_active

        if is_active then
            love.graphics.setColor(c.focus)
            love.graphics.rectangle("fill", tx, ty, tab_w, tab_h, 6, 6)
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(c.surface)
            love.graphics.rectangle("fill", tx, ty, tab_w, tab_h, 6, 6)
            love.graphics.setColor(c.text_muted)
        end

        -- Focus border outline when navigation is on tabs!
        if is_selected_tab then
            love.graphics.setColor(c.accent)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", tx - 2, ty - 2, tab_w + 4, tab_h + 4, 8, 8)
            love.graphics.setLineWidth(1)
        end

        theme.set_font("header")
        local tw = theme.get_font("header"):getWidth(tab.title)
        love.graphics.print(tab.title, tx + (tab_w - tw) / 2, ty + 6)
    end
end

local function draw_bottom_hints(vw, vh)
    local c = theme.colors()
    local by = vh - 36

    -- Bottom Bar Background
    love.graphics.setColor(c.tab_bg)
    love.graphics.rectangle("fill", 0, by, vw, 36)
    love.graphics.setColor(c.border)
    love.graphics.line(0, by, vw, by)

    local active_tab_id = TABS[current_tab_idx].id
    local bx = 24

    if focus_zone == "tabs" then
        bx = bx + theme.draw_key_badge("◀/▶", "选择标签", bx, by + 8)
        bx = bx + theme.draw_key_badge("▼/A", "进入内容", bx, by + 8)
        bx = bx + theme.draw_key_badge("L1/R1", "快速切换", bx, by + 8)
        return
    end

    if active_tab_id == "bookshelf" then
        bx = bx + theme.draw_key_badge("A", "打开/确认", bx, by + 8)
        bx = bx + theme.draw_key_badge("◀/▶", "卡片按钮", bx, by + 8)
        bx = bx + theme.draw_key_badge("L3", "缓存全书", bx, by + 8)
        bx = bx + theme.draw_key_badge("X", "移出书架", bx, by + 8)
        bx = bx + theme.draw_key_badge("L1/R1", "切换标签", bx, by + 8)
    elseif active_tab_id == "discover" then
        if Game_Can_Online == false then
            bx = bx + theme.draw_key_badge("▲", "返回顶部标签", bx, by + 8)
        else
            local in_books = discover_view.get_focus_subzone and discover_view.get_focus_subzone() == "books"
            bx = bx + theme.draw_key_badge("A", in_books and "卡片按钮/操作" or "进入列表", bx, by + 8)
            bx = bx + theme.draw_key_badge("◀/▶", in_books and "卡片按钮" or "选择分类", bx, by + 8)
            bx = bx + theme.draw_key_badge("X", "加/移书架", bx, by + 8)
            bx = bx + theme.draw_key_badge("L2/R2", "切换书源", bx, by + 8)
        end
        bx = bx + theme.draw_key_badge("L1/R1", "切换标签", bx, by + 8)
    elseif active_tab_id == "search" then
        bx = bx + theme.draw_key_badge("A", "书籍操作", bx, by + 8)
        bx = bx + theme.draw_key_badge("X", "加/移书架", bx, by + 8)
        bx = bx + theme.draw_key_badge("▲", "顶部标签", bx, by + 8)
        bx = bx + theme.draw_key_badge("◀/▶", "预设热搜", bx, by + 8)
    elseif active_tab_id == "sources" then
        bx = bx + theme.draw_key_badge("X", "切换单个", bx, by + 8)
        bx = bx + theme.draw_key_badge("L2/R2", "全关/全开", bx, by + 8)
        bx = bx + theme.draw_key_badge("A", "测速诊断", bx, by + 8)
        bx = bx + theme.draw_key_badge("L1/R1", "切换标签", bx, by + 8)
    elseif active_tab_id == "settings" then
        bx = bx + theme.draw_key_badge("▲/▼", "选择设置项", bx, by + 8)
        bx = bx + theme.draw_key_badge("◀/▶", "切换 / 清理缓存", bx, by + 8)
        bx = bx + theme.draw_key_badge("A", "确认", bx, by + 8)
        bx = bx + theme.draw_key_badge("L1/R1", "切换标签", bx, by + 8)
    end
end

function love.draw()
    viewport.begin_draw()

    local vw, vh = viewport.get_dimensions()
    local c = theme.colors()

    if in_reader then
        reader_view.draw(vw, vh)
    else
        -- Background Fill
        love.graphics.setColor(c.bg)
        love.graphics.rectangle("fill", 0, 0, vw, vh)

        -- Top Navigation Tabs
        draw_top_nav(vw, vh, focus_zone == "tabs")

        -- Active Tab Content
        local current_view = TABS[current_tab_idx].view
        if current_view and current_view.draw then
            current_view.draw(vw, vh, focus_zone == "content")
        end

        -- Bottom Handheld Key Guide
        draw_bottom_hints(vw, vh)
    end

    viewport.end_draw()

    -- Overlay a slim progress bar while the Start+Select safety combo is held.
    if safety_quit.is_holding() then
        local vw, vh = viewport.get_dimensions()
        local p = safety_quit.get_progress()
        local bar_w = 300
        local bx = (vw - bar_w) / 2
        -- Sit above the persistent bottom hint bar (which starts at vh-36).
        local by = vh - 62
        theme.set_font("hint")
        love.graphics.setColor(c.text)
        love.graphics.printf("长按 Start+Select 退出…", 0, by - 26, vw, "center")
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", bx - 8, by - 6, bar_w + 16, 18, 6, 6)
        love.graphics.setColor(c.surface_active)
        love.graphics.rectangle("fill", bx, by, bar_w, 6, 3, 3)
        love.graphics.setColor(c.danger)
        love.graphics.rectangle("fill", bx, by, bar_w * p, 6, 3, 3)
    end
end

-- ---------------------------------------------------------------------------
-- Power-optimised main loop.
--
-- LÖVE's default love.run spins as fast as the OS allows and never sleeps,
-- which keeps the SoC hot and drains the battery. This replacement sleeps off
-- the idle remainder of every frame (targeted by src/frame_pacer), so a static
-- reader page costs a fraction of the CPU/GPU wake-ups while input stays snappy.
-- ---------------------------------------------------------------------------
function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

    if love.timer then love.timer.step() end

    return function()
        if love.event then
            love.event.pump()
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" then
                    if not love.quit or not love.quit() then
                        return a or 0
                    end
                end
                love.handlers[name](a, b, c, d, e, f)
            end
        end

        -- dt = real seconds since the previous frame (includes the idle sleep,
        -- so animations/logic still see wall-clock time).
        local dt = 0
        if love.timer then dt = love.timer.step() end

        local frame_start = love.timer and love.timer.getTime() or 0

        if love.update then love.update(dt) end

        if love.graphics and love.graphics.isActive() then
            love.graphics.clear(love.graphics.getBackgroundColor())
            love.graphics.origin()
            if love.draw then love.draw() end
            love.graphics.present()
        end

        -- Sleep off the unused part of the frame at the pacer's target rate.
        -- Measuring real work time (not dt) is what actually yields the CPU.
        if love.timer then
            local work = love.timer.getTime() - frame_start
            local remainder = frame_pacer.get_frame_time() - work
            if remainder > 0 then
                love.timer.sleep(remainder)
            end
        end
    end
end
