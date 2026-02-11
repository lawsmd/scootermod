-- settingspanel/ascii.lua - ASCII art data, UTF-8 helpers, and animation
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme

--------------------------------------------------------------------------------
-- Animation Constants
--------------------------------------------------------------------------------

local ASCII_ANIMATION_DURATION = 1.0      -- Total animation time in seconds
local ASCII_ANIMATION_TICK = 0.016        -- Update rate (~60fps)

--------------------------------------------------------------------------------
-- UTF-8 String Helpers (for column-by-column ASCII animation)
--------------------------------------------------------------------------------

-- Extract a table of UTF-8 characters from a string
-- Uses byte-based iteration to avoid Lua pattern issues with escape sequences
local function utf8Chars(s)
    if not s then return {} end
    local chars = {}
    local i = 1
    local len = #s
    while i <= len do
        local c = s:byte(i)
        local charLen = 1
        -- Determine UTF-8 character length from first byte
        if c >= 0xF0 then      -- 4-byte sequence (0xF0-0xF4)
            charLen = 4
        elseif c >= 0xE0 then  -- 3-byte sequence (0xE0-0xEF)
            charLen = 3
        elseif c >= 0xC0 then  -- 2-byte sequence (0xC0-0xDF)
            charLen = 2
        end
        -- Extract the character and add to table
        table.insert(chars, s:sub(i, i + charLen - 1))
        i = i + charLen
    end
    return chars
end

-- Get first N UTF-8 characters as a string
local function utf8Sub(s, n)
    if not s or n <= 0 then return "" end
    local chars = utf8Chars(s)
    local result = {}
    for i = 1, math.min(n, #chars) do
        table.insert(result, chars[i])
    end
    return table.concat(result)
end

-- Count UTF-8 characters in a string
local function utf8Len(s)
    if not s then return 0 end
    return #utf8Chars(s)
end

--------------------------------------------------------------------------------
-- ASCII Art Data
--------------------------------------------------------------------------------

local ASCII_LOGO = [[
 ██████╗ █████╗  █████╗  █████╗ ████████╗███████╗██████╗ ███╗   ███╗ █████╗ ██████╗
██╔════╝██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██╔══██╗██╔══██╗
╚█████╗ ██║  ╚═╝██║  ██║██║  ██║   ██║   █████╗  ██████╔╝██╔████╔██║██║  ██║██║  ██║
 ╚═══██╗██║  ██╗██║  ██║██║  ██║   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║  ██║██║  ██║
██████╔╝╚█████╔╝╚█████╔╝╚█████╔╝   ██║   ███████╗██║  ██║██║ ╚═╝ ██║╚█████╔╝██████╔╝
╚═════╝  ╚════╝  ╚════╝  ╚════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚════╝ ╚═════╝ ]]

-- ASCII Art Mascot (54 chars wide) for homepage
local ASCII_MASCOT = [[
                             ***
         .==.              **====*
         ..==            *==========
          .==          **======....-==
          .==-        ***=====...   .==
          .==:       **=======....   =*
          .==:     .*******==-....
          .==:  ***..========-***..
           ==. .--..@@@@%@@@@*@==..-==
           ==:    .     -    :@@@=%=..=
            =:    *%   %%%   #@@===+
            =:     %%*@@@@@@%@@@==%
            =:      @@=====@@@@@...
           %+=##= *@@@@@@@@@@@@.-==-..
          %%%%===.+@@@@@@@@@@@@..====..
          %%%%=%===.@@@@@@@@@*....====..
           %%+.=..=..=@@@@@@.==....*===..
             :...... ===@..=====...**===.
             -:-..  ......===..   .#****-
             -=.    ...............=%%%%*
             -=.    ***==========..:=====
              =.   **=============..=
              =.. ***==============.==
              =-. *+================-:=*
              ==..==....=========..==...*
              .=.=====...........======.-=*]]

-- Pre-parse ASCII logo into lines and character arrays for animation
local ASCII_LINES = {}
local ASCII_MAX_COLS = 0

do
    -- Split ASCII_LOGO into lines
    for line in ASCII_LOGO:gmatch("[^\n]+") do
        local lineData = {
            text = line,
            chars = utf8Chars(line),
        }
        lineData.len = #lineData.chars
        table.insert(ASCII_LINES, lineData)
        if lineData.len > ASCII_MAX_COLS then
            ASCII_MAX_COLS = lineData.len
        end
    end
end

--------------------------------------------------------------------------------
-- ASCII Art Column Animation
--
-- Reveals the ASCII art one vertical column at a time, from left to right.
-- All lines are updated simultaneously to reveal up to column N.
--------------------------------------------------------------------------------

-- Build partial ASCII text showing only columns 1..n
local function buildPartialAscii(numCols)
    if numCols <= 0 then return "" end
    if numCols >= ASCII_MAX_COLS then return ASCII_LOGO end

    local lines = {}
    for i, lineData in ipairs(ASCII_LINES) do
        local partial = ""
        for j = 1, math.min(numCols, lineData.len) do
            partial = partial .. lineData.chars[j]
        end
        table.insert(lines, partial)
    end
    return table.concat(lines, "\n")
end

-- Animate ASCII logo reveal (column by column)
function UIPanel:AnimateAsciiReveal()
    local frame = self.frame
    if not frame or not frame._logo then return end

    local logo = frame._logo
    local logoBtn = frame._logoBtn

    -- Cancel any existing animation
    self:StopAsciiAnimation()

    local startTime = GetTime()
    local totalColumns = ASCII_MAX_COLS

    -- Ensure text color is accent (not hover state) at start
    local ar, ag, ab = Theme:GetAccentColor()
    logo:SetTextColor(ar, ag, ab, 1)

    -- Start with empty text
    logo:SetText("")

    -- Create animation ticker
    local ticker
    ticker = C_Timer.NewTicker(ASCII_ANIMATION_TICK, function()
        local elapsed = GetTime() - startTime
        local progress = math.min(elapsed / ASCII_ANIMATION_DURATION, 1.0)

        -- Calculate how many columns to show (linear progression)
        local columnsToShow = math.floor(progress * totalColumns)

        -- Build and set partial text
        local partialText = buildPartialAscii(columnsToShow)
        logo:SetText(partialText)

        -- Stop when complete
        if progress >= 1.0 then
            ticker:Cancel()
            frame._asciiAnimTicker = nil
            logo:SetText(ASCII_LOGO)  -- Ensure final state is exact
            -- Reset color to accent (unless currently hovering)
            if logoBtn and not logoBtn:IsMouseOver() then
                local r, g, b = Theme:GetAccentColor()
                logo:SetTextColor(r, g, b, 1)
            end
        end
    end)

    -- Store reference for cleanup
    frame._asciiAnimTicker = ticker
end

-- Stop ASCII animation and reset to full state
function UIPanel:StopAsciiAnimation()
    local frame = self.frame
    if not frame then return end

    if frame._asciiAnimTicker then
        frame._asciiAnimTicker:Cancel()
        frame._asciiAnimTicker = nil
    end

    -- Reset to full logo with proper color
    if frame._logo then
        frame._logo:SetText(ASCII_LOGO)
        -- Reset color to accent (unless currently hovering)
        if frame._logoBtn and not frame._logoBtn:IsMouseOver() then
            local r, g, b = Theme:GetAccentColor()
            frame._logo:SetTextColor(r, g, b, 1)
        end
    end
end

-- Check if animation is running
function UIPanel:IsAsciiAnimationRunning()
    local frame = self.frame
    return frame and frame._asciiAnimTicker ~= nil
end

--------------------------------------------------------------------------------
-- Cross-file promotions (consumed by core.lua and navigation.lua)
--------------------------------------------------------------------------------

UIPanel._ASCII_LOGO = ASCII_LOGO
UIPanel._ASCII_MASCOT = ASCII_MASCOT
