-- fskit/ui/footer.lua
-- Declarative button-hint bar. Right-anchored items measure their own width and
-- inset from the safe edge, so nothing clips on a cropped / overscanned panel.
--
--   footer.draw{
--     {icon = "a", label = "Edit"},
--     {icon = "b", label = "Quit", side = "right"},
--   }
--
-- Options table (2nd arg, all optional):
--   x, w      : bar bounds in virtual px (default: full width)
--   y, h      : bar position/height   (default: pinned to bottom, h = 40)
--   pad       : inner inset from x / x+w (default: screen.SAFE)
--   font      : label font            (default: fskit.font.xs)

local theme  = require("fskit.theme")
local glyph  = require("fskit.glyph")
local font   = require("fskit.font")
local screen = require("fskit.screen")

local footer = {}

footer.H = 40

local GAP     = 12   -- between hint groups
local ICON_GAP = 6   -- icon -> label

local function drawHint(item, x, y, h, f)
    local g  = glyph.get(item.icon)
    local iw = 0
    if g then
        local s  = glyph.scaleFor(item.icon)
        local ih = g:getHeight() * s
        theme.rgba("text_primary")
        love.graphics.draw(g, x, y + (h - ih) / 2, 0, s, s)
        iw = g:getWidth() * s + ICON_GAP
    end
    theme.rgba("text_secondary")
    love.graphics.setFont(f)
    love.graphics.print(item.label, x + iw, y + (h - f:getHeight()) / 2)
    return iw + f:getWidth(item.label)
end

local function hintWidth(item, f)
    local w = f:getWidth(item.label)
    local g = glyph.get(item.icon)
    if g then w = w + g:getWidth() * glyph.scaleFor(item.icon) + ICON_GAP end
    return w
end

function footer.draw(items, opt)
    opt = opt or {}
    local f  = opt.font or font.xs
    local h  = opt.h or footer.H
    local y  = opt.y or (screen.H - h)
    local x  = opt.x or 0
    local w  = opt.w or screen.W
    local pad = opt.pad or screen.SAFE

    -- bar
    theme.rgba("bg_btn_bar")
    love.graphics.rectangle("fill", x, y, w, h)
    theme.rgba("separator", 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(x, y + 0.5, x + w, y + 0.5)

    -- left group packs from the left safe edge
    local lx = x + pad
    for _, it in ipairs(items) do
        if (it.side or "left") == "left" then
            lx = lx + drawHint(it, lx, y, h, f) + GAP
        end
    end

    -- right group packs from the right safe edge, measured so it never clips
    local rx = x + w - pad
    for i = #items, 1, -1 do
        local it = items[i]
        if it.side == "right" then
            rx = rx - hintWidth(it, f)
            drawHint(it, rx, y, h, f)
            rx = rx - GAP
        end
    end
end

return footer
