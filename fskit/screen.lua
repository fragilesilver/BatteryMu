-- fskit/screen.lua
-- Fixed 640x480 virtual canvas, letterbox-scaled (never stretched) onto the
-- real framebuffer. Covers:
--   * every RG35XX variant (all 640x480 internally)
--   * HDMI-out on the Pro (1280x720) and any other target muOS hands us
--   * panel-variant edge crop / overscan  -> SAFE inset keeps chrome visible
--
-- The app always draws in 0..640 x 0..480. Input is button-only, so no
-- coordinate remapping is needed.

local screen = {}

screen.W, screen.H = 640, 480
screen.SAFE        = 10          -- virtual px kept clear at each edge for chrome

local canvas
local scale, ox, oy = 1, 0, 0

function screen.load()
    canvas = love.graphics.newCanvas(screen.W, screen.H)
    canvas:setFilter("linear", "linear")
    local w, h = love.graphics.getDimensions()
    screen.resize(w, h)
end

function screen.resize(w, h)
    w = w or love.graphics.getWidth()
    h = h or love.graphics.getHeight()
    scale = math.min(w / screen.W, h / screen.H)
    ox = math.floor((w - screen.W * scale) / 2 + 0.5)
    oy = math.floor((h - screen.H * scale) / 2 + 0.5)
end

-- draw the frame into the virtual canvas
function screen.begin()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
end

-- blit the virtual canvas to the real framebuffer, centred and scaled
function screen.finish()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, ox, oy, 0, scale, scale)
end

-- safe-area rectangle in virtual coords
function screen.safe()
    local s = screen.SAFE
    return s, s, screen.W - s * 2, screen.H - s * 2
end

return screen
