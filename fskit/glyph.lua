-- fskit/glyph.lua
-- Canonical button-glyph set. White/greyscale masks: set a colour with
-- love.graphics.setColor(...) before drawing to recolour.
-- Names are controller-agnostic: a b x y  l1 r1 l2 r2  menu select start.

local DIR = "fskit/assets/glyph/"

local glyph = {}
local img   = {}

local NAMES = { "a", "b", "x", "y", "l1", "r1", "l2", "r2", "menu", "select", "start" }

function glyph.load()
    for _, n in ipairs(NAMES) do
        local p = DIR .. n .. ".png"
        if love.filesystem.getInfo(p) then
            img[n] = love.graphics.newImage(p)
            img[n]:setFilter("linear", "linear")
        end
    end
end

function glyph.get(name)
    return img[name]
end

-- rendered height is normalised to ~20px in virtual space
glyph.SIZE = 20

function glyph.scaleFor(name)
    local i = img[name]
    if not i then return 1 end
    return glyph.SIZE / i:getHeight()
end

return glyph
