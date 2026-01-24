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

    -- "Copy From" dropdown for Action Bars (to the left of Collapse All button)
    local copyFromDropdown = Controls:CreateDropdown({
        parent = header,
        name = "ScooterUICopyFromDropdown",
        values = {},  -- Will be populated dynamically
        placeholder = "Select a bar...",
        width = 140,
        height = 22,
        fontSize = 11,
        onSelect = function(sourceKey, displayText)
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

    -- Container for centering (holds welcome text + ASCII art)
    local homeContainer = CreateFrame("Frame", nil, homeContent)
    homeContainer:SetPoint("CENTER", homeContent, "CENTER", 0, 20)  -- Slightly above center

    -- "Welcome to" text
    local welcomeText = homeContainer:CreateFontString(nil, "OVERLAY")
    local labelFont = Theme:GetFont("LABEL")
    welcomeText:SetFont(labelFont, 16, "")
    welcomeText:SetText("Welcome to")
    welcomeText:SetTextColor(1, 1, 1, 1)  -- White
    welcomeText:SetPoint("BOTTOM", homeContainer, "CENTER", 0, 30)  -- Position above ASCII

    -- Large ASCII art logo
    local homeAscii = homeContainer:CreateFontString(nil, "OVERLAY")
    homeAscii:SetFont(labelFont, 10, "")  -- Larger than title bar (6pt -> 10pt)
    homeAscii:SetText(ASCII_LOGO)
    homeAscii:SetJustifyH("CENTER")
    homeAscii:SetTextColor(ar, ag, ab, 1)  -- Accent color
    homeAscii:SetPoint("TOP", welcomeText, "BOTTOM", 0, -8)

    -- Size the container based on ASCII dimensions (deferred for accurate measurement)
    C_Timer.After(0.05, function()
        if homeAscii and homeContainer then
            local w = homeAscii:GetStringWidth() or 600
            local h = homeAscii:GetStringHeight() or 80
            homeContainer:SetSize(w, h + 60)  -- Extra height for welcome text
        end
    end)
    -- Fallback size
    homeContainer:SetSize(700, 120)

    homeContent._welcomeText = welcomeText
    homeContent._asciiLogo = homeAscii
    contentPane._homeContent = homeContent

    -- Subscribe to theme updates for home ASCII
    Theme:Subscribe("UIPanel_HomeContent", function(r, g, b)
        if homeAscii then
            homeAscii:SetTextColor(r, g, b, 1)
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

function UIPanel:UpdateCopyFromDropdown()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local dropdown = contentPane._copyFromDropdown
    local label = contentPane._copyFromLabel
    if not dropdown then return end

    local key = self._currentCategoryKey

    -- Check if this category supports Copy From
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
    else
        -- Hide dropdown and label
        dropdown:Hide()
        if label then label:Hide() end
    end
end

function UIPanel:HandleCopyFrom(sourceKey)
    local destKey = self._currentCategoryKey
    if not sourceKey or not destKey then return end

    -- Get display names for the confirmation dialog
    local sourceName = ACTION_BAR_NAMES[sourceKey] or sourceKey
    local destName = ACTION_BAR_NAMES[destKey] or self:GetCategoryTitle(destKey)

    -- Use ScooterMod custom dialog to avoid tainting StaticPopupDialogs
    if addon.Dialogs and addon.Dialogs.Show then
        local panel = self
        addon.Dialogs:Show("SCOOTERMOD_COPY_ACTIONBAR_CONFIRM", {
            formatArgs = { sourceName, destName },
            data = {
                sourceId = sourceKey,
                destId = destKey,
                sourceName = sourceName,
                destName = destName,
            },
            onAccept = function()
                panel:ExecuteCopyFrom(sourceKey, destKey)
            end,
        })
    else
        -- Fallback if dialogs not loaded
        self:ExecuteCopyFrom(sourceKey, destKey)
    end
end

function UIPanel:ExecuteCopyFrom(sourceKey, destKey)
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

--------------------------------------------------------------------------------
-- CDM Quality of Life Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderCdmQoL(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- CVar helpers (local to this render)
    local function getCooldownViewerEnabledFromCVar()
        local v
        if C_CVar and C_CVar.GetCVar then
            v = C_CVar.GetCVar("cooldownViewerEnabled")
        elseif GetCVar then
            v = GetCVar("cooldownViewerEnabled")
        end
        return (v == "1") or false
    end

    local function setCooldownViewerEnabledCVar(enabled)
        local value = (enabled and "1") or "0"
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "cooldownViewerEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "cooldownViewerEnabled", value)
        end
    end

    -- Profile data helpers
    local function getProfileQoL()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.cdmQoL
    end

    local function ensureProfileQoL()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.cdmQoL = addon.db.profile.cdmQoL or {}
        return addon.db.profile.cdmQoL
    end

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    builder:AddToggle({
        label = "Enable the Cooldown Manager Per-Profile",
        description = "When enabled, the Cooldown Manager will be active for this profile. This overrides the character-wide Blizzard setting.",
        get = function()
            local q = getProfileQoL()
            if q and q.enableCDM ~= nil then
                return q.enableCDM
            end
            return getCooldownViewerEnabledFromCVar()
        end,
        set = function(value)
            local q = ensureProfileQoL()
            if not q then return end
            q.enableCDM = value
            setCooldownViewerEnabledCVar(value)
            -- If enabling, apply stored CDM styling
            if value and addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
        end,
    })

    builder:AddToggle({
        label = "Enable /cdm command",
        description = "Type /cdm to quickly open the Cooldown Manager settings menu.",
        get = function()
            local q = getProfileQoL()
            return (q and q.enableSlashCDM) or false
        end,
        set = function(value)
            local q = ensureProfileQoL()
            if not q then return end
            q.enableSlashCDM = value
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Essential Cooldowns Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderEssentialCooldowns(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderEssentialCooldowns(scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["essentialCooldowns"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.essentialCooldowns and components.essentialCooldowns[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            -- Ensure component DB exists
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            -- Fallback to profile.components
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.essentialCooldowns = profile.components.essentialCooldowns or {}
                profile.components.essentialCooldowns[key] = value
            end
        end
    end

    -- Helper to sync Edit Mode settings after value change.
    -- Uses skipApply=true: visual updates happen via updaters inside
    -- SyncComponentSettingToEditMode; Edit Mode layout cache is refreshed
    -- by a post-hook on EnterEditMode (see core/editmode.lua).
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "essentialCooldowns",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use centralized setting patterns for orientation-dependent settings
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation

            -- Get current orientation for initial values
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")

                    -- Dynamically update dependent controls
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end

                    local columnsSlider = inner:GetControl("columnsRows")
                    if columnsSlider then
                        columnsSlider:SetLabel(OrientationPatterns.getColumnsLabel(v))
                    end
                end,
                -- Prevent rapid changes during Edit Mode sync (orientation changes trigger
                -- expensive Apply operations; allow 400ms for sync to complete)
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                key = "columnsRows",
                label = OrientationPatterns.getColumnsLabel(currentOrientation),
                description = OrientationPatterns.getColumnsDescription(currentOrientation),
                min = 1,
                max = 20,
                step = 1,
                get = function() return getSetting("columns") or 12 end,
                set = function(v) setSetting("columns", v) end,
                minLabel = "1",
                maxLabel = "20",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_columns",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("columns")
                end,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                -- Prevent rapid changes during Edit Mode sync
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between cooldown icons in pixels.",
                min = 2,
                max = 14,
                step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px",
                maxLabel = "14px",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "essentialCooldowns",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Icon Size (Scale) - Edit Mode setting
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_essentialCooldowns_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconSize")
                end,
            })

            -- Icon Width (addon-only)
            inner:AddSlider({
                label = "Icon Width",
                description = "Custom icon width in pixels.",
                min = 24,
                max = 96,
                step = 1,
                get = function() return getSetting("iconWidth") or 50 end,
                set = function(v)
                    setSetting("iconWidth", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "24px",
                maxLabel = "96px",
            })

            -- Icon Height (addon-only)
            inner:AddSlider({
                label = "Icon Height",
                description = "Custom icon height in pixels.",
                min = 24,
                max = 96,
                step = 1,
                get = function() return getSetting("iconHeight") or 50 end,
                set = function(v)
                    setSetting("iconHeight", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "24px",
                maxLabel = "96px",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "essentialCooldowns",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use Custom Border toggle
            inner:AddToggle({
                key = "borderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for cooldown icons.",
                get = function() return getSetting("borderEnable") or false end,
                set = function(val)
                    setSetting("borderEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            -- Border Tint toggle+color
            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function()
                    return getSetting("borderTintEnable") or false
                end,
                set = function(val)
                    setSetting("borderTintEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", { r = r, g = g, b = b, a = a })
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                hasAlpha = true,
            })

            -- Border Style selector
            -- Build options from IconBorders
            local borderStyleValues = { square = "Default" }
            local borderStyleOrder = { "square" }
            if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
                local entries = addon.IconBorders.GetDropdownEntries()
                if entries then
                    borderStyleValues = {}
                    borderStyleOrder = {}
                    for _, entry in ipairs(entries) do
                        local key = entry.value or entry.key
                        local label = entry.text or entry.label or key
                        if key then
                            borderStyleValues[key] = label
                            table.insert(borderStyleOrder, key)
                        end
                    end
                end
            end

            inner:AddSelector({
                key = "borderStyle",
                label = "Border Style",
                description = "Choose the visual style for icon borders.",
                values = borderStyleValues,
                order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            -- Border Thickness slider
            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v)
                    setSetting("borderThickness", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "1",
                maxLabel = "8",
            })

            -- Border Inset slider
            inner:AddSlider({
                label = "Border Inset",
                description = "Move border inward (positive) or outward (negative).",
                min = -4,
                max = 4,
                step = 1,
                get = function() return getSetting("borderInset") or -1 end,
                set = function(v)
                    setSetting("borderInset", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "-4",
                maxLabel = "+4",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Text (contains tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "essentialCooldowns",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Helper to apply text styling
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            -- Font style options
            local fontStyleValues = {
                NONE = "None",
                OUTLINE = "Outline",
                THICKOUTLINE = "Thick Outline",
            }
            local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

            -- Tabbed section for Charges (stacks) and Cooldowns text settings
            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                },
                componentId = "essentialCooldowns",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        -- Helper to get/set textStacks sub-properties
                        local function getStacksSetting(key, default)
                            local ts = getSetting("textStacks")
                            if ts and ts[key] ~= nil then return ts[key] end
                            return default
                        end
                        local function setStacksSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textStacks = comp.db.textStacks or {}
                                comp.db.textStacks[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for charges/stacks text.",
                            get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setStacksSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getStacksSetting("size", 16) end,
                            set = function(v) setStacksSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getStacksSetting("style", "OUTLINE") end,
                            set = function(v) setStacksSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getStacksSetting("colorMode", "default") end,
                            set = function(v) setStacksSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getStacksSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setStacksSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset X slider
                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.x = v
                                end
                                applyText()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        -- Offset Y slider
                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.y = v
                                end
                                applyText()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        -- Helper to get/set textCooldown sub-properties
                        local function getCooldownSetting(key, default)
                            local tc = getSetting("textCooldown")
                            if tc and tc[key] ~= nil then return tc[key] end
                            return default
                        end
                        local function setCooldownSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textCooldown = comp.db.textCooldown or {}
                                comp.db.textCooldown[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for cooldown timer text.",
                            get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setCooldownSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getCooldownSetting("size", 14) end,
                            set = function(v) setCooldownSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getCooldownSetting("style", "OUTLINE") end,
                            set = function(v) setCooldownSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getCooldownSetting("colorMode", "default") end,
                            set = function(v) setCooldownSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getCooldownSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setCooldownSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset X slider
                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getCooldownSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                    comp.db.textCooldown.offset.x = v
                                end
                                applyText()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        -- Offset Y slider
                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getCooldownSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                    comp.db.textCooldown.offset.y = v
                                end
                                applyText()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility & Misc
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "essentialCooldowns",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Visibility Mode selector (Edit Mode setting)
            local visibilityValues = {
                always = "Always",
                combat = "Only in Combat",
                never = "Hidden",
            }
            local visibilityOrder = { "always", "combat", "never" }

            inner:AddSelector({
                label = "Visibility",
                description = "When the cooldown tracker is visible.",
                values = visibilityValues,
                order = visibilityOrder,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            -- Opacity in Combat slider (Edit Mode setting)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%",
                maxLabel = "100%",
                debounceKey = "UI_essentialCooldowns_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("opacity")
                end,
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            -- Opacity Out of Combat slider (addon-only)
            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Opacity when not in combat.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            -- Opacity With Target slider (addon-only)
            inner:AddSlider({
                label = "Opacity With Target",
                description = "Opacity when you have a target.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            -- Show Timer toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Timer",
                description = "Display cooldown timer text on icons.",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            -- Show Tooltips toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Tooltips",
                description = "Display tooltips when hovering over icons.",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Utility Cooldowns Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderUtilityCooldowns(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderUtilityCooldowns(scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["utilityCooldowns"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.utilityCooldowns and components.utilityCooldowns[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            -- Ensure component DB exists
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            -- Fallback to profile.components
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.utilityCooldowns = profile.components.utilityCooldowns or {}
                profile.components.utilityCooldowns[key] = value
            end
        end
    end

    -- Helper to sync Edit Mode settings after value change (debounced)
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "utilityCooldowns",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end
                    local columnsSlider = inner:GetControl("columnsRows")
                    if columnsSlider then
                        columnsSlider:SetLabel(OrientationPatterns.getColumnsLabel(v))
                    end
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                key = "columnsRows",
                label = OrientationPatterns.getColumnsLabel(currentOrientation),
                description = OrientationPatterns.getColumnsDescription(currentOrientation),
                min = 1,
                max = 20,
                step = 1,
                get = function() return getSetting("columns") or 12 end,
                set = function(v) setSetting("columns", v) end,
                minLabel = "1",
                maxLabel = "20",
                debounceKey = "UI_utilityCooldowns_columns",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("columns")
                end,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between cooldown icons in pixels.",
                min = 2,
                max = 14,
                step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px",
                maxLabel = "14px",
                debounceKey = "UI_utilityCooldowns_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "utilityCooldowns",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_utilityCooldowns_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconSize")
                end,
            })

            inner:AddSlider({
                label = "Icon Width",
                description = "Custom icon width in pixels.",
                min = 24,
                max = 96,
                step = 1,
                get = function() return getSetting("iconWidth") or 44 end,
                set = function(v)
                    setSetting("iconWidth", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "24px",
                maxLabel = "96px",
            })

            inner:AddSlider({
                label = "Icon Height",
                description = "Custom icon height in pixels.",
                min = 24,
                max = 96,
                step = 1,
                get = function() return getSetting("iconHeight") or 44 end,
                set = function(v)
                    setSetting("iconHeight", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "24px",
                maxLabel = "96px",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "utilityCooldowns",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                key = "borderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for cooldown icons.",
                get = function() return getSetting("borderEnable") or false end,
                set = function(val)
                    setSetting("borderEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(val)
                    setSetting("borderTintEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1 end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", { r = r, g = g, b = b, a = a })
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                hasAlpha = true,
            })

            local borderStyleValues = { square = "Default" }
            local borderStyleOrder = { "square" }
            if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
                local entries = addon.IconBorders.GetDropdownEntries()
                if entries then
                    borderStyleValues = {}
                    borderStyleOrder = {}
                    for _, entry in ipairs(entries) do
                        local key = entry.value or entry.key
                        local label = entry.text or entry.label or key
                        if key then
                            borderStyleValues[key] = label
                            table.insert(borderStyleOrder, key)
                        end
                    end
                end
            end

            inner:AddSelector({
                key = "borderStyle",
                label = "Border Style",
                description = "Choose the visual style for icon borders.",
                values = borderStyleValues,
                order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1, max = 8, step = 0.5, precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v)
                    setSetting("borderThickness", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "1", maxLabel = "8",
            })

            inner:AddSlider({
                label = "Border Inset",
                description = "Move border inward (positive) or outward (negative).",
                min = -4, max = 4, step = 1,
                get = function() return getSetting("borderInset") or -1 end,
                set = function(v)
                    setSetting("borderInset", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "-4", maxLabel = "+4",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Text
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "utilityCooldowns",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            local fontStyleValues = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" }
            local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                },
                componentId = "utilityCooldowns",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        local function getStacksSetting(key, default)
                            local ts = getSetting("textStacks")
                            if ts and ts[key] ~= nil then return ts[key] end
                            return default
                        end
                        local function setStacksSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textStacks = comp.db.textStacks or {}
                                comp.db.textStacks[key] = value
                            end
                            applyText()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setStacksSetting("fontFace", v) end,
                        })
                        tabBuilder:AddSlider({
                            label = "Font Size", min = 6, max = 32, step = 1,
                            get = function() return getStacksSetting("size", 16) end,
                            set = function(v) setStacksSetting("size", v) end,
                            minLabel = "6", maxLabel = "32",
                        })
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues, order = fontStyleOrder,
                            get = function() return getStacksSetting("style", "OUTLINE") end,
                            set = function(v) setStacksSetting("style", v) end,
                        })
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues, order = textColorOrder,
                            get = function() return getStacksSetting("colorMode", "default") end,
                            set = function(v) setStacksSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getStacksSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r,g,b,a) setStacksSetting("color", {r,g,b,a}) end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabBuilder:AddSlider({
                            label = "Offset X", min = -50, max = 50, step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.x = v
                                end
                                applyText()
                            end,
                            minLabel = "-50", maxLabel = "+50",
                        })
                        tabBuilder:AddSlider({
                            label = "Offset Y", min = -50, max = 50, step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.y = v
                                end
                                applyText()
                            end,
                            minLabel = "-50", maxLabel = "+50",
                        })
                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        local function getCooldownSetting(key, default)
                            local tc = getSetting("textCooldown")
                            if tc and tc[key] ~= nil then return tc[key] end
                            return default
                        end
                        local function setCooldownSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textCooldown = comp.db.textCooldown or {}
                                comp.db.textCooldown[key] = value
                            end
                            applyText()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setCooldownSetting("fontFace", v) end,
                        })
                        tabBuilder:AddSlider({
                            label = "Font Size", min = 6, max = 32, step = 1,
                            get = function() return getCooldownSetting("size", 14) end,
                            set = function(v) setCooldownSetting("size", v) end,
                            minLabel = "6", maxLabel = "32",
                        })
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues, order = fontStyleOrder,
                            get = function() return getCooldownSetting("style", "OUTLINE") end,
                            set = function(v) setCooldownSetting("style", v) end,
                        })
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues, order = textColorOrder,
                            get = function() return getCooldownSetting("colorMode", "default") end,
                            set = function(v) setCooldownSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getCooldownSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r,g,b,a) setCooldownSetting("color", {r,g,b,a}) end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabBuilder:AddSlider({
                            label = "Offset X", min = -50, max = 50, step = 1,
                            get = function()
                                local offset = getCooldownSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                    comp.db.textCooldown.offset.x = v
                                end
                                applyText()
                            end,
                            minLabel = "-50", maxLabel = "+50",
                        })
                        tabBuilder:AddSlider({
                            label = "Offset Y", min = -50, max = 50, step = 1,
                            get = function()
                                local offset = getCooldownSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                    comp.db.textCooldown.offset.y = v
                                end
                                applyText()
                            end,
                            minLabel = "-50", maxLabel = "+50",
                        })
                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility & Misc
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "utilityCooldowns",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local visibilityValues = { always = "Always", combat = "Only in Combat", never = "Hidden" }
            local visibilityOrder = { "always", "combat", "never" }

            inner:AddSelector({
                label = "Visibility",
                description = "When the cooldown tracker is visible.",
                values = visibilityValues,
                order = visibilityOrder,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%", maxLabel = "100%",
                debounceKey = "UI_utilityCooldowns_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("utilityCooldowns")
                    end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("utilityCooldowns")
                    end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            -- Hide when inactive (Edit Mode setting)
            inner:AddToggle({
                label = "Hide When Inactive",
                description = "Hide icons when they are not on cooldown.",
                get = function() return getSetting("hideWhenInactive") or false end,
                set = function(v)
                    setSetting("hideWhenInactive", v)
                    syncEditModeSetting("hideWhenInactive")
                end,
            })

            inner:AddToggle({
                label = "Show Timer",
                description = "Display cooldown timer text on icons.",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            inner:AddToggle({
                label = "Show Tooltips",
                description = "Display tooltips when hovering over icons.",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Tracked Buffs Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderTrackedBuffs(scrollContent)
    self:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function() panel:RenderTrackedBuffs(scrollContent) end)

    local function getComponent()
        return addon.Components and addon.Components["trackedBuffs"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.trackedBuffs and components.trackedBuffs[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.trackedBuffs = profile.components.trackedBuffs or {}
                profile.components.trackedBuffs[key] = value
            end
        end
    end

    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Positioning Section (different from Essential/Utility - has orientation but no columns)
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "trackedBuffs",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end
                end,
                syncCooldown = 0.4,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                min = 2, max = 14, step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px", maxLabel = "14px",
                debounceKey = "UI_trackedBuffs_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
            })

            inner:Finalize()
        end,
    })

    -- Sizing Section
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "trackedBuffs",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%", maxLabel = "200%",
                debounceKey = "UI_trackedBuffs_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
            })

            inner:AddSlider({
                label = "Icon Width", min = 24, max = 96, step = 1,
                get = function() return getSetting("iconWidth") or 44 end,
                set = function(v)
                    setSetting("iconWidth", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                minLabel = "24px", maxLabel = "96px",
            })

            inner:AddSlider({
                label = "Icon Height", min = 24, max = 96, step = 1,
                get = function() return getSetting("iconHeight") or 44 end,
                set = function(v)
                    setSetting("iconHeight", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                minLabel = "24px", maxLabel = "96px",
            })

            inner:Finalize()
        end,
    })

    -- Border Section
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "trackedBuffs",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Use Custom Border",
                get = function() return getSetting("borderEnable") or false end,
                set = function(v)
                    setSetting("borderEnable", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v)
                    setSetting("borderTintEnable", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1 end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", { r = r, g = g, b = b, a = a })
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                hasAlpha = true,
            })

            local borderStyleValues, borderStyleOrder = { square = "Default" }, { "square" }
            if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
                local entries = addon.IconBorders.GetDropdownEntries()
                if entries then
                    borderStyleValues, borderStyleOrder = {}, {}
                    for _, entry in ipairs(entries) do
                        local key = entry.value or entry.key
                        if key then
                            borderStyleValues[key] = entry.text or entry.label or key
                            table.insert(borderStyleOrder, key)
                        end
                    end
                end
            end

            inner:AddSelector({
                label = "Border Style",
                values = borderStyleValues, order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v)
                    setSetting("borderThickness", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                minLabel = "1", maxLabel = "8",
            })

            inner:AddSlider({
                label = "Border Inset", min = -4, max = 4, step = 1,
                get = function() return getSetting("borderInset") or -1 end,
                set = function(v)
                    setSetting("borderInset", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                minLabel = "-4", maxLabel = "+4",
            })

            inner:Finalize()
        end,
    })

    -- Visibility & Misc Section
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "trackedBuffs",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local visibilityValues = { always = "Always", combat = "Only in Combat", never = "Hidden" }
            local visibilityOrder = { "always", "combat", "never" }

            inner:AddSelector({
                label = "Visibility",
                values = visibilityValues, order = visibilityOrder,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Opacity in Combat", min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%", maxLabel = "100%",
                debounceKey = "UI_trackedBuffs_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBuffs") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBuffs") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddToggle({
                label = "Hide When Inactive",
                get = function() return getSetting("hideWhenInactive") or false end,
                set = function(v)
                    setSetting("hideWhenInactive", v)
                    syncEditModeSetting("hideWhenInactive")
                end,
            })

            inner:AddToggle({
                label = "Show Timer",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            inner:AddToggle({
                label = "Show Tooltips",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Tracked Bars Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderTrackedBars(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderTrackedBars(scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["trackedBars"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.trackedBars and components.trackedBars[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.trackedBars = profile.components.trackedBars or {}
                profile.components.trackedBars[key] = value
            end
        end
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function() addon:ApplyStyles() end)
        end
    end

    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Build bar texture options for selector (returns values and order)
    local function getBarTextureOptions()
        local values = { bevelled = "Bevelled" }
        local order = { "bevelled" }
        if addon.BuildBarTextureOptionsContainer then
            local data = addon.BuildBarTextureOptionsContainer()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    -- Build bar border options for selector (returns values and order)
    local function getBarBorderOptions()
        local values = { square = "Default (Square)" }
        local order = { "square" }
        if addon.BuildBarBorderOptionsContainer then
            local data = addon.BuildBarBorderOptionsContainer()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    -- Build icon border options for selector (returns values and order)
    local function getIconBorderOptions()
        local values = { square = "Default (Square)" }
        local order = { "square" }
        if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
            local data = addon.IconBorders.GetDropdownEntries()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "trackedBars",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 3 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = "trackedBars_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:AddSlider({
                label = "Icon/Bar Padding", min = -20, max = 80, step = 1,
                get = function() return getSetting("iconBarPadding") or 0 end,
                set = function(v) setSetting("iconBarPadding", v) end,
                minLabel = "-20", maxLabel = "80",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "trackedBars",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = "trackedBars_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Bar Width", min = 120, max = 480, step = 2,
                get = function() return getSetting("barWidth") or 220 end,
                set = function(v) setSetting("barWidth", v) end,
                minLabel = "120", maxLabel = "480",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "trackedBars",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Custom Textures",
                get = function() return getSetting("styleEnableCustom") ~= false end,
                set = function(v) setSetting("styleEnableCustom", v) end,
            })

            inner:AddBarTextureSelector({
                label = "Foreground Texture",
                get = function() return getSetting("styleForegroundTexture") or "bevelled" end,
                set = function(v) setSetting("styleForegroundTexture", v) end,
            })

            inner:AddBarTextureSelector({
                label = "Background Texture",
                get = function() return getSetting("styleBackgroundTexture") or "bevelled" end,
                set = function(v) setSetting("styleBackgroundTexture", v) end,
            })

            inner:AddColorPicker({
                label = "Foreground Color",
                get = function()
                    local c = getSetting("styleForegroundColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                set = function(r, g, b, a) setSetting("styleForegroundColor", {r, g, b, a}) end,
            })

            inner:AddColorPicker({
                label = "Background Color",
                get = function()
                    local c = getSetting("styleBackgroundColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 0.9
                end,
                set = function(r, g, b, a) setSetting("styleBackgroundColor", {r, g, b, a}) end,
            })

            inner:AddSlider({
                label = "Background Opacity", min = 0, max = 100, step = 1,
                get = function() return getSetting("styleBackgroundOpacity") or 50 end,
                set = function(v) setSetting("styleBackgroundOpacity", v) end,
                minLabel = "0%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "trackedBars",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Use Custom Border",
                get = function() return getSetting("borderEnable") or false end,
                set = function(v) setSetting("borderEnable", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                getToggle = function() return getSetting("borderTintEnable") or false end,
                setToggle = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("borderTintColor", {r, g, b, a}) end,
            })

            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = false,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v) setSetting("borderStyle", v) end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.2,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v) setSetting("borderThickness", v) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Icon Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Icon",
        componentId = "trackedBars",
        sectionKey = "icon",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Width", min = 8, max = 32, step = 1,
                get = function() return getSetting("iconWidth") or 30 end,
                set = function(v) setSetting("iconWidth", v) end,
                minLabel = "8", maxLabel = "32",
            })

            inner:AddSlider({
                label = "Icon Height", min = 8, max = 32, step = 1,
                get = function() return getSetting("iconHeight") or 30 end,
                set = function(v) setSetting("iconHeight", v) end,
                minLabel = "8", maxLabel = "32",
            })

            inner:AddToggle({
                label = "Enable Border",
                get = function() return getSetting("iconBorderEnable") or false end,
                set = function(v) setSetting("iconBorderEnable", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                getToggle = function() return getSetting("iconBorderTintEnable") or false end,
                setToggle = function(v) setSetting("iconBorderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("iconBorderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("iconBorderTintColor", {r, g, b, a}) end,
            })

            local iconBorderValues, iconBorderOrder = getIconBorderOptions()
            inner:AddSelector({
                label = "Border Style",
                values = iconBorderValues,
                order = iconBorderOrder,
                get = function() return getSetting("iconBorderStyle") or "square" end,
                set = function(v) setSetting("iconBorderStyle", v) end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.2,
                get = function() return getSetting("iconBorderThickness") or 1 end,
                set = function(v) setSetting("iconBorderThickness", v) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Misc Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "trackedBars",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Visibility Mode",
                values = {
                    always = "Always",
                    combat = "Only in Combat",
                    never = "Hidden",
                },
                order = { "always", "combat", "never" },
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.5,
            })

            inner:AddSlider({
                label = "Opacity in Combat", min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v)
                    setSetting("opacity", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                debounceKey = "trackedBars_opacity",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
                minLabel = "50%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSelector({
                label = "Display Mode",
                values = {
                    both = "Icon & Name",
                    icon = "Icon Only",
                    name = "Name Only",
                },
                order = { "both", "icon", "name" },
                get = function() return getSetting("displayMode") or "both" end,
                set = function(v)
                    setSetting("displayMode", v)
                    syncEditModeSetting("displayMode")
                end,
                syncCooldown = 0.5,
            })

            inner:AddToggle({
                label = "Hide When Inactive",
                get = function() return getSetting("hideWhenInactive") or false end,
                set = function(v)
                    setSetting("hideWhenInactive", v)
                    syncEditModeSetting("hideWhenInactive")
                end,
            })

            inner:AddToggle({
                label = "Show Timer",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            inner:AddToggle({
                label = "Show Tooltips",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Action Bar Renderer (Parameterized for bars 1-8, Pet Bar, Stance Bar)
--------------------------------------------------------------------------------

function UIPanel:RenderActionBar(scrollContent, componentId)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderActionBar(scrollContent, componentId)
    end)

    local function getComponent()
        return addon.Components and addon.Components[componentId]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components[componentId] and components[componentId][key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components[componentId] = profile.components[componentId] or {}
                profile.components[componentId][key] = value
            end
        end
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function() addon:ApplyStyles() end)
        end
    end

    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Build icon border options for selector (returns values and order)
    local function getIconBorderOptions()
        local values = { square = "Default (Square)" }
        local order = { "square" }
        if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
            local data = addon.IconBorders.GetDropdownEntries()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    -- Build backdrop options for selector (returns values and order)
    local function getBackdropOptions()
        local values = { blizzardBg = "Default Blizzard Backdrop" }
        local order = { "blizzardBg" }
        if addon.BuildIconBackdropOptionsContainer then
            local data = addon.BuildIconBackdropOptionsContainer()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    -- Determine bar type characteristics
    local isBar1 = (componentId == "actionBar1")
    local isBar2to8 = componentId:match("^actionBar[2-8]$") ~= nil
    local isPetBar = (componentId == "petBar")
    local isStanceBar = (componentId == "stanceBar")
    local hasNumIcons = isBar1 or isBar2to8  -- Only action bars 1-8 have numIcons
    local hasBorderBackdrop = not isStanceBar  -- Stance bar doesn't have border/backdrop in this UI

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = componentId,
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                key = "orientationSelector",
                label = "Orientation",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                    local columnsControl = inner:GetControl("columnsSlider")
                    if columnsControl and columnsControl.SetLabel then
                        columnsControl:SetLabel((v == "V") and "# of Rows" or "# of Columns")
                    end
                end,
                syncCooldown = 0.5,
            })

            local orientation = getSetting("orientation") or "H"
            inner:AddSlider({
                key = "columnsSlider",
                label = (orientation == "V") and "# of Rows" or "# of Columns",
                min = 1, max = 4, step = 1,
                get = function() return getSetting("columns") or 1 end,
                set = function(v) setSetting("columns", v) end,
                debounceKey = componentId .. "_columns",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("columns") end,
                minLabel = "1", maxLabel = "4",
            })

            if hasNumIcons then
                inner:AddSlider({
                    label = "# of Icons", min = 6, max = 12, step = 1,
                    get = function() return getSetting("numIcons") or 12 end,
                    set = function(v) setSetting("numIcons", v) end,
                    debounceKey = componentId .. "_numIcons",
                    debounceDelay = 0.3,
                    onEditModeSync = function() syncEditModeSetting("numIcons") end,
                    minLabel = "6", maxLabel = "12",
                })
            end

            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = componentId .. "_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = componentId,
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = componentId .. "_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Action Bars 1-8 and Pet Bar only, NOT Stance Bar)
    ---------------------------------------------------------------------------
    local hasTextSection = isBar1 or isBar2to8 or isPetBar
    if hasTextSection then
        builder:AddCollapsibleSection({
            title = "Text",
            componentId = componentId,
            sectionKey = "text",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                -- Helper to apply text styling
                local function applyText()
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end

                -- Font style options
                local fontStyleValues = {
                    NONE = "None",
                    OUTLINE = "Outline",
                    THICKOUTLINE = "Thick Outline",
                }
                local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

                -- Determine tabs based on bar type
                -- Action Bars and Pet Bar have 4 tabs: Charges, Cooldowns, Hotkey, Macro Name
                local tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                    { key = "hotkey", label = "Keybind" },
                    { key = "macroName", label = "Macro Name" },
                }

                inner:AddTabbedSection({
                    tabs = tabs,
                    componentId = componentId,
                    sectionKey = "textTabs",
                    buildContent = {
                        -------------------------------------------------------
                        -- Charges (textStacks) Tab
                        -------------------------------------------------------
                        charges = function(tabContent, tabBuilder)
                            local function getStacksSetting(key, default)
                                local ts = getSetting("textStacks")
                                if ts and ts[key] ~= nil then return ts[key] end
                                return default
                            end
                            local function setStacksSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setStacksSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getStacksSetting("size", 16) end,
                                set = function(v) setStacksSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getStacksSetting("style", "OUTLINE") end,
                                set = function(v) setStacksSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getStacksSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setStacksSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Cooldowns (textCooldown) Tab
                        -------------------------------------------------------
                        cooldowns = function(tabContent, tabBuilder)
                            local function getCooldownSetting(key, default)
                                local tc = getSetting("textCooldown")
                                if tc and tc[key] ~= nil then return tc[key] end
                                return default
                            end
                            local function setCooldownSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setCooldownSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getCooldownSetting("size", 14) end,
                                set = function(v) setCooldownSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getCooldownSetting("style", "OUTLINE") end,
                                set = function(v) setCooldownSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getCooldownSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setCooldownSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Hotkey (textHotkey) Tab
                        -------------------------------------------------------
                        hotkey = function(tabContent, tabBuilder)
                            local function getHotkeySetting(key, default)
                                local th = getSetting("textHotkey")
                                if th and th[key] ~= nil then return th[key] end
                                return default
                            end
                            local function setHotkeySetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textHotkey = comp.db.textHotkey or {}
                                    comp.db.textHotkey[key] = value
                                end
                                applyText()
                            end

                            -- Hide Hotkey toggle (stored as textHotkeyHidden)
                            tabBuilder:AddToggle({
                                label = "Hide Hotkey Text",
                                get = function() return getSetting("textHotkeyHidden") or false end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkeyHidden = v
                                    end
                                    applyText()
                                end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getHotkeySetting("fontFace", "FRIZQT__") end,
                                set = function(v) setHotkeySetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getHotkeySetting("size", 14) end,
                                set = function(v) setHotkeySetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getHotkeySetting("style", "OUTLINE") end,
                                set = function(v) setHotkeySetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getHotkeySetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setHotkeySetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getHotkeySetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkey = comp.db.textHotkey or {}
                                        comp.db.textHotkey.offset = comp.db.textHotkey.offset or {}
                                        comp.db.textHotkey.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getHotkeySetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkey = comp.db.textHotkey or {}
                                        comp.db.textHotkey.offset = comp.db.textHotkey.offset or {}
                                        comp.db.textHotkey.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Macro Name (textMacro) Tab
                        -------------------------------------------------------
                        macroName = function(tabContent, tabBuilder)
                            local function getMacroSetting(key, default)
                                local tm = getSetting("textMacro")
                                if tm and tm[key] ~= nil then return tm[key] end
                                return default
                            end
                            local function setMacroSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textMacro = comp.db.textMacro or {}
                                    comp.db.textMacro[key] = value
                                end
                                applyText()
                            end

                            -- Hide Macro Name toggle (stored as textMacroHidden)
                            tabBuilder:AddToggle({
                                label = "Hide Macro Name",
                                get = function() return getSetting("textMacroHidden") or false end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacroHidden = v
                                    end
                                    applyText()
                                end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getMacroSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setMacroSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getMacroSetting("size", 14) end,
                                set = function(v) setMacroSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getMacroSetting("style", "OUTLINE") end,
                                set = function(v) setMacroSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getMacroSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setMacroSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getMacroSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacro = comp.db.textMacro or {}
                                        comp.db.textMacro.offset = comp.db.textMacro.offset or {}
                                        comp.db.textMacro.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getMacroSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacro = comp.db.textMacro or {}
                                        comp.db.textMacro.offset = comp.db.textMacro.offset or {}
                                        comp.db.textMacro.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,
                    },
                })

                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Border Section (not for Stance Bar)
    ---------------------------------------------------------------------------
    if hasBorderBackdrop then
        builder:AddCollapsibleSection({
            title = "Border",
            componentId = componentId,
            sectionKey = "border",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddToggle({
                    label = "Disable All Borders",
                    get = function() return getSetting("borderDisableAll") or false end,
                    set = function(v) setSetting("borderDisableAll", v) end,
                })

                inner:AddToggle({
                    label = "Use Custom Border",
                    get = function() return getSetting("borderEnable") or false end,
                    set = function(v) setSetting("borderEnable", v) end,
                })

                inner:AddToggleColorPicker({
                    label = "Border Tint",
                    getToggle = function() return getSetting("borderTintEnable") or false end,
                    setToggle = function(v) setSetting("borderTintEnable", v) end,
                    getColor = function()
                        local c = getSetting("borderTintColor")
                        return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                    end,
                    setColor = function(r, g, b, a) setSetting("borderTintColor", {r, g, b, a}) end,
                })

                local borderValues, borderOrder = getIconBorderOptions()
                inner:AddSelector({
                    label = "Border Style",
                    values = borderValues,
                    order = borderOrder,
                    get = function() return getSetting("borderStyle") or "square" end,
                    set = function(v) setSetting("borderStyle", v) end,
                })

                inner:AddSlider({
                    label = "Border Thickness", min = 1, max = 8, step = 0.2,
                    get = function() return getSetting("borderThickness") or 1 end,
                    set = function(v) setSetting("borderThickness", v) end,
                    minLabel = "1", maxLabel = "8",
                })

                inner:AddSlider({
                    label = "Border Inset", min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInset") or 0 end,
                    set = function(v) setSetting("borderInset", v) end,
                    minLabel = "-4", maxLabel = "4",
                })

                inner:Finalize()
            end,
        })

        ---------------------------------------------------------------------------
        -- Backdrop Section (not for Stance Bar)
        ---------------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Backdrop",
            componentId = componentId,
            sectionKey = "backdrop",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddToggle({
                    label = "Disable Backdrop",
                    get = function() return getSetting("backdropDisable") or false end,
                    set = function(v) setSetting("backdropDisable", v) end,
                })

                local backdropValues, backdropOrder = getBackdropOptions()
                inner:AddSelector({
                    label = "Backdrop Style",
                    values = backdropValues,
                    order = backdropOrder,
                    get = function() return getSetting("backdropStyle") or "blizzardBg" end,
                    set = function(v) setSetting("backdropStyle", v) end,
                })

                inner:AddSlider({
                    label = "Backdrop Opacity", min = 1, max = 100, step = 1,
                    get = function() return getSetting("backdropOpacity") or 100 end,
                    set = function(v) setSetting("backdropOpacity", v) end,
                    minLabel = "1%", maxLabel = "100%",
                })

                inner:AddToggleColorPicker({
                    label = "Backdrop Tint",
                    getToggle = function() return getSetting("backdropTintEnable") or false end,
                    setToggle = function(v) setSetting("backdropTintEnable", v) end,
                    getColor = function()
                        local c = getSetting("backdropTintColor")
                        return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                    end,
                    setColor = function(r, g, b, a) setSetting("backdropTintColor", {r, g, b, a}) end,
                })

                inner:AddSlider({
                    label = "Backdrop Inset", min = -4, max = 4, step = 1,
                    get = function() return getSetting("backdropInset") or 0 end,
                    set = function(v) setSetting("backdropInset", v) end,
                    minLabel = "-4", maxLabel = "4",
                })

                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Misc/Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = componentId,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if isBar2to8 then
                inner:AddSelector({
                    label = "Bar Visible",
                    values = {
                        always = "Always",
                        combat = "In Combat",
                        not_in_combat = "Not In Combat",
                        hidden = "Hidden",
                    },
                    order = { "always", "combat", "not_in_combat", "hidden" },
                    get = function() return getSetting("barVisibility") or "always" end,
                    set = function(v)
                        setSetting("barVisibility", v)
                        syncEditModeSetting("barVisibility")
                    end,
                    syncCooldown = 0.5,
                })
            end

            if isBar1 or isBar2to8 or isPetBar then
                inner:AddToggle({
                    label = "Always Show Buttons",
                    get = function() return getSetting("alwaysShowButtons") ~= false end,
                    set = function(v)
                        setSetting("alwaysShowButtons", v)
                        syncEditModeSetting("alwaysShowButtons")
                    end,
                })
            end

            if isBar1 then
                inner:AddToggle({
                    label = "Hide Bar Art",
                    get = function() return getSetting("hideBarArt") or false end,
                    set = function(v)
                        setSetting("hideBarArt", v)
                        syncEditModeSetting("hideBarArt")
                    end,
                })

                inner:AddToggle({
                    label = "Hide Bar Scrolling",
                    get = function() return getSetting("hideBarScrolling") or false end,
                    set = function(v)
                        setSetting("hideBarScrolling", v)
                        syncEditModeSetting("hideBarScrolling")
                    end,
                })
            end

            inner:AddSlider({
                label = "Opacity in Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacity") or 100 end,
                set = function(v) setSetting("barOpacity", v) end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityOutOfCombat") or 100 end,
                set = function(v) setSetting("barOpacityOutOfCombat", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityWithTarget") or 100 end,
                set = function(v) setSetting("barOpacityWithTarget", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddToggle({
                label = "Mouseover Mode",
                get = function() return getSetting("mouseoverMode") or false end,
                set = function(v) setSetting("mouseoverMode", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Micro Bar Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderMicroBar(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderMicroBar(scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["microBar"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.microBar and components.microBar[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.microBar = profile.components.microBar or {}
                profile.components.microBar[key] = value
            end
        end
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function() addon:ApplyStyles() end)
        end
    end

    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "microBar",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Orientation",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                end,
                syncCooldown = 0.5,
            })

            inner:AddSelector({
                label = "Direction",
                values = {
                    left = "Left",
                    right = "Right",
                    up = "Up",
                    down = "Down",
                },
                order = { "left", "right", "up", "down" },
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.5,
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "microBar",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Menu Size (Scale)", min = 70, max = 200, step = 5,
                get = function() return getSetting("menuSize") or 100 end,
                set = function(v) setSetting("menuSize", v) end,
                debounceKey = "microBar_menuSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("menuSize") end,
                minLabel = "70%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Eye Size", min = 50, max = 150, step = 5,
                get = function() return getSetting("eyeSize") or 100 end,
                set = function(v) setSetting("eyeSize", v) end,
                debounceKey = "microBar_eyeSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("eyeSize") end,
                minLabel = "50%", maxLabel = "150%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "microBar",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity in Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacity") or 100 end,
                set = function(v) setSetting("barOpacity", v) end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityWithTarget") or 100 end,
                set = function(v) setSetting("barOpacityWithTarget", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityOutOfCombat") or 100 end,
                set = function(v) setSetting("barOpacityOutOfCombat", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddToggle({
                label = "Mouseover Mode",
                get = function() return getSetting("mouseoverMode") or false end,
                set = function(v) setSetting("mouseoverMode", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Chat Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderChat(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    -- Helper to get/set chat profile settings
    local function getChatSetting(key)
        local profile = addon.db and addon.db.profile
        return profile and profile.chat and profile.chat[key]
    end

    local function setChatSetting(key, value)
        if not (addon.db and addon.db.profile) then return end
        addon.db.profile.chat = addon.db.profile.chat or {}
        addon.db.profile.chat[key] = value
        -- Apply styles after setting change
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    builder:AddToggle({
        label = "Hide In-Game Chat",
        get = function()
            return getChatSetting("hideInGameChat") or false
        end,
        set = function(val)
            setChatSetting("hideInGameChat", val)
        end,
        infoIcon = {
            tooltipTitle = "Hide In-Game Chat",
            tooltipText = "Hides chat windows/tabs and related controls, but keeps the chat input box so you can see slash commands you run. Added for use with the ScooterDeck preset. If you want to customize your Chat frame, I recommend Chattynator. :)",
        },
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- SCT Damage Numbers Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderSctDamage(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["sctDamage"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.sctDamage and components.sctDamage[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.sctDamage = profile.components.sctDamage or {}
                profile.components.sctDamage[key] = value
            end
        end
    end

    builder:AddDescription(
        "Changes to the damage number font require a full game restart (not just a reload) to take effect. " ..
        "The scale slider applies immediately."
    )

    builder:AddFontSelector({
        label = "Font",
        description = "The font used for floating combat text damage numbers.",
        get = function()
            return getSetting("fontFace") or "FRIZQT__"
        end,
        set = function(fontKey)
            setSetting("fontFace", fontKey or "FRIZQT__")
            local comp = getComponent()
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end,
    })

    builder:AddSlider({
        label = "Font Scale",
        description = "Scale of floating combat text numbers (affects all world text).",
        min = 50,
        max = 150,
        step = 1,
        get = function()
            return getSetting("fontScale") or 100
        end,
        set = function(v)
            setSetting("fontScale", v)
            local comp = getComponent()
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end,
        minLabel = "50%",
        maxLabel = "150%",
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Personal Resource Display Renderers
--------------------------------------------------------------------------------

function UIPanel:RenderPRDGeneral(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderPRDGeneral(scrollContent)
    end)

    -- CVar helpers
    local function getPRDEnabledFromCVar()
        if GetCVarBool then
            return GetCVarBool("nameplateShowSelf")
        end
        if C_CVar and C_CVar.GetCVar then
            return C_CVar.GetCVar("nameplateShowSelf") == "1"
        end
        return false
    end

    local function setPRDEnabledCVar(enabled)
        local value = (enabled and "1") or "0"
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "nameplateShowSelf", value)
        elseif SetCVar then
            pcall(SetCVar, "nameplateShowSelf", value)
        end
    end

    -- Profile data helpers
    local function getProfilePRDSettings()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.prdSettings
    end

    local function ensureProfilePRDSettings()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.prdSettings = addon.db.profile.prdSettings or {}
        return addon.db.profile.prdSettings
    end

    builder:AddToggle({
        label = "Enable the PRD Per-Profile",
        description = "When enabled, the Personal Resource Display will be active for this profile. This overrides the character-wide Blizzard setting.",
        get = function()
            local s = getProfilePRDSettings()
            if s and s.enablePRD ~= nil then
                return s.enablePRD
            end
            return getPRDEnabledFromCVar()
        end,
        set = function(value)
            local s = ensureProfilePRDSettings()
            if not s then return end
            s.enablePRD = value
            setPRDEnabledCVar(value)
            -- Re-apply styling so borders/overlays respond to the change
            if addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
        end,
    })

    builder:Finalize()
end

function UIPanel:RenderPRDHealthBar(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderPRDHealthBar(scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["prdHealth"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        return nil
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        end
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end)
        end
    end

    -- Build border options
    local function getBorderOptions()
        local values = { none = "None", square = "Default (Square)" }
        local order = { "none", "square" }
        if addon.BuildBarBorderOptionsContainer then
            local data = addon.BuildBarBorderOptionsContainer()
            if data and #data > 0 then
                values = { none = "None" }
                order = { "none" }
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdHealth",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Width",
                min = 60, max = 600, step = 1,
                get = function() return getSetting("barWidth") or 200 end,
                set = function(v) setSetting("barWidth", v) end,
                minLabel = "60", maxLabel = "600",
            })

            inner:AddSlider({
                label = "Bar Height",
                min = 4, max = 60, step = 1,
                get = function() return getSetting("barHeight") or 12 end,
                set = function(v) setSetting("barHeight", v) end,
                minLabel = "4", maxLabel = "60",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "prdHealth",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = true,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v) setSetting("borderStyle", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                getToggle = function() return getSetting("borderTintEnable") or false end,
                setToggle = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                end,
                hasAlpha = true,
            })

            inner:AddSlider({
                label = "Border Thickness",
                min = 1, max = 8, step = 0.5, precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v) setSetting("borderThickness", v) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "prdHealth",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Foreground Texture
            inner:AddBarTextureSelector({
                label = "Foreground Texture",
                get = function() return getSetting("styleForegroundTexture") or "default" end,
                set = function(v) setSetting("styleForegroundTexture", v) end,
            })

            -- Foreground Color
            inner:AddSelectorColorPicker({
                label = "Foreground Color",
                values = {
                    default = "Default",
                    class = "Class Color",
                    custom = "Custom",
                },
                order = { "default", "class", "custom" },
                get = function() return getSetting("styleForegroundColorMode") or "default" end,
                set = function(v) setSetting("styleForegroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleForegroundTint") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleForegroundTint", {r, g, b, a})
                end,
                customValue = "custom",
                hasAlpha = true,
            })

            inner:AddSpacer(8)

            -- Background Texture
            inner:AddBarTextureSelector({
                label = "Background Texture",
                get = function() return getSetting("styleBackgroundTexture") or "default" end,
                set = function(v) setSetting("styleBackgroundTexture", v) end,
            })

            -- Background Color
            inner:AddSelectorColorPicker({
                label = "Background Color",
                values = {
                    default = "Default",
                    custom = "Custom",
                },
                order = { "default", "custom" },
                get = function() return getSetting("styleBackgroundColorMode") or "default" end,
                set = function(v) setSetting("styleBackgroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleBackgroundTint") or {0, 0, 0, 1}
                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleBackgroundTint", {r, g, b, a})
                end,
                customValue = "custom",
                hasAlpha = true,
            })

            -- Background Opacity
            inner:AddSlider({
                label = "Background Opacity",
                min = 0, max = 100, step = 1,
                get = function() return getSetting("styleBackgroundOpacity") or 50 end,
                set = function(v) setSetting("styleBackgroundOpacity", v) end,
                minLabel = "0%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Tabbed: Value Text / % Text)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "prdHealth",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local textTabs = {
                {
                    key = "valueText",
                    label = "Value Text",
                    infoIcon = {
                        tooltipTitle = "Value Text",
                        tooltipText = "Displays current health as a number on the PRD health bar.",
                    },
                },
                {
                    key = "percentText",
                    label = "% Text",
                    infoIcon = {
                        tooltipTitle = "Percentage Text",
                        tooltipText = "Displays current health as a percentage on the PRD health bar.",
                    },
                },
            }

            inner:AddTabbedSection({
                tabs = textTabs,
                componentId = "prdHealth",
                sectionKey = "textTabs",
                buildContent = {
                    valueText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Value Text",
                            get = function() return getSetting("valueTextShow") or false end,
                            set = function(v) setSetting("valueTextShow", v) end,
                        })

                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("valueTextFont") or "Friz Quadrata TT" end,
                            set = function(v) setSetting("valueTextFont", v) end,
                        })

                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function() return getSetting("valueTextFontSize") or 10 end,
                            set = function(v) setSetting("valueTextFontSize", v) end,
                            minLabel = "6", maxLabel = "24",
                        })

                        tabInner:AddSelector({
                            label = "Font Style",
                            values = {
                                NONE = "Regular",
                                OUTLINE = "Outline",
                                THICKOUTLINE = "Thick Outline",
                                HEAVYTHICKOUTLINE = "Heavy Thick Outline",
                                SHADOW = "Shadow",
                                SHADOWOUTLINE = "Shadow Outline",
                                SHADOWTHICKOUTLINE = "Shadow Thick Outline",
                                HEAVYSHADOWTHICKOUTLINE = "Heavy Shadow Thick Outline",
                            },
                            order = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE", "HEAVYSHADOWTHICKOUTLINE" },
                            get = function() return getSetting("valueTextFontFlags") or "OUTLINE" end,
                            set = function(v) setSetting("valueTextFontFlags", v) end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getSetting("valueTextColorMode") or "default" end,
                            set = function(v) setSetting("valueTextColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("valueTextColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("valueTextColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Text Alignment",
                            values = {
                                LEFT = "Left",
                                CENTER = "Center",
                                RIGHT = "Right",
                            },
                            order = { "RIGHT", "LEFT", "CENTER" },
                            get = function() return getSetting("valueTextAlignment") or "RIGHT" end,
                            set = function(v) setSetting("valueTextAlignment", v) end,
                        })

                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show % Text",
                            get = function() return getSetting("percentTextShow") or false end,
                            set = function(v) setSetting("percentTextShow", v) end,
                        })

                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("percentTextFont") or "Friz Quadrata TT" end,
                            set = function(v) setSetting("percentTextFont", v) end,
                        })

                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function() return getSetting("percentTextFontSize") or 10 end,
                            set = function(v) setSetting("percentTextFontSize", v) end,
                            minLabel = "6", maxLabel = "24",
                        })

                        tabInner:AddSelector({
                            label = "Font Style",
                            values = {
                                NONE = "Regular",
                                OUTLINE = "Outline",
                                THICKOUTLINE = "Thick Outline",
                                HEAVYTHICKOUTLINE = "Heavy Thick Outline",
                                SHADOW = "Shadow",
                                SHADOWOUTLINE = "Shadow Outline",
                                SHADOWTHICKOUTLINE = "Shadow Thick Outline",
                                HEAVYSHADOWTHICKOUTLINE = "Heavy Shadow Thick Outline",
                            },
                            order = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE", "HEAVYSHADOWTHICKOUTLINE" },
                            get = function() return getSetting("percentTextFontFlags") or "OUTLINE" end,
                            set = function(v) setSetting("percentTextFontFlags", v) end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getSetting("percentTextColorMode") or "default" end,
                            set = function(v) setSetting("percentTextColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("percentTextColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("percentTextColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Text Alignment",
                            values = {
                                LEFT = "Left",
                                CENTER = "Center",
                                RIGHT = "Right",
                            },
                            order = { "LEFT", "RIGHT", "CENTER" },
                            get = function() return getSetting("percentTextAlignment") or "LEFT" end,
                            set = function(v) setSetting("percentTextAlignment", v) end,
                        })

                        tabInner:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdHealth",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Health Bar",
                get = function() return getSetting("hideBar") or false end,
                set = function(v) setSetting("hideBar", v) end,
            })

            inner:AddToggle({
                label = "Hide the Bar but not its Text",
                get = function() return getSetting("hideTextureOnly") or false end,
                set = function(v) setSetting("hideTextureOnly", v) end,
                infoIcon = {
                    tooltipTitle = "Hide the Bar but not its Text",
                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your health.",
                },
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

function UIPanel:RenderPRDPowerBar(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderPRDPowerBar(scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["prdPower"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        return nil
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        end
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end)
        end
    end

    -- Build border options
    local function getBorderOptions()
        local values = { none = "None", square = "Default (Square)" }
        local order = { "none", "square" }
        if addon.BuildBarBorderOptionsContainer then
            local data = addon.BuildBarBorderOptionsContainer()
            if data and #data > 0 then
                values = { none = "None" }
                order = { "none" }
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdPower",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Height",
                min = 4, max = 40, step = 1,
                get = function() return getSetting("barHeight") or 8 end,
                set = function(v) setSetting("barHeight", v) end,
                minLabel = "4", maxLabel = "40",
                infoIcon = {
                    tooltipTitle = "Power Bar Height",
                    tooltipText = "Width automatically follows the Health Bar width.",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "prdPower",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Foreground Texture
            inner:AddBarTextureSelector({
                label = "Foreground Texture",
                get = function() return getSetting("styleForegroundTexture") or "default" end,
                set = function(v) setSetting("styleForegroundTexture", v) end,
            })

            -- Foreground Color
            inner:AddSelectorColorPicker({
                label = "Foreground Color",
                values = {
                    default = "Default",
                    power = "Power Color",
                    custom = "Custom",
                },
                order = { "default", "power", "custom" },
                get = function() return getSetting("styleForegroundColorMode") or "default" end,
                set = function(v) setSetting("styleForegroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleForegroundTint") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleForegroundTint", {r, g, b, a})
                end,
                customValue = "custom",
                hasAlpha = true,
            })

            inner:AddSpacer(8)

            -- Background Texture
            inner:AddBarTextureSelector({
                label = "Background Texture",
                get = function() return getSetting("styleBackgroundTexture") or "default" end,
                set = function(v) setSetting("styleBackgroundTexture", v) end,
            })

            -- Background Color
            inner:AddSelectorColorPicker({
                label = "Background Color",
                values = {
                    default = "Default",
                    custom = "Custom",
                },
                order = { "default", "custom" },
                get = function() return getSetting("styleBackgroundColorMode") or "default" end,
                set = function(v) setSetting("styleBackgroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleBackgroundTint") or {0, 0, 0, 1}
                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleBackgroundTint", {r, g, b, a})
                end,
                customValue = "custom",
                hasAlpha = true,
            })

            -- Background Opacity
            inner:AddSlider({
                label = "Background Opacity",
                min = 0, max = 100, step = 1,
                get = function() return getSetting("styleBackgroundOpacity") or 50 end,
                set = function(v) setSetting("styleBackgroundOpacity", v) end,
                minLabel = "0%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "prdPower",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = true,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v) setSetting("borderStyle", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                getToggle = function() return getSetting("borderTintEnable") or false end,
                setToggle = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                end,
                hasAlpha = true,
            })

            inner:AddSlider({
                label = "Border Thickness",
                min = 1, max = 8, step = 0.5, precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v) setSetting("borderThickness", v) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Tabbed: Value Text / % Text)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "prdPower",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local textTabs = {
                {
                    key = "valueText",
                    label = "Value Text",
                    infoIcon = {
                        tooltipTitle = "Value Text",
                        tooltipText = "Displays current power as a number on the PRD power bar.",
                    },
                },
                {
                    key = "percentText",
                    label = "% Text",
                    infoIcon = {
                        tooltipTitle = "Percentage Text",
                        tooltipText = "Displays current power as a percentage on the PRD power bar.",
                    },
                },
            }

            inner:AddTabbedSection({
                tabs = textTabs,
                componentId = "prdPower",
                sectionKey = "textTabs",
                buildContent = {
                    valueText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Value Text",
                            get = function() return getSetting("valueTextShow") or false end,
                            set = function(v) setSetting("valueTextShow", v) end,
                        })

                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("valueTextFont") or "Friz Quadrata TT" end,
                            set = function(v) setSetting("valueTextFont", v) end,
                        })

                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function() return getSetting("valueTextFontSize") or 10 end,
                            set = function(v) setSetting("valueTextFontSize", v) end,
                            minLabel = "6", maxLabel = "24",
                        })

                        tabInner:AddSelector({
                            label = "Font Style",
                            values = {
                                NONE = "Regular",
                                OUTLINE = "Outline",
                                THICKOUTLINE = "Thick Outline",
                                HEAVYTHICKOUTLINE = "Heavy Thick Outline",
                                SHADOW = "Shadow",
                                SHADOWOUTLINE = "Shadow Outline",
                                SHADOWTHICKOUTLINE = "Shadow Thick Outline",
                                HEAVYSHADOWTHICKOUTLINE = "Heavy Shadow Thick Outline",
                            },
                            order = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE", "HEAVYSHADOWTHICKOUTLINE" },
                            get = function() return getSetting("valueTextFontFlags") or "OUTLINE" end,
                            set = function(v) setSetting("valueTextFontFlags", v) end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorPowerValues,
                            order = textColorPowerOrder,
                            get = function() return getSetting("valueTextColorMode") or "default" end,
                            set = function(v) setSetting("valueTextColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("valueTextColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("valueTextColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Text Alignment",
                            values = {
                                LEFT = "Left",
                                CENTER = "Center",
                                RIGHT = "Right",
                            },
                            order = { "RIGHT", "LEFT", "CENTER" },
                            get = function() return getSetting("valueTextAlignment") or "RIGHT" end,
                            set = function(v) setSetting("valueTextAlignment", v) end,
                        })

                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show % Text",
                            get = function() return getSetting("percentTextShow") or false end,
                            set = function(v) setSetting("percentTextShow", v) end,
                        })

                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("percentTextFont") or "Friz Quadrata TT" end,
                            set = function(v) setSetting("percentTextFont", v) end,
                        })

                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function() return getSetting("percentTextFontSize") or 10 end,
                            set = function(v) setSetting("percentTextFontSize", v) end,
                            minLabel = "6", maxLabel = "24",
                        })

                        tabInner:AddSelector({
                            label = "Font Style",
                            values = {
                                NONE = "Regular",
                                OUTLINE = "Outline",
                                THICKOUTLINE = "Thick Outline",
                                HEAVYTHICKOUTLINE = "Heavy Thick Outline",
                                SHADOW = "Shadow",
                                SHADOWOUTLINE = "Shadow Outline",
                                SHADOWTHICKOUTLINE = "Shadow Thick Outline",
                                HEAVYSHADOWTHICKOUTLINE = "Heavy Shadow Thick Outline",
                            },
                            order = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE", "HEAVYSHADOWTHICKOUTLINE" },
                            get = function() return getSetting("percentTextFontFlags") or "OUTLINE" end,
                            set = function(v) setSetting("percentTextFontFlags", v) end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorPowerValues,
                            order = textColorPowerOrder,
                            get = function() return getSetting("percentTextColorMode") or "default" end,
                            set = function(v) setSetting("percentTextColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("percentTextColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("percentTextColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Text Alignment",
                            values = {
                                LEFT = "Left",
                                CENTER = "Center",
                                RIGHT = "Right",
                            },
                            order = { "LEFT", "RIGHT", "CENTER" },
                            get = function() return getSetting("percentTextAlignment") or "LEFT" end,
                            set = function(v) setSetting("percentTextAlignment", v) end,
                        })

                        tabInner:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdPower",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Power Bar",
                get = function() return getSetting("hideBar") or false end,
                set = function(v) setSetting("hideBar", v) end,
            })

            inner:AddToggle({
                label = "Hide the Bar but not its Text",
                get = function() return getSetting("hideTextureOnly") or false end,
                set = function(v) setSetting("hideTextureOnly", v) end,
                infoIcon = {
                    tooltipTitle = "Hide the Bar but not its Text",
                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your power resource.",
                },
            })

            inner:AddToggle({
                label = "Hide Full Bar Animations",
                get = function() return getSetting("hideSpikeAnimations") or false end,
                set = function(v) setSetting("hideSpikeAnimations", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Full Bar Animations",
                    tooltipText = "Hides the 'spike' animations that play when your power bar reaches full.",
                },
            })

            inner:AddToggle({
                label = "Hide Power Feedback",
                get = function() return getSetting("hidePowerFeedback") or false end,
                set = function(v) setSetting("hidePowerFeedback", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Power Feedback",
                    tooltipText = "Hides the visual feedback animation when power is gained or spent.",
                },
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

function UIPanel:RenderPRDClassResource(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderPRDClassResource(scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["prdClassResource"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        return nil
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        end
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdClassResource",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Scale",
                min = 50, max = 150, step = 1,
                get = function() return getSetting("scale") or 100 end,
                set = function(v) setSetting("scale", v) end,
                minLabel = "50%", maxLabel = "150%",
                infoIcon = {
                    tooltipTitle = "Class Resource Scale",
                    tooltipText = "Adjusts the size of the class resource display (combo points, runes, holy power, etc.).",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdClassResource",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Class Resource",
                get = function() return getSetting("hideBar") or false end,
                set = function(v) setSetting("hideBar", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Tooltip Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderTooltip(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderTooltip(scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["tooltip"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.tooltip and components.tooltip[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            -- Ensure component DB exists
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            -- Fallback to profile.components
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.tooltip = profile.components.tooltip or {}
                profile.components.tooltip[key] = value
            end
        end
        -- Apply styles after setting change
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    -- Helper to get text config sub-table
    local function getTextConfig(key)
        local comp = getComponent()
        local db = comp and comp.db
        if db and type(db[key]) == "table" then
            return db[key]
        end
        return nil
    end

    local function ensureTextConfig(key, defaults)
        local comp = getComponent()
        if not comp then return nil end
        local db = comp.db
        if not db then return nil end

        db[key] = db[key] or {}
        local t = db[key]
        if t.fontFace == nil then t.fontFace = defaults.fontFace end
        if t.size == nil then t.size = defaults.size end
        if t.style == nil then t.style = defaults.style end
        return t
    end

    -- Font style options
    local fontStyleValues = {
        NONE = "Regular",
        OUTLINE = "Outline",
        THICKOUTLINE = "Thick Outline",
    }
    local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

    -- Helper to build text tab content (used by all three tabs)
    local function buildTextTabContent(tabBuilder, dbKey, defaults)
        -- Font selector
        tabBuilder:AddFontSelector({
            label = "Font",
            description = "The font used for this text element.",
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.fontFace) or defaults.fontFace
            end,
            set = function(fontKey)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.fontFace = fontKey or defaults.fontFace
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
        })

        -- Font size slider
        tabBuilder:AddSlider({
            label = "Font Size",
            description = "The size of this text element.",
            min = 6,
            max = 32,
            step = 1,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.size) or defaults.size
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.size = v or defaults.size
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
            minLabel = "6",
            maxLabel = "32",
        })

        -- Font style selector
        tabBuilder:AddSelector({
            label = "Font Style",
            description = "The outline style for this text.",
            values = fontStyleValues,
            order = fontStyleOrder,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.style) or defaults.style
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.style = v or defaults.style
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
        })

        tabBuilder:Finalize()
    end

    -- Collapsible section: Text (with tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "tooltip",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "nameTitle", label = "Name & Title" },
                    { key = "everythingElse", label = "Everything Else" },
                    { key = "comparison", label = "Comparison" },
                },
                componentId = "tooltip",
                sectionKey = "textTabs",
                buildContent = {
                    nameTitle = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textTitle", {
                            fontFace = "FRIZQT__",
                            size = 12,
                            style = "NONE",
                        })
                    end,
                    everythingElse = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textEverythingElse", {
                            fontFace = "FRIZQT__",
                            size = 12,
                            style = "NONE",
                        })
                    end,
                    comparison = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textComparison", {
                            fontFace = "FRIZQT__",
                            size = 12,
                            style = "NONE",
                        })
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "tooltip",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Tooltip Health Bar",
                description = "Hide the health bar that appears on unit tooltips.",
                get = function()
                    return getSetting("hideHealthBar") or false
                end,
                set = function(val)
                    setSetting("hideHealthBar", val)
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Minimap Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderMinimap(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    builder:AddDescription(
        "Minimap customization is coming soon.\n\n" ..
        "This section will include options for positioning, scale, and visibility of minimap buttons."
    )

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Objective Tracker Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderObjectiveTracker(scrollContent)
    -- Clear any existing content
    self:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderObjectiveTracker(scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["objectiveTracker"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.objectiveTracker and components.objectiveTracker[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            -- Ensure component DB exists
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            -- Fallback to profile.components
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.objectiveTracker = profile.components.objectiveTracker or {}
                profile.components.objectiveTracker[key] = value
            end
        end
        -- Apply styles after setting change
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    -- Helper to sync Edit Mode settings after value change (debounced)
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Helper to get text config sub-table
    local function getTextConfig(key)
        local comp = getComponent()
        local db = comp and comp.db
        if db and type(db[key]) == "table" then
            return db[key]
        end
        return nil
    end

    local function ensureTextConfig(key, defaults)
        local comp = getComponent()
        if not comp then return nil end
        local db = comp.db
        if not db then return nil end

        db[key] = db[key] or {}
        local t = db[key]
        if t.fontFace == nil then t.fontFace = defaults.fontFace end
        if t.style == nil then t.style = defaults.style end
        if t.colorMode == nil then t.colorMode = defaults.colorMode end
        if type(t.color) ~= "table" then
            t.color = { defaults.color[1], defaults.color[2], defaults.color[3], defaults.color[4] }
        end
        return t
    end

    -- Font style options
    local fontStyleValues = {
        NONE = "Regular",
        OUTLINE = "Outline",
        THICKOUTLINE = "Thick Outline",
    }
    local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

    -- Font color mode options (for UISelectorColorPicker)
    local fontColorValues = {
        default = "Default",
        custom = "Custom",
    }
    local fontColorOrder = { "default", "custom" }

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "objectiveTracker",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Height",
                description = "Maximum height of the Objective Tracker frame.",
                min = 200,
                max = 1000,
                step = 10,
                get = function() return getSetting("height") or 400 end,
                set = function(v) setSetting("height", v) end,
                minLabel = "200",
                maxLabel = "1000",
                debounceKey = "UI_objectiveTracker_height",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("height")
                end,
            })

            inner:AddSlider({
                label = "Text Size",
                description = "Size of text in the Objective Tracker.",
                min = 10,
                max = 24,
                step = 1,
                get = function() return getSetting("textSize") or 14 end,
                set = function(v) setSetting("textSize", v) end,
                minLabel = "10",
                maxLabel = "24",
                debounceKey = "UI_objectiveTracker_textSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("textSize")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Style
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "objectiveTracker",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Header Backgrounds",
                description = "Remove the backgrounds behind section headers.",
                get = function()
                    return getSetting("hideHeaderBackgrounds") or false
                end,
                set = function(val)
                    setSetting("hideHeaderBackgrounds", val)
                end,
            })

            inner:AddToggleColorPicker({
                label = "Tint Header Background",
                description = "Apply a custom tint color to section header backgrounds.",
                get = function()
                    return getSetting("tintHeaderBackgroundEnable") or false
                end,
                set = function(val)
                    setSetting("tintHeaderBackgroundEnable", val)
                end,
                getColor = function()
                    local c = getSetting("tintHeaderBackgroundColor")
                    if c and type(c) == "table" then
                        return c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("tintHeaderBackgroundColor", { r, g, b, a })
                end,
                hasAlpha = true,
            })

            inner:Finalize()
        end,
    })

    -- Helper to build text tab content (used by all three tabs)
    local function buildTextTabContent(tabBuilder, dbKey, defaults)
        -- Font selector
        tabBuilder:AddFontSelector({
            label = "Font",
            description = "The font used for this text element.",
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.fontFace) or defaults.fontFace
            end,
            set = function(fontKey)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.fontFace = fontKey or defaults.fontFace
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
        })

        -- Font style selector
        tabBuilder:AddSelector({
            label = "Font Style",
            description = "The outline style for this text.",
            values = fontStyleValues,
            order = fontStyleOrder,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.style) or defaults.style
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.style = v or defaults.style
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
        })

        -- Font color selector with inline swatch (UISelectorColorPicker)
        tabBuilder:AddSelectorColorPicker({
            label = "Font Color",
            description = "Color mode for this text. Select 'Custom' to choose a specific color.",
            values = fontColorValues,
            order = fontColorOrder,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.colorMode) or defaults.colorMode
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.colorMode = v or defaults.colorMode
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
            getColor = function()
                local t = getTextConfig(dbKey)
                local c = (t and type(t.color) == "table" and t.color) or defaults.color
                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end,
            setColor = function(r, g, b, a)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.color = { r or 1, g or 1, b or 1, a or 1 }
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
            customValue = "custom",
            hasAlpha = true,
        })

        tabBuilder:Finalize()
    end

    -- Collapsible section: Text (with tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "objectiveTracker",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "header", label = "Header" },
                    { key = "questName", label = "Quest Name" },
                    { key = "questObjective", label = "Quest Objective" },
                },
                componentId = "objectiveTracker",
                sectionKey = "textTabs",
                buildContent = {
                    header = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textHeader", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    questName = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textQuestName", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    questObjective = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textQuestObjective", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 0.8, 0.8, 0.8, 1 },
                        })
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "objectiveTracker",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Background Opacity",
                description = "Overall background opacity of the Objective Tracker.",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "0%",
                maxLabel = "100%",
                debounceKey = "UI_objectiveTracker_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("opacity")
                end,
            })

            inner:AddSlider({
                label = "Opacity In-Instance-Combat",
                description = "Opacity when in combat inside an instance (dungeon/raid).",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityInInstanceCombat") or 100 end,
                set = function(v)
                    setSetting("opacityInInstanceCombat", v)
                    if addon and addon.RefreshOpacityState then
                        addon:RefreshOpacityState()
                    end
                end,
                minLabel = "0%",
                maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Rules UI (TUI-styled)
--------------------------------------------------------------------------------
-- Custom card-based layout for Rules with TUI styling.
-- Uses manual frame creation rather than SettingsBuilder due to the
-- unique card-based structure with display/edit modes.
--
-- CLEANUP: Since Rules uses manual state tracking (_rulesState.currentControls)
-- instead of the builder pattern, cleanup is handled in TWO places:
--   1. ClearContent() - Cleans up when navigating AWAY from Rules
--   2. RenderProfilesRules() - Cleans up when re-rendering Rules (refresh)
-- Both are needed to ensure proper cleanup in all scenarios.

-- Module-level state for Rules UI
UIPanel._rulesState = UIPanel._rulesState or {
    editingRules = {},      -- Track which rules are in edit mode (keyed by rule.id)
    breadcrumbs = {},       -- Track partial breadcrumb selections (keyed by rule.id)
    cardFrames = {},        -- Recycled card frames
    dividerFrames = {},     -- Recycled divider frames
    currentControls = {},   -- Track created controls for cleanup (see CLEANUP note above)
}

-- Constants for Rules UI layout
local RULES_CARD_HEIGHT_DISPLAY = 130
local RULES_CARD_HEIGHT_EDIT = 340
local RULES_DIVIDER_HEIGHT = 24
local RULES_ADD_BUTTON_HEIGHT = 50
local RULES_EMPTY_STATE_HEIGHT = 80
local RULES_INDEX_BADGE_SIZE = 26
local RULES_CARD_LEFT_MARGIN = 44  -- Space for index badge
local RULES_CARD_RIGHT_MARGIN = 8
local RULES_CARD_PADDING = 12
local RULES_MAX_DISPLAY_BADGES = 3
local RULES_SPEC_BADGE_GAP = 4  -- Horizontal gap between spec badges
local RULES_BREADCRUMB_HEIGHT = 30  -- Taller dropdowns for long text

--------------------------------------------------------------------------------
-- Rules: Spec Picker Popup
--------------------------------------------------------------------------------

local rulesSpecPickerFrame = nil
local rulesSpecPickerElements = {}

local function CloseSpecPicker()
    if rulesSpecPickerFrame then
        rulesSpecPickerFrame:Hide()
    end
end

local function ShowSpecPicker(anchor, rule, callback)
    -- Get theme colors
    local ar, ag, ab = Theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = Theme:GetBackgroundSolidColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local fontPath = Theme:GetFont("VALUE")
    local labelFont = Theme:GetFont("LABEL")
    local headerFont = Theme:GetFont("HEADER")

    -- Get spec data (this is an ARRAY of class entries, not a key-value table)
    local specBuckets = {}
    if addon.Rules and addon.Rules.GetSpecBuckets then
        specBuckets = addon.Rules:GetSpecBuckets() or {}
    end

    -- Get currently selected specs
    local selectedSpecs = {}
    if rule and rule.trigger and rule.trigger.specIds then
        for _, id in ipairs(rule.trigger.specIds) do
            selectedSpecs[id] = true
        end
    end

    -- Clean up previous elements
    for _, elem in ipairs(rulesSpecPickerElements) do
        if elem.Hide then elem:Hide() end
        if elem.SetParent then elem:SetParent(nil) end
    end
    wipe(rulesSpecPickerElements)

    -- Create frame if needed
    if not rulesSpecPickerFrame then
        local frame = CreateFrame("Frame", "ScooterSpecPicker", UIParent, "BackdropTemplate")
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(200)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:Hide()

        -- ESC to close
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                CloseSpecPicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        rulesSpecPickerFrame = frame
    end

    local frame = rulesSpecPickerFrame

    -- Calculate content height first
    local specRowHeight = 20
    local classHeaderHeight = 22
    local classGap = 8
    local specsPerRow = 3
    local contentHeight = 0

    for _, classEntry in ipairs(specBuckets) do
        contentHeight = contentHeight + classHeaderHeight
        local specRows = math.ceil(#classEntry.specs / specsPerRow)
        contentHeight = contentHeight + (specRows * specRowHeight) + classGap
    end

    -- Frame sizing
    local frameWidth = 360
    local titleHeight = 28
    local bottomPadding = 44
    local maxContentHeight = 300
    local actualContentHeight = math.min(contentHeight, maxContentHeight)
    local frameHeight = titleHeight + actualContentHeight + bottomPadding + 12
    local needsScroll = contentHeight > maxContentHeight

    frame:SetSize(frameWidth, frameHeight)

    -- Position below anchor using absolute coordinates
    -- (relative anchoring doesn't work reliably for popup frames)
    frame:ClearAllPoints()
    local anchorLeft = anchor:GetLeft()
    local anchorBottom = anchor:GetBottom()
    local scale = frame:GetEffectiveScale()
    if anchorLeft and anchorBottom then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorLeft, anchorBottom - 4)
    else
        -- Fallback: position near mouse
        local x, y = GetCursorPosition()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    -- Update backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(bgR, bgG, bgB, 0.98)
    frame:SetBackdropBorderColor(ar, ag, ab, 0.9)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    titleBar:SetHeight(titleHeight)
    table.insert(rulesSpecPickerElements, titleBar)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(ar, ag, ab, 0.15)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(headerFont, 12, "")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("Select Specializations")
    titleText:SetTextColor(ar, ag, ab, 1)

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    table.insert(rulesSpecPickerElements, closeBtn)

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(headerFont, 14, "")
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeText:SetTextColor(dimR, dimG, dimB, 1)

    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3, 1) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(dimR, dimG, dimB, 1) end)
    closeBtn:SetScript("OnClick", function()
        CloseSpecPicker()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)

    -- Content area (with optional scroll)
    local contentParent
    local scrollFrame, scrollBar

    if needsScroll then
        -- Create scroll frame manually (no Blizzard template)
        scrollFrame = CreateFrame("ScrollFrame", nil, frame)
        scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 6, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, bottomPadding)
        scrollFrame:EnableMouseWheel(true)
        table.insert(rulesSpecPickerElements, scrollFrame)

        local scrollContent = CreateFrame("Frame", nil, scrollFrame)
        scrollContent:SetSize(frameWidth - 24, contentHeight)
        scrollFrame:SetScrollChild(scrollContent)
        contentParent = scrollContent

        -- TUI-styled scrollbar
        scrollBar = CreateFrame("Frame", nil, frame)
        scrollBar:SetWidth(6)
        scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(titleHeight + 8))
        scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, bottomPadding + 2)
        table.insert(rulesSpecPickerElements, scrollBar)

        local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
        scrollTrack:SetAllPoints()
        scrollTrack:SetColorTexture(0.15, 0.15, 0.15, 0.8)

        local scrollThumb = CreateFrame("Frame", nil, scrollBar)
        scrollThumb:SetWidth(6)
        local thumbRatio = actualContentHeight / contentHeight
        local thumbHeight = math.max(20, scrollBar:GetHeight() * thumbRatio)
        scrollThumb:SetHeight(thumbHeight)
        scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)

        local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(ar, ag, ab, 0.6)
        scrollBar._thumb = scrollThumb
        scrollBar._thumbTex = thumbTex

        -- Scroll wheel handler
        local maxScroll = contentHeight - actualContentHeight
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
            self:SetVerticalScroll(newScroll)
            -- Update thumb position
            local scrollRatio = newScroll / maxScroll
            local trackHeight = scrollBar:GetHeight() - thumbHeight
            scrollThumb:ClearAllPoints()
            scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -scrollRatio * trackHeight)
        end)
    else
        -- No scroll needed, content directly in frame
        contentParent = CreateFrame("Frame", nil, frame)
        contentParent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 6, -6)
        contentParent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -6, -6)
        contentParent:SetHeight(contentHeight)
        table.insert(rulesSpecPickerElements, contentParent)
    end

    -- Build spec list
    local yOffset = 0
    local specColWidth = 105

    for _, classEntry in ipairs(specBuckets) do
        -- Class header
        local classHeader = contentParent:CreateFontString(nil, "OVERLAY")
        classHeader:SetFont(labelFont, 11, "")
        classHeader:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, yOffset)
        classHeader:SetText(classEntry.name or "Unknown")

        -- Class color
        local classColor = RAID_CLASS_COLORS[classEntry.file]
        if classColor then
            classHeader:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        else
            classHeader:SetTextColor(ar, ag, ab, 1)
        end

        yOffset = yOffset - classHeaderHeight

        -- Specs
        local xOffset = 10
        local colCount = 0
        for _, spec in ipairs(classEntry.specs) do
            local specID = spec.specID

            local toggle = CreateFrame("Button", nil, contentParent)
            toggle:SetSize(specColWidth, specRowHeight)
            toggle:SetPoint("TOPLEFT", contentParent, "TOPLEFT", xOffset, yOffset)
            toggle._selected = selectedSpecs[specID] or false

            -- Checkbox
            local checkbox = toggle:CreateTexture(nil, "ARTWORK")
            checkbox:SetSize(12, 12)
            checkbox:SetPoint("LEFT", toggle, "LEFT", 0, 0)
            checkbox:SetTexture("Interface\\Buttons\\WHITE8x8")
            toggle._checkbox = checkbox

            -- Icon
            local icon = toggle:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
            if spec.icon then icon:SetTexture(spec.icon) end

            -- Name
            local nameText = toggle:CreateFontString(nil, "OVERLAY")
            nameText:SetFont(fontPath, 10, "")
            nameText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
            nameText:SetText(spec.name or "")
            nameText:SetWidth(specColWidth - 35)
            nameText:SetJustifyH("LEFT")
            toggle._nameText = nameText

            local function updateVisual()
                if toggle._selected then
                    checkbox:SetColorTexture(ar, ag, ab, 1)
                    nameText:SetTextColor(1, 1, 1, 1)
                else
                    checkbox:SetColorTexture(0.25, 0.25, 0.25, 1)
                    nameText:SetTextColor(dimR, dimG, dimB, 1)
                end
            end
            updateVisual()

            toggle:SetScript("OnEnter", function(self)
                if not self._selected then checkbox:SetColorTexture(ar, ag, ab, 0.5) end
            end)
            toggle:SetScript("OnLeave", function() updateVisual() end)
            toggle:SetScript("OnClick", function(self)
                self._selected = not self._selected
                updateVisual()
                if addon.Rules and addon.Rules.ToggleRuleSpec then
                    addon.Rules:ToggleRuleSpec(rule.id, specID)
                end
                if callback then callback() end
                PlaySound(self._selected and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            end)

            colCount = colCount + 1
            if colCount >= specsPerRow then
                colCount = 0
                xOffset = 10
                yOffset = yOffset - specRowHeight
            else
                xOffset = xOffset + specColWidth
            end
        end

        -- Move to next row if we didn't complete the last row
        if colCount > 0 then
            yOffset = yOffset - specRowHeight
        end
        yOffset = yOffset - classGap
    end

    -- Done button
    local doneBtn = Controls:CreateButton({
        parent = frame,
        text = "Done",
        width = 80,
        height = 26,
        onClick = function()
            CloseSpecPicker()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end,
    })
    doneBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    table.insert(rulesSpecPickerElements, doneBtn)

    frame:Show()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

--------------------------------------------------------------------------------
-- Rules: Spec Badge (icon + class-colored text, no background)
--------------------------------------------------------------------------------

local function CreateRulesSpecBadge(parent, specID)
    if not parent or not specID then return nil end
    if not addon.Rules or not addon.Rules.GetSpecBuckets then return nil end

    local _, specById = addon.Rules:GetSpecBuckets()
    local specEntry = specById and specById[specID]
    if not specEntry then return nil end

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(90, 20)
    badge.specID = specID
    badge.specEntry = specEntry

    -- Spec icon
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", badge, "LEFT", 0, 0)
    if specEntry.icon then
        icon:SetTexture(specEntry.icon)
    end
    badge._icon = icon

    -- Spec name in class color (NO background per HOLDING3.md)
    local name = badge:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("VALUE")
    name:SetFont(fontPath, 11, "")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetText(specEntry.name or tostring(specID))
    name:SetJustifyH("LEFT")

    -- Apply class color to text
    local classFile = specEntry.file or specEntry.classFile
    if classFile then
        local classColor = RAID_CLASS_COLORS[classFile]
        if classColor then
            name:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        else
            name:SetTextColor(1, 1, 1, 1)
        end
    else
        name:SetTextColor(1, 1, 1, 1)
    end
    badge._name = name

    -- Auto-size based on text width
    C_Timer.After(0, function()
        if name and badge then
            local textWidth = name:GetStringWidth() or 60
            badge:SetWidth(20 + textWidth + 8)
        end
    end)

    -- Tooltip
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(specEntry.className or "Unknown Class", 1, 1, 1)
        GameTooltip:AddLine(specEntry.name or "Unknown Spec", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return badge
end

--------------------------------------------------------------------------------
-- Rules: Format action value for display
--------------------------------------------------------------------------------

local function FormatRulesActionValue(actionId, value)
    if not addon.Rules then
        return tostring(value or "?"), nil
    end

    local meta = addon.Rules:GetActionMetadata(actionId)
    if not meta then
        return tostring(value or "?"), nil
    end

    local widget = meta.widget or "checkbox"
    local valueType = meta.valueType or "boolean"

    if widget == "checkbox" or valueType == "boolean" then
        return value and "True" or "False", nil
    elseif widget == "slider" or valueType == "number" then
        local num = tonumber(value) or 0
        if meta.uiMeta and meta.uiMeta.format == "percent" then
            return string.format("%d%%", num), nil
        end
        return tostring(num), nil
    elseif widget == "dropdown" then
        if meta.uiMeta and meta.uiMeta.values then
            local displayLabel = meta.uiMeta.values[value]
            if displayLabel then
                return displayLabel, nil
            end
        end
        return tostring(value or "?"), nil
    elseif widget == "color" or valueType == "color" then
        local colorValue = value
        if type(colorValue) ~= "table" then
            colorValue = { 1, 1, 1, 1 }
        end
        return nil, colorValue
    else
        return tostring(value or "?"), nil
    end
end

--------------------------------------------------------------------------------
-- Rules: Get action leaf name and parent path
--------------------------------------------------------------------------------

local function GetRulesActionLeafAndPath(actionId)
    if not addon.Rules then return "Select Target", "" end
    local meta = addon.Rules:GetActionMetadata(actionId)
    if not meta or not meta.path then
        return "Select Target", ""
    end
    local path = meta.path
    local leaf = path[#path] or "Unknown"
    local parentPath = ""
    if #path > 1 then
        local parents = {}
        for i = 1, #path - 1 do
            table.insert(parents, path[i])
        end
        parentPath = table.concat(parents, " › ")
    end
    return leaf, parentPath
end

--------------------------------------------------------------------------------
-- Rules: Create TUI-styled rule card
--------------------------------------------------------------------------------

local function CreateRulesCard(parent, rule, refreshCallback)
    local state = UIPanel._rulesState
    local isEditing = state.editingRules[rule.id]

    -- Get theme colors
    local ar, ag, ab = Theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = Theme:GetCollapsibleBgColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()

    -- Card container with TUI styling (gray background within border)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(isEditing and RULES_CARD_HEIGHT_EDIT or RULES_CARD_HEIGHT_DISPLAY)

    -- Gray background (like collapsible section headers per HOLDING3.md)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    card._bg = bg

    -- Border
    local borderAlpha = 0.6
    local borders = {}
    local function createBorder(side)
        local tex = card:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(ar, ag, ab, borderAlpha)
        if side == "TOP" then
            tex:SetHeight(1)
            tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        elseif side == "BOTTOM" then
            tex:SetHeight(1)
            tex:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        elseif side == "LEFT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        elseif side == "RIGHT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        end
        borders[side] = tex
    end
    createBorder("TOP")
    createBorder("BOTTOM")
    createBorder("LEFT")
    createBorder("RIGHT")
    card._borders = borders

    -- Theme subscription
    local subscribeKey = "RulesCard_" .. (rule.id or tostring(card))
    Theme:Subscribe(subscribeKey, function(r, g, b)
        for _, tex in pairs(borders) do
            tex:SetColorTexture(r, g, b, borderAlpha)
        end
    end)
    card._subscribeKey = subscribeKey

    card.Cleanup = function(self)
        if self._subscribeKey then
            Theme:Unsubscribe(self._subscribeKey)
        end
        -- Clean up spec badges
        if self._specBadges then
            for _, badge in ipairs(self._specBadges) do
                badge:Hide()
                badge:SetParent(nil)
            end
        end
    end

    -- === INDEX BADGE (outside card, on the left) ===
    local indexBadge = CreateFrame("Frame", nil, card)
    indexBadge:SetSize(RULES_INDEX_BADGE_SIZE, RULES_INDEX_BADGE_SIZE)
    indexBadge:SetPoint("TOPRIGHT", card, "TOPLEFT", -10, -8)

    local indexBg = indexBadge:CreateTexture(nil, "BACKGROUND")
    indexBg:SetAllPoints()
    indexBg:SetColorTexture(ar, ag, ab, 1)
    indexBadge._bg = indexBg

    local indexText = indexBadge:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("LABEL")
    indexText:SetFont(fontPath, 12, "")
    indexText:SetPoint("CENTER")
    indexText:SetText(tostring(rule.displayIndex or "?"))
    indexText:SetTextColor(0.05, 0.05, 0.05, 1)  -- Dark text for contrast
    indexBadge._text = indexText
    card._indexBadge = indexBadge

    if isEditing then
        -- === EDIT MODE ===
        RenderRulesCardEditMode(card, rule, refreshCallback, ar, ag, ab)
    else
        -- === DISPLAY MODE ===
        RenderRulesCardDisplayMode(card, rule, refreshCallback, ar, ag, ab)
    end

    return card
end

--------------------------------------------------------------------------------
-- Rules: Display Mode (collapsed card)
--------------------------------------------------------------------------------

function RenderRulesCardDisplayMode(card, rule, refreshCallback, ar, ag, ab)
    local fontPath = Theme:GetFont("VALUE")
    local labelFont = Theme:GetFont("LABEL")
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local state = UIPanel._rulesState

    -- === HEADER ROW ===
    -- Enable toggle (using text-based ON/OFF indicator like Toggle)
    local enableLabel = card:CreateFontString(nil, "OVERLAY")
    enableLabel:SetFont(labelFont, 11, "")
    enableLabel:SetPoint("TOPLEFT", card, "TOPLEFT", RULES_CARD_PADDING, -RULES_CARD_PADDING)
    enableLabel:SetText("Enabled?")
    enableLabel:SetTextColor(ar, ag, ab, 1)
    card._enableLabel = enableLabel

    -- ON/OFF indicator
    local indicator = CreateFrame("Frame", nil, card)
    indicator:SetSize(50, 20)
    indicator:SetPoint("LEFT", enableLabel, "RIGHT", 8, 0)

    local indicatorBorder = {}
    for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        local tex = indicator:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(ar, ag, ab, 0.8)
        if side == "TOP" then
            tex:SetHeight(1)
            tex:SetPoint("TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", 0, 0)
        elseif side == "BOTTOM" then
            tex:SetHeight(1)
            tex:SetPoint("BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", 0, 0)
        elseif side == "LEFT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", 0, 0)
        elseif side == "RIGHT" then
            tex:SetWidth(1)
            tex:SetPoint("TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", 0, 0)
        end
        indicatorBorder[side] = tex
    end

    local indicatorBg = indicator:CreateTexture(nil, "BACKGROUND")
    indicatorBg:SetAllPoints()
    local isEnabled = rule.enabled ~= false
    if isEnabled then
        indicatorBg:SetColorTexture(ar, ag, ab, 1)
    else
        indicatorBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    end
    indicator._bg = indicatorBg

    local indicatorText = indicator:CreateFontString(nil, "OVERLAY")
    indicatorText:SetFont(fontPath, 11, "")
    indicatorText:SetPoint("CENTER")
    indicatorText:SetText(isEnabled and "ON" or "OFF")
    indicatorText:SetTextColor(isEnabled and 0.05 or dimR, isEnabled and 0.05 or dimG, isEnabled and 0.05 or dimB, 1)
    indicator._text = indicatorText

    -- Make indicator clickable
    indicator:EnableMouse(true)
    indicator:SetScript("OnMouseDown", function()
        if addon.Rules and addon.Rules.SetRuleEnabled then
            addon.Rules:SetRuleEnabled(rule.id, not isEnabled)
            if refreshCallback then refreshCallback() end
        end
    end)
    card._indicator = indicator

    -- Edit button
    local editBtn = Controls:CreateButton({
        parent = card,
        text = "Edit",
        width = 50,
        height = 22,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            state.editingRules[rule.id] = true
            if refreshCallback then refreshCallback() end
        end,
    })
    editBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING, -RULES_CARD_PADDING)
    card._editBtn = editBtn

    -- === WHEN ROW ===
    local whenLabel = card:CreateFontString(nil, "OVERLAY")
    whenLabel:SetFont(labelFont, 13, "")
    whenLabel:SetPoint("TOPLEFT", card, "TOPLEFT", RULES_CARD_PADDING + 4, -42)
    whenLabel:SetText("WHEN")
    whenLabel:SetTextColor(ar, ag, ab, 1)
    card._whenLabel = whenLabel

    local triggerType = rule.trigger and rule.trigger.type or "specialization"

    if triggerType == "playerLevel" then
        -- Player Level display
        local levelText = card:CreateFontString(nil, "OVERLAY")
        levelText:SetFont(fontPath, 12, "")
        levelText:SetPoint("LEFT", whenLabel, "RIGHT", 16, 0)
        local levelVal = rule.trigger and rule.trigger.level
        if levelVal then
            levelText:SetText(string.format("Player Level = %d", levelVal))
        else
            levelText:SetText("Player Level = (not set)")
        end
        levelText:SetTextColor(1, 1, 1, 1)
        card._levelText = levelText
    else
        -- Spec badges container
        local specIds = rule.trigger and rule.trigger.specIds or {}
        local specContainer = CreateFrame("Frame", nil, card)
        specContainer:SetPoint("LEFT", whenLabel, "RIGHT", 16, 0)
        specContainer:SetSize(400, 20)
        card._specContainer = specContainer
        card._specBadges = {}

        local xOffset = 0
        local visibleCount = math.min(#specIds, RULES_MAX_DISPLAY_BADGES)

        for i = 1, visibleCount do
            local specID = specIds[i]
            local badge = CreateRulesSpecBadge(specContainer, specID)
            if badge then
                badge:SetPoint("LEFT", specContainer, "LEFT", xOffset, 0)
                badge:Show()
                table.insert(card._specBadges, badge)
                xOffset = xOffset + badge:GetWidth() + RULES_SPEC_BADGE_GAP
            end
        end

        -- Overflow indicator
        local overflowCount = #specIds - visibleCount
        if overflowCount > 0 then
            local overflow = card:CreateFontString(nil, "OVERLAY")
            overflow:SetFont(fontPath, 10, "")
            overflow:SetPoint("LEFT", specContainer, "LEFT", xOffset, 0)
            overflow:SetText(string.format("+%d more", overflowCount))
            overflow:SetTextColor(dimR, dimG, dimB, 1)
            card._overflow = overflow
        end

        -- No specs placeholder
        if #specIds == 0 then
            local noSpec = card:CreateFontString(nil, "OVERLAY")
            noSpec:SetFont(fontPath, 11, "")
            noSpec:SetPoint("LEFT", whenLabel, "RIGHT", 16, 0)
            noSpec:SetText("(no specs selected)")
            noSpec:SetTextColor(dimR, dimG, dimB, 1)
            card._noSpec = noSpec
        end
    end

    -- === DO ROW ===
    local doLabel = card:CreateFontString(nil, "OVERLAY")
    doLabel:SetFont(labelFont, 13, "")
    doLabel:SetPoint("TOPLEFT", whenLabel, "BOTTOMLEFT", 0, -20)
    doLabel:SetText("DO")
    doLabel:SetTextColor(ar, ag, ab, 1)
    card._doLabel = doLabel

    local actionId = rule.action and rule.action.id
    local leaf, parentPath = GetRulesActionLeafAndPath(actionId)
    local displayText, colorValue = FormatRulesActionValue(actionId, rule.action and rule.action.value)

    local actionText = card:CreateFontString(nil, "OVERLAY")
    actionText:SetFont(fontPath, 12, "")
    actionText:SetPoint("LEFT", doLabel, "RIGHT", 28, 0)

    if colorValue then
        actionText:SetText(string.format("%s =", leaf))
        actionText:SetTextColor(1, 1, 1, 1)

        -- Color swatch
        local swatch = CreateFrame("Frame", nil, card)
        swatch:SetSize(24, 14)
        swatch:SetPoint("LEFT", actionText, "RIGHT", 6, 0)
        local swatchBg = swatch:CreateTexture(nil, "ARTWORK")
        swatchBg:SetAllPoints()
        local r, g, b, a = colorValue[1] or 1, colorValue[2] or 1, colorValue[3] or 1, colorValue[4] or 1
        swatchBg:SetColorTexture(r, g, b, a)
        card._swatch = swatch
    else
        actionText:SetText(string.format("%s = %s", leaf, displayText or "?"))
        actionText:SetTextColor(1, 1, 1, 1)
    end
    card._actionText = actionText

    -- Parent path (muted, smaller)
    if parentPath and parentPath ~= "" then
        local pathText = card:CreateFontString(nil, "OVERLAY")
        pathText:SetFont(fontPath, 10, "")
        pathText:SetPoint("TOPLEFT", actionText, "BOTTOMLEFT", 0, -4)
        pathText:SetText("@ " .. parentPath)
        pathText:SetTextColor(dimR, dimG, dimB, 1)
        card._pathText = pathText
    end
end

--------------------------------------------------------------------------------
-- Rules: Edit Mode (expanded card)
--------------------------------------------------------------------------------

function RenderRulesCardEditMode(card, rule, refreshCallback, ar, ag, ab)
    local fontPath = Theme:GetFont("VALUE")
    local labelFont = Theme:GetFont("LABEL")
    local headerFont = Theme:GetFont("HEADER")
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local bgR, bgG, bgB, bgA = Theme:GetCollapsibleBgColor()
    local state = UIPanel._rulesState

    -- === HEADER ROW ===
    -- Delete button
    local deleteBtn = Controls:CreateButton({
        parent = card,
        text = "Delete",
        width = 60,
        height = 22,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOTERMOD_DELETE_RULE", {
                    onAccept = function()
                        if rule.id and addon.Rules and addon.Rules.DeleteRule then
                            state.editingRules[rule.id] = nil
                            state.breadcrumbs[rule.id] = nil
                            addon.Rules:DeleteRule(rule.id)
                            if refreshCallback then refreshCallback() end
                        end
                    end,
                })
            end
        end,
    })
    deleteBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING - 60, -RULES_CARD_PADDING)
    card._deleteBtn = deleteBtn

    -- Done button
    local doneBtn = Controls:CreateButton({
        parent = card,
        text = "Done",
        width = 50,
        height = 22,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            state.editingRules[rule.id] = nil
            if refreshCallback then refreshCallback() end
        end,
    })
    doneBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING, -RULES_CARD_PADDING)
    card._doneBtn = doneBtn

    -- === TRIGGER SECTION ===
    local triggerSection = CreateFrame("Frame", nil, card)
    triggerSection:SetPoint("TOPLEFT", card, "TOPLEFT", RULES_CARD_PADDING, -40)
    triggerSection:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RULES_CARD_PADDING, -40)
    triggerSection:SetHeight(90)

    local triggerBg = triggerSection:CreateTexture(nil, "BACKGROUND")
    triggerBg:SetAllPoints()
    triggerBg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    triggerSection._bg = triggerBg
    card._triggerSection = triggerSection

    -- TRIGGER header
    local triggerHeader = triggerSection:CreateFontString(nil, "OVERLAY")
    triggerHeader:SetFont(headerFont, 14, "")
    triggerHeader:SetPoint("TOPLEFT", triggerSection, "TOPLEFT", 8, -8)
    triggerHeader:SetText("TRIGGER")
    triggerHeader:SetTextColor(ar, ag, ab, 1)

    -- Type label
    local typeLabel = triggerSection:CreateFontString(nil, "OVERLAY")
    typeLabel:SetFont(labelFont, 11, "")
    typeLabel:SetPoint("TOPLEFT", triggerHeader, "BOTTOMLEFT", 0, -12)
    typeLabel:SetText("Type:")
    typeLabel:SetTextColor(ar, ag, ab, 1)

    -- Type selector (using Controls:CreateSelector directly for compact layout)
    local triggerType = rule.trigger and rule.trigger.type or "specialization"
    local typeSelector = Controls:CreateDropdown({
        parent = triggerSection,
        values = {
            specialization = "Specialization",
            playerLevel = "Player Level",
        },
        order = { "specialization", "playerLevel" },
        get = function() return triggerType end,
        set = function(val)
            if addon.Rules and addon.Rules.SetRuleTriggerType then
                addon.Rules:SetRuleTriggerType(rule.id, val)
            end
            if refreshCallback then refreshCallback() end
        end,
        placeholder = "Select...",
        width = 140,
    })
    typeSelector:SetPoint("LEFT", typeLabel, "RIGHT", 8, 0)
    card._typeSelector = typeSelector

    -- Trigger type-specific content
    if triggerType == "specialization" then
        -- Specs label
        local specsLabel = triggerSection:CreateFontString(nil, "OVERLAY")
        specsLabel:SetFont(labelFont, 11, "")
        specsLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -16)
        specsLabel:SetText("Specs:")
        specsLabel:SetTextColor(ar, ag, ab, 1)

        -- Add/Remove button
        local addSpecBtn = Controls:CreateButton({
            parent = triggerSection,
            text = "Add/Remove",
            width = 100,
            height = 22,
            borderWidth = 1,
            borderAlpha = 0.6,
            onClick = function(self)
                -- Open spec picker
                ShowSpecPicker(self, rule, refreshCallback)
            end,
        })
        addSpecBtn:SetPoint("LEFT", specsLabel, "RIGHT", 8, 0)
        card._addSpecBtn = addSpecBtn

        -- Spec badges in edit mode
        local specIds = rule.trigger and rule.trigger.specIds or {}
        local editSpecContainer = CreateFrame("Frame", nil, triggerSection)
        editSpecContainer:SetPoint("LEFT", addSpecBtn, "RIGHT", 12, 0)
        editSpecContainer:SetSize(280, 20)
        card._editSpecContainer = editSpecContainer
        card._editSpecBadges = {}

        local xOffset = 0
        local visibleCount = math.min(#specIds, RULES_MAX_DISPLAY_BADGES)
        for i = 1, visibleCount do
            local specID = specIds[i]
            local badge = CreateRulesSpecBadge(editSpecContainer, specID)
            if badge then
                badge:SetPoint("LEFT", editSpecContainer, "LEFT", xOffset, 0)
                badge:Show()
                table.insert(card._editSpecBadges, badge)
                xOffset = xOffset + badge:GetWidth() + RULES_SPEC_BADGE_GAP
            end
        end

        if #specIds - visibleCount > 0 then
            local overflow = triggerSection:CreateFontString(nil, "OVERLAY")
            overflow:SetFont(fontPath, 10, "")
            overflow:SetPoint("LEFT", editSpecContainer, "LEFT", xOffset, 0)
            overflow:SetText(string.format("+%d more", #specIds - visibleCount))
            overflow:SetTextColor(dimR, dimG, dimB, 1)
        end

    elseif triggerType == "playerLevel" then
        -- Level label
        local levelLabel = triggerSection:CreateFontString(nil, "OVERLAY")
        levelLabel:SetFont(labelFont, 11, "")
        levelLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -16)
        levelLabel:SetText("Level:")
        levelLabel:SetTextColor(ar, ag, ab, 1)

        -- Level input
        local levelInput = CreateFrame("EditBox", nil, triggerSection, "InputBoxTemplate")
        levelInput:SetSize(60, 22)
        levelInput:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
        levelInput:SetAutoFocus(false)
        levelInput:SetNumeric(true)
        levelInput:SetMaxLetters(3)
        local currentLevel = rule.trigger and rule.trigger.level
        levelInput:SetText(currentLevel and tostring(currentLevel) or "")
        levelInput:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText())
            if addon.Rules and addon.Rules.SetRuleTriggerLevel then
                addon.Rules:SetRuleTriggerLevel(rule.id, val)
            end
            self:ClearFocus()
            if refreshCallback then refreshCallback() end
        end)
        levelInput:SetScript("OnEscapePressed", function(self)
            self:SetText(currentLevel and tostring(currentLevel) or "")
            self:ClearFocus()
        end)
        card._levelInput = levelInput
    end

    -- === TARGET SECTION ===
    local targetSection = CreateFrame("Frame", nil, card)
    targetSection:SetPoint("TOPLEFT", triggerSection, "BOTTOMLEFT", 0, -8)
    targetSection:SetPoint("TOPRIGHT", triggerSection, "BOTTOMRIGHT", 0, -8)
    targetSection:SetHeight(90)

    local targetBg = targetSection:CreateTexture(nil, "BACKGROUND")
    targetBg:SetAllPoints()
    targetBg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    card._targetSection = targetSection

    -- TARGET header
    local targetHeader = targetSection:CreateFontString(nil, "OVERLAY")
    targetHeader:SetFont(headerFont, 14, "")
    targetHeader:SetPoint("TOPLEFT", targetSection, "TOPLEFT", 8, -8)
    targetHeader:SetText("TARGET")
    targetHeader:SetTextColor(ar, ag, ab, 1)

    -- Target description
    local targetDesc = targetSection:CreateFontString(nil, "OVERLAY")
    targetDesc:SetFont(fontPath, 10, "")
    targetDesc:SetPoint("TOPLEFT", targetHeader, "BOTTOMLEFT", 0, -8)
    targetDesc:SetText("Select the setting you want this rule to modify:")
    targetDesc:SetTextColor(dimR, dimG, dimB, 1)

    -- Breadcrumb dropdowns
    local actionId = rule.action and rule.action.id
    local currentPath = {}
    if actionId and addon.Rules then
        currentPath = addon.Rules:GetActionPath(actionId) or {}
    end

    -- Initialize breadcrumb state
    local breadcrumbState = state.breadcrumbs[rule.id]
    if not breadcrumbState then
        if #currentPath > 0 then
            breadcrumbState = { currentPath[1], currentPath[2], currentPath[3], currentPath[4] }
        else
            breadcrumbState = {}
        end
        state.breadcrumbs[rule.id] = breadcrumbState
    end

    -- Helper to get options for a level
    local function getOptionsForLevel(level)
        local pathPrefix = {}
        for i = 1, level - 1 do
            if breadcrumbState[i] then
                table.insert(pathPrefix, breadcrumbState[i])
            end
        end
        local rawOptions = addon.Rules and addon.Rules:GetActionsAtPath(pathPrefix) or {}
        local opts = {}
        local order = {}
        for _, opt in ipairs(rawOptions) do
            opts[opt.text] = opt.text
            table.insert(order, opt.text)
        end
        return opts, order
    end

    -- Helper to handle breadcrumb change
    local function onBreadcrumbChange(level, selectedText)
        breadcrumbState[level] = selectedText
        for i = level + 1, 4 do
            breadcrumbState[i] = nil
        end
        state.breadcrumbs[rule.id] = breadcrumbState

        local fullPath = {}
        for i = 1, 4 do
            if breadcrumbState[i] then
                table.insert(fullPath, breadcrumbState[i])
            else
                break
            end
        end

        local newActionId = addon.Rules and addon.Rules:GetActionIdForPath(fullPath)
        if newActionId then
            state.breadcrumbs[rule.id] = nil
            if addon.Rules and addon.Rules.SetRuleAction then
                addon.Rules:SetRuleAction(rule.id, newActionId)
            end
        else
            rule.action = rule.action or {}
            rule.action.id = nil
        end

        if refreshCallback then refreshCallback() end
    end

    -- Create breadcrumb dropdowns
    local dropdownWidth = 130
    local dropdownGap = 8
    local xPos = 8
    card._breadcrumbs = {}

    for level = 1, 4 do
        local shouldShow = (level == 1) or (breadcrumbState[level - 1] ~= nil)
        if shouldShow then
            local opts, order = getOptionsForLevel(level)
            if #order > 0 or breadcrumbState[level] then
                local dropdown = Controls:CreateDropdown({
                    parent = targetSection,
                    values = opts,
                    order = order,
                    get = function() return breadcrumbState[level] end,
                    set = function(val)
                        onBreadcrumbChange(level, val)
                    end,
                    placeholder = "Select...",
                    width = dropdownWidth,
                    height = RULES_BREADCRUMB_HEIGHT,  -- Taller to accommodate wrapped text
                })
                dropdown:SetPoint("TOPLEFT", targetSection, "TOPLEFT", xPos, -50)
                table.insert(card._breadcrumbs, dropdown)
                xPos = xPos + dropdownWidth + dropdownGap

                -- Separator
                if level < 4 and breadcrumbState[level] then
                    local sep = targetSection:CreateFontString(nil, "OVERLAY")
                    sep:SetFont(labelFont, 14, "")
                    sep:SetPoint("LEFT", dropdown, "RIGHT", 4, 0)
                    sep:SetText(">")
                    sep:SetTextColor(ar, ag, ab, 1)
                    xPos = xPos + 20
                end
            end
        end
    end

    -- === ACTION SECTION ===
    local actionSection = CreateFrame("Frame", nil, card)
    actionSection:SetPoint("TOPLEFT", targetSection, "BOTTOMLEFT", 0, -8)
    actionSection:SetPoint("TOPRIGHT", targetSection, "BOTTOMRIGHT", 0, -8)
    actionSection:SetHeight(80)

    local actionBg = actionSection:CreateTexture(nil, "BACKGROUND")
    actionBg:SetAllPoints()
    actionBg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    card._actionSection = actionSection

    -- ACTION header
    local actionHeader = actionSection:CreateFontString(nil, "OVERLAY")
    actionHeader:SetFont(headerFont, 14, "")
    actionHeader:SetPoint("TOPLEFT", actionSection, "TOPLEFT", 8, -8)
    actionHeader:SetText("ACTION")
    actionHeader:SetTextColor(ar, ag, ab, 1)

    -- Get action metadata
    local actionId = rule.action and rule.action.id
    local actionMeta = actionId and addon.Rules and addon.Rules:GetActionMetadata(actionId)
    local widget = actionMeta and actionMeta.widget or "checkbox"
    local currentValue = rule.action and rule.action.value

    -- Render appropriate control
    if actionId and actionMeta then
        if widget == "checkbox" then
            -- TUI Toggle-style control
            local toggle = Controls:CreateToggle({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Enabled",
                get = function() return currentValue and true or false end,
                set = function(val)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, val)
                    end
                end,
            })
            toggle:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            toggle:SetWidth(300)
            card._actionToggle = toggle

        elseif widget == "slider" then
            local uiMeta = actionMeta.uiMeta or {}
            local slider = Controls:CreateSlider({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Value",
                min = uiMeta.min or 0,
                max = uiMeta.max or 100,
                step = uiMeta.step or 1,
                get = function() return tonumber(currentValue) or uiMeta.min or 0 end,
                set = function(val)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, val)
                    end
                end,
                width = 200,
            })
            slider:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            slider:SetWidth(400)
            card._actionSlider = slider

        elseif widget == "dropdown" then
            local uiMeta = actionMeta.uiMeta or {}
            local values = uiMeta.values or {}
            local selector = Controls:CreateSelector({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Option",
                values = values,
                get = function() return currentValue end,
                set = function(val)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, val)
                    end
                end,
                width = 200,
            })
            selector:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            selector:SetWidth(400)
            card._actionSelector = selector

        elseif widget == "color" then
            local colorPicker = Controls:CreateColorPicker({
                parent = actionSection,
                label = actionMeta.path and actionMeta.path[#actionMeta.path] or "Color",
                get = function()
                    local c = currentValue
                    if type(c) == "table" then
                        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                set = function(r, g, b, a)
                    if addon.Rules and addon.Rules.SetRuleActionValue then
                        addon.Rules:SetRuleActionValue(rule.id, { r, g, b, a })
                    end
                end,
                hasAlpha = true,
            })
            colorPicker:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
            colorPicker:SetWidth(400)
            card._actionColor = colorPicker
        end
    else
        -- No action selected placeholder
        local placeholder = actionSection:CreateFontString(nil, "OVERLAY")
        placeholder:SetFont(fontPath, 11, "")
        placeholder:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -12)
        placeholder:SetText("Select a target setting above to configure the action value.")
        placeholder:SetTextColor(dimR, dimG, dimB, 1)
    end
end

--------------------------------------------------------------------------------
-- Rules: Divider between cards
--------------------------------------------------------------------------------

local function CreateRulesDivider(parent)
    local ar, ag, ab = Theme:GetAccentColor()

    local divider = CreateFrame("Frame", nil, parent)
    divider:SetHeight(RULES_DIVIDER_HEIGHT)

    -- Left line
    local leftLine = divider:CreateTexture(nil, "ARTWORK")
    leftLine:SetHeight(1)
    leftLine:SetPoint("LEFT", divider, "LEFT", RULES_CARD_LEFT_MARGIN, 0)
    leftLine:SetPoint("RIGHT", divider, "CENTER", -16, 0)
    leftLine:SetColorTexture(ar, ag, ab, 0.3)
    divider._leftLine = leftLine

    -- Right line
    local rightLine = divider:CreateTexture(nil, "ARTWORK")
    rightLine:SetHeight(1)
    rightLine:SetPoint("LEFT", divider, "CENTER", 16, 0)
    rightLine:SetPoint("RIGHT", divider, "RIGHT", -8, 0)
    rightLine:SetColorTexture(ar, ag, ab, 0.3)
    divider._rightLine = rightLine

    -- Center diamond ornament
    local ornament = divider:CreateTexture(nil, "OVERLAY")
    ornament:SetSize(10, 10)
    ornament:SetPoint("CENTER", divider, "CENTER", 0, 0)
    ornament:SetTexture("Interface\\Buttons\\WHITE8x8")
    ornament:SetVertexColor(ar, ag, ab, 0.6)
    ornament:SetRotation(math.rad(45))
    divider._ornament = ornament

    -- Theme subscription
    local subscribeKey = "RulesDivider_" .. tostring(divider)
    Theme:Subscribe(subscribeKey, function(r, g, b)
        leftLine:SetColorTexture(r, g, b, 0.3)
        rightLine:SetColorTexture(r, g, b, 0.3)
        ornament:SetVertexColor(r, g, b, 0.6)
    end)
    divider._subscribeKey = subscribeKey

    divider.Cleanup = function(self)
        if self._subscribeKey then
            Theme:Unsubscribe(self._subscribeKey)
        end
    end

    return divider
end

--------------------------------------------------------------------------------
-- Rules: Main renderer
--------------------------------------------------------------------------------

function UIPanel:RenderProfilesRules(scrollContent)
    self:ClearContent()

    -- Clean up previous Rules UI controls
    local state = self._rulesState
    if state.currentControls then
        for _, control in ipairs(state.currentControls) do
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
    end
    state.currentControls = {}

    local ar, ag, ab = Theme:GetAccentColor()
    local fontPath = Theme:GetFont("VALUE")

    -- Refresh callback
    local function refreshRules()
        self:RenderProfilesRules(scrollContent)
    end

    local yOffset = -8

    -- Add Rule button
    local addBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Add Rule",
        width = 200,
        height = 36,
        onClick = function()
            if addon.Rules and addon.Rules.CreateRule then
                local newRule = addon.Rules:CreateRule()
                if newRule and newRule.id then
                    state.editingRules[newRule.id] = true
                end
                refreshRules()
            end
        end,
    })
    addBtn:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    table.insert(state.currentControls, addBtn)
    yOffset = yOffset - RULES_ADD_BUTTON_HEIGHT

    -- Get rules
    local rules = addon.Rules and addon.Rules:GetRules() or {}

    if #rules == 0 then
        -- Empty state
        local emptyFrame = CreateFrame("Frame", nil, scrollContent)
        emptyFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", RULES_CARD_LEFT_MARGIN, yOffset - 20)
        emptyFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -8, yOffset - 20)
        emptyFrame:SetHeight(40)

        local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
        emptyText:SetFont(fontPath, 12, "")
        emptyText:SetAllPoints()
        emptyText:SetText("No rules configured. Click 'Add Rule' to create your first automation.")
        emptyText:SetTextColor(0.6, 0.6, 0.6, 1)
        emptyText:SetJustifyH("CENTER")

        table.insert(state.currentControls, emptyFrame)
        yOffset = yOffset - RULES_EMPTY_STATE_HEIGHT
    else
        -- Render each rule
        for index, rule in ipairs(rules) do
            rule.displayIndex = index

            local card = CreateRulesCard(scrollContent, rule, refreshRules)
            card:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", RULES_CARD_LEFT_MARGIN, yOffset)
            card:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -8, yOffset)
            yOffset = yOffset - card:GetHeight()

            -- Track for cleanup
            table.insert(state.currentControls, card)

            -- Divider between cards (not after last)
            if index < #rules then
                local divider = CreateRulesDivider(scrollContent)
                divider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
                divider:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, yOffset)
                yOffset = yOffset - RULES_DIVIDER_HEIGHT
                table.insert(state.currentControls, divider)
            end
        end
    end

    -- Set scroll content height
    local totalHeight = math.abs(yOffset) + 20
    scrollContent:SetHeight(totalHeight)
end

--------------------------------------------------------------------------------
-- Profiles > Manage Profiles Renderer
--------------------------------------------------------------------------------

-- Profiles Manage state (similar to _rulesState for Rules)
UIPanel._profilesManageState = {
    currentControls = {},
}

function UIPanel:RenderProfilesManage(scrollContent)
    self:ClearContent()

    -- Clean up previous Profiles Manage controls
    local state = self._profilesManageState
    if state.currentControls then
        for _, control in ipairs(state.currentControls) do
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
    end
    state.currentControls = {}

    local ar, ag, ab = Theme:GetAccentColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local fontPath = Theme:GetFont("VALUE")
    local fontPathMed = Theme:GetFont("LABEL")

    -- Constants for this page
    local DROPDOWN_SCALE = 1.2
    local BUTTON_WIDTH = 140
    local BUTTON_HEIGHT = 32
    local BUTTON_GAP = 16
    local SPEC_ICON_SIZE = 28
    local CONTENT_PADDING = 8

    -- Refresh callback
    local function refreshProfilesManage()
        self:RenderProfilesManage(scrollContent)
    end

    -- Helper: Get active profile key
    local function getActiveProfileKey()
        if addon.Profiles and addon.Profiles.GetActiveProfile then
            return addon.Profiles:GetActiveProfile()
        end
        if addon.db and addon.db.GetCurrentProfile then
            return addon.db:GetCurrentProfile()
        end
        return nil
    end

    -- Helper: Build layout menu entries
    local function buildLayoutEntries()
        if not addon.Profiles or not addon.Profiles.GetLayoutMenuEntries then
            return {}
        end
        return addon.Profiles:GetLayoutMenuEntries()
    end

    -- Track y offset for manual layout
    local yOffset = -CONTENT_PADDING

    ---------------------------------------------------------------------------
    -- Info Text Section
    ---------------------------------------------------------------------------
    local infoFrame = CreateFrame("Frame", nil, scrollContent)
    infoFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 8, yOffset)
    infoFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING - 8, yOffset)

    local infoText = infoFrame:CreateFontString(nil, "OVERLAY")
    infoText:SetFont(fontPath, 13, "")
    infoText:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
    infoText:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", 0, 0)
    infoText:SetText("ScooterMod profiles stay synchronized with Edit Mode layouts. Switch layouts here or via Edit Mode and ScooterMod will keep them in sync.")
    infoText:SetTextColor(dimR, dimG, dimB, 1)
    infoText:SetJustifyH("LEFT")
    infoText:SetWordWrap(true)

    -- Calculate text height after layout
    C_Timer.After(0, function()
        if infoText and infoFrame then
            local h = infoText:GetStringHeight() or 40
            infoFrame:SetHeight(h + 8)
        end
    end)
    infoFrame:SetHeight(50)
    table.insert(state.currentControls, infoFrame)
    yOffset = yOffset - 60

    ---------------------------------------------------------------------------
    -- Active Layout Dropdown (centered, larger)
    ---------------------------------------------------------------------------
    local activeLayoutLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    activeLayoutLabel:SetFont(fontPathMed, 18, "")
    activeLayoutLabel:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    activeLayoutLabel:SetText("Active Layout")
    activeLayoutLabel:SetTextColor(ar, ag, ab, 1)
    table.insert(state.currentControls, activeLayoutLabel)
    yOffset = yOffset - 24

    -- Build values and order for dropdown
    local entries = buildLayoutEntries()
    local dropdownValues = {}
    local dropdownOrder = {}
    for _, entry in ipairs(entries) do
        dropdownValues[entry.key] = entry.text
        table.insert(dropdownOrder, entry.key)
    end

    local activeDropdown = Controls:CreateDropdown({
        parent = scrollContent,
        values = dropdownValues,
        order = dropdownOrder,
        get = function()
            return getActiveProfileKey()
        end,
        set = function(key)
            local entry = nil
            for _, e in ipairs(entries) do
                if e.key == key then
                    entry = e
                    break
                end
            end
            if entry and entry.preset then
                -- Preset selected - need to clone
                local currentKey = getActiveProfileKey()
                addon.Profiles:PromptClonePreset(key, nil, entry.text, currentKey)
                return
            end
            if addon.Profiles and addon.Profiles.SwitchToProfile then
                addon.Profiles:SwitchToProfile(key, { reason = "ManageProfilesDropdown" })
            end
            -- Refresh after switch
            C_Timer.After(0.1, refreshProfilesManage)
        end,
        placeholder = "Select a layout...",
        width = 240,
        height = 28,
        fontSize = 13,
    })
    activeDropdown:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    activeDropdown:SetScale(DROPDOWN_SCALE)
    table.insert(state.currentControls, activeDropdown)
    yOffset = yOffset - (34 * DROPDOWN_SCALE) - 28

    -- Store reference for button state updates
    state.activeDropdown = activeDropdown

    ---------------------------------------------------------------------------
    -- Action Buttons Row (Create, Rename, Copy)
    ---------------------------------------------------------------------------
    local totalButtonsWidth = (BUTTON_WIDTH * 3) + (BUTTON_GAP * 2)
    local startX = -totalButtonsWidth / 2

    -- Update button states helper
    local function updateButtonStates()
        local current = getActiveProfileKey()
        local isPreset = current and addon.Profiles and addon.Profiles:IsPreset(current)
        if state.renameBtn then
            state.renameBtn:SetEnabled(current and not isPreset)
        end
        if state.copyBtn then
            state.copyBtn:SetEnabled(not not current)
        end
    end

    -- Create button
    local createBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Create",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            addon.Profiles:PromptCreateLayout(nil)
            C_Timer.After(0.1, refreshProfilesManage)
        end,
    })
    createBtn:SetPoint("TOP", scrollContent, "TOP", startX + (BUTTON_WIDTH / 2), yOffset)
    table.insert(state.currentControls, createBtn)
    state.createBtn = createBtn

    -- Rename button
    local renameBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Rename",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            local current = getActiveProfileKey()
            if current then
                addon.Profiles:PromptRenameLayout(current, nil)
                C_Timer.After(0.1, refreshProfilesManage)
            end
        end,
    })
    renameBtn:SetPoint("LEFT", createBtn, "RIGHT", BUTTON_GAP, 0)
    table.insert(state.currentControls, renameBtn)
    state.renameBtn = renameBtn

    -- Copy button
    local copyBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Copy",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            local current = getActiveProfileKey()
            if not current then return end
            if addon.Profiles and addon.Profiles:IsPreset(current) then
                addon.Profiles:PromptClonePreset(current, nil, addon.Profiles:GetLayoutDisplayText(current), current)
            else
                addon.Profiles:PromptCopyLayout(current, nil)
            end
            C_Timer.After(0.1, refreshProfilesManage)
        end,
    })
    copyBtn:SetPoint("LEFT", renameBtn, "RIGHT", BUTTON_GAP, 0)
    table.insert(state.currentControls, copyBtn)
    state.copyBtn = copyBtn

    -- Update button states
    updateButtonStates()
    yOffset = yOffset - BUTTON_HEIGHT - 24

    ---------------------------------------------------------------------------
    -- Delete a Profile (Collapsible Section)
    ---------------------------------------------------------------------------
    local deleteSection = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = "Delete a Profile",
        componentId = "profilesManage",
        sectionKey = "deleteProfile",
        defaultExpanded = false,
        onToggle = function()
            C_Timer.After(0, refreshProfilesManage)
        end,
    })
    deleteSection:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    deleteSection:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    table.insert(state.currentControls, deleteSection)

    -- Build delete dropdown content
    local deleteContent = deleteSection:GetContentFrame()

    -- Get deletable profiles (exclude current and presets)
    local function getDeletableProfiles()
        local deletable = {}
        local currentProfile = getActiveProfileKey()
        for _, entry in ipairs(entries) do
            if entry.key ~= currentProfile and not entry.preset then
                table.insert(deletable, entry)
            end
        end
        return deletable
    end

    local deletable = getDeletableProfiles()
    local deleteValues = {}
    local deleteOrder = {}
    for _, entry in ipairs(deletable) do
        deleteValues[entry.key] = entry.text
        table.insert(deleteOrder, entry.key)
    end

    local deleteDropdown = Controls:CreateDropdown({
        parent = deleteContent,
        values = deleteValues,
        order = deleteOrder,
        set = function(key)
            -- Confirm deletion
            addon.Profiles:ConfirmDeleteLayout(key, nil)
            C_Timer.After(0.2, refreshProfilesManage)
        end,
        placeholder = #deletable > 0 and "Select a profile to delete..." or "No deletable profiles",
        width = 280,
        height = 26,
        fontSize = 12,
    })
    deleteDropdown:SetPoint("TOP", deleteContent, "TOP", 0, -12)
    table.insert(state.currentControls, deleteDropdown)

    -- Set content height
    deleteSection:SetContentHeight(60)

    -- Get section height and update offset
    local deleteSectionHeight = deleteSection:GetHeight()
    yOffset = yOffset - deleteSectionHeight - 16

    ---------------------------------------------------------------------------
    -- Spec Profiles (Collapsible Section)
    ---------------------------------------------------------------------------
    local specSection = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = "Spec Profiles",
        componentId = "profilesManage",
        sectionKey = "specProfiles",
        defaultExpanded = false,
        onToggle = function()
            C_Timer.After(0, refreshProfilesManage)
        end,
    })
    specSection:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    specSection:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    table.insert(state.currentControls, specSection)

    local specContent = specSection:GetContentFrame()

    -- Enable Spec Profiles toggle
    local specEnabled = addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled() or false

    local enableToggle = Controls:CreateToggle({
        parent = specContent,
        label = "Enable Spec Profiles",
        description = "Automatically switch profiles when you change specializations.",
        get = function()
            return addon.Profiles and addon.Profiles:IsSpecProfilesEnabled() or false
        end,
        set = function(value)
            local wasEnabled = addon.Profiles and addon.Profiles:IsSpecProfilesEnabled()
            if addon.Profiles and addon.Profiles.SetSpecProfilesEnabled then
                addon.Profiles:SetSpecProfilesEnabled(value)
            end
            -- Seed assignments when first enabling
            if value and not wasEnabled then
                local current = getActiveProfileKey()
                if current and addon.Profiles and addon.Profiles.SetSpecAssignment then
                    local specs = (addon.Profiles.GetSpecOptions and addon.Profiles:GetSpecOptions()) or {}
                    for _, s in ipairs(specs) do
                        if s and s.specID then
                            addon.Profiles:SetSpecAssignment(s.specID, current)
                        end
                    end
                end
            end
            if value and addon.Profiles and addon.Profiles.OnPlayerSpecChanged then
                addon.Profiles:OnPlayerSpecChanged()
            end
            -- Refresh to show/hide spec rows
            C_Timer.After(0.05, refreshProfilesManage)
        end,
    })
    enableToggle:SetPoint("TOPLEFT", specContent, "TOPLEFT", 0, 0)
    enableToggle:SetPoint("TOPRIGHT", specContent, "TOPRIGHT", 0, 0)
    table.insert(state.currentControls, enableToggle)

    local specContentHeight = enableToggle:GetHeight() + 8

    -- Spec rows (only if enabled)
    if specEnabled then
        local specOptions = (addon.Profiles and addon.Profiles.GetSpecOptions and addon.Profiles:GetSpecOptions()) or {}
        local specYOffset = -enableToggle:GetHeight() - 16

        for _, spec in ipairs(specOptions) do
            -- Spec row frame
            local specRow = CreateFrame("Frame", nil, specContent)
            specRow:SetPoint("TOPLEFT", specContent, "TOPLEFT", 8, specYOffset)
            specRow:SetPoint("TOPRIGHT", specContent, "TOPRIGHT", -8, specYOffset)
            specRow:SetHeight(40)

            -- Spec icon
            local specIcon = specRow:CreateTexture(nil, "ARTWORK")
            specIcon:SetSize(SPEC_ICON_SIZE, SPEC_ICON_SIZE)
            specIcon:SetPoint("LEFT", specRow, "LEFT", 0, 0)
            if spec.icon then
                specIcon:SetTexture(spec.icon)
            end

            -- Spec name
            local specName = specRow:CreateFontString(nil, "OVERLAY")
            specName:SetFont(fontPath, 13, "")
            specName:SetPoint("LEFT", specIcon, "RIGHT", 10, 0)
            specName:SetText(spec.name or ("Spec " .. tostring(spec.specIndex)))
            specName:SetTextColor(1, 1, 1, 1)
            specName:SetWidth(120)
            specName:SetJustifyH("LEFT")

            -- Spec dropdown (profile assignment)
            local assigned = addon.Profiles and addon.Profiles.GetSpecAssignment and addon.Profiles:GetSpecAssignment(spec.specID) or nil

            local specDropdown = Controls:CreateDropdown({
                parent = specRow,
                values = dropdownValues,
                order = dropdownOrder,
                get = function()
                    return addon.Profiles and addon.Profiles:GetSpecAssignment(spec.specID) or getActiveProfileKey()
                end,
                set = function(key)
                    if addon.Profiles and addon.Profiles.SetSpecAssignment then
                        addon.Profiles:SetSpecAssignment(spec.specID, key)
                    end
                    -- Trigger spec change if applicable
                    if addon.Profiles and addon.Profiles:IsSpecProfilesEnabled() then
                        if addon.Profiles.OnPlayerSpecChanged then
                            addon.Profiles:OnPlayerSpecChanged()
                        end
                    end
                end,
                placeholder = "Select a layout...",
                width = 200,
                height = 24,
                fontSize = 11,
            })
            specDropdown:SetPoint("LEFT", specName, "RIGHT", 16, 0)

            table.insert(state.currentControls, specRow)
            table.insert(state.currentControls, specDropdown)

            specYOffset = specYOffset - 44
            specContentHeight = specContentHeight + 44
        end
    end

    -- Set content height for spec section
    specSection:SetContentHeight(specContentHeight + 16)

    local specSectionHeight = specSection:GetHeight()
    yOffset = yOffset - specSectionHeight - 24

    ---------------------------------------------------------------------------
    -- Warning Notice (bottom)
    ---------------------------------------------------------------------------
    local warningFrame = CreateFrame("Frame", nil, scrollContent)
    warningFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset)
    warningFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset)
    warningFrame:SetHeight(80)

    -- Divider line above warning
    local divider = warningFrame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", warningFrame, "TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", warningFrame, "TOPRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(ar, ag, ab, 0.3)

    -- Warning text
    local warningText = warningFrame:CreateFontString(nil, "OVERLAY")
    warningText:SetFont(fontPath, 12, "")
    warningText:SetPoint("TOPLEFT", warningFrame, "TOPLEFT", 0, -12)
    warningText:SetPoint("TOPRIGHT", warningFrame, "TOPRIGHT", 0, -12)
    warningText:SetText("Creating, deleting, or switching between profiles will require a |cFFFFD100RELOAD|r.\n\nScooterMod only layers customizations on top of the Blizzard UI and a reload is needed to obtain current defaults for fields which you have customized in one profile but not another.")
    warningText:SetTextColor(1.0, 0.82, 0.0, 1)
    warningText:SetJustifyH("CENTER")
    warningText:SetWordWrap(true)

    table.insert(state.currentControls, warningFrame)
    yOffset = yOffset - 100

    ---------------------------------------------------------------------------
    -- Set scroll content height
    ---------------------------------------------------------------------------
    local totalHeight = math.abs(yOffset) + 20
    scrollContent:SetHeight(totalHeight)
end

--------------------------------------------------------------------------------
-- Profiles > Presets Renderer
--------------------------------------------------------------------------------

-- Presets state
UIPanel._presetsState = {
    currentControls = {},
    selectedIndex = 1,
}

function UIPanel:RenderProfilesPresets(scrollContent)
    self:ClearContent()

    -- Clean up previous controls
    local state = self._presetsState
    if state.currentControls then
        for _, control in ipairs(state.currentControls) do
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
    end
    state.currentControls = {}

    local ar, ag, ab = Theme:GetAccentColor()
    local dimR, dimG, dimB = Theme:GetDimTextColor()
    local fontPath = Theme:GetFont("VALUE")
    local fontPathMed = Theme:GetFont("LABEL")
    local fontPathBold = Theme:GetFont("HEADER")

    -- Constants
    local CONTENT_PADDING = 8
    local HERO_WIDTH = 560
    local HERO_HEIGHT = 315
    local COLUMN_WIDTH = 240
    local COLUMN_OUTER_MARGIN = 40
    local BUTTON_WIDTH = 280
    local BUTTON_HEIGHT = 36

    -- Get preset list
    local function getPresetList()
        if not addon.Presets or not addon.Presets.GetList then
            return {}
        end
        return addon.Presets:GetList()
    end

    local presets = getPresetList()

    -- Clamp selected index
    if state.selectedIndex < 1 then state.selectedIndex = 1 end
    if state.selectedIndex > #presets then state.selectedIndex = math.max(1, #presets) end

    -- Refresh callback
    local function refreshPresets()
        self:RenderProfilesPresets(scrollContent)
    end

    local yOffset = -CONTENT_PADDING

    ---------------------------------------------------------------------------
    -- Empty State
    ---------------------------------------------------------------------------
    if #presets == 0 then
        local emptyFrame = CreateFrame("Frame", nil, scrollContent)
        emptyFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, yOffset - 40)
        emptyFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, yOffset - 40)
        emptyFrame:SetHeight(100)

        -- Terminal-style empty message
        local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
        emptyText:SetFont(fontPath, 14, "")
        emptyText:SetPoint("CENTER", emptyFrame, "CENTER", 0, 0)
        emptyText:SetText("[ No presets available ]\n\nPreset collections are coming soon.\nFor now, use Edit Mode to swap between\nBlizzard's Modern and Classic presets.")
        emptyText:SetTextColor(dimR, dimG, dimB, 1)
        emptyText:SetJustifyH("CENTER")

        table.insert(state.currentControls, emptyFrame)
        scrollContent:SetHeight(200)
        return
    end

    ---------------------------------------------------------------------------
    -- Preset Selector (horizontal: label on left, dropdown on right)
    ---------------------------------------------------------------------------
    local selectorRow = CreateFrame("Frame", nil, scrollContent)
    selectorRow:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    selectorRow:SetSize(400, 32)
    table.insert(state.currentControls, selectorRow)

    local selectorLabel = selectorRow:CreateFontString(nil, "OVERLAY")
    selectorLabel:SetFont(fontPathMed, 14, "")
    selectorLabel:SetPoint("LEFT", selectorRow, "LEFT", 0, 0)
    selectorLabel:SetText("Select a preset:")
    selectorLabel:SetTextColor(ar, ag, ab, 1)

    -- Build dropdown values
    local dropdownValues = {}
    local dropdownOrder = {}
    for i, preset in ipairs(presets) do
        local key = tostring(i)
        dropdownValues[key] = preset.name or preset.id or ("Preset " .. i)
        table.insert(dropdownOrder, key)
    end

    local presetDropdown = Controls:CreateDropdown({
        parent = selectorRow,
        values = dropdownValues,
        order = dropdownOrder,
        get = function()
            return tostring(state.selectedIndex)
        end,
        set = function(key)
            state.selectedIndex = tonumber(key) or 1
            refreshPresets()
        end,
        placeholder = "Select a preset...",
        width = 240,
        height = 26,
        fontSize = 12,
    })
    presetDropdown:SetPoint("LEFT", selectorLabel, "RIGHT", 12, 0)
    table.insert(state.currentControls, presetDropdown)
    yOffset = yOffset - 40

    -- Get current preset
    local currentPreset = presets[state.selectedIndex]
    if not currentPreset then
        scrollContent:SetHeight(100)
        return
    end

    ---------------------------------------------------------------------------
    -- Hero Image (with TUI-styled border)
    ---------------------------------------------------------------------------
    local heroContainer = CreateFrame("Frame", nil, scrollContent)
    heroContainer:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    heroContainer:SetSize(HERO_WIDTH + 6, HERO_HEIGHT + 6)

    -- Border around hero image
    local borderTop = heroContainer:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", heroContainer, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", heroContainer, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(2)
    borderTop:SetColorTexture(ar, ag, ab, 0.6)

    local borderBottom = heroContainer:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", heroContainer, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", heroContainer, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(2)
    borderBottom:SetColorTexture(ar, ag, ab, 0.6)

    local borderLeft = heroContainer:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", heroContainer, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", heroContainer, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(2)
    borderLeft:SetColorTexture(ar, ag, ab, 0.6)

    local borderRight = heroContainer:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", heroContainer, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", heroContainer, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(2)
    borderRight:SetColorTexture(ar, ag, ab, 0.6)

    -- Hero image texture
    local heroTexture = heroContainer:CreateTexture(nil, "ARTWORK")
    heroTexture:SetPoint("TOPLEFT", heroContainer, "TOPLEFT", 3, -3)
    heroTexture:SetPoint("BOTTOMRIGHT", heroContainer, "BOTTOMRIGHT", -3, 3)
    heroTexture:SetTexture(currentPreset.previewTexture or "Interface\\AddOns\\ScooterMod\\Scooter")

    -- "Coming Soon" overlay if applicable
    if currentPreset.comingSoon then
        local overlay = heroContainer:CreateTexture(nil, "OVERLAY")
        overlay:SetAllPoints(heroTexture)
        overlay:SetColorTexture(0, 0, 0, 0.7)

        local comingSoonText = heroContainer:CreateFontString(nil, "OVERLAY")
        comingSoonText:SetFont(fontPathBold, 24, "")
        comingSoonText:SetPoint("CENTER", heroContainer, "CENTER", 0, 0)
        comingSoonText:SetText("COMING SOON")
        comingSoonText:SetTextColor(ar, ag, ab, 1)
    end

    table.insert(state.currentControls, heroContainer)
    yOffset = yOffset - (HERO_HEIGHT + 6) - 20

    ---------------------------------------------------------------------------
    -- Two-Column Info Section
    ---------------------------------------------------------------------------
    local columnsContainer = CreateFrame("Frame", nil, scrollContent)
    columnsContainer:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    columnsContainer:SetSize(HERO_WIDTH + (COLUMN_OUTER_MARGIN * 2), 120)
    table.insert(state.currentControls, columnsContainer)

    -- Helper to format bullet list
    local function formatBulletList(items)
        if type(items) ~= "table" or #items == 0 then
            return "> (none specified)"
        end
        local lines = {}
        for _, item in ipairs(items) do
            table.insert(lines, "> " .. tostring(item))
        end
        return table.concat(lines, "\n")
    end

    -- Left column: "Designed for..."
    local leftHeader = columnsContainer:CreateFontString(nil, "OVERLAY")
    leftHeader:SetFont(fontPathMed, 14, "")
    leftHeader:SetPoint("TOPLEFT", columnsContainer, "TOPLEFT", COLUMN_OUTER_MARGIN, 0)
    leftHeader:SetText("Designed for...")
    leftHeader:SetTextColor(ar, ag, ab, 1)

    local leftList = columnsContainer:CreateFontString(nil, "OVERLAY")
    leftList:SetFont(fontPath, 12, "")
    leftList:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -8)
    leftList:SetWidth(COLUMN_WIDTH)
    leftList:SetJustifyH("LEFT")
    leftList:SetJustifyV("TOP")
    leftList:SetText(formatBulletList(currentPreset.designedFor))
    leftList:SetTextColor(1, 1, 1, 0.9)
    leftList:SetSpacing(4)

    -- Right column: "Author also recommends..."
    local rightHeader = columnsContainer:CreateFontString(nil, "OVERLAY")
    rightHeader:SetFont(fontPathMed, 14, "")
    rightHeader:SetPoint("TOPLEFT", columnsContainer, "TOP", 40, 0)
    rightHeader:SetText("Author also recommends...")
    rightHeader:SetTextColor(ar, ag, ab, 1)

    local rightList = columnsContainer:CreateFontString(nil, "OVERLAY")
    rightList:SetFont(fontPath, 12, "")
    rightList:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -8)
    rightList:SetWidth(COLUMN_WIDTH)
    rightList:SetJustifyH("LEFT")
    rightList:SetJustifyV("TOP")
    rightList:SetText(formatBulletList(currentPreset.recommends))
    rightList:SetTextColor(1, 1, 1, 0.9)
    rightList:SetSpacing(4)

    -- Calculate column height based on content
    C_Timer.After(0, function()
        if leftList and rightList and columnsContainer then
            local leftH = leftList:GetStringHeight() or 60
            local rightH = rightList:GetStringHeight() or 60
            local maxH = math.max(leftH, rightH) + 30
            columnsContainer:SetHeight(maxH)
        end
    end)

    yOffset = yOffset - 140

    ---------------------------------------------------------------------------
    -- Apply Button
    ---------------------------------------------------------------------------
    -- Determine if preset is actionable
    local canApplyPayload = addon.Presets and addon.Presets.IsPayloadReady and addon.Presets:IsPayloadReady(currentPreset)
    local depsOk, depsErr = true, nil
    if addon.Presets and addon.Presets.CheckDependencies then
        depsOk, depsErr = addon.Presets:CheckDependencies(currentPreset)
    end
    local actionable = canApplyPayload and depsOk and not currentPreset.comingSoon

    local disabledReason
    if not canApplyPayload then
        disabledReason = "Preset payload pending."
    elseif not depsOk then
        disabledReason = depsErr or "Dependencies not met."
    elseif currentPreset.comingSoon then
        disabledReason = "Preset not yet published."
    end

    local applyBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Apply this preset",
        width = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            if not actionable then return end
            -- Use the same apply logic as the old panel
            if addon.SettingsPanel and addon.SettingsPanel.ApplyPresetFromUI then
                addon.SettingsPanel:ApplyPresetFromUI(currentPreset)
            elseif addon.Presets and addon.Presets.ApplyPreset then
                -- Fallback: show the apply preset dialog directly
                if addon.Dialogs and addon.Dialogs.Show then
                    local presetName = currentPreset.name or currentPreset.id or "Preset"
                    addon.Dialogs:Show("SCOOTERMOD_APPLY_PRESET", {
                        formatArgs = { presetName },
                        editBoxText = presetName,
                        data = { preset = currentPreset },
                        onAccept = function(d, newName)
                            local ok, err = addon.Presets:ApplyPreset(d.preset.id, {
                                targetName = newName,
                            })
                            if not ok then
                                if err and addon.Print then addon:Print(err) end
                                return
                            end
                            addon:Print(("Preset '%s' was created. Reloading UI to activate it..."):format(presetName))
                            if type(ReloadUI) == "function" then
                                ReloadUI()
                            end
                        end,
                    })
                end
            end
        end,
    })
    applyBtn:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    applyBtn:SetEnabled(actionable)
    if not actionable then
        applyBtn:SetAlpha(0.5)
    end
    table.insert(state.currentControls, applyBtn)

    -- Tooltip for disabled state
    if not actionable and disabledReason then
        applyBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(disabledReason, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        applyBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    yOffset = yOffset - BUTTON_HEIGHT - 24

    ---------------------------------------------------------------------------
    -- Additional Info (optional notes)
    ---------------------------------------------------------------------------
    if currentPreset.notes and currentPreset.notes ~= "" then
        local notesFrame = CreateFrame("Frame", nil, scrollContent)
        notesFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 40, yOffset)
        notesFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING - 40, yOffset)
        notesFrame:SetHeight(60)

        local notesText = notesFrame:CreateFontString(nil, "OVERLAY")
        notesText:SetFont(fontPath, 11, "")
        notesText:SetAllPoints()
        notesText:SetText(currentPreset.notes)
        notesText:SetTextColor(dimR, dimG, dimB, 1)
        notesText:SetJustifyH("CENTER")
        notesText:SetWordWrap(true)

        table.insert(state.currentControls, notesFrame)
        yOffset = yOffset - 70
    end

    ---------------------------------------------------------------------------
    -- Set scroll content height
    ---------------------------------------------------------------------------
    local totalHeight = math.abs(yOffset) + 40
    scrollContent:SetHeight(totalHeight)
end

--------------------------------------------------------------------------------
-- Apply All: Fonts
--------------------------------------------------------------------------------
-- Simple layout: Info row explaining the operation, FontSelector dropdown, Apply button.
-- Uses TUI components for consistent styling.

function UIPanel:RenderApplyAllFonts(scrollContent)
    self:ClearContent()

    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    -- Track controls for cleanup
    self._applyAllFontsControls = self._applyAllFontsControls or {}
    for _, ctrl in ipairs(self._applyAllFontsControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    self._applyAllFontsControls = {}

    local ar, ag, ab = Theme:GetAccentColor()

    -- Container frame for layout
    local container = CreateFrame("Frame", nil, scrollContent)
    container:SetSize(500, 280)
    container:SetPoint("TOP", scrollContent, "TOP", 0, -60)
    container:SetPoint("LEFT", scrollContent, "LEFT", 40, 0)
    container:SetPoint("RIGHT", scrollContent, "RIGHT", -40, 0)
    table.insert(self._applyAllFontsControls, container)

    -- Info text (centered, dimmed)
    local info = container:CreateFontString(nil, "OVERLAY")
    info:SetFont(Theme:GetFont("LABEL"), 12, "")
    info:SetPoint("TOP", container, "TOP", 0, 0)
    info:SetWidth(420)
    info:SetJustifyH("CENTER")
    info:SetText("Select a font below, then click Apply. This will overwrite every ScooterMod font face and force a UI reload. Sizes, colors, offsets, and outlines remain unchanged.\n\nScrolling Combat Text fonts are excluded (require game restart).")
    info:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Font selector row (larger, minimal label)
    local fontSelector = Controls:CreateFontSelector({
        parent = container,
        label = "Font",
        get = function()
            return addon.ApplyAll and addon.ApplyAll:GetPendingFont() or "FRIZQT__"
        end,
        set = function(fontKey)
            if addon.ApplyAll and addon.ApplyAll.SetPendingFont then
                addon.ApplyAll:SetPendingFont(fontKey)
            end
        end,
        width = 320,
        labelFontSize = 16,
        selectorHeight = 35,
        rowHeight = 52,
    })
    if fontSelector then
        fontSelector:SetPoint("TOPLEFT", container, "TOPLEFT", 20, -120)
        fontSelector:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -120)
        table.insert(self._applyAllFontsControls, fontSelector)
    end

    -- Apply button
    local applyBtn = Controls:CreateButton({
        parent = container,
        text = "Apply",
        width = 160,
        height = 38,
        fontSize = 14,
        onClick = function()
            local pending = addon.ApplyAll and addon.ApplyAll:GetPendingFont()
            if not pending or pending == "" then
                if addon.Print then addon:Print("Select a font before applying.") end
                return
            end

            local displayName = addon.FontDisplayNames and addon.FontDisplayNames[pending] or pending

            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOTERMOD_APPLYALL_FONTS", {
                    formatArgs = { displayName },
                    data = { fontKey = pending },
                    onAccept = function(data)
                        if not data or not data.fontKey then return end
                        if not addon.ApplyAll or not addon.ApplyAll.ApplyFonts then return end

                        local result = addon.ApplyAll:ApplyFonts(data.fontKey, { updatePending = true })
                        if result and result.ok and result.changed and result.changed > 0 then
                            ReloadUI()
                        else
                            local reason = result and result.reason or "Unknown"
                            local friendly = {
                                noProfile = "Profile database unavailable.",
                                noSelection = "Select a font before applying.",
                                noChanges = "All entries already use that font.",
                            }
                            local detail = friendly[reason] or tostring(reason or "Unknown error.")
                            if addon.Print then
                                addon:Print("Apply All (Fonts) aborted: " .. detail)
                            end
                        end
                    end,
                })
            else
                if addon.Print then addon:Print("Dialog system unavailable.") end
            end
        end,
    })
    applyBtn:SetPoint("TOP", container, "TOP", 0, -200)
    table.insert(self._applyAllFontsControls, applyBtn)

    -- Set scroll content height
    scrollContent:SetHeight(400)
end

--------------------------------------------------------------------------------
-- Apply All: Bar Textures
--------------------------------------------------------------------------------
-- Simple layout: Info row explaining the operation, BarTextureSelector dropdown, Apply button.
-- Uses TUI components for consistent styling.

function UIPanel:RenderApplyAllTextures(scrollContent)
    self:ClearContent()

    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    -- Track controls for cleanup
    self._applyAllTexturesControls = self._applyAllTexturesControls or {}
    for _, ctrl in ipairs(self._applyAllTexturesControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    self._applyAllTexturesControls = {}

    local ar, ag, ab = Theme:GetAccentColor()

    -- Container frame for layout
    local container = CreateFrame("Frame", nil, scrollContent)
    container:SetSize(500, 260)
    container:SetPoint("TOP", scrollContent, "TOP", 0, -60)
    container:SetPoint("LEFT", scrollContent, "LEFT", 40, 0)
    container:SetPoint("RIGHT", scrollContent, "RIGHT", -40, 0)
    table.insert(self._applyAllTexturesControls, container)

    -- Info text (centered, dimmed)
    local info = container:CreateFontString(nil, "OVERLAY")
    info:SetFont(Theme:GetFont("LABEL"), 12, "")
    info:SetPoint("TOP", container, "TOP", 0, 0)
    info:SetWidth(420)
    info:SetJustifyH("CENTER")
    info:SetText("Select a texture below, then click Apply. This will overwrite every ScooterMod bar texture (foreground and background) and force a UI reload. Tint, opacity, and color settings remain unchanged.")
    info:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Bar texture selector row (larger, minimal label)
    local textureSelector = Controls:CreateBarTextureSelector({
        parent = container,
        label = "Texture",
        get = function()
            return addon.ApplyAll and addon.ApplyAll:GetPendingBarTexture() or "default"
        end,
        set = function(textureKey)
            if addon.ApplyAll and addon.ApplyAll.SetPendingBarTexture then
                addon.ApplyAll:SetPendingBarTexture(textureKey)
            end
        end,
        width = 320,
        labelFontSize = 16,
        selectorHeight = 35,
        rowHeight = 52,
    })
    if textureSelector then
        textureSelector:SetPoint("TOPLEFT", container, "TOPLEFT", 20, -100)
        textureSelector:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -100)
        table.insert(self._applyAllTexturesControls, textureSelector)
    end

    -- Apply button
    local applyBtn = Controls:CreateButton({
        parent = container,
        text = "Apply",
        width = 160,
        height = 38,
        fontSize = 14,
        onClick = function()
            local pending = addon.ApplyAll and addon.ApplyAll:GetPendingBarTexture()
            if not pending or pending == "" then
                if addon.Print then addon:Print("Select a texture before applying.") end
                return
            end

            local displayName = addon.Media and addon.Media.GetBarTextureDisplayName
                and addon.Media.GetBarTextureDisplayName(pending) or pending

            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOTERMOD_APPLYALL_TEXTURES", {
                    formatArgs = { displayName or pending },
                    data = { textureKey = pending },
                    onAccept = function(data)
                        if not data or not data.textureKey then return end
                        if not addon.ApplyAll or not addon.ApplyAll.ApplyBarTextures then return end

                        local result = addon.ApplyAll:ApplyBarTextures(data.textureKey, { updatePending = true })
                        if result and result.ok and result.changed and result.changed > 0 then
                            ReloadUI()
                        else
                            local reason = result and result.reason or "Unknown"
                            local friendly = {
                                noProfile = "Profile database unavailable.",
                                noSelection = "Select a texture before applying.",
                                noChanges = "All entries already use that texture.",
                            }
                            local detail = friendly[reason] or tostring(reason or "Unknown error.")
                            if addon.Print then
                                addon:Print("Apply All (Bar Textures) aborted: " .. detail)
                            end
                        end
                    end,
                })
            else
                if addon.Print then addon:Print("Dialog system unavailable.") end
            end
        end,
    })
    applyBtn:SetPoint("TOP", container, "TOP", 0, -180)
    table.insert(self._applyAllTexturesControls, applyBtn)

    -- Set scroll content height
    scrollContent:SetHeight(400)
end

--------------------------------------------------------------------------------
-- Buffs Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderBuffs(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderBuffs(scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["buffs"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.buffs and components.buffs[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.buffs = profile.components.buffs or {}
                profile.components.buffs[key] = value
            end
        end
    end

    -- Helper to sync Edit Mode settings after value change
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Helper to apply styles after value change
    local function applyStyles()
        if addon and addon.ApplyAuraFrameVisualsFor then
            C_Timer.After(0, function()
                local comp = getComponent()
                if comp then
                    addon.ApplyAuraFrameVisualsFor(comp)
                end
            end)
        end
    end

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "buffs",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local OrientationPatterns = addon.UI and addon.UI.SettingPatterns and addon.UI.SettingPatterns.Orientation

            local orientationValues = { H = "Horizontal", V = "Vertical" }
            local orientationOrder = { "H", "V" }

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = orientationValues,
                order = orientationOrder,
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                end,
                syncCooldown = 0.4,
            })

            local wrapValues = { down = "Down", up = "Up" }
            local wrapOrder = { "down", "up" }

            inner:AddSelector({
                key = "iconWrap",
                label = "Icon Wrap",
                description = "Direction icons wrap when reaching the limit per row/column.",
                values = wrapValues,
                order = wrapOrder,
                get = function() return getSetting("iconWrap") or "down" end,
                set = function(v)
                    setSetting("iconWrap", v)
                    syncEditModeSetting("iconWrap")
                end,
                syncCooldown = 0.4,
            })

            local dirValues = { left = "Left", right = "Right" }
            local dirOrder = { "left", "right" }

            inner:AddSelector({
                key = "direction",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = dirValues,
                order = dirOrder,
                get = function() return getSetting("direction") or "left" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between buff icons in pixels.",
                min = 5,
                max = 15,
                step = 1,
                get = function() return getSetting("iconPadding") or 10 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "5px",
                maxLabel = "15px",
                debounceKey = "UI_buffs_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:AddSlider({
                label = "Icon Limit",
                description = "Maximum number of buff icons to display.",
                min = 2,
                max = 32,
                step = 1,
                get = function() return getSetting("iconLimit") or 11 end,
                set = function(v) setSetting("iconLimit", v) end,
                minLabel = "2",
                maxLabel = "32",
                debounceKey = "UI_buffs_iconLimit",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconLimit")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "buffs",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_buffs_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconSize")
                end,
            })

            inner:AddSlider({
                label = "Icon Width",
                description = "Custom icon width in pixels.",
                min = 24,
                max = 48,
                step = 1,
                get = function() return getSetting("iconWidth") or 30 end,
                set = function(v)
                    setSetting("iconWidth", v)
                    applyStyles()
                end,
                minLabel = "24px",
                maxLabel = "48px",
            })

            inner:AddSlider({
                label = "Icon Height",
                description = "Custom icon height in pixels.",
                min = 24,
                max = 48,
                step = 1,
                get = function() return getSetting("iconHeight") or 30 end,
                set = function(v)
                    setSetting("iconHeight", v)
                    applyStyles()
                end,
                minLabel = "24px",
                maxLabel = "48px",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "buffs",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                key = "borderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for buff icons.",
                get = function() return getSetting("borderEnable") or false end,
                set = function(val)
                    setSetting("borderEnable", val)
                    applyStyles()
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(val)
                    setSetting("borderTintEnable", val)
                    applyStyles()
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", { r = r, g = g, b = b, a = a })
                    applyStyles()
                end,
                hasAlpha = true,
            })

            -- Border Style selector
            local borderStyleValues = { square = "Default" }
            local borderStyleOrder = { "square" }
            if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
                local entries = addon.IconBorders.GetDropdownEntries()
                if entries then
                    borderStyleValues = {}
                    borderStyleOrder = {}
                    for _, entry in ipairs(entries) do
                        local key = entry.value or entry.key
                        local label = entry.text or entry.label or key
                        if key then
                            borderStyleValues[key] = label
                            table.insert(borderStyleOrder, key)
                        end
                    end
                end
            end

            inner:AddSelector({
                key = "borderStyle",
                label = "Border Style",
                description = "Choose the visual style for icon borders.",
                values = borderStyleValues,
                order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    applyStyles()
                end,
            })

            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v)
                    setSetting("borderThickness", v)
                    applyStyles()
                end,
                minLabel = "1",
                maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Text (tabbed for Stacks and Duration)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "buffs",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local fontStyleValues = {
                NONE = "None",
                OUTLINE = "Outline",
                THICKOUTLINE = "Thick Outline",
            }
            local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

            inner:AddTabbedSection({
                tabs = {
                    { key = "stacks", label = "Stacks" },
                    { key = "duration", label = "Duration" },
                },
                componentId = "buffs",
                sectionKey = "textTabs",
                buildContent = {
                    stacks = function(tabContent, tabBuilder)
                        local function getStacksSetting(key, default)
                            local ts = getSetting("textStacks")
                            if ts and ts[key] ~= nil then return ts[key] end
                            return default
                        end
                        local function setStacksSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textStacks = comp.db.textStacks or {}
                                comp.db.textStacks[key] = value
                            end
                            applyStyles()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for stack count text.",
                            get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setStacksSetting("fontFace", v) end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getStacksSetting("size", 16) end,
                            set = function(v) setStacksSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getStacksSetting("style", "OUTLINE") end,
                            set = function(v) setStacksSetting("style", v) end,
                        })

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            get = function()
                                local c = getStacksSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                setStacksSetting("color", {r, g, b, a})
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.x = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.y = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:Finalize()
                    end,
                    duration = function(tabContent, tabBuilder)
                        local function getDurationSetting(key, default)
                            local td = getSetting("textDuration")
                            if td and td[key] ~= nil then return td[key] end
                            return default
                        end
                        local function setDurationSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textDuration = comp.db.textDuration or {}
                                comp.db.textDuration[key] = value
                            end
                            applyStyles()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for remaining time text.",
                            get = function() return getDurationSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setDurationSetting("fontFace", v) end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getDurationSetting("size", 14) end,
                            set = function(v) setDurationSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getDurationSetting("style", "OUTLINE") end,
                            set = function(v) setDurationSetting("style", v) end,
                        })

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            get = function()
                                local c = getDurationSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                setDurationSetting("color", {r, g, b, a})
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getDurationSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textDuration = comp.db.textDuration or {}
                                    comp.db.textDuration.offset = comp.db.textDuration.offset or {}
                                    comp.db.textDuration.offset.x = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getDurationSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textDuration = comp.db.textDuration or {}
                                    comp.db.textDuration.offset = comp.db.textDuration.offset or {}
                                    comp.db.textDuration.offset.y = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility & Misc
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "buffs",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v)
                    setSetting("opacity", v)
                    applyStyles()
                end,
                minLabel = "50%",
                maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Opacity when not in combat.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    applyStyles()
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target",
                description = "Opacity when you have a target.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    applyStyles()
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            inner:AddToggle({
                label = "Hide Expand/Collapse Button",
                description = "Hide the button that expands or collapses the buff frame.",
                get = function() return getSetting("hideCollapseButton") or false end,
                set = function(val)
                    setSetting("hideCollapseButton", val)
                    applyStyles()
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Debuffs Renderer
--------------------------------------------------------------------------------

function UIPanel:RenderDebuffs(scrollContent)
    self:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    self._currentBuilder = builder

    local panel = self
    builder:SetOnRefresh(function()
        panel:RenderDebuffs(scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["debuffs"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.debuffs and components.debuffs[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.debuffs = profile.components.debuffs or {}
                profile.components.debuffs[key] = value
            end
        end
    end

    -- Helper to sync Edit Mode settings after value change
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Helper to apply styles after value change
    local function applyStyles()
        if addon and addon.ApplyAuraFrameVisualsFor then
            C_Timer.After(0, function()
                local comp = getComponent()
                if comp then
                    addon.ApplyAuraFrameVisualsFor(comp)
                end
            end)
        end
    end

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "debuffs",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local orientationValues = { H = "Horizontal", V = "Vertical" }
            local orientationOrder = { "H", "V" }

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = orientationValues,
                order = orientationOrder,
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                end,
                syncCooldown = 0.4,
            })

            local wrapValues = { down = "Down", up = "Up" }
            local wrapOrder = { "down", "up" }

            inner:AddSelector({
                key = "iconWrap",
                label = "Icon Wrap",
                description = "Direction icons wrap when reaching the limit per row/column.",
                values = wrapValues,
                order = wrapOrder,
                get = function() return getSetting("iconWrap") or "down" end,
                set = function(v)
                    setSetting("iconWrap", v)
                    syncEditModeSetting("iconWrap")
                end,
                syncCooldown = 0.4,
            })

            local dirValues = { left = "Left", right = "Right" }
            local dirOrder = { "left", "right" }

            inner:AddSelector({
                key = "direction",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = dirValues,
                order = dirOrder,
                get = function() return getSetting("direction") or "left" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between debuff icons in pixels.",
                min = 5,
                max = 15,
                step = 1,
                get = function() return getSetting("iconPadding") or 10 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "5px",
                maxLabel = "15px",
                debounceKey = "UI_debuffs_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:AddSlider({
                label = "Icon Limit",
                description = "Maximum number of debuff icons to display.",
                min = 1,
                max = 16,
                step = 1,
                get = function() return getSetting("iconLimit") or 8 end,
                set = function(v) setSetting("iconLimit", v) end,
                minLabel = "1",
                maxLabel = "16",
                debounceKey = "UI_debuffs_iconLimit",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconLimit")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "debuffs",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_debuffs_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconSize")
                end,
            })

            inner:AddSlider({
                label = "Icon Width",
                description = "Custom icon width in pixels.",
                min = 24,
                max = 48,
                step = 1,
                get = function() return getSetting("iconWidth") or 30 end,
                set = function(v)
                    setSetting("iconWidth", v)
                    applyStyles()
                end,
                minLabel = "24px",
                maxLabel = "48px",
            })

            inner:AddSlider({
                label = "Icon Height",
                description = "Custom icon height in pixels.",
                min = 24,
                max = 48,
                step = 1,
                get = function() return getSetting("iconHeight") or 30 end,
                set = function(v)
                    setSetting("iconHeight", v)
                    applyStyles()
                end,
                minLabel = "24px",
                maxLabel = "48px",
            })

            inner:Finalize()
        end,
    })

    -- Note: Debuffs do NOT have a Border section - they use Blizzard's red DebuffBorder

    -- Collapsible section: Text (tabbed for Stacks and Duration)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "debuffs",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local fontStyleValues = {
                NONE = "None",
                OUTLINE = "Outline",
                THICKOUTLINE = "Thick Outline",
            }
            local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

            inner:AddTabbedSection({
                tabs = {
                    { key = "stacks", label = "Stacks" },
                    { key = "duration", label = "Duration" },
                },
                componentId = "debuffs",
                sectionKey = "textTabs",
                buildContent = {
                    stacks = function(tabContent, tabBuilder)
                        local function getStacksSetting(key, default)
                            local ts = getSetting("textStacks")
                            if ts and ts[key] ~= nil then return ts[key] end
                            return default
                        end
                        local function setStacksSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textStacks = comp.db.textStacks or {}
                                comp.db.textStacks[key] = value
                            end
                            applyStyles()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for stack count text.",
                            get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setStacksSetting("fontFace", v) end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getStacksSetting("size", 16) end,
                            set = function(v) setStacksSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getStacksSetting("style", "OUTLINE") end,
                            set = function(v) setStacksSetting("style", v) end,
                        })

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            get = function()
                                local c = getStacksSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                setStacksSetting("color", {r, g, b, a})
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.x = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getStacksSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                    comp.db.textStacks.offset.y = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:Finalize()
                    end,
                    duration = function(tabContent, tabBuilder)
                        local function getDurationSetting(key, default)
                            local td = getSetting("textDuration")
                            if td and td[key] ~= nil then return td[key] end
                            return default
                        end
                        local function setDurationSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textDuration = comp.db.textDuration or {}
                                comp.db.textDuration[key] = value
                            end
                            applyStyles()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for remaining time text.",
                            get = function() return getDurationSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setDurationSetting("fontFace", v) end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getDurationSetting("size", 14) end,
                            set = function(v) setDurationSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getDurationSetting("style", "OUTLINE") end,
                            set = function(v) setDurationSetting("style", v) end,
                        })

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            get = function()
                                local c = getDurationSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                setDurationSetting("color", {r, g, b, a})
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getDurationSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textDuration = comp.db.textDuration or {}
                                    comp.db.textDuration.offset = comp.db.textDuration.offset or {}
                                    comp.db.textDuration.offset.x = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local offset = getDurationSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textDuration = comp.db.textDuration or {}
                                    comp.db.textDuration.offset = comp.db.textDuration.offset or {}
                                    comp.db.textDuration.offset.y = v
                                end
                                applyStyles()
                            end,
                            minLabel = "-50",
                            maxLabel = "+50",
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "debuffs",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v)
                    setSetting("opacity", v)
                    applyStyles()
                end,
                minLabel = "50%",
                maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Opacity when not in combat.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    applyStyles()
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target",
                description = "Opacity when you have a target.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    applyStyles()
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Registry
--------------------------------------------------------------------------------
-- Maps navigation keys to render functions. Add new renderers here.

UIPanel._renderers = {
    -- Cooldown Manager
    cdmQoL = function(self, scrollContent)
        self:RenderCdmQoL(scrollContent)
    end,
    essentialCooldowns = function(self, scrollContent)
        self:RenderEssentialCooldowns(scrollContent)
    end,
    utilityCooldowns = function(self, scrollContent)
        self:RenderUtilityCooldowns(scrollContent)
    end,
    trackedBuffs = function(self, scrollContent)
        self:RenderTrackedBuffs(scrollContent)
    end,
    trackedBars = function(self, scrollContent)
        self:RenderTrackedBars(scrollContent)
    end,
    -- Action Bars
    actionBar1 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar1")
    end,
    actionBar2 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar2")
    end,
    actionBar3 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar3")
    end,
    actionBar4 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar4")
    end,
    actionBar5 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar5")
    end,
    actionBar6 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar6")
    end,
    actionBar7 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar7")
    end,
    actionBar8 = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "actionBar8")
    end,
    petBar = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "petBar")
    end,
    stanceBar = function(self, scrollContent)
        self:RenderActionBar(scrollContent, "stanceBar")
    end,
    microBar = function(self, scrollContent)
        self:RenderMicroBar(scrollContent)
    end,
    -- Personal Resource Display
    prdGeneral = function(self, scrollContent)
        self:RenderPRDGeneral(scrollContent)
    end,
    prdHealthBar = function(self, scrollContent)
        self:RenderPRDHealthBar(scrollContent)
    end,
    prdPowerBar = function(self, scrollContent)
        self:RenderPRDPowerBar(scrollContent)
    end,
    prdClassResource = function(self, scrollContent)
        self:RenderPRDClassResource(scrollContent)
    end,
    -- Interface
    tooltip = function(self, scrollContent)
        self:RenderTooltip(scrollContent)
    end,
    objectiveTracker = function(self, scrollContent)
        self:RenderObjectiveTracker(scrollContent)
    end,
    minimap = function(self, scrollContent)
        self:RenderMinimap(scrollContent)
    end,
    chat = function(self, scrollContent)
        self:RenderChat(scrollContent)
    end,
    -- SCT
    sctDamage = function(self, scrollContent)
        self:RenderSctDamage(scrollContent)
    end,
    -- Unit Frames
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
    ufBoss = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderBoss then
            UF.RenderBoss(self, scrollContent)
        end
    end,
    -- Group Frames
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
    -- Profiles
    profilesManage = function(self, scrollContent)
        self:RenderProfilesManage(scrollContent)
    end,
    profilesPresets = function(self, scrollContent)
        self:RenderProfilesPresets(scrollContent)
    end,
    profilesRules = function(self, scrollContent)
        self:RenderProfilesRules(scrollContent)
    end,
    -- Apply All
    applyAllFonts = function(self, scrollContent)
        self:RenderApplyAllFonts(scrollContent)
    end,
    applyAllTextures = function(self, scrollContent)
        self:RenderApplyAllTextures(scrollContent)
    end,
    -- Buffs/Debuffs
    buffs = function(self, scrollContent)
        self:RenderBuffs(scrollContent)
    end,
    debuffs = function(self, scrollContent)
        self:RenderDebuffs(scrollContent)
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
        prdGeneral = "Personal Resource: General",
        prdHealthBar = "Personal Resource: Health Bar",
        prdPowerBar = "Personal Resource: Power Bar",
        prdClassResource = "Personal Resource: Class Resource",
        ufPlayer = "Unit Frames: Player",
        ufTarget = "Unit Frames: Target",
        ufFocus = "Unit Frames: Focus",
        ufPet = "Unit Frames: Pet",
        ufToT = "Unit Frames: Target of Target",
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
        if addon and addon.Print then
            addon:Print("Cannot open settings during combat.")
        end
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
        if addon and addon.Print then
            addon:Print("Cannot open settings during combat.")
        end
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
-- Combat Safety (auto-close on combat start)
--------------------------------------------------------------------------------

-- Register for combat events to auto-close if needed
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat started - hide UI panel if shown
        if UIPanel.frame and UIPanel.frame:IsShown() then
            UIPanel.frame:Hide()
            if addon and addon.Print then
                addon:Print("UI Settings closed for combat.")
            end
        end
    end
end)
