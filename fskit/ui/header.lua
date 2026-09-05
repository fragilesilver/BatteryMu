-- fskit/ui/header.lua
-- Top chrome bar: title on the left, optional centre + right slots. Content is
-- kept inside the safe area so it survives a cropped panel.
--
--   header.draw{ title = "ClockMu", centre = "Ocean Blue", right = "07:41" }

local theme  = require("fskit.theme")
local font   = require("fskit.font")
local screen = require("fskit.screen")

local header = {}

header.H = 44

function header.draw(o)
    o = o or {}
    local h   = o.h or header.H
    local pad = o.pad or screen.SAFE

    theme.rgba("bg_header")
    love.graphics.rectangle("fill", 0, 0, screen.W, h)
    theme.rgba("separator", 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, h - 0.5, screen.W, h - 0.5)

    if o.title then
        love.graphics.setFont(o.titleFont or font.big)
        theme.rgba("text_accent")
        love.graphics.print(o.title, pad, (h - (o.titleFont or font.big):getHeight()) / 2)
    end

    if o.right then
        local f = o.rightFont or font.med
        love.graphics.setFont(f)
        theme.rgba("text_secondary")
        love.graphics.print(o.right, screen.W - pad - f:getWidth(o.right),
            (h - f:getHeight()) / 2)
    end

    if o.centre then
        local f = o.centreFont or font.xs
        love.graphics.setFont(f)
        theme.rgba("text_disabled")
        love.graphics.print(o.centre, (screen.W - f:getWidth(o.centre)) / 2,
            (h - f:getHeight()) / 2)
    end
end

return header
