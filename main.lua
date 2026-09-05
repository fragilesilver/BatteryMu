-- ============================================================
-- BatteryMu  v2.1  (AXP2202 -- whole RG35XX family)
-- muOS Andromeda 2606.0  (Jacaranda-compatible)
-- ============================================================

local love  = require("love")
local fskit = require("fskit")

-- ============================================================
-- LAYOUT  (fixed 640x480 virtual canvas; fskit.screen letterboxes it onto
-- whatever muOS is driving -- every RG35XX variant + HDMI-out)
-- ============================================================
local SW, SH    = fskit.screen.W, fskit.screen.H
local HDR_H     = 44
local BTN_BAR_H = 36
local BTN_BAR_Y = SH - BTN_BAR_H

-- ============================================================
-- THEME  (colours from fskit/themes.lua, driven through fskit.theme)
-- T is a plain snapshot table rebuilt on every theme change, so the many
-- `setC(T.xxx)` / `return T.xxx` call sites below stay untouched.
-- ============================================================
local KEYMAP = {
    bg_main = "bg_main", bg_header = "bg_header", bg_card = "bg_panel",
    bg_btn_bar = "bg_btn_bar", accent = "accent", accent_glow = "accent_glow",
    col_charging = "ok", col_full = "full", col_warn = "warn",
    col_crit = "danger", col_unknown = "muted", col_discharging = "discharging",
    text_primary = "text_primary", text_secondary = "text_secondary",
    text_disabled = "text_disabled", separator = "separator",
}

local T = {}
local function rebuildT()
    for bmKey, role in pairs(KEYMAP) do
        T[bmKey] = { fskit.theme.get(role) }
    end
end
fskit.theme.onChange(rebuildT)

local supplyLabel                 -- short name for the header sub-title
local handleInput                 -- forward decl (defined below, used in love.load)

-- ============================================================
-- SYSFS
-- ============================================================
local SUPPLY_CANDIDATES = {
    "axp2202-battery","axp20x-battery","axp209-battery",
    "axp813-battery","battery","BAT0","BAT1",
}
local SYSFS_BASE = "/sys/class/power_supply/"

-- ============================================================
-- STATE
-- ============================================================
local supply      = nil
local pollTimer   = 0
local saveTimer   = 0
local POLL_INTERVAL = 1.0

local data = {
    voltage_uv         = nil,
    charge_current_ma  = nil,
    capacity           = nil,
    capacity_level     = nil,
    status             = "Unknown",
    health             = "Unknown",
    temp_tdeg          = nil,
    charge_counter     = nil,
    charge_full        = nil,   -- learned full capacity (uAh)
    energy_full_design = nil,   -- factory design capacity (uAh)
    time_to_empty      = nil,
    time_to_full       = nil,
    health_pct         = nil,   -- charge_full / energy_full_design * 100
}

-- History (in-session, 1 sample/sec, max 300 = 5 min)
local HISTORY_MAX  = 300
local histVoltage  = {}   -- stored as V floats
local histCapacity = {}   -- stored as % ints

-- Plug-in banner
local prevCharging = nil
local bannerActive = false
local bannerTimer  = 0
local BANNER_SECS  = 3.0

-- Scene: "main" | "graph" | "theme" | "exit" | "healthinfo"
local scene        = "main"
local themeSelIdx  = 1        -- corrected after fskit.theme.bind in love.load

-- Scene transition
local transAlpha   = 0.0          -- 0=transparent overlay, used on scene push
local transDir     = 0            -- 1=fading in, -1=fading out, 0=idle
local transTarget  = ""
local TRANS_SPEED  = 4.0

-- Animation timers
local globalTime   = 0            -- always ticks, drives all animations

-- Last-charged / time-on-battery tracking
local lastChargedTimestamp     = nil  -- os.time() epoch of most recent plug-in event
local timeOnBattery            = 0    -- accumulated seconds discharging since last charge
local lastMeasurementTimestamp = nil  -- os.time() epoch of last accounting update (persisted)

-- Settings store: the launcher exports BATTERYMU_DATA (an absolute, writable
-- dir inside the app). Write there with plain io so persistence never depends
-- on LÖVE's save-dir resolution or muOS bind-mount behaviour. Desktop falls
-- back to love.filesystem under "data/".
local SETTINGS_FILE = "settings.txt"
local STORE_DIR     = os.getenv("BATTERYMU_DATA")
local _lastWritten  = nil

local function storeRead()
    if STORE_DIR then
        local f = io.open(STORE_DIR .. "/" .. SETTINGS_FILE, "rb")
        if f then local d = f:read("*a"); f:close(); if d and #d > 0 then return d end end
    end
    if love.filesystem.getInfo("data/" .. SETTINGS_FILE) then
        return love.filesystem.read("data/" .. SETTINGS_FILE)
    end
    return nil
end

local function storeWrite(data)
    if data == _lastWritten then return true end   -- skip no-op writes (flash wear)
    _lastWritten = data
    if STORE_DIR then
        local f, err = io.open(STORE_DIR .. "/" .. SETTINGS_FILE, "wb")
        if not f then print("[BatteryMu] storeWrite failed: " .. tostring(err)); return false end
        f:write(data); f:close(); return true
    end
    love.filesystem.createDirectory("data")
    return love.filesystem.write("data/" .. SETTINGS_FILE, data)
end

-- Fonts / icons
local fHuge, fBig, fBoldBig, fBoldMed, fBoldSm, fBoldXs, fSm, fXs
local ic = {}

-- ============================================================
-- SYSFS HELPERS
-- ============================================================
local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*l"); f:close()
    return s and s:match("^%s*(.-)%s*$")
end

local function readInt(path)
    local s = readFile(path)
    return s and tonumber(s)
end

local function findSupply()
    for _, name in ipairs(SUPPLY_CANDIDATES) do
        if readFile(SYSFS_BASE..name.."/type") == "Battery" then return name end
    end
    local f = io.popen("ls "..SYSFS_BASE.." 2>/dev/null")
    if f then
        for line in f:lines() do
            if readFile(SYSFS_BASE..line.."/type") == "Battery" then
                f:close(); return line
            end
        end
        f:close()
    end
    return nil
end

-- ------------------------------------------------------------
-- Battery source resolution (Andromeda-native, all-variant safe)
--
-- muOS exposes the per-device battery sysfs nodes via GET_VAR "device"
-- "battery/*". The launcher resolves these once and exports:
--   BATTERYMU_BASE      -- sysfs dir, e.g. /sys/class/power_supply/axp2202-battery/
--   BATTERYMU_CAP_NODE  -- pre-parsed capacity file ($MUOS_RUN_DIR/battery/capacity)
--   BATTERYMU_CHG_NODE  -- pre-parsed charging flag  ($MUOS_RUN_DIR/battery/charging)
--   BATTERYMU_USAGE_DIR -- muOS battery-usage tracker dir ($MUOS_RUN_DIR/battery_usage)
--   BATTERYMU_VMIN / BATTERYMU_VMAX  -- pack voltage limits in mV (3400 / 4000)
-- All optional -- absent on desktop, where findSupply() autodetects instead.
-- Every RG35XX variant is Allwinner H700 / AXP2202, so the sysfs layout is
-- identical across the family; these vars just make it explicit and also let
-- BatteryMu run correctly on non-H700 muOS devices.
-- ------------------------------------------------------------
local ENV_BASE      = os.getenv("BATTERYMU_BASE")
local ENV_CAP_NODE  = os.getenv("BATTERYMU_CAP_NODE")
local ENV_CHG_NODE  = os.getenv("BATTERYMU_CHG_NODE")
local ENV_USAGE_DIR = os.getenv("BATTERYMU_USAGE_DIR")
local ENV_VMIN      = tonumber(os.getenv("BATTERYMU_VMIN") or "")
local ENV_VMAX      = tonumber(os.getenv("BATTERYMU_VMAX") or "")

-- Volt range for the graph default window (Volts). muOS gives mV.
local PACK_VMIN = ENV_VMIN and ENV_VMIN / 1000 or 3.5
local PACK_VMAX = ENV_VMAX and ENV_VMAX / 1000 or 4.2

-- Returns the sysfs base dir (with trailing "/") or nil.
local function resolveBase()
    if ENV_BASE and #ENV_BASE > 0 then
        return (ENV_BASE:sub(-1) == "/") and ENV_BASE or (ENV_BASE .. "/")
    end
    local name = findSupply()
    return name and (SYSFS_BASE .. name .. "/") or nil
end

-- Read muOS's own battery-usage tracker if present; returns a table or nil.
local function readUsageTracker()
    if not ENV_USAGE_DIR then return nil end
    local lc = readInt(ENV_USAGE_DIR .. "/last_charged")
    local tob = readInt(ENV_USAGE_DIR .. "/time_on_battery")
    if not lc and not tob then return nil end
    return {
        last_charged   = (lc and lc > 0) and lc or nil,
        time_on_battery = tob,
    }
end

-- ============================================================
-- SETTINGS
-- ============================================================
local function saveSettings()
    storeWrite(table.concat({
        "theme=" .. tostring(fskit.theme.index()),
        "last_charged=" .. tostring(lastChargedTimestamp or ""),
        "time_on_battery=" .. tostring(math.floor(timeOnBattery)),
        "last_measurement=" .. tostring(lastMeasurementTimestamp or ""),
    }, "\n"))
end

-- fskit.theme persistence bridge (theme index lives in the same settings file)
local function themeLoad()
    local s = storeRead()
    if not s then return nil end
    local bare = s:match("^%s*(%d+)%s*$")
    if bare then return tonumber(bare) end
    return tonumber(s:match("theme=(%d+)"))
end

-- Load the battery-usage tracking fields (theme handled by fskit.theme.bind)
local function loadSettings()
    local s = storeRead()
    if not s then return end
    for key, val in s:gmatch("(%w+)=([^\n]*)") do
        if key == "last_charged" then
            lastChargedTimestamp = tonumber(val)
        elseif key == "time_on_battery" then
            timeOnBattery = tonumber(val) or 0
        elseif key == "last_measurement" then
            lastMeasurementTimestamp = tonumber(val)
        end
    end
end

-- "21 Jun, 14:03" / "-" if never recorded
local function fmtLastCharged(ts)
    if not ts then return "-" end
    return os.date("%d %b, %H:%M", ts)
end

-- ============================================================
-- POLL
-- ============================================================
local function pollBattery()
    local base = supply   -- supply now holds the resolved base dir (with "/")
    if not base then return end

    data.voltage_uv        = readInt(base.."voltage_now")
    data.charge_current_ma = readInt(base.."constant_charge_current")
    -- Prefer muOS's pre-parsed capacity; fall back to the raw sysfs node.
    data.capacity          = (ENV_CAP_NODE and readInt(ENV_CAP_NODE))
                             or readInt(base.."capacity")
    data.capacity_level    = readFile(base.."capacity_level")
    data.status            = readFile(base.."status")  or "Unknown"
    -- If sysfs status is unhelpful, derive it from muOS's charging flag.
    if (data.status == "Unknown" or not data.status) and ENV_CHG_NODE then
        local chg = readInt(ENV_CHG_NODE)
        if chg == 1 then
            data.status = (data.capacity and data.capacity >= 100) and "Full" or "Charging"
        elseif chg == 0 then
            data.status = "Discharging"
        end
    end
    data.health            = readFile(base.."health")  or "Unknown"
    data.temp_tdeg         = readInt(base.."temp")
    data.charge_counter        = readInt(base.."charge_counter")
    data.charge_full           = readInt(base.."charge_full")
    data.energy_full_design    = readInt(base.."energy_full_design")
    -- Use energy_full_design as charge_full fallback
    if not data.charge_full then
        data.charge_full = data.energy_full_design
    end
    -- Battery health: how much learned capacity remains vs factory spec
    if data.charge_full and data.energy_full_design
       and data.energy_full_design > 0 then
        data.health_pct = math.floor(
            (data.charge_full / data.energy_full_design) * 100)
    else
        data.health_pct = nil
    end
    data.time_to_empty     = readInt(base.."time_to_empty_now")
    data.time_to_full      = readInt(base.."time_to_full_now")

    -- History append
    if data.voltage_uv then
        histVoltage[#histVoltage+1]  = data.voltage_uv / 1000000
        histCapacity[#histCapacity+1]= data.capacity or 0
        if #histVoltage  > HISTORY_MAX then table.remove(histVoltage,  1) end
        if #histCapacity > HISTORY_MAX then table.remove(histCapacity, 1) end
    end

    -- Plug-in banner (rising edge)
    local charging = (data.status == "Charging" or data.status == "Full")
    if prevCharging ~= nil and (not prevCharging) and charging then
        bannerActive = true
        bannerTimer  = 0
        lastChargedTimestamp = os.time()
        timeOnBattery = 0
        saveSettings()
    end
    prevCharging = charging

    -- If muOS's own battery-usage tracker is available, trust it for the
    -- "last charged" / "time on battery" readouts instead of our own estimate.
    local u = readUsageTracker()
    if u then
        if u.last_charged then lastChargedTimestamp = u.last_charged end
        if u.time_on_battery then timeOnBattery = u.time_on_battery end
    end
end

-- ============================================================
-- SCENE TRANSITIONS
-- ============================================================
local function gotoScene(name)
    if name == scene then return end
    transTarget = name
    transDir    = 1        -- fade to black
    transAlpha  = 0
end

-- ============================================================
-- FORMATTING
-- ============================================================
local function fmtVoltage(uv)
    if not uv then return "---" end
    return string.format("%.3f V", uv/1000000)
end

local function fmtChargeCurrent(ma)
    if not ma then return "---" end
    return ma >= 1000
        and string.format("%.2f A", ma/1000)
        or  string.format("%d mA", ma)
end

local function fmtTemp(tdeg)
    if not tdeg then return "---" end
    return string.format("%.1f C", tdeg/10)
end

local function fmtCharge(counter, full)
    if not counter or not full or full == 0 then return "---" end
    return string.format("%d / %d mAh",
        math.floor(counter/1000), math.floor(full/1000))
end

local function fmtSeconds(s)
    if not s or s <= 0 then return "---" end
    local h = math.floor(s/3600)
    local m = math.floor((s%3600)/60)
    return h > 0
        and string.format("%dh %02dm", h, m)
        or  string.format("%dm", m)
end

local function statusColor()
    local s = data.status
    if s == "Charging"    then return T.col_charging    end
    if s == "Full"        then return T.col_full        end
    if s == "Discharging" then
        local c = data.capacity or 100
        if c <= 10 then return T.col_crit end
        if c <= 20 then return T.col_warn end
        return T.col_discharging
    end
    return T.col_unknown
end

local function capacityColor()
    local s = data.status or ""
    local c = data.capacity or 100
    if s == "Full"     then return T.col_full     end
    if s == "Charging" then return T.col_charging end
    if c <= 10 then return T.col_crit end
    if c <= 20 then return T.col_warn end
    return T.col_discharging
end

-- ============================================================
-- DRAW HELPERS
-- ============================================================
local function setC(col, a)
    love.graphics.setColor(col[1], col[2], col[3], a or 1)
end

local function rect(mode, x, y, w, h, r)
    love.graphics.rectangle(mode, x, y, w, h, r or 0, r or 0)
end

local function rightText(font, text, rx, y, col, a)
    love.graphics.setFont(font)
    setC(col or T.text_primary, a)
    love.graphics.print(text, rx - font:getWidth(text), y)
end

local function centreText(font, text, cx, y, col, a)
    love.graphics.setFont(font)
    setC(col or T.text_primary, a)
    love.graphics.print(text, cx - font:getWidth(text)/2, y)
end

-- Glowing rectangle outline — layers 3 rects with decreasing alpha
local function glowRect(x, y, w, h, col, intensity, r)
    r = r or 6
    local sizes = {4, 2, 1}
    local alphas = {0.12 * intensity, 0.22 * intensity, 0.9 * intensity}
    for i = 1, 3 do
        local pad = sizes[i]
        setC(col, alphas[i])
        rect("line", x-pad, y-pad, w+pad*2, h+pad*2, r+pad)
    end
end

-- Pulse helper: returns 0..1 sine wave
local function pulse(speed, phase)
    return (math.sin(globalTime * speed + (phase or 0)) + 1) * 0.5
end

-- ============================================================
-- SHARED CHROME (header + button bar)
-- ============================================================
local function drawHeader(title, sub)
    setC(T.bg_header)
    rect("fill", 0, 0, SW, HDR_H)
    setC(T.separator)
    love.graphics.line(0, HDR_H, SW, HDR_H)

    love.graphics.setFont(fBoldBig)
    setC(T.accent)
    love.graphics.print(title, 12, (HDR_H - fBoldBig:getHeight()) / 2)

    if sub then
        centreText(fBoldXs, sub, SW/2,
            (HDR_H - fBoldXs:getHeight()) / 2, T.text_disabled)
    end

    local now = os.date("*t")
    rightText(fBoldMed,
        string.format("%02d:%02d", now.hour, now.min),
        SW-10, (HDR_H - fBoldMed:getHeight())/2, T.text_secondary)
end

-- Generic button bar builder: list of {icon, label, side="left"|"right"|"centre"}
local function drawBtnBar(buttons)
    setC(T.bg_btn_bar)
    rect("fill", 0, BTN_BAR_Y, SW, BTN_BAR_H)
    setC(T.separator)
    love.graphics.line(0, BTN_BAR_Y, SW, BTN_BAR_Y)

    local by = BTN_BAR_Y + (BTN_BAR_H - 20) / 2
    local ty = BTN_BAR_Y + (BTN_BAR_H - fBoldSm:getHeight()) / 2
    love.graphics.setFont(fBoldSm)
    setC(T.text_secondary)

    local lx = 10
    local rx = SW - 10
    -- measure right-side buttons first
    local rightW = 0
    for _, b in ipairs(buttons) do
        if b.side == "right" then rightW = rightW + 26 + fBoldSm:getWidth(b.label) + 12 end
    end
    rx = SW - rightW - 4

    for _, b in ipairs(buttons) do
        if b.side == "right" then
            love.graphics.draw(b.icon, rx, by)
            love.graphics.print(b.label, rx + 26, ty)
            rx = rx + 26 + fBoldSm:getWidth(b.label) + 12
        else
            love.graphics.draw(b.icon, lx, by)
            love.graphics.print(b.label, lx + 26, ty)
            lx = lx + 26 + fBoldSm:getWidth(b.label) + 14
        end
    end
end

-- ============================================================
-- BATTERY BAR
-- ============================================================
local function drawBatteryBar(x, y, w, h, pct, col)
    -- Shell
    setC(T.separator)
    rect("line", x, y, w, h, 4)
    -- Nub
    local nubH = h * 0.4
    rect("fill", x+w, y+(h-nubH)/2, 6, nubH, 2)
    -- Fill
    local fillW = math.max(0, math.min(w-4, (w-4)*pct/100))
    -- Charging shimmer: scan line moves left-to-right
    if data.status == "Charging" then
        setC(col, 0.5)
        rect("fill", x+2, y+2, fillW, h-4, 3)
        local shimX = x+2 + (fillW * ((globalTime * 0.4) % 1.0))
        local shimW = math.min(fillW * 0.25, 40)
        setC(col, 0.9)
        rect("fill", math.min(shimX, x+2+fillW-shimW), y+2, shimW, h-4, 3)
    else
        setC(col)
        rect("fill", x+2, y+2, fillW, h-4, 3)
    end
end

-- ============================================================
-- CARD
-- ============================================================
local function drawCard(x, y, w, h, label, value, valueCol, sub, glowIntensity)
    setC(T.bg_card)
    rect("fill", x, y, w, h, 6)
    if glowIntensity and glowIntensity > 0.01 then
        glowRect(x, y, w, h, valueCol or T.accent, glowIntensity, 6)
    else
        setC(T.separator)
        rect("line", x, y, w, h, 6)
    end

    love.graphics.setFont(fBoldXs)
    setC(T.text_secondary)
    love.graphics.print(label, x+10, y+8)

    love.graphics.setFont(fBig)
    setC(valueCol or T.text_primary)
    local vw = fBig:getWidth(value)
    love.graphics.print(value, x+w/2-vw/2, y+h/2-fBig:getHeight()/2)

    if sub then
        centreText(fBoldXs, sub, x+w/2,
            y+h-fBoldXs:getHeight()-8, T.text_disabled)
    end
end

-- ============================================================
-- INFO ROW
-- ============================================================
local function drawRow(x, y, w, label, value, valueCol, alpha)
    love.graphics.setFont(fBoldSm)
    setC(T.text_secondary)
    love.graphics.print(label, x, y)
    rightText(fBoldSm, value, x+w, y, valueCol or T.text_primary, alpha)
end

local function drawSep(y)
    setC(T.separator)
    love.graphics.line(16, y, SW-16, y)
end

-- ============================================================
-- GRAPH (shared renderer for voltage or capacity)
-- ============================================================
local function drawLineGraph(x, y, w, h, samples, minVal, maxVal, col, label, fmtFn)
    -- Background
    setC(T.bg_card)
    rect("fill", x, y, w, h, 6)
    setC(T.separator)
    rect("line", x, y, w, h, 6)

    -- Label
    love.graphics.setFont(fBoldXs)
    setC(T.text_secondary)
    love.graphics.print(label, x+8, y+6)

    -- Y-axis bounds text
    local yPad = 18
    local gx, gy = x+36, y+yPad
    local gw, gh  = w-44, h-yPad*2

    love.graphics.setFont(fBoldXs)
    setC(T.text_disabled)
    rightText(fBoldXs, fmtFn(maxVal), x+36, gy-2, T.text_disabled)
    rightText(fBoldXs, fmtFn(minVal), x+36, gy+gh-fBoldXs:getHeight()+2, T.text_disabled)

    -- Grid lines (3)
    setC(T.separator, 0.5)
    for i = 0, 2 do
        local ly = gy + (gh * i / 2)
        love.graphics.line(gx, ly, gx+gw, ly)
    end

    if #samples < 2 then
        centreText(fBoldSm, "Collecting data...", x+w/2, y+h/2-6, T.text_disabled)
        return
    end

    -- Plot line
    local range = maxVal - minVal
    if range == 0 then range = 1 end

    love.graphics.setLineWidth(2)
    local points = {}
    for i, v in ipairs(samples) do
        local px = gx + (i-1)/(#samples-1) * gw
        local py = gy + gh - ((v - minVal)/range) * gh
        points[#points+1] = px
        points[#points+1] = py
    end

    -- Filled area under curve
    local areaPoints = {gx, gy+gh}
    for i = 1, #points do areaPoints[#areaPoints+1] = points[i] end
    areaPoints[#areaPoints+1] = gx+gw
    areaPoints[#areaPoints+1] = gy+gh
    setC(col, 0.15)
    love.graphics.polygon("fill", areaPoints)

    -- Line itself
    setC(col, 0.9)
    love.graphics.line(points)

    -- Latest value dot with glow
    local lx2 = points[#points-1]
    local ly2  = points[#points]
    local dotR = 5 + pulse(3) * 2
    setC(col, 0.25)
    love.graphics.circle("fill", lx2, ly2, dotR+4)
    setC(col)
    love.graphics.circle("fill", lx2, ly2, dotR)

    love.graphics.setLineWidth(1)

    -- Latest value label
    local count = #samples
    local timeAgo = count < HISTORY_MAX
        and string.format("last %ds", count)
        or  "last 5 min"
    rightText(fBoldXs, timeAgo, x+w-6, y+6, T.text_disabled)
end

-- ============================================================
-- SCENE: MAIN
-- ============================================================
local function drawSceneMain()
    setC(T.bg_main)
    rect("fill", 0, 0, SW, SH)

    drawHeader("BatteryMu", supplyLabel)
    drawBtnBar({
        {icon=ic.B,  label="Quit",       side="left"},
        {icon=ic.Y,  label="Theme",      side="left"},
        {icon=ic.X,  label="Graph",      side="left"},
        {icon=ic.A,  label="Health Info",side="right"},
    })

    if not supply then
        centreText(fBig,  "No battery supply found", SW/2, SH/2-20, T.col_warn)
        centreText(fBoldSm, "Could not detect /sys/class/power_supply/", SW/2, SH/2+10, T.text_disabled)
        return
    end

    local PAD   = 14
    local cardY = HDR_H + 8
    local cardH = 86
    local cardW = (SW - PAD*3) / 2

    -- Voltage card — pulse glow when charging
    local isCharging = (data.status == "Charging")
    local isFull     = (data.status == "Full")
    local voltGlow   = isCharging and (0.4 + pulse(2.5) * 0.6) or 0
    drawCard(PAD, cardY, cardW, cardH,
        "VOLTAGE", fmtVoltage(data.voltage_uv),
        T.accent_glow, nil, voltGlow)

    -- Right card
    local r2label, r2value, r2col, r2sub, r2glow
    if isCharging then
        r2label = "CHARGE CURRENT"
        r2value = fmtChargeCurrent(data.charge_current_ma)
        r2col   = T.col_charging
        r2sub   = "constant charge limit"
        r2glow  = 0.4 + pulse(2.5, math.pi) * 0.6
    elseif isFull then
        r2label = "STATUS"
        r2value = "Full"
        r2col   = T.col_full
        r2glow  = 0.3 + pulse(1.5) * 0.4
    else
        r2label = "TIME LEFT"
        r2value = fmtSeconds(data.time_to_empty)
        r2col   = T.text_primary
        r2glow  = 0
    end
    drawCard(PAD*2+cardW, cardY, cardW, cardH,
        r2label, r2value, r2col, r2sub, r2glow)

    -- Battery bar strip
    local barAreaY = cardY + cardH + 8
    local barAreaH = 52
    local cap      = data.capacity or 0
    local capCol   = capacityColor()

    setC(T.bg_card)
    rect("fill", PAD, barAreaY, SW-PAD*2, barAreaH, 6)

    -- Glow the bar border when low
    if cap <= 10 then
        glowRect(PAD, barAreaY, SW-PAD*2, barAreaH, T.col_crit,
            0.5 + pulse(4) * 0.5, 6)
    elseif cap <= 20 then
        glowRect(PAD, barAreaY, SW-PAD*2, barAreaH, T.col_warn,
            0.3 + pulse(2) * 0.3, 6)
    else
        setC(T.separator)
        rect("line", PAD, barAreaY, SW-PAD*2, barAreaH, 6)
    end

    -- % label (pulses when critical)
    local capStr    = data.capacity and tostring(data.capacity).."%"  or "?%"
    local capAlpha  = (cap <= 10) and (0.5 + pulse(4) * 0.5) or 1.0
    love.graphics.setFont(fHuge)
    setC(capCol, capAlpha)
    local capLabelW = fHuge:getWidth(capStr)
    love.graphics.print(capStr, PAD+10, barAreaY+(barAreaH-fHuge:getHeight())/2)

    local barX  = PAD + capLabelW + 24
    local barW  = SW-PAD*2 - capLabelW - 80
    local barH2 = 22
    drawBatteryBar(barX, barAreaY+(barAreaH-barH2)/2, barW, barH2, cap, capCol)

    rightText(fBoldSm, data.status or "Unknown",
        SW-PAD-8, barAreaY+(barAreaH-fBoldSm:getHeight())/2, statusColor())

    -- Battery health card (full width, below bar)
    local healthY = barAreaY + barAreaH + 8
    local healthH = 42
    local hp      = data.health_pct
    local hpStr   = hp and (tostring(hp).."%") or "---"
    local hpCol
    if not hp then
        hpCol = T.col_unknown
    elseif hp >= 80 then
        hpCol = T.col_charging
    elseif hp >= 60 then
        hpCol = T.col_warn
    else
        hpCol = T.col_crit
    end
    local hpGlow = (hp and hp < 60) and (0.3 + pulse(2)*0.4) or 0

    setC(T.bg_card)
    rect("fill", PAD, healthY, SW-PAD*2, healthH, 6)
    if hpGlow > 0.01 then
        glowRect(PAD, healthY, SW-PAD*2, healthH, hpCol, hpGlow, 6)
    else
        setC(T.separator)
        rect("line", PAD, healthY, SW-PAD*2, healthH, 6)
    end

    -- Label
    love.graphics.setFont(fBoldXs)
    setC(T.text_secondary)
    love.graphics.print("BATTERY HEALTH", PAD+10, healthY+6)

    -- Value
    love.graphics.setFont(fBoldBig)
    setC(hpCol)
    love.graphics.print(hpStr, PAD+10, healthY+healthH-fBoldBig:getHeight()-6)

    -- Sub label
    local hpLabel = "---"
    if hp then
        if hp >= 80 then hpLabel = "Good"
        elseif hp >= 60 then hpLabel = "Fair"
        else hpLabel = "Poor — consider replacing" end
    end
    love.graphics.setFont(fBoldSm)
    setC(hpCol)
    local hpLabelX = PAD+10 + fBoldBig:getWidth(hpStr) + 10
    love.graphics.print(hpLabel,
        hpLabelX, healthY+healthH-fBoldSm:getHeight()-8)

    -- Info hint (right side)
    love.graphics.setFont(fBoldXs)
    setC(T.text_disabled)
    rightText(fBoldXs, "A = What is this?",
        SW-PAD-10, healthY+(healthH-fBoldXs:getHeight())/2, T.text_disabled)

    -- Info panel
    local infoY  = healthY + healthH + 8
    local infoW  = SW - PAD*2
    local rowGap = 22
    local panelH = 7*rowGap + 12

    setC(T.bg_card)
    rect("fill", PAD, infoY, infoW, panelH, 6)
    setC(T.separator)
    rect("line", PAD, infoY, infoW, panelH, 6)

    local ry = infoY+8
    local rx = PAD+10
    local rw = infoW-20

    drawRow(rx, ry, rw, "Charge",
        fmtCharge(data.charge_counter, data.charge_full), T.text_primary)
    ry=ry+rowGap; drawSep(ry-4)

    drawRow(rx, ry, rw,
        isCharging and "Time to Full" or "Time to Empty",
        isCharging and fmtSeconds(data.time_to_full) or fmtSeconds(data.time_to_empty),
        isCharging and T.col_charging or T.col_discharging)
    ry=ry+rowGap; drawSep(ry-4)

    drawRow(rx, ry, rw, "Temperature", fmtTemp(data.temp_tdeg), T.col_warn)
    ry=ry+rowGap; drawSep(ry-4)

    drawRow(rx, ry, rw, "Chemical Health", data.health or "---", T.col_charging)
    ry=ry+rowGap; drawSep(ry-4)

    local lvl    = data.capacity_level or "---"
    local lvlCol = T.text_secondary
    if lvl == "Critical" then lvlCol = T.col_crit
    elseif lvl == "Low"  then lvlCol = T.col_warn
    elseif lvl == "High" then lvlCol = T.col_charging end
    drawRow(rx, ry, rw, "Level", lvl, lvlCol)
    ry=ry+rowGap; drawSep(ry-4)

    -- Last charged timestamp
    drawRow(rx, ry, rw, "Last Charged",
        fmtLastCharged(lastChargedTimestamp), T.text_primary)
    ry=ry+rowGap; drawSep(ry-4)

    -- Time on battery since last charge — pulses once the session
    -- has run long (>6h) as a gentle "you've been off charger a while" cue
    local LONG_SESSION_SECS = 6 * 3600
    local tobAlpha = nil
    local tobCol   = T.col_discharging
    if (not isCharging) and (not isFull) and timeOnBattery > LONG_SESSION_SECS then
        tobAlpha = 0.5 + pulse(1.5) * 0.5
        tobCol   = T.col_warn
    end
    drawRow(rx, ry, rw, "Time on Battery",
        fmtSeconds(timeOnBattery), tobCol, tobAlpha)

    -- Plug-in banner
    if bannerActive then
        local alpha = math.max(0, 1 - bannerTimer/BANNER_SECS)
        setC(T.col_charging, alpha*0.15)
        rect("fill", 0, 0, SW, SH)
        local bw, bh = 340, 58
        local bx = SW/2-bw/2
        local by = SH/2-bh/2
        setC(T.bg_card, alpha)
        rect("fill", bx, by, bw, bh, 8)
        setC(T.col_charging, alpha)
        rect("line", bx, by, bw, bh, 8)
        centreText(fBoldBig, "Cable plugged in  --  Charging",
            SW/2, by+(bh-fBoldBig:getHeight())/2, T.col_charging, alpha)
    end
end

-- ============================================================
-- SCENE: GRAPH
-- ============================================================
local function drawSceneGraph()
    setC(T.bg_main)
    rect("fill", 0, 0, SW, SH)

    drawHeader("Graph", supplyLabel)
    drawBtnBar({
        {icon=ic.B, label="Back", side="left"},
    })

    local PAD    = 14
    local bodyY  = HDR_H + 8
    local bodyH  = BTN_BAR_Y - bodyY - 8
    local graphH = (bodyH - 10) / 2

    -- Voltage range: compute dynamic min/max with padding
    local vMin, vMax = math.huge, -math.huge
    for _, v in ipairs(histVoltage) do
        if v < vMin then vMin = v end
        if v > vMax then vMax = v end
    end
    if vMin == math.huge then vMin, vMax = 3.5, 4.2 end
    local vPad = math.max(0.05, (vMax-vMin)*0.1)
    vMin = vMin - vPad; vMax = vMax + vPad

    drawLineGraph(
        PAD, bodyY, SW-PAD*2, graphH,
        histVoltage, vMin, vMax,
        T.accent_glow, "VOLTAGE",
        function(v) return string.format("%.2fV", v) end)

    -- Capacity: fixed 0-100
    drawLineGraph(
        PAD, bodyY+graphH+10, SW-PAD*2, graphH,
        histCapacity, 0, 100,
        capacityColor(), "CAPACITY",
        function(v) return string.format("%d%%", math.floor(v)) end)
end

-- ============================================================
-- SCENE: THEME PICKER
-- ============================================================
local function drawSceneTheme()
    setC(T.bg_main)
    rect("fill", 0, 0, SW, SH)

    drawHeader("Theme", nil)
    drawBtnBar({
        {icon=ic.B, label="Back",   side="left"},
        {icon=ic.A, label="Select", side="right"},
    })

    local listY  = HDR_H + 6
    local count  = fskit.theme.count()
    local rowH   = (BTN_BAR_Y - listY - 6) / count
    local PAD    = 14

    for i = 1, count do
        local theme = fskit.theme.palette(i)   -- raw fskit palette (fskit key names)
        local ry  = listY + (i-1)*rowH
        local sel = (i == themeSelIdx)

        if sel then
            setC(theme.accent, 0.20)
        else
            setC(theme.bg_panel, 0.45)
        end
        rect("fill", PAD, ry+2, SW-PAD*2, rowH-4, 5)

        if sel then
            glowRect(PAD, ry+2, SW-PAD*2, rowH-4, theme.accent,
                0.5 + pulse(2)*0.5, 5)
        end

        -- Colour swatches
        local swatches = {theme.accent, theme.ok, theme.warn, theme.danger, theme.bg_header}
        local sw2 = 16
        local sx0 = SW - PAD - (#swatches*(sw2+3))
        for j, col in ipairs(swatches) do
            setC(col)
            rect("fill", sx0+(j-1)*(sw2+3), ry+6, sw2, rowH-12, 3)
        end

        love.graphics.setFont(sel and fBoldMed or fBoldSm)
        setC(sel and theme.text_primary or T.text_secondary)
        love.graphics.print(theme.name, PAD+12,
            ry+(rowH-(sel and fBoldMed or fBoldSm):getHeight())/2)

        if i == fskit.theme.index() then
            love.graphics.setFont(fBoldXs)
            setC(theme.ok)
            love.graphics.print("[active]",
                PAD+12+(sel and fBoldMed or fBoldSm):getWidth(theme.name)+8,
                ry+(rowH-fBoldXs:getHeight())/2)
        end
    end
end

-- ============================================================
-- SCENE: HEALTH INFO DIALOG
-- ============================================================
local function drawSceneHealthInfo()
    -- Draw main underneath, dimmed
    drawSceneMain()
    setC({0, 0, 0}, 0.60)
    rect("fill", 0, 0, SW, SH)

    local dw, dh = 480, 300
    local dx = SW/2 - dw/2
    local dy = SH/2 - dh/2

    setC(T.bg_card)
    rect("fill", dx, dy, dw, dh, 10)
    glowRect(dx, dy, dw, dh, T.accent, 0.4 + pulse(1.5)*0.3, 10)

    -- Title
    love.graphics.setFont(fBoldBig)
    setC(T.accent_glow)
    centreText(fBoldBig, "About Battery Health", SW/2, dy+16, T.accent_glow)

    -- Divider
    setC(T.separator)
    love.graphics.line(dx+16, dy+42, dx+dw-16, dy+42)

    -- Body text — wrapped manually into lines
    local lines = {
        {text="What is Battery Health %?", font=fBoldMed, col=T.text_primary},
        {text="", font=fSm, col=T.text_secondary},
        {text="It compares your battery's current learned capacity", font=fSm, col=T.text_secondary},
        {text="against its original factory capacity. Over time,", font=fSm, col=T.text_secondary},
        {text="batteries lose the ability to hold a full charge.", font=fSm, col=T.text_secondary},
        {text="", font=fSm, col=T.text_secondary},
        {text="  >80%   Good  —  battery is healthy", font=fBoldSm, col=T.col_charging},
        {text="  60-80%  Fair  —  some wear, still usable", font=fBoldSm, col=T.col_warn},
        {text="  <60%   Poor  —  consider replacing", font=fBoldSm, col=T.col_crit},
        {text="", font=fSm, col=T.text_secondary},
        {text="How to recalibrate:", font=fBoldMed, col=T.text_primary},
        {text="Fully discharge the battery, then charge to 100%", font=fSm, col=T.text_secondary},
        {text="without interruption. This lets the AXP2202 fuel", font=fSm, col=T.text_secondary},
        {text="gauge relearn the battery's true capacity.", font=fSm, col=T.text_secondary},
    }

    local lineY = dy + 52
    local lineH = 15
    for _, line in ipairs(lines) do
        if line.text ~= "" then
            love.graphics.setFont(line.font)
            setC(line.col)
            love.graphics.print(line.text, dx+18, lineY)
        end
        lineY = lineY + lineH
    end

    -- Button bar area at bottom of dialog
    local btnY = dy + dh - 36
    setC(T.separator)
    love.graphics.line(dx+16, btnY, dx+dw-16, btnY)
    love.graphics.draw(ic.B, dx+16, btnY+8)
    love.graphics.setFont(fBoldSm)
    setC(T.text_secondary)
    love.graphics.print("Close", dx+42, btnY+10)
end

-- ============================================================
-- SCENE: EXIT DIALOG
-- ============================================================
local function drawSceneExit()
    -- Dim the background
    setC({0, 0, 0}, 0.55)
    rect("fill", 0, 0, SW, SH)

    local dw, dh = 340, 160
    local dx = SW/2 - dw/2
    local dy = SH/2 - dh/2

    -- Card background
    setC(T.bg_card)
    rect("fill", dx, dy, dw, dh, 10)

    -- Accent border with glow
    glowRect(dx, dy, dw, dh, T.accent, 0.5 + pulse(2)*0.4, 10)

    -- Icon area — small battery warning
    love.graphics.setFont(fBoldBig)
    setC(T.accent_glow)
    centreText(fBoldBig, "Exit BatteryMu?", SW/2, dy+22, T.accent_glow)

    love.graphics.setFont(fBoldSm)
    setC(T.text_secondary)
    centreText(fBoldSm, "Are you sure you want to quit?", SW/2, dy+52, T.text_secondary)

    -- Buttons
    local btnW, btnH = 120, 38
    local gap        = 20
    local totalW     = btnW*2 + gap
    local btnY       = dy + dh - btnH - 18

    -- Cancel (B) — left
    local cancelX = SW/2 - totalW/2
    setC(T.bg_main)
    rect("fill", cancelX, btnY, btnW, btnH, 6)
    setC(T.separator)
    rect("line", cancelX, btnY, btnW, btnH, 6)
    love.graphics.draw(ic.B, cancelX+10, btnY+(btnH-20)/2)
    love.graphics.setFont(fBoldSm)
    setC(T.text_primary)
    love.graphics.print("Cancel", cancelX+36, btnY+(btnH-fBoldSm:getHeight())/2)

    -- Confirm (A) — right, glowing
    local confirmX = SW/2 - totalW/2 + btnW + gap
    setC(T.bg_main)
    rect("fill", confirmX, btnY, btnW, btnH, 6)
    glowRect(confirmX, btnY, btnW, btnH, T.col_crit,
        0.4 + pulse(3)*0.5, 6)
    love.graphics.draw(ic.A, confirmX+10, btnY+(btnH-20)/2)
    setC(T.col_crit)
    love.graphics.print("Quit", confirmX+36, btnY+(btnH-fBoldSm:getHeight())/2)
end

-- ============================================================
-- TRANSITION OVERLAY
-- ============================================================
local function drawTransition()
    if transAlpha > 0.01 then
        setC({0, 0, 0}, transAlpha)
        rect("fill", 0, 0, SW, SH)
    end
end

-- ============================================================
-- LOVE CALLBACKS
-- ============================================================
function love.load()
    fskit.load()

    fHuge    = fskit.font.huge
    fBig     = fskit.font.xl
    fBoldBig = fskit.font.lg
    fBoldMed = fskit.font.md
    fBoldSm  = fskit.font.sm
    fBoldXs  = fskit.font.xs
    fSm      = fskit.font.body
    fXs      = fskit.font.body_xs

    ic.A  = fskit.glyph.get("a")
    ic.B  = fskit.glyph.get("b")
    ic.X  = fskit.glyph.get("x")
    ic.Y  = fskit.glyph.get("y")
    ic.L1 = fskit.glyph.get("l1")
    ic.R1 = fskit.glyph.get("r1")

    fskit.theme.bind{ load = themeLoad, save = function() saveSettings() end }
    rebuildT()
    themeSelIdx = fskit.theme.index()
    fskit.input.hook(handleInput)

    loadSettings()
    supply      = resolveBase()          -- sysfs base dir (with "/") or nil
    supplyLabel = supply and (supply:match("([^/]+)/?$") or supply) or nil
    pollBattery()

    -- Backfill time-on-battery for the gap while the app was closed. Skipped
    -- when muOS's own battery-usage tracker is authoritative (pollBattery
    -- already pulled the real figure from it).
    local now = os.time()
    local stillNotCharging = not (data.status == "Charging" or data.status == "Full")
    if not ENV_USAGE_DIR and lastMeasurementTimestamp and stillNotCharging then
        local gap = now - lastMeasurementTimestamp
        if gap > 0 then
            timeOnBattery = timeOnBattery + gap
        end
    end
    lastMeasurementTimestamp = now
    saveSettings()
end

function love.update(dt)
    globalTime = globalTime + dt

    -- Banner countdown
    if bannerActive then
        bannerTimer = bannerTimer + dt
        if bannerTimer >= BANNER_SECS then
            bannerActive = false
            bannerTimer  = 0
        end
    end

    -- Live accumulation of time-on-battery while discharging
    local notCharging = not (data.status == "Charging" or data.status == "Full")
    if notCharging then
        timeOnBattery = timeOnBattery + dt
    end

    -- Poll battery (every second) but only flush settings to disk every 30s
    -- (plus on quit / on charge-state change) -- avoids hammering SD flash.
    pollTimer = pollTimer + dt
    if pollTimer >= POLL_INTERVAL then
        pollTimer = 0
        pollBattery()
        lastMeasurementTimestamp = os.time()
        saveTimer = (saveTimer or 0) + POLL_INTERVAL
        if saveTimer >= 30 then
            saveTimer = 0
            saveSettings()
        end
    end

    -- Scene transition
    if transDir == 1 then
        transAlpha = math.min(1, transAlpha + dt * TRANS_SPEED)
        if transAlpha >= 1 then
            scene    = transTarget
            transDir = -1
        end
    elseif transDir == -1 then
        transAlpha = math.max(0, transAlpha - dt * TRANS_SPEED)
        if transAlpha <= 0 then
            transDir = 0
        end
    end
end

function love.quit()
    lastMeasurementTimestamp = os.time()
    saveSettings()
end

function love.draw()
    fskit.screen.begin()

    if     scene == "main"       then drawSceneMain()
    elseif scene == "graph"      then drawSceneGraph()
    elseif scene == "theme"      then drawSceneTheme()
    elseif scene == "healthinfo" then drawSceneHealthInfo()
    end

    -- Exit dialog draws on top of whatever scene is current
    if scene == "exit" then
        drawSceneMain()
        drawSceneExit()
    end

    drawTransition()
    fskit.screen.finish()
end

function love.resize(w, h)
    fskit.screen.resize(w, h)
end

-- ============================================================
-- INPUT   (love callbacks are wired by fskit.input.hook in love.load;
--          canonical button names: up/down/left/right a/b/x/y l1/r1 ...)
-- ============================================================
function handleInput(button)
    if transDir ~= 0 then return end

    if scene == "main" then
        if     button == "b" then gotoScene("exit")
        elseif button == "a" then gotoScene("healthinfo")
        elseif button == "x" then gotoScene("graph")
        elseif button == "y" then gotoScene("theme"); themeSelIdx = fskit.theme.index()
        end

    elseif scene == "exit" then
        if     button == "a" then love.event.quit()
        elseif button == "b" then gotoScene("main")
        end

    elseif scene == "graph" then
        if button == "b" then gotoScene("main") end

    elseif scene == "theme" then
        local count = fskit.theme.count()
        if     button == "b" then gotoScene("main")
        elseif button == "a" then
            fskit.theme.set(themeSelIdx)   -- persists + rebuilds T via onChange
            gotoScene("main")
        elseif button == "up" then
            themeSelIdx = ((themeSelIdx-2) % count)+1
        elseif button == "down" then
            themeSelIdx = (themeSelIdx % count)+1
        end

    elseif scene == "healthinfo" then
        if button == "b" then gotoScene("main") end
    end
end
