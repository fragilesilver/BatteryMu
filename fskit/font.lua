-- fskit/font.lua  (BatteryMu size set)
-- Sizes tuned for the 640x480 virtual canvas (fskit.screen). Kept identical to
-- BatteryMu's pre-fskit font sizes so the layout is unchanged.
-- NOTE: ClockMu ships a different size set in its own copy; the two reconcile
-- when fskit is extracted to fragilesilver/fskit.

local DIR = "fskit/assets/font/"

local font = {}

function font.load()
    local B = DIR .. "Bold.ttf"
    local R = DIR .. "Regular.ttf"

    font.huge    = love.graphics.newFont(B, 36)   -- big % readout
    font.xl      = love.graphics.newFont(B, 22)
    font.lg      = love.graphics.newFont(B, 18)
    font.md      = love.graphics.newFont(B, 14)
    font.sm      = love.graphics.newFont(B, 12)
    font.xs      = love.graphics.newFont(B, 10)

    font.body    = love.graphics.newFont(R, 12)
    font.body_xs = love.graphics.newFont(R, 10)

    for _, f in pairs(font) do
        if type(f) == "userdata" then f:setFilter("linear", "linear") end
    end
end

return font
