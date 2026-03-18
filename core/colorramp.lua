-- colorramp.lua - Per-character gradient text utility
local addonName, addon = ...

-- Lighten a color by mixing toward white.
-- ratio 0.0 = unchanged, 1.0 = white
function addon.LightenColor(r, g, b, ratio)
    local t = ratio or 0.45
    return r + (1.0 - r) * t, g + (1.0 - g) * t, b + (1.0 - b) * t
end

-- Darken a color by mixing toward black.
-- ratio 0.0 = unchanged, 1.0 = black
function addon.DarkenColor(r, g, b, ratio)
    local t = ratio or 0.15
    return r * (1 - t), g * (1 - t), b * (1 - t)
end

-- Curated gradient endpoint colors per class.
-- Each is a brighter, hue-shifted variant that creates a richer ramp than generic lightening.
addon.CLASS_GRADIENT_ENDPOINTS = {
    DEATHKNIGHT = { 1.00, 0.35, 0.30 },
    DEMONHUNTER = { 0.88, 0.45, 1.00 },
    DRUID       = { 1.00, 0.75, 0.35 },
    EVOKER      = { 0.40, 0.85, 0.75 },
    HUNTER      = { 0.85, 1.00, 0.60 },
    MAGE        = { 0.55, 0.92, 1.00 },
    MONK        = { 0.35, 1.00, 0.80 },
    PALADIN     = { 1.00, 0.78, 0.88 },
    PRIEST      = { 1.00, 1.00, 0.85 },
    ROGUE       = { 1.00, 1.00, 0.70 },
    SHAMAN      = { 0.30, 0.70, 1.00 },
    WARLOCK     = { 0.75, 0.55, 1.00 },
    WARRIOR     = { 0.95, 0.80, 0.60 },
}

-- Strip WoW escape sequences (|cff..., |r, |T...|t, |A...|a, |n) from a string.
local function stripEscapes(text)
    local s = text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")  -- |cffRRGGBB or |cAARRGGBB
    s = s:gsub("|r", "")
    s = s:gsub("|T.-|t", "")                -- texture escapes
    s = s:gsub("|A.-|a", "")                -- atlas escapes
    s = s:gsub("|n", "\n")                  -- newline escape
    return s
end

-- Extract individual UTF-8 characters from a string into a table.
local function utf8Chars(text)
    local chars = {}
    local i = 1
    local len = #text
    while i <= len do
        local byte = text:byte(i)
        local charLen
        if byte < 0x80 then
            charLen = 1
        elseif byte < 0xE0 then
            charLen = 2
        elseif byte < 0xF0 then
            charLen = 3
        else
            charLen = 4
        end
        chars[#chars + 1] = text:sub(i, i + charLen - 1)
        i = i + charLen
    end
    return chars
end

-- Build a string with per-character |cffRRGGBB color codes for a two-stop gradient.
-- r1,g1,b1 = start color (0-1), r2,g2,b2 = end color (0-1)
function addon.BuildColorRampString(text, r1, g1, b1, r2, g2, b2)
    if type(text) ~= "string" or text == "" then return text end

    local clean = stripEscapes(text)
    if clean == "" then return text end

    local chars = utf8Chars(clean)
    local total = #chars
    if total == 0 then return text end

    -- Single character: just use start color
    if total == 1 then
        local ch = chars[1]
        if ch:match("^%s+$") then return ch end
        return string.format("|cff%02x%02x%02x%s|r",
            math.floor(r1 * 255 + 0.5),
            math.floor(g1 * 255 + 0.5),
            math.floor(b1 * 255 + 0.5),
            ch)
    end

    local parts = {}
    local visibleCount = 0
    -- Count non-whitespace characters for gradient spread
    for idx = 1, total do
        if not chars[idx]:match("^%s+$") then
            visibleCount = visibleCount + 1
        end
    end

    local colorIdx = 0
    local denom = math.max(visibleCount - 1, 1)
    for idx = 1, total do
        local ch = chars[idx]
        if ch:match("^%s+$") then
            -- Whitespace passes through without color codes
            parts[#parts + 1] = ch
        else
            local t = colorIdx / denom
            local cr = r1 + (r2 - r1) * t
            local cg = g1 + (g2 - g1) * t
            local cb = b1 + (b2 - b1) * t
            parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r",
                math.floor(cr * 255 + 0.5),
                math.floor(cg * 255 + 0.5),
                math.floor(cb * 255 + 0.5),
                ch)
            colorIdx = colorIdx + 1
        end
    end

    return table.concat(parts)
end
