-- SettingsPanel.lua - Main UI settings panel orchestration
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Window = addon.UI.Window
local Controls = addon.UI.Controls
local Navigation = addon.UI.Navigation
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PANEL_WIDTH = 1125   -- 25% wider than original 900
local PANEL_HEIGHT = 715   -- 10% taller than original 650
local TITLE_BAR_HEIGHT = 80  -- Taller for ASCII art
local CLOSE_BUTTON_SIZE = 24
local RESIZE_HANDLE_SIZE = 16
local HEADER_BUTTON_HEIGHT = 26
local HEADER_BUTTON_SPACING = 10  -- Gap between header buttons

-- Resize limits (reasonable bounds for usability)
local MIN_WIDTH = 800
local MIN_HEIGHT = 550
local MAX_WIDTH = 1600
local MAX_HEIGHT = 1000

-- Text color mode options (used by PRD and CDM SelectorColorPickers)
local textColorValues = { default = "Default", class = "Class Color", custom = "Custom" }
local textColorOrder = { "default", "class", "custom" }
local textColorPowerValues = { default = "Default", class = "Class Color", classPower = "Class Power Color", custom = "Custom" }
local textColorPowerOrder = { "default", "class", "classPower", "custom" }

-- Animation constants for ASCII art column reveal
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
-- Panel State
--------------------------------------------------------------------------------

UIPanel.frame = nil
UIPanel._initialized = false
UIPanel._currentCategoryKey = nil    -- Currently displayed category
UIPanel._pendingBackSync = {}        -- Components needing refresh from Edit Mode back-sync

--------------------------------------------------------------------------------
-- Edit Mode Back-Sync Handler
--------------------------------------------------------------------------------
-- Called by addon.EditMode when Edit Mode writes values back to ScooterMod.
-- Marks the affected component for refresh and triggers re-render if visible.
--------------------------------------------------------------------------------

function UIPanel:HandleEditModeBackSync(componentId, settingId)
    if not componentId then return end

    -- Mark component as needing refresh
    self._pendingBackSync[componentId] = true

    -- Map componentId to navigation key
    local categoryKey = nil
    if componentId == "essentialCooldowns" then
        categoryKey = "essentialCooldowns"
    elseif componentId == "utilityCooldowns" then
        categoryKey = "utilityCooldowns"
    elseif componentId == "trackedBuffs" then
        categoryKey = "trackedBuffs"
    elseif componentId == "trackedBars" then
        categoryKey = "trackedBars"
    elseif componentId == "cdmQoL" then
        categoryKey = "cdmQoL"
    -- Unit Frames
    elseif componentId == "ufPlayer" then
        categoryKey = "ufPlayer"
    elseif componentId == "ufTarget" then
        categoryKey = "ufTarget"
    elseif componentId == "ufFocus" then
        categoryKey = "ufFocus"
    elseif componentId == "ufPet" then
        categoryKey = "ufPet"
    elseif componentId == "ufToT" then
        categoryKey = "ufToT"
    elseif componentId == "ufBoss" then
        categoryKey = "ufBoss"
    -- Buffs/Debuffs
    elseif componentId == "buffs" then
        categoryKey = "buffs"
    elseif componentId == "debuffs" then
        categoryKey = "debuffs"
    -- Group Frames
    elseif componentId == "gfParty" then
        categoryKey = "gfParty"
    elseif componentId == "gfRaid" then
        categoryKey = "gfRaid"
    -- Action Bars (ab1 through ab8)
    elseif componentId == "ab1" then
        categoryKey = "ab1"
    elseif componentId == "ab2" then
        categoryKey = "ab2"
    elseif componentId == "ab3" then
        categoryKey = "ab3"
    elseif componentId == "ab4" then
        categoryKey = "ab4"
    elseif componentId == "ab5" then
        categoryKey = "ab5"
    elseif componentId == "ab6" then
        categoryKey = "ab6"
    elseif componentId == "ab7" then
        categoryKey = "ab7"
    elseif componentId == "ab8" then
        categoryKey = "ab8"
    -- Micro/Menu bar
    elseif componentId == "microBar" then
        categoryKey = "microBar"
    -- Damage Meter
    elseif componentId == "damageMeter" then
        categoryKey = "damageMeter"
    -- Objective Tracker
    elseif componentId == "objectiveTracker" then
        categoryKey = "objectiveTracker"
    end

    -- If currently viewing this category, trigger refresh
    if categoryKey and self._currentCategoryKey == categoryKey then
        -- Defer to avoid mid-render issues
        C_Timer.After(0, function()
            if self.frame and self.frame:IsShown() then
                self:OnNavigationSelect(categoryKey, categoryKey)
            end
        end)
    end
end

-- Check and clear pending back-sync for a component
function UIPanel:CheckPendingBackSync(componentId)
    if self._pendingBackSync[componentId] then
        self._pendingBackSync[componentId] = nil
        return true
    end
    return false
end

-- Clear all pending back-syncs (e.g., when panel closes)
function UIPanel:ClearPendingBackSync()
    wipe(self._pendingBackSync)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function UIPanel:Initialize()
    if self._initialized then return end

    -- Restore saved size or use defaults
    local savedWidth, savedHeight = PANEL_WIDTH, PANEL_HEIGHT
    if addon.db and addon.db.global and addon.db.global.windowSize then
        local size = addon.db.global.windowSize
        savedWidth = size.width or PANEL_WIDTH
        savedHeight = size.height or PANEL_HEIGHT
    end

    -- Create main window frame
    local frame = Window:Create("ScooterUISettingsFrame", UIParent, savedWidth, savedHeight)
    frame:SetPoint("CENTER")
    frame:Hide()
    self.frame = frame

    -- Enable resizing with limits
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)

    -- Build UI components
    self:CreateTitleBar()
    self:CreateCloseButton()
    self:CreateHeaderButtons()
    self:CreateResizeHandle()
    self:CreateNavigation()
    self:CreateContentPane()

    -- Register for ESC to close
    tinsert(UISpecialFrames, "ScooterUISettingsFrame")


    -- Restore saved position if available
    Window:RestorePosition(frame)

    self._initialized = true
end

--------------------------------------------------------------------------------
-- ASCII Art Header
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
-- Title Bar (with clickable ASCII art logo)
--------------------------------------------------------------------------------

function UIPanel:CreateTitleBar()
    local frame = self.frame
    if not frame then return end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(TITLE_BAR_HEIGHT)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    -- Make title bar draggable (but not the logo button area)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if addon.db and addon.db.global then
            local point, _, relPoint, x, y = frame:GetPoint()
            addon.db.global.windowPosition = {
                point = point,
                relPoint = relPoint,
                x = x,
                y = y
            }
        end
    end)

    -- Clickable ASCII logo button (navigates to Home)
    local logoBtn = CreateFrame("Button", "ScooterUILogoBtn", titleBar)
    logoBtn:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 10, -6)
    logoBtn:EnableMouse(true)
    logoBtn:RegisterForClicks("AnyUp")

    local ar, ag, ab = Theme:GetAccentColor()

    -- ASCII art logo text (create first to measure)
    local logo = logoBtn:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("LABEL")
    logo:SetFont(fontPath, 6, "")
    logo:SetPoint("TOPLEFT", 2, -2)
    logo:SetText(ASCII_LOGO)
    logo:SetJustifyH("LEFT")
    logo:SetTextColor(ar, ag, ab, 1)
    logoBtn._logo = logo

    -- Size button tightly to the logo (defer to get accurate measurements)
    -- NOTE: We always measure with full ASCII_LOGO text since current text may be
    -- empty (home state) when the timer fires
    C_Timer.After(0.05, function()
        if logo and logoBtn then
            -- Temporarily set full text to measure, then restore
            local currentText = logo:GetText()
            logo:SetText(ASCII_LOGO)
            local w = logo:GetStringWidth() or 400
            local h = logo:GetStringHeight() or 40
            logo:SetText(currentText or "")
            logoBtn:SetSize(w + 4, h + 4)
            if logoBtn._hoverBg then
                logoBtn._hoverBg:SetSize(w + 4, h + 4)
            end
        end
    end)
    -- Fallback size
    logoBtn:SetSize(420, 45)

    -- Hover background (hidden by default, sized to match logo)
    local hoverBg = logoBtn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetPoint("TOPLEFT", 0, 0)
    hoverBg:SetPoint("BOTTOMRIGHT", 0, 0)
    hoverBg:SetColorTexture(ar, ag, ab, 1)
    hoverBg:Hide()
    logoBtn._hoverBg = hoverBg

    -- Store reference to panel for click handler
    local panel = self

    -- Hover effect: inverted colors (dark text on accent background)
    logoBtn:SetScript("OnEnter", function(btn)
        local r, g, b = Theme:GetAccentColor()
        btn._hoverBg:SetColorTexture(r, g, b, 1)
        btn._hoverBg:Show()
        btn._logo:SetTextColor(0, 0, 0, 1)  -- Dark text on accent bg
    end)

    logoBtn:SetScript("OnLeave", function(btn)
        btn._hoverBg:Hide()
        local r, g, b = Theme:GetAccentColor()
        btn._logo:SetTextColor(r, g, b, 1)  -- Accent text on transparent bg
    end)

    -- Click to navigate to Home
    logoBtn:SetScript("OnClick", function(btn, mouseButton)
        if panel then
            panel:GoHome()
        end
    end)

    -- Allow dragging from logo area too
    logoBtn:RegisterForDrag("LeftButton")
    logoBtn:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    logoBtn:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if addon.db and addon.db.global then
            local point, _, relPoint, x, y = frame:GetPoint()
            addon.db.global.windowPosition = {
                point = point,
                relPoint = relPoint,
                x = x,
                y = y
            }
        end
    end)

    -- Store references
    frame._titleBar = titleBar
    frame._logoBtn = logoBtn
    frame._logo = logo

    -- Subscribe to theme updates
    Theme:Subscribe("UIPanel_TitleBar", function(r, g, b)
        if logo and logo.SetTextColor and not logoBtn:IsMouseOver() then
            logo:SetTextColor(r, g, b, 1)
        end
        if hoverBg then
            hoverBg:SetColorTexture(r, g, b, 1)
        end
    end)
end

--------------------------------------------------------------------------------
-- Go Home (navigate to home, clear nav selection)
--------------------------------------------------------------------------------

function UIPanel:GoHome()
    -- Clear navigation selection
    if Navigation then
        Navigation._selectedKey = nil
        Navigation:UpdateRowColors()
    end

    -- Update content pane for home
    self:OnNavigationSelect("home", Navigation and Navigation._selectedKey)
end

--------------------------------------------------------------------------------
-- Close Button (with hover effect: green bg + black X)
--------------------------------------------------------------------------------

function UIPanel:CreateCloseButton()
    local frame = self.frame
    if not frame then return end

    -- Create button with explicit frame level above everything else
    local closeBtn = CreateFrame("Button", "ScooterUICloseButton", frame)
    closeBtn:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    closeBtn:EnableMouse(true)
    closeBtn:RegisterForClicks("AnyUp", "AnyDown")

    -- Background (hidden by default, shown on hover)
    local bg = closeBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local ar, ag, ab = Theme:GetAccentColor()
    bg:SetColorTexture(ar, ag, ab, 1)
    bg:Hide()
    closeBtn._bg = bg

    -- Button label (X character)
    local label = closeBtn:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("BUTTON")
    label:SetFont(fontPath, 16, "")
    label:SetPoint("CENTER", 0, -1)
    label:SetText("X")
    label:SetTextColor(ar, ag, ab, 1)
    closeBtn._label = label

    -- Store reference to panel for click handler
    local panel = self

    -- Hover: show green background, make X black
    closeBtn:SetScript("OnEnter", function(btn)
        local r, g, b = Theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 1)
        btn._bg:Show()
        btn._label:SetTextColor(0, 0, 0, 1)  -- Black X on green bg
    end)

    closeBtn:SetScript("OnLeave", function(btn)
        btn._bg:Hide()
        local r, g, b = Theme:GetAccentColor()
        btn._label:SetTextColor(r, g, b, 1)  -- Green X on transparent bg
    end)

    -- Click to close
    closeBtn:SetScript("OnClick", function(btn, button, down)
        if panel and panel.frame then
            panel.frame:Hide()
        end
    end)

    frame._closeBtn = closeBtn

    -- Subscribe to theme updates
    Theme:Subscribe("UIPanel_CloseBtn", function(r, g, b)
        if closeBtn._bg then
            closeBtn._bg:SetColorTexture(r, g, b, 1)
        end
        if closeBtn._label and not closeBtn:IsMouseOver() then
            closeBtn._label:SetTextColor(r, g, b, 1)
        end
    end)
end

--------------------------------------------------------------------------------
-- Header Buttons (straddling top edge: Edit Mode, Cooldown Manager)
--------------------------------------------------------------------------------

function UIPanel:CreateHeaderButtons()
    local frame = self.frame
    if not frame then return end

    -- Store reference to panel for click handlers
    local panel = self

    -- Edit Mode button
    local editModeBtn = Controls:CreateButton({
        parent = frame,
        name = "ScooterUIEditModeBtn",
        text = "Edit Mode",
        height = HEADER_BUTTON_HEIGHT,
        fontSize = 11,
        template = "SecureActionButtonTemplate, SecureHandlerClickTemplate",
        secureAction = {}, -- triggers AnyUp registration in Button.lua
    })

    local function setupSecureEditMode()
        if not C_AddOns.IsAddOnLoaded("Blizzard_EditMode") then
             C_AddOns.LoadAddOn("Blizzard_EditMode")
        end
        if EditModeManagerFrame then
             SecureHandlerSetFrameRef(editModeBtn, "em", EditModeManagerFrame)
             editModeBtn:SetAttribute("_onclick", [[ self:GetFrameRef("em"):Show() ]])
        end
    end

    if InCombatLockdown() then
        editModeBtn:RegisterEvent("PLAYER_REGEN_ENABLED")
        editModeBtn:HookScript("OnEvent", function(self, event)
             if event == "PLAYER_REGEN_ENABLED" then
                  setupSecureEditMode()
                  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
             end
        end)
    else
        setupSecureEditMode()
    end

    -- Pre-click handler: only set the guard flag for Edit Mode entry.
    -- Do NOT call ApplyChanges() here — it taints the execution context.
    -- The EnterEditMode post-hook (core/editmode.lua) handles refreshing
    -- each system frame's settings from fresh C-side data.
    editModeBtn:SetScript("PreClick", function()
        if addon and addon.EditMode then
            if addon.EditMode.MarkOpeningEditMode then
                addon.EditMode.MarkOpeningEditMode()
            end
        end
    end)

    -- Cooldown Manager button
    local cdmBtn = Controls:CreateButton({
        parent = frame,
        name = "ScooterUICdmBtn",
        text = "Cooldown Manager",
        height = HEADER_BUTTON_HEIGHT,
        fontSize = 11,
        onClick = function(btn, mouseButton)
            if addon and addon.OpenCooldownManagerSettings then
                addon:OpenCooldownManagerSettings()
            end
            -- Close settings panel
            if panel and panel.frame and panel.frame:IsShown() then
                panel.frame:Hide()
            end
        end
    })

    -- Position buttons straddling the top edge, right-aligned
    -- They should be centered vertically on the top border
    local function PositionHeaderButtons()
        local inset = math.floor((frame:GetWidth() or 0) * 0.10)

        cdmBtn:ClearAllPoints()
        cdmBtn:SetPoint("CENTER", frame, "TOPRIGHT", -inset - (cdmBtn:GetWidth() / 2), 0)

        editModeBtn:ClearAllPoints()
        editModeBtn:SetPoint("RIGHT", cdmBtn, "LEFT", -HEADER_BUTTON_SPACING, 0)
    end

    PositionHeaderButtons()

    -- Reposition on window resize
    frame:HookScript("OnSizeChanged", PositionHeaderButtons)

    -- Elevate frame level to ensure buttons appear above the border
    editModeBtn:SetFrameLevel(frame:GetFrameLevel() + 15)
    cdmBtn:SetFrameLevel(frame:GetFrameLevel() + 15)

    -- Store references
    frame._editModeBtn = editModeBtn
    frame._cdmBtn = cdmBtn
end

--------------------------------------------------------------------------------
-- Resize Handle (bottom-right corner grip)
--------------------------------------------------------------------------------

function UIPanel:CreateResizeHandle()
    local frame = self.frame
    if not frame then return end

    -- Create resize handle frame
    local resizeHandle = CreateFrame("Button", "ScooterUIResizeHandle", frame)
    resizeHandle:SetSize(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizeHandle:EnableMouse(true)

    -- Diagonal grip lines (UI style: simple corner pattern)
    -- Using three diagonal lines to create a resize grip appearance
    local ar, ag, ab = Theme:GetAccentColor()

    -- Create grip lines (bottom-right corner style)
    local lines = {}
    for i = 1, 3 do
        local line = resizeHandle:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(ar, ag, ab, 0.7)
        line:SetSize(2, 2)
        -- Position lines diagonally from bottom-right
        local offset = (i - 1) * 4
        line:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -offset - 2, offset + 2)
        lines[i] = line
    end

    -- Additional lines for fuller grip appearance
    for i = 1, 2 do
        local line = resizeHandle:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(ar, ag, ab, 0.7)
        line:SetSize(2, 2)
        local offset = (i - 1) * 4
        line:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -offset - 6, offset + 2)
        lines[3 + i] = line
    end

    -- One more for the corner
    local cornerDot = resizeHandle:CreateTexture(nil, "OVERLAY")
    cornerDot:SetColorTexture(ar, ag, ab, 0.7)
    cornerDot:SetSize(2, 2)
    cornerDot:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -2, 6)
    lines[6] = cornerDot

    resizeHandle._lines = lines

    -- Store reference to panel for callbacks
    local panel = self

    -- Hover effect: brighten grip
    resizeHandle:SetScript("OnEnter", function(handle)
        local r, g, b = Theme:GetAccentColor()
        for _, line in ipairs(handle._lines) do
            line:SetColorTexture(r, g, b, 1)
        end
        -- Change cursor to resize indicator (if supported)
        SetCursor("Interface\\CURSOR\\UI-Cursor-Size")
    end)

    resizeHandle:SetScript("OnLeave", function(handle)
        local r, g, b = Theme:GetAccentColor()
        for _, line in ipairs(handle._lines) do
            line:SetColorTexture(r, g, b, 0.7)
        end
        ResetCursor()
    end)

    -- Resize functionality
    resizeHandle:SetScript("OnMouseDown", function(handle, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)

    resizeHandle:SetScript("OnMouseUp", function(handle, button)
        frame:StopMovingOrSizing()
        -- Save size to AceDB
        if addon.db and addon.db.global then
            local width, height = frame:GetSize()
            addon.db.global.windowSize = {
                width = width,
                height = height
            }
        end
    end)

    frame._resizeHandle = resizeHandle

    -- Subscribe to theme updates
    Theme:Subscribe("UIPanel_ResizeHandle", function(r, g, b)
        if resizeHandle._lines and not resizeHandle:IsMouseOver() then
            for _, line in ipairs(resizeHandle._lines) do
                line:SetColorTexture(r, g, b, 0.7)
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Navigation Sidebar (Terminal file explorer style)
--------------------------------------------------------------------------------

local NAV_WIDTH = 220  -- Width of navigation sidebar

function UIPanel:CreateNavigation()
    local frame = self.frame
    if not frame then return end

    -- Create navigation using UINavigation module
    local navFrame = Navigation:Create(frame)
    if navFrame then
        frame._navigation = navFrame

        -- Set up selection callback for future content pane integration
        Navigation:SetOnSelectCallback(function(key, previousKey)
            -- Will be wired to content pane renderer in Phase 2
            self:OnNavigationSelect(key, previousKey)
        end)
    end
end

--------------------------------------------------------------------------------
-- Content Pane (Right side - will render selected category's settings)
--------------------------------------------------------------------------------

-- Content pane scrollbar constants
local CONTENT_SCROLLBAR_WIDTH = 8
local CONTENT_SCROLLBAR_THUMB_MIN = 30
local CONTENT_SCROLLBAR_MARGIN = 8
local CONTENT_PADDING = 8
local CONTENT_SCROLLBAR_BOTTOM_MARGIN = RESIZE_HANDLE_SIZE + 8  -- Clear the resize grip

-- Creates a custom UI scrollbar for the content pane
local function CreateContentScrollbar(parent, scrollFrame)
    local ar, ag, ab = Theme:GetAccentColor()

    local scrollbar = CreateFrame("Frame", nil, parent)
    scrollbar:SetWidth(CONTENT_SCROLLBAR_WIDTH)
    -- Anchors are set after creation in CreateContentPane to account for header height

    -- Track
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, 0.1)
    scrollbar._track = track

    -- Thumb
    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(CONTENT_SCROLLBAR_WIDTH)
    thumb:SetHeight(CONTENT_SCROLLBAR_THUMB_MIN)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, 0.5)
    thumb._tex = thumbTex

    thumb:SetScript("OnEnter", function(self)
        local r, g, b = Theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 0.8)
    end)

    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    scrollbar._thumb = thumb
    scrollbar._scrollFrame = scrollFrame

    local function UpdateScrollbar()
        if not scrollFrame then return end

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local trackHeight = scrollbar:GetHeight() or 1

        if contentHeight <= visibleHeight then
            scrollbar:Hide()
            return
        end

        scrollbar:Show()

        local thumbHeight = math.max(
            CONTENT_SCROLLBAR_THUMB_MIN,
            (visibleHeight / contentHeight) * trackHeight
        )
        thumb:SetHeight(thumbHeight)

        local maxScroll = contentHeight - visibleHeight
        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local scrollPercent = maxScroll > 0 and (currentScroll / maxScroll) or 0

        local maxThumbOffset = trackHeight - thumbHeight
        local thumbOffset = scrollPercent * maxThumbOffset

        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -thumbOffset)
    end

    scrollbar.Update = UpdateScrollbar

    local dragStartY, dragStartScroll

    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        local r, g, b = Theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 1)

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)

    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        local r, g, b = Theme:GetAccentColor()
        if self:IsMouseOver() then
            self._tex:SetColorTexture(r, g, b, 0.8)
        else
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale

        local deltaY = dragStartY - cursorY

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local trackHeight = scrollbar:GetHeight() or 1
        local thumbHeight = thumb:GetHeight()

        local maxScroll = contentHeight - visibleHeight
        local maxThumbOffset = trackHeight - thumbHeight

        if maxThumbOffset > 0 and maxScroll > 0 then
            local scrollDelta = (deltaY / maxThumbOffset) * maxScroll
            local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + scrollDelta))
            scrollFrame:SetVerticalScroll(newScroll)
            UpdateScrollbar()
        end
    end)

    scrollbar:EnableMouse(true)
    scrollbar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale

        local selfBottom = self:GetBottom() or 0
        local clickY = cursorY - selfBottom
        local trackHeight = self:GetHeight() or 1

        local clickPercent = 1 - (clickY / trackHeight)

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local maxScroll = contentHeight - visibleHeight

        if maxScroll > 0 then
            local newScroll = clickPercent * maxScroll
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, newScroll)))
            UpdateScrollbar()
        end
    end)

    Theme:Subscribe("UIContentScrollbar_" .. tostring(scrollbar), function(r, g, b)
        if scrollbar._track then
            scrollbar._track:SetColorTexture(r, g, b, 0.1)
        end
        if thumb._tex and not thumb._isDragging then
            thumb._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    return scrollbar
end

function UIPanel:CreateContentPane()
    local frame = self.frame
    if not frame then return end

    -- Create content pane frame (right of navigation) - no background
    local contentPane = CreateFrame("Frame", "ScooterUIContentPane", frame)
    contentPane:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_WIDTH + Theme.BORDER_WIDTH + 1, -(TITLE_BAR_HEIGHT))
    contentPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.BORDER_WIDTH, Theme.BORDER_WIDTH)

    -- Header area for content pane (category title + controls)
    local header = CreateFrame("Frame", nil, contentPane)
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", contentPane, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", contentPane, "TOPRIGHT", 0, 0)

    -- Header title
    local headerTitle = header:CreateFontString(nil, "OVERLAY")
    Theme:ApplyHeaderFont(headerTitle, 20)
    headerTitle:SetPoint("LEFT", header, "LEFT", 16, 0)
    headerTitle:SetText("Home")  -- Default
    contentPane._headerTitle = headerTitle

    -- "Collapse All" button (right side of header, same Y-axis as title)
    -- Uses reduced border thickness/brightness to match content area styling
    local panel = self
    local collapseAllBtn = Controls:CreateButton({
        parent = header,
        name = "ScooterUICollapseAllBtn",
        text = "Collapse All",
        height = 22,
        fontSize = 11,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function(btn, mouseButton)
            panel:CollapseAllSections()
        end
    })
    collapseAllBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    collapseAllBtn:Hide()  -- Hidden by default, shown when collapsible sections exist
    contentPane._collapseAllBtn = collapseAllBtn

    -- "Copy From" dropdown for Action Bars and Unit Frames (to the left of Collapse All button)
    local copyFromDropdown = Controls:CreateDropdown({
        parent = header,
        name = "ScooterUICopyFromDropdown",
        values = {},  -- Will be populated dynamically
        placeholder = "Select...",
        width = 140,
        height = 22,
        fontSize = 11,
        set = function(sourceKey)
            -- Handle copy operation
            panel:HandleCopyFrom(sourceKey)
        end,
    })
    copyFromDropdown:SetPoint("RIGHT", collapseAllBtn, "LEFT", -12, 0)
    copyFromDropdown:Hide()  -- Hidden by default, shown for Action Bar categories
    contentPane._copyFromDropdown = copyFromDropdown

    -- "Copy from:" label (to the left of the dropdown)
    local copyFromLabel = header:CreateFontString(nil, "OVERLAY")
    local labelFont = Theme:GetFont("LABEL")
    copyFromLabel:SetFont(labelFont, 11, "")
    copyFromLabel:SetText("Copy from:")
    local ar, ag, ab = Theme:GetAccentColor()
    copyFromLabel:SetTextColor(ar, ag, ab, 0.8)
    copyFromLabel:SetPoint("RIGHT", copyFromDropdown, "LEFT", -8, 0)
    copyFromLabel:Hide()  -- Hidden by default
    contentPane._copyFromLabel = copyFromLabel

    -- Header separator line
    local headerSep = header:CreateTexture(nil, "BORDER")
    headerSep:SetHeight(1)
    headerSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0)
    headerSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0)
    headerSep:SetColorTexture(ar, ag, ab, 0.3)
    contentPane._headerSep = headerSep
    contentPane._header = header

    -- Scrollable content area (custom scroll frame, no Blizzard template)
    local scrollFrame = CreateFrame("ScrollFrame", "ScooterUIContentScrollFrame", contentPane)
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", CONTENT_PADDING, -CONTENT_PADDING)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -(CONTENT_SCROLLBAR_MARGIN + CONTENT_SCROLLBAR_WIDTH + CONTENT_PADDING), CONTENT_PADDING)
    scrollFrame:EnableMouseWheel(true)

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local scrollChild = self:GetScrollChild()
        local contentHeight = scrollChild and scrollChild:GetHeight() or 0
        local visibleHeight = self:GetHeight() or 1
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        local step = 60  -- Pixels per scroll
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        self:SetVerticalScroll(newScroll)

        if contentPane._scrollbar and contentPane._scrollbar.Update then
            contentPane._scrollbar:Update()
        end
    end)

    local scrollContent = CreateFrame("Frame", "ScooterUIContentScrollContent", scrollFrame)
    scrollContent:SetWidth(scrollFrame:GetWidth() or 400)
    scrollFrame:SetScrollChild(scrollContent)
    contentPane._scrollFrame = scrollFrame
    contentPane._scrollContent = scrollContent

    -- Custom UI scrollbar
    local scrollbar = CreateContentScrollbar(contentPane, scrollFrame)
    scrollbar:SetPoint("TOPRIGHT", contentPane, "TOPRIGHT", -CONTENT_SCROLLBAR_MARGIN, -header:GetHeight() - CONTENT_PADDING)
    scrollbar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -CONTENT_SCROLLBAR_MARGIN, CONTENT_SCROLLBAR_BOTTOM_MARGIN)
    contentPane._scrollbar = scrollbar

    -- Update scrollbar when scroll range changes
    scrollFrame:SetScript("OnScrollRangeChanged", function()
        if scrollbar and scrollbar.Update then
            scrollbar:Update()
        end
    end)

    -- Placeholder content (will be replaced by category renderers)
    local placeholder = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyDimFont(placeholder, 13)
    placeholder:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, -16)
    placeholder:SetWidth(500)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetText("")
    placeholder:Hide()  -- Start hidden (Home page is blank)
    contentPane._placeholder = placeholder

    -- Home content frame (centered welcome message and ASCII art)
    local homeContent = CreateFrame("Frame", "ScooterUIHomeContent", contentPane)
    homeContent:SetAllPoints(contentPane)

    -- Container for centering (holds ASCII title + ASCII mascot)
    local homeContainer = CreateFrame("Frame", nil, homeContent)
    homeContainer:SetPoint("CENTER", homeContent, "CENTER", 0, -10)  -- Slightly below center

    local labelFont = Theme:GetFont("LABEL")

    -- Large ASCII art title (anchor point for other elements)
    local homeAscii = homeContainer:CreateFontString(nil, "OVERLAY")
    homeAscii:SetFont(labelFont, 10, "")  -- Larger than title bar (6pt -> 10pt)
    homeAscii:SetText(ASCII_LOGO)
    homeAscii:SetJustifyH("CENTER")
    homeAscii:SetTextColor(ar, ag, ab, 1)  -- Accent color
    homeAscii:SetPoint("LEFT", homeContainer, "LEFT", 0, 0)

    -- ASCII mascot (above the title, slightly right)
    local homeMascot = homeContainer:CreateFontString(nil, "OVERLAY")
    homeMascot:SetFont(labelFont, 7.5, "")  -- 25% larger than 6pt
    homeMascot:SetText(ASCII_MASCOT)
    homeMascot:SetJustifyH("LEFT")  -- Must be LEFT to keep ASCII art internally aligned
    homeMascot:SetTextColor(ar, ag, ab, 1)  -- Accent color
    homeMascot:SetPoint("BOTTOM", homeAscii, "TOP", 65, 8)  -- Above title, offset right 65px

    -- "Welcome to" text (above-left of ASCII title)
    local welcomeText = homeContainer:CreateFontString(nil, "OVERLAY")
    welcomeText:SetFont(labelFont, 16, "")
    welcomeText:SetText("Welcome to")
    welcomeText:SetTextColor(1, 1, 1, 1)  -- White
    welcomeText:SetPoint("BOTTOMLEFT", homeAscii, "TOPLEFT", 65, 8)  -- Above-left of ASCII, offset right 65px

    -- Size the container based on combined dimensions (deferred for accurate measurement)
    C_Timer.After(0.05, function()
        if homeAscii and homeMascot and homeContainer then
            local titleW = homeAscii:GetStringWidth() or 600
            local titleH = homeAscii:GetStringHeight() or 80
            local mascotW = homeMascot:GetStringWidth() or 200
            local mascotH = homeMascot:GetStringHeight() or 150
            -- Container width = max of title or mascot, height = title + mascot + welcome text
            homeContainer:SetSize(math.max(titleW, mascotW), titleH + mascotH + 50)
        end
    end)
    -- Fallback size
    homeContainer:SetSize(700, 300)

    homeContent._welcomeText = welcomeText
    homeContent._asciiLogo = homeAscii
    homeContent._asciiMascot = homeMascot
    contentPane._homeContent = homeContent

    -- Subscribe to theme updates for home ASCII elements
    Theme:Subscribe("UIPanel_HomeContent", function(r, g, b)
        if homeAscii then
            homeAscii:SetTextColor(r, g, b, 1)
        end
        if homeMascot then
            homeMascot:SetTextColor(r, g, b, 1)
        end
    end)

    frame._contentPane = contentPane

    -- Initialize in Home state (header hidden, ASCII logo hidden, home content shown)
    headerTitle:Hide()
    headerSep:Hide()
    scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
    homeContent:Show()  -- Show home content by default

    -- Also hide ASCII logo in title bar initially (will animate when navigating away from home)
    if frame._logo then
        frame._logo:SetText("")
    end
    -- Disable mouse on logo button initially (home page, no hover effect)
    if frame._logoBtn then
        frame._logoBtn:EnableMouse(false)
    end

    -- Subscribe to theme updates
    Theme:Subscribe("UIPanel_ContentPane", function(r, g, b)
        if contentPane._headerSep then
            contentPane._headerSep:SetColorTexture(r, g, b, 0.3)
        end
        if contentPane._headerTitle then
            contentPane._headerTitle:SetTextColor(r, g, b, 1)
        end
        if contentPane._copyFromLabel then
            contentPane._copyFromLabel:SetTextColor(r, g, b, 0.8)
        end
    end)

    -- Handle resize to update scroll content width and scrollbar
    frame:HookScript("OnSizeChanged", function()
        if scrollFrame and scrollContent then
            local width = scrollFrame:GetWidth()
            if width and width > 0 then
                scrollContent:SetWidth(width - 16)
            end
        end
        if scrollbar and scrollbar.Update then
            C_Timer.After(0.05, function()
                scrollbar:Update()
            end)
        end
    end)

    -- Initial scrollbar update
    C_Timer.After(0.1, function()
        if scrollbar and scrollbar.Update then
            scrollbar:Update()
        end
    end)
end

--------------------------------------------------------------------------------
-- Content Renderers
--------------------------------------------------------------------------------
-- Each renderer builds the content for a specific navigation category using
-- the UISettingsBuilder pattern. This keeps rendering logic organized and
-- makes it easy to add new categories.

-- Store current builder instance for cleanup
UIPanel._currentBuilder = nil

--------------------------------------------------------------------------------
-- Content Cleanup System
--------------------------------------------------------------------------------
-- ClearContent() is called before rendering any new section. It must clean up
-- ALL content types:
--
-- 1. Builder-based content (_currentBuilder): Most sections use SettingsBuilder
--    which tracks controls in builder._controls and cleans them up via Cleanup().
--
-- 2. Custom state-based content: Some sections (e.g., Rules) use manual frame
--    creation with custom state tracking. These must be cleaned up here too.
--
-- IMPORTANT: If you add a new section that uses custom state tracking instead
-- of the builder pattern, you MUST add its cleanup logic here to prevent
-- content from persisting when navigating away.
--------------------------------------------------------------------------------

function UIPanel:ClearContent()
    -- 1. Clean up builder-based content (most sections)
    if self._currentBuilder then
        self._currentBuilder:Cleanup()
        self._currentBuilder = nil
    end

    -- 2. Clean up Rules state-based content
    -- Rules uses manual frame creation with state tracking in _rulesState.currentControls
    if self._rulesState and self._rulesState.currentControls then
        for _, control in ipairs(self._rulesState.currentControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
        self._rulesState.currentControls = {}
    end

    -- 3. Clean up Profiles > Manage Profiles state-based content
    if self._profilesManageState and self._profilesManageState.currentControls then
        for _, control in ipairs(self._profilesManageState.currentControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
        self._profilesManageState.currentControls = {}
    end

    -- 4. Clean up Profiles > Presets state-based content
    if self._presetsState and self._presetsState.currentControls then
        for _, control in ipairs(self._presetsState.currentControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
        self._presetsState.currentControls = {}
    end

    -- 5. Clean up Apply All > Fonts state-based content
    if self._applyAllFontsControls then
        for _, control in ipairs(self._applyAllFontsControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
        self._applyAllFontsControls = {}
    end

    -- 6. Clean up Apply All > Bar Textures state-based content
    if self._applyAllTexturesControls then
        for _, control in ipairs(self._applyAllTexturesControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
        self._applyAllTexturesControls = {}
    end

    -- 7. Clean up Debug Menu state-based content
    if self._debugMenuControls then
        for _, control in ipairs(self._debugMenuControls) do
            if control.Cleanup then
                control:Cleanup()
            end
            if control.Hide then
                control:Hide()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
        self._debugMenuControls = {}
    end
end

--------------------------------------------------------------------------------
-- Collapse All Sections
--------------------------------------------------------------------------------
-- Collapses all expanded collapsible sections and refreshes the current page.

function UIPanel:CollapseAllSections()
    local key = self._currentCategoryKey
    if not key then return end

    -- Get componentId from the current category key
    -- For most categories, the key is the componentId (e.g., "essentialCooldowns")
    local componentId = key

    -- Collapse all sections for this component in the session state
    local sectionStates = addon.UI._sectionStates
    if sectionStates and sectionStates[componentId] then
        for sectionKey in pairs(sectionStates[componentId]) do
            sectionStates[componentId][sectionKey] = false
        end
    end

    -- Trigger re-render of the current category
    self:OnNavigationSelect(key, key)

    -- Play a sound for feedback
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

--------------------------------------------------------------------------------
-- Update Collapse All Button Visibility
--------------------------------------------------------------------------------
-- Shows the button only when the current page has collapsible sections.

function UIPanel:UpdateCollapseAllButton()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local collapseBtn = contentPane._collapseAllBtn
    if not collapseBtn then return end

    -- Check if we have any collapsible sections in the current builder
    local hasCollapsible = false
    if self._currentBuilder and self._currentBuilder._controls then
        for _, control in ipairs(self._currentBuilder._controls) do
            if control._componentId and control._sectionKey then
                hasCollapsible = true
                break
            end
        end
    end

    if hasCollapsible then
        collapseBtn:Show()
    else
        collapseBtn:Hide()
    end
end

--------------------------------------------------------------------------------
-- Copy From Dropdown Management
--------------------------------------------------------------------------------
-- Shows the "Copy From" dropdown for Action Bar categories that support it.
-- Action Bars 1-8 can copy from other Action Bars (excluding self).
-- Pet Bar can copy from Action Bars 1-8 (destination only).
-- Stance Bar and Micro Bar do not support Copy From.

-- Map of Action Bar keys that support Copy From functionality
local ACTION_BAR_COPY_TARGETS = {
    actionBar1 = true,
    actionBar2 = true,
    actionBar3 = true,
    actionBar4 = true,
    actionBar5 = true,
    actionBar6 = true,
    actionBar7 = true,
    actionBar8 = true,
    petBar = true,  -- Can only be a destination, not a source
}

-- Action Bar display names (for dropdown options)
local ACTION_BAR_NAMES = {
    actionBar1 = "Action Bar 1",
    actionBar2 = "Action Bar 2",
    actionBar3 = "Action Bar 3",
    actionBar4 = "Action Bar 4",
    actionBar5 = "Action Bar 5",
    actionBar6 = "Action Bar 6",
    actionBar7 = "Action Bar 7",
    actionBar8 = "Action Bar 8",
}

-- Order for dropdown (1-8, no pet bar as source)
local ACTION_BAR_ORDER = {
    "actionBar1", "actionBar2", "actionBar3", "actionBar4",
    "actionBar5", "actionBar6", "actionBar7", "actionBar8",
}

-- Map of Unit Frame keys that support Copy From functionality
local UNIT_FRAME_COPY_TARGETS = {
    ufPlayer = true,
    ufTarget = true,
    ufFocus = true,
    ufPet = true,
    ufToT = true,
    ufFocusTarget = true,
    -- ufBoss excluded (no copy support)
}

-- Unit Frame display names
local UNIT_FRAME_NAMES = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "Target of Target",
    ufFocusTarget = "Target of Focus",
}

-- Unit key for CopyUnitFrameSettings (maps category key to unit name)
local UNIT_FRAME_KEYS = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "TargetOfTarget",
    ufFocusTarget = "FocusTarget",
}

-- Full unit frames that can copy from each other
local FULL_UNIT_FRAME_ORDER = { "ufPlayer", "ufTarget", "ufFocus", "ufPet" }

-- ToT/FoT can only copy from each other
local TOT_FOT_SOURCES = {
    ufToT = { "ufFocusTarget" },
    ufFocusTarget = { "ufToT" },
}

function UIPanel:UpdateCopyFromDropdown()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local dropdown = contentPane._copyFromDropdown
    local label = contentPane._copyFromLabel
    if not dropdown then return end

    local key = self._currentCategoryKey

    -- Check if this is an Action Bar category
    if key and ACTION_BAR_COPY_TARGETS[key] then
        -- Build options: all Action Bars 1-8 except the current one
        local values = {}
        local order = {}
        for _, barKey in ipairs(ACTION_BAR_ORDER) do
            if barKey ~= key then
                values[barKey] = ACTION_BAR_NAMES[barKey]
                table.insert(order, barKey)
            end
        end

        -- Update dropdown options
        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()  -- Reset to placeholder for each category

        -- Show dropdown and label
        dropdown:Show()
        if label then label:Show() end

    -- Check if this is a Unit Frame category
    elseif key and UNIT_FRAME_COPY_TARGETS[key] then
        local values = {}
        local order = {}

        -- ToT/FoT have restricted sources
        if TOT_FOT_SOURCES[key] then
            for _, sourceKey in ipairs(TOT_FOT_SOURCES[key]) do
                values[sourceKey] = UNIT_FRAME_NAMES[sourceKey]
                table.insert(order, sourceKey)
            end
        else
            -- Full unit frames can copy from other full unit frames
            for _, ufKey in ipairs(FULL_UNIT_FRAME_ORDER) do
                if ufKey ~= key then
                    values[ufKey] = UNIT_FRAME_NAMES[ufKey]
                    table.insert(order, ufKey)
                end
            end
        end

        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()
        dropdown:Show()
        if label then label:Show() end
    else
        -- Hide for unsupported categories
        dropdown:Hide()
        if label then label:Hide() end
    end
end

function UIPanel:HandleCopyFrom(sourceKey)
    local destKey = self._currentCategoryKey
    if not sourceKey or not destKey then return end

    -- Determine if this is Action Bar or Unit Frame
    local isActionBar = ACTION_BAR_COPY_TARGETS[destKey]
    local isUnitFrame = UNIT_FRAME_COPY_TARGETS[destKey]

    local sourceName, destName

    if isActionBar then
        sourceName = ACTION_BAR_NAMES[sourceKey] or sourceKey
        destName = ACTION_BAR_NAMES[destKey] or self:GetCategoryTitle(destKey)
    elseif isUnitFrame then
        sourceName = UNIT_FRAME_NAMES[sourceKey] or sourceKey
        destName = UNIT_FRAME_NAMES[destKey] or self:GetCategoryTitle(destKey)
    else
        return
    end

    -- Use ScooterMod custom dialog to avoid tainting StaticPopupDialogs
    if addon.Dialogs and addon.Dialogs.Show then
        local panel = self
        local dialogKey = isUnitFrame and "SCOOTERMOD_COPY_UF_CONFIRM"
                                       or "SCOOTERMOD_COPY_ACTIONBAR_CONFIRM"
        addon.Dialogs:Show(dialogKey, {
            formatArgs = { sourceName, destName },
            data = {
                sourceId = sourceKey,
                destId = destKey,
                sourceName = sourceName,
                destName = destName,
                isUnitFrame = isUnitFrame,
            },
            onAccept = function()
                panel:ExecuteCopyFrom(sourceKey, destKey, isUnitFrame)
            end,
        })
    else
        -- Fallback if dialogs not loaded
        self:ExecuteCopyFrom(sourceKey, destKey, isUnitFrame)
    end
end

function UIPanel:ExecuteCopyFrom(sourceKey, destKey, isUnitFrame)
    if isUnitFrame then
        -- Unit Frame copy
        if addon and addon.CopyUnitFrameSettings then
            local sourceUnit = UNIT_FRAME_KEYS[sourceKey]
            local destUnit = UNIT_FRAME_KEYS[destKey]
            local ok, err = addon.CopyUnitFrameSettings(sourceUnit, destUnit)

            if ok then
                -- Refresh the current category
                C_Timer.After(0.1, function()
                    local panel = addon.UI and addon.UI.SettingsPanel
                    if panel and panel._currentCategoryKey == destKey then
                        panel:OnNavigationSelect(destKey, destKey)
                    end
                end)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            else
                -- Show error dialog
                if addon.Dialogs and addon.Dialogs.Show then
                    addon.Dialogs:Show("SCOOTERMOD_COPY_UF_ERROR", {
                        formatArgs = { err or "Unknown error" },
                    })
                elseif addon.Print then
                    addon:Print("Copy failed: " .. (err or "unknown error"))
                end
            end
        end
    else
        -- Action Bar copy
        if addon and addon.CopyActionBarSettings then
            addon.CopyActionBarSettings(sourceKey, destKey)

            -- Refresh the current category to show the copied settings
            C_Timer.After(0.1, function()
                local panel = addon.UI and addon.UI.SettingsPanel
                if panel and panel._currentCategoryKey == destKey then
                    panel:OnNavigationSelect(destKey, destKey)
                end
            end)

            -- Play success sound
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end
end

-- NOTE: Render functions have been extracted to ui/v2/settings/ modules.
-- See: cdm/, actionbars/, prd/, interface/, profiles/, applyall/, auras/

--------------------------------------------------------------------------------
-- Renderer Registry
--------------------------------------------------------------------------------
-- Maps navigation keys to render functions. Add new renderers here.

UIPanel._renderers = {
    -- Cooldown Manager (external modules)
    cdmQoL = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.QoL
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    essentialCooldowns = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.EssentialCooldowns
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    utilityCooldowns = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.UtilityCooldowns
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    trackedBuffs = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.TrackedBuffs
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    trackedBars = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.TrackedBars
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Action Bars (external modules)
    actionBar1 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar1") end
    end,
    actionBar2 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar2") end
    end,
    actionBar3 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar3") end
    end,
    actionBar4 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar4") end
    end,
    actionBar5 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar5") end
    end,
    actionBar6 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar6") end
    end,
    actionBar7 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar7") end
    end,
    actionBar8 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar8") end
    end,
    petBar = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "petBar") end
    end,
    stanceBar = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "stanceBar") end
    end,
    microBar = function(self, scrollContent)
        local M = addon.UI.Settings.MicroBar
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    extraAbilities = function(self, scrollContent)
        local M = addon.UI.Settings.ExtraAbilities
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Personal Resource Display (external modules)
    prdGeneral = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.General
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    prdHealthBar = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.HealthBar
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    prdPowerBar = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.PowerBar
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    prdClassResource = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.ClassResource
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Interface (external modules)
    damageMeter = function(self, scrollContent)
        local M = addon.UI.Settings.DamageMeter
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    tooltip = function(self, scrollContent)
        local M = addon.UI.Settings.Tooltip
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    objectiveTracker = function(self, scrollContent)
        local M = addon.UI.Settings.ObjectiveTracker
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    minimap = function(self, scrollContent)
        local M = addon.UI.Settings.Minimap
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    chat = function(self, scrollContent)
        local M = addon.UI.Settings.Chat
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    misc = function(self, scrollContent)
        local M = addon.UI.Settings.Misc
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- SCT (external module)
    sctDamage = function(self, scrollContent)
        local M = addon.UI.Settings.SctDamage
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Unit Frames (external modules - unchanged)
    ufPlayer = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderPlayer then
            UF.RenderPlayer(self, scrollContent)
        end
    end,
    ufTarget = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderTarget then
            UF.RenderTarget(self, scrollContent)
        end
    end,
    ufFocus = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderFocus then
            UF.RenderFocus(self, scrollContent)
        end
    end,
    ufPet = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderPet then
            UF.RenderPet(self, scrollContent)
        end
    end,
    ufToT = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderToT then
            UF.RenderToT(self, scrollContent)
        end
    end,
    ufFocusTarget = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderFocusTarget then
            UF.RenderFocusTarget(self, scrollContent)
        end
    end,
    ufBoss = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderBoss then
            UF.RenderBoss(self, scrollContent)
        end
    end,
    -- Group Frames (external modules - unchanged)
    gfParty = function(self, scrollContent)
        local GF = addon.UI and addon.UI.GroupFrames
        if GF and GF.RenderParty then
            GF.RenderParty(self, scrollContent)
        end
    end,
    gfRaid = function(self, scrollContent)
        local GF = addon.UI and addon.UI.GroupFrames
        if GF and GF.RenderRaid then
            GF.RenderRaid(self, scrollContent)
        end
    end,
    -- Profiles (external modules)
    profilesManage = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Manage
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    profilesPresets = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Presets
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    profilesRules = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Rules
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Apply All (external modules)
    applyAllFonts = function(self, scrollContent)
        local M = addon.UI.Settings.ApplyAll and addon.UI.Settings.ApplyAll.Fonts
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    applyAllTextures = function(self, scrollContent)
        local M = addon.UI.Settings.ApplyAll and addon.UI.Settings.ApplyAll.Textures
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Buffs/Debuffs (external modules)
    buffs = function(self, scrollContent)
        local M = addon.UI.Settings.Auras and addon.UI.Settings.Auras.Buffs
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    debuffs = function(self, scrollContent)
        local M = addon.UI.Settings.Auras and addon.UI.Settings.Auras.Debuffs
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Debug Menu (hidden by default)
    debugMenu = function(self, scrollContent)
        local Controls = addon.UI.Controls
        local Theme = addon.UI.Theme

        -- Track controls for cleanup on the PANEL so ClearContent() can find them
        self._debugMenuControls = self._debugMenuControls or {}
        for _, ctrl in ipairs(self._debugMenuControls) do
            if ctrl.Cleanup then ctrl:Cleanup() end
            if ctrl.Hide then ctrl:Hide() end
            if ctrl.SetParent then ctrl:SetParent(nil) end
        end
        self._debugMenuControls = {}

        -- Section header
        local headerLabel = scrollContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyLabelFont(headerLabel, 14)
        headerLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
        headerLabel:SetText("Developer Testing Tools")
        local ar, ag, ab = Theme:GetAccentColor()
        headerLabel:SetTextColor(ar, ag, ab, 1)
        table.insert(self._debugMenuControls, headerLabel)

        local yOffset = -30

        -- Description
        local descLabel = scrollContent:CreateFontString(nil, "OVERLAY")
        Theme:ApplyValueFont(descLabel, 11)
        descLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        descLabel:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
        descLabel:SetText("These options are for addon development and testing. Use with caution.")
        descLabel:SetTextColor(0.7, 0.7, 0.7, 1)
        descLabel:SetJustifyH("LEFT")
        descLabel:SetWordWrap(true)
        table.insert(self._debugMenuControls, descLabel)

        yOffset = yOffset - 50

        -- Force Secret Restrictions toggle
        local secretCVars = {
            "secretCombatRestrictionsForced",
            "secretChallengeModeRestrictionsForced",
            "secretEncounterRestrictionsForced",
            "secretMapRestrictionsForced",
            "secretPvPMatchRestrictionsForced",
        }

        local toggle = Controls:CreateToggle({
            parent = scrollContent,
            label = "Force Secret Restrictions",
            description = "Enables all secret restriction CVars to simulate combat/instance restrictions for testing taint behavior.",
            get = function()
                local val = GetCVar("secretCombatRestrictionsForced")
                return val == "1"
            end,
            set = function(enabled)
                local newVal = enabled and "1" or "0"
                for _, cvar in ipairs(secretCVars) do
                    pcall(SetCVar, cvar, newVal)
                end
            end,
        })
        toggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        toggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
        table.insert(self._debugMenuControls, toggle)

        yOffset = yOffset - 70

        -- Keep BugSack Button Separate toggle
        local bugSackToggle = Controls:CreateToggle({
            parent = scrollContent,
            label = "Keep BugSack Button Separate",
            description = "Keep BugSack's minimap button visible outside the addon button container.",
            get = function()
                return addon.db and addon.db.profile and addon.db.profile.bugSackButtonSeparate
            end,
            set = function(enabled)
                if addon.db and addon.db.profile then
                    addon.db.profile.bugSackButtonSeparate = enabled
                    -- Re-apply minimap styling to update button visibility
                    local minimapComp = addon.Components and addon.Components["minimapStyle"]
                    if minimapComp and minimapComp.ApplyStyling then
                        minimapComp:ApplyStyling()
                    end
                end
            end,
        })
        bugSackToggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        bugSackToggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
        table.insert(self._debugMenuControls, bugSackToggle)

        yOffset = yOffset - 70

        -- Set content height
        scrollContent:SetHeight(math.abs(yOffset) + 20)
    end,
}

--------------------------------------------------------------------------------
-- Navigation Selection Handler
--------------------------------------------------------------------------------

function UIPanel:OnNavigationSelect(key, previousKey)
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local scrollContent = contentPane._scrollContent
    local isHome = (key == "home" or key == nil)
    local wasHome = (previousKey == "home" or previousKey == nil)

    -- Track current category for back-sync handling
    self._currentCategoryKey = key

    -- Clear any pending back-sync for this category (we're about to refresh it)
    self:CheckPendingBackSync(key)

    -- Clear existing rendered content
    self:ClearContent()

    -- Home page: hide header, show blank content
    if isHome then
        -- Hide header elements
        if contentPane._headerTitle then
            contentPane._headerTitle:Hide()
        end
        if contentPane._headerSep then
            contentPane._headerSep:Hide()
        end
        if contentPane._collapseAllBtn then
            contentPane._collapseAllBtn:Hide()
        end
        if contentPane._copyFromDropdown then
            contentPane._copyFromDropdown:Hide()
        end
        if contentPane._copyFromLabel then
            contentPane._copyFromLabel:Hide()
        end

        -- Hide ASCII logo on home page (stop any running animation first)
        self:StopAsciiAnimation()
        if frame._logo then
            frame._logo:SetText("")
        end
        -- Disable mouse on logo button so hover effect doesn't trigger
        if frame._logoBtn then
            frame._logoBtn:EnableMouse(false)
        end

        -- Expand scroll area to fill space where header was
        if contentPane._scrollFrame then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        -- Hide placeholder
        if contentPane._placeholder then
            contentPane._placeholder:SetText("")
            contentPane._placeholder:Hide()
        end

        -- Show home content (centered welcome + ASCII art)
        if contentPane._homeContent then
            contentPane._homeContent:Show()
        end

        -- Reset scroll content height for home
        if scrollContent then
            scrollContent:SetHeight(1)
        end
    else
        -- Hide home content when navigating to a category
        if contentPane._homeContent then
            contentPane._homeContent:Hide()
        end

        -- Show ASCII logo when navigating away from home
        -- Animate if coming from home, otherwise just show instantly
        if wasHome then
            self:AnimateAsciiReveal()
        elseif frame._logo and frame._logo:GetText() == "" then
            -- Ensure logo is visible if it was hidden (e.g., panel reopened)
            frame._logo:SetText(ASCII_LOGO)
        end
        -- Re-enable mouse on logo button for hover effect
        if frame._logoBtn then
            frame._logoBtn:EnableMouse(true)
        end
        -- Category page: show header
        if contentPane._headerTitle then
            contentPane._headerTitle:SetText(self:GetCategoryTitle(key))
            contentPane._headerTitle:Show()
        end
        if contentPane._headerSep then
            contentPane._headerSep:Show()
        end

        -- Restore scroll area below header
        if contentPane._scrollFrame and contentPane._header then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane._header, "BOTTOMLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        -- Check if we have a renderer for this key
        local renderer = self._renderers and self._renderers[key]
        if renderer and scrollContent then
            -- Hide placeholder, render actual content
            if contentPane._placeholder then
                contentPane._placeholder:Hide()
            end
            renderer(self, scrollContent)
        else
            -- Show placeholder for unimplemented categories
            if contentPane._placeholder then
                contentPane._placeholder:Show()
                contentPane._placeholder:SetText(string.format([[
> Selected: %s

Content renderer not yet implemented.

Navigation key: "%s"
]], self:GetCategoryTitle(key), key or "nil"))
            end
            -- Set minimal scroll content height
            if scrollContent then
                scrollContent:SetHeight(100)
            end
        end
    end

    -- Reset scroll position to top
    if contentPane._scrollFrame then
        contentPane._scrollFrame:SetVerticalScroll(0)
    end

    -- Update scrollbar
    if contentPane._scrollbar and contentPane._scrollbar.Update then
        C_Timer.After(0.05, function()
            contentPane._scrollbar:Update()
        end)
    end

    -- Update Collapse All button visibility
    self:UpdateCollapseAllButton()

    -- Update Copy From dropdown visibility and options
    self:UpdateCopyFromDropdown()
end

--------------------------------------------------------------------------------
-- Get Category Display Title
--------------------------------------------------------------------------------

function UIPanel:GetCategoryTitle(key)
    if not key then return "Home" end

    -- Map navigation keys to display titles
    local titles = {
        home = "Home",
        profilesManage = "Manage Profiles",
        profilesPresets = "Presets",
        profilesRules = "Rules",
        applyAllFonts = "Apply All: Fonts",
        applyAllTextures = "Apply All: Bar Textures",
        damageMeter = "Damage Meters",
        tooltip = "Tooltip",
        objectiveTracker = "Objective Tracker",
        minimap = "Minimap",
        chat = "Chat",
        cdmQoL = "CDM: Quality of Life",
        essentialCooldowns = "CDM: Essential Cooldowns",
        utilityCooldowns = "CDM: Utility Cooldowns",
        trackedBuffs = "CDM: Tracked Buffs",
        trackedBars = "CDM: Tracked Bars",
        actionBar1 = "Action Bar 1",
        actionBar2 = "Action Bar 2",
        actionBar3 = "Action Bar 3",
        actionBar4 = "Action Bar 4",
        actionBar5 = "Action Bar 5",
        actionBar6 = "Action Bar 6",
        actionBar7 = "Action Bar 7",
        actionBar8 = "Action Bar 8",
        petBar = "Pet Bar",
        stanceBar = "Stance Bar",
        microBar = "Micro Bar",
        extraAbilities = "Extra Abilities",
        prdGeneral = "Personal Resource: General",
        prdHealthBar = "Personal Resource: Health Bar",
        prdPowerBar = "Personal Resource: Power Bar",
        prdClassResource = "Personal Resource: Class Resource",
        ufPlayer = "Unit Frames: Player",
        ufTarget = "Unit Frames: Target",
        ufFocus = "Unit Frames: Focus",
        ufPet = "Unit Frames: Pet",
        ufToT = "Unit Frames: ToT",
        ufFocusTarget = "Unit Frames: ToF",
        ufBoss = "Unit Frames: Boss",
        gfParty = "Party Frames",
        gfRaid = "Raid Frames",
        buffs = "Buffs",
        debuffs = "Debuffs",
        sctDamage = "SCT: Damage Numbers",
    }

    return titles[key] or key
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function UIPanel:Toggle()
    if InCombatLockdown and InCombatLockdown() then
        -- Message already shown when panel was closed; don't spam
        return
    end

    if not self._initialized then
        self:Initialize()
    end

    if self.frame then
        if self.frame:IsShown() then
            self:Hide()
        else
            self:Show()  -- Use our Show() method to ensure category re-render
        end
    end
end

function UIPanel:Show()
    if InCombatLockdown and InCombatLockdown() then
        -- Message already shown when panel was closed; don't spam
        return
    end

    if not self._initialized then
        self:Initialize()
    end

    if self.frame then
        -- CRITICAL: Sync all Edit Mode values to component.db BEFORE showing/rendering.
        -- This matches what the old UI does in ShowPanel() via RefreshSyncAndNotify("OpenPanel").
        -- Without this, the renderer may read stale cached values from component.db even if
        -- the user waited several seconds after Edit Mode exit (the scheduled back-syncs
        -- at 0.1s/0.5s/1.0s may not have updated all components correctly).
        if addon and addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
            addon.EditMode.RefreshSyncAndNotify("OpenPanel")
        end

        self.frame:Show()

        -- Rebuild navigation to reflect dynamic visibility (e.g., debug menu)
        if Navigation and Navigation.Rebuild then
            Navigation:Rebuild()
        end

        -- ALWAYS re-render the current category when the panel opens.
        -- This ensures UI controls show the latest values from Edit Mode.
        -- Without this, widgets cache old values and only refresh when tabbing away/back.
        -- Since ScooterMod auto-closes when Edit Mode opens, we know any reopen
        -- could have stale data if the user changed something in Edit Mode.
        local currentKey = self._currentCategoryKey
        if currentKey and currentKey ~= "home" then
            -- Clear any pending back-sync flags for this category
            self._pendingBackSync[currentKey] = nil
            -- Defer the re-render to after the frame is fully shown
            C_Timer.After(0, function()
                if self.frame and self.frame:IsShown() then
                    self:OnNavigationSelect(currentKey, currentKey)
                end
            end)
        end
    end
end

function UIPanel:Hide()
    -- Stop any running ASCII animation before hiding
    self:StopAsciiAnimation()

    if self.frame then
        self.frame:Hide()
    end
end

function UIPanel:IsShown()
    return self.frame and self.frame:IsShown()
end

--------------------------------------------------------------------------------
-- Combat Safety (auto-close on combat start, auto-reopen on combat end)
--------------------------------------------------------------------------------

-- Track if panel was closed by combat (for auto-reopen)
UIPanel._closedByCombat = false

-- Register for combat events
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat started - hide UI panel if shown
        if UIPanel.frame and UIPanel.frame:IsShown() then
            UIPanel._closedByCombat = true
            UIPanel.frame:Hide()
            if addon and addon.Print then
                addon:Print("ScooterMod settings will reopen when combat ends.")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended - reopen if we closed it
        if UIPanel._closedByCombat then
            UIPanel._closedByCombat = false
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    UIPanel:Show()
                end
            end)
        end
    end
end)
