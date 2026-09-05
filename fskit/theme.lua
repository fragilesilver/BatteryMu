-- fskit/theme.lua
-- In-app colour theme: a fixed set of named palettes, one active at a time,
-- read live at draw time. Nothing here touches muOS's own theme files.
--
--   theme.get(role)   -> r, g, b        (0..1)
--   theme.rgba(role,a) -> love.graphics.setColor(r,g,b,a)
--   theme.set(i)       -> switch, fires onChange observers immediately
--   theme.isLight()    -> true for light palettes (Yoga White)
--
-- Persistence is delegated to the host app via theme.bind{ load=, save= }.

local themes = require("fskit.themes")

local theme = {}

local active    = 1
local observers = {}
local io_load, io_save

-- role -> role fallback when a palette omits a key
local FALLBACK = {
    ok        = "accent",
    full      = "accent_glow",
    danger    = "warn",
    separator = "accent_dim",
    muted     = "text_disabled",
}

local function clamp(i)
    i = tonumber(i) or 1
    if i < 1 then i = 1 end
    if i > #themes then i = #themes end
    return math.floor(i)
end

function theme.count() return #themes end
function theme.index() return active end
function theme.name()  return themes[active].name end
function theme.isLight() return themes[active].light == true end

function theme.list()
    local names = {}
    for i, t in ipairs(themes) do names[i] = t.name end
    return names
end

-- full palette table for a given index (used by the picker's swatches)
function theme.palette(i) return themes[clamp(i or active)] end

function theme.get(role)
    local t = themes[active]
    local c = t[role]
    if not c then
        local fb = FALLBACK[role]
        c = fb and t[fb]
    end
    if not c then return 1, 0, 1 end   -- magenta = missing key, obvious in dev
    return c[1], c[2], c[3]
end

function theme.rgba(role, a)
    local r, g, b = theme.get(role)
    love.graphics.setColor(r, g, b, a or 1)
end

function theme.onChange(fn)
    observers[#observers + 1] = fn
end

local function fire()
    for _, fn in ipairs(observers) do fn(active) end
end

function theme.set(i)
    local n = clamp(i)
    if n == active then return end
    active = n
    if io_save then io_save(active) end
    fire()
end

-- host wires persistence: load() -> index or nil ; save(index)
function theme.bind(opt)
    io_load = opt and opt.load
    io_save = opt and opt.save
    if io_load then
        local n = io_load()
        if n then active = clamp(n) end
    end
end

return theme
