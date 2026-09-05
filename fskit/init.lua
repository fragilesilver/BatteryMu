-- fskit  --  shared LÖVE kit for the MustardOS apps (ClockMu / JarMu / BatteryMu)
-- First consumer: ClockMu. Extracted later to fragilesilver/fskit.
--
--   local fskit = require("fskit")
--   function love.load()
--       fskit.load()                       -- fonts, glyphs, virtual canvas
--       fskit.theme.bind{ load = ..., save = ... }
--   end
--   function love.draw()
--       fskit.screen.begin()
--       ... draw at 640x480 ...
--       fskit.screen.finish()
--   end

local fskit = {
    _VERSION = "0.1.0",
    theme    = require("fskit.theme"),
    themes   = require("fskit.themes"),
    screen   = require("fskit.screen"),
    font     = require("fskit.font"),
    glyph    = require("fskit.glyph"),
    input    = require("fskit.input"),
    ui = {
        header = require("fskit.ui.header"),
        footer = require("fskit.ui.footer"),
    },
}

-- one-shot resource load; call from love.load()
function fskit.load()
    fskit.font.load()
    fskit.glyph.load()
    fskit.screen.load()
end

return fskit
