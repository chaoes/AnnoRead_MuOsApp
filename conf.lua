function love.conf(t)
    t.identity = "rgcubexx-game"
    t.version = "11.5"
    t.console = true

    t.window.title = "AnnoRead 阿诺阅读"
    t.window.width = 720
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 240
    t.window.minheight = 240
    t.window.vsync = 0
    t.window.highdpi = false

    -- Audio and sound enabled for TTS voice reading
    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = true
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false
    t.modules.window = true
end
