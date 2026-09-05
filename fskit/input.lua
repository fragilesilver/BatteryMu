-- fskit/input.lua
-- One button vocabulary for every path muOS can deliver input through:
--   * native SDL gamepad  (love.gamepadpressed)  -- the real path on device
--   * key events           (love.keypressed)     -- gptokeyb fallback + desktop dev
--
-- Canonical names: up down left right  a b x y  l1 r1 l2 r2  menu select start
-- Semantics fixed for every fskit app: A = confirm, B = back / quit-from-root.

local input = {}

-- SDL gamepad button -> canonical
local PAD = {
    dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
    a = "a", b = "b", x = "x", y = "y",
    leftshoulder = "l1", rightshoulder = "r1",
    triggerleft = "l2", triggerright = "r2",
    back = "select", start = "start", guide = "menu",
}

-- key event -> canonical. gptokeyb on muOS emits the letter/arrow keys
-- directly; the rest are desktop-dev conveniences and are harmless on device.
local KEY = {
    up = "up", down = "down", left = "left", right = "right",
    a = "a", b = "b", x = "x", y = "y",
    ["return"] = "a", kpenter = "a", space = "a",
    escape = "b", backspace = "x",
    ["1"] = "l1", ["2"] = "r1",       -- dev-only shoulder aliases
    lshift = "l1", rshift = "r1",
    ["kp7"] = "l1", ["kp9"] = "r1",
    rctrl = "start", tab = "select",
}

function input.fromPad(button) return PAD[button] end
function input.fromKey(key)     return KEY[key]    end

-- Wire love callbacks to a single dispatch(name) function.
function input.hook(dispatch)
    function love.keypressed(key)
        local n = KEY[key]
        if n then dispatch(n) end
    end
    function love.gamepadpressed(_, button)
        local n = PAD[button]
        if n then dispatch(n) end
    end
    -- Fallback for a pad with no gamecontroller mapping (rare on RG35XX). Skip
    -- when the gamepad path is already handling this joystick, or the d-pad
    -- would register twice.
    function love.joystickhat(js, _, dir)
        if js.isGamepad and js:isGamepad() then return end
        local m = { u = "up", d = "down", l = "left", r = "right" }
        local n = m[dir]
        if n then dispatch(n) end
    end
end

return input
