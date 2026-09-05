-- BatteryMu -- LÖVE configuration
-- muOS Andromeda 2606.0, whole RG35XX family (Allwinner H700 / AXP2202, 640x480).
-- fskit.screen letterboxes a fixed 640x480 virtual canvas onto whatever muOS
-- is driving (internal panel or HDMI), so nothing here is device-specific.

function love.conf(t)
    t.identity            = "BatteryMu"
    t.version             = "11.5"
    t.console             = false
    t.appendidentity      = true

    t.window.title        = "BatteryMu"
    t.window.width        = 640
    t.window.height       = 480
    t.window.fullscreen   = true
    t.window.fullscreentype = "exclusive"
    t.window.resizable    = false
    t.window.borderless   = true
    t.window.vsync        = 1
    t.window.highdpi      = false
    t.window.displayindex = 1

    -- Trim modules BatteryMu never uses.
    t.modules.physics = false
    t.modules.video   = false
    t.modules.touch   = false
    t.modules.mouse   = false
    t.modules.joystick = true
end
