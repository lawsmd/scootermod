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
    if addon.db and addon.db.global and addon.db.global.tuiWindowSize then
        local size = addon.db.global.tuiWindowSize
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

    -- Protect against unintended closure during Edit Mode ApplyChanges.
    -- LibEditModeOverride:ApplyChanges() briefly shows/hides EditModeManagerFrame,
    -- which can trigger Blizzard's frame management to close other panels.
    -- If we're inside our own ApplyChanges call, re-show the panel immediately.
    -- NOTE: Immediate re-show (no defer) matches old panel behavior and avoids visible flicker.
    frame:HookScript("OnHide", function(f)
        if addon and addon.EditMode and addon.EditMode._inScooterApplyChanges then
            if f and not f:IsShown() then
                f:Show()
            end
        end
    end)

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
            addon.db.global.tuiWindowPosition = {
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
    C_Timer.After(0.05, function()
        if logo and logoBtn then
            local w = logo:GetStringWidth() or 400
            local h = logo:GetStringHeight() or 40
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
            addon.db.global.tuiWindowPosition = {
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
        onClick = function(btn, mouseButton)
            -- Close settings panel first
            if panel and panel.frame and panel.frame:IsShown() then
                panel.frame:Hide()
            end
            -- Cancel any pending Edit Mode apply changes
            if addon and addon.EditMode and addon.EditMode.CancelPendingApplyChanges then
                addon.EditMode.CancelPendingApplyChanges()
            end
            -- Open Edit Mode
            if SlashCmdList and SlashCmdList["EDITMODE"] then
                SlashCmdList["EDITMODE"]("")
            elseif RunBinding then
                RunBinding("TOGGLE_EDIT_MODE")
            else
                if addon and addon.Print then
                    addon:Print("Use /editmode to open the layout manager.")
                end
            end
        end
    })

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
            addon.db.global.tuiWindowSize = {
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

    frame._contentPane = contentPane

    -- Initialize in Home state (header hidden, blank content)
    headerTitle:Hide()
    headerSep:Hide()
    scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)

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

-- Clear existing content and prepare for new render
function UIPanel:ClearContent()
    if self._currentBuilder then
        self._currentBuilder:Cleanup()
        self._currentBuilder = nil
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
        if comp and comp.GetSetting then
            return comp:GetSetting(key)
        end
        -- Fallback to profile if component not loaded
        local profile = addon.db and addon.db.profile
        return profile and profile.essentialCooldowns and profile.essentialCooldowns[key]
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
            -- Fallback to profile
            local profile = addon.db and addon.db.profile
            if profile then
                profile.essentialCooldowns = profile.essentialCooldowns or {}
                profile.essentialCooldowns[key] = value
            end
        end
    end

    -- Helper to sync Edit Mode settings after value change (debounced)
    -- This is called by onEditModeSync for slider/selector controls
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            -- Sync to Edit Mode
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId)
            -- Save and apply
            if addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            if addon.EditMode.RequestApplyChanges then
                addon.EditMode.RequestApplyChanges(0.2)
            end
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
            inner:AddDescription("Adjust the size of cooldown icons.")
            inner:AddSpacer(8)
            inner:AddDescription("Settings: Icon Size (Scale), Icon Width, Icon Height", { dim = true })
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
            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function()
                    return getSetting("useBorderTint") or false
                end,
                set = function(val)
                    setSetting("useBorderTint", val)
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
                end,
                hasAlpha = true,
            })

            inner:AddSpacer(8)
            inner:AddDescription("More settings coming: Use Custom Border, Border Style, Border Thickness, Border Inset", { dim = true })
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
            -- Optional: Add description or disclaimer text above tabs if needed
            -- inner:AddDescription("Configure text display on cooldown icons.")
            -- inner:AddSpacer(8)

            -- Tabbed section for Charges and Cooldowns text settings
            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                },
                componentId = "essentialCooldowns",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        -- Font selector for charges text
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for charges text display.",
                            get = function()
                                return getSetting("chargesFontFace") or "FRIZQT__"
                            end,
                            set = function(fontKey)
                                setSetting("chargesFontFace", fontKey)
                            end,
                        })

                        -- Color picker for charges text
                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            description = "The color used for charges text.",
                            get = function()
                                local c = getSetting("chargesFontColor")
                                if c then
                                    return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                                end
                                return 1, 1, 1, 1  -- Default white
                            end,
                            set = function(r, g, b, a)
                                setSetting("chargesFontColor", { r = r, g = g, b = b, a = a })
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddSpacer(8)
                        tabBuilder:AddDescription("More settings coming: Font Size, Style, Offset X, Offset Y", { dim = true })
                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        -- Cooldowns tab content (placeholder for now)
                        tabBuilder:AddDescription("Cooldown text settings will go here.")
                        tabBuilder:AddSpacer(8)
                        tabBuilder:AddDescription("Settings: Font, Font Size, Style, Color, Offset X, Offset Y", { dim = true })
                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Misc
    builder:AddCollapsibleSection({
        title = "Misc",
        componentId = "essentialCooldowns",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddDescription("Additional display options for the cooldown tracker.")
            inner:AddSpacer(8)
            inner:AddDescription("Settings: Visibility, Opacity in Combat, Opacity Out of Combat, Opacity With Target, Show Timer, Show Tooltips", { dim = true })
            inner:Finalize()
        end,
    })

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
        if comp and comp.GetSetting then
            return comp:GetSetting(key)
        end
        -- Fallback to profile if component not loaded
        local profile = addon.db and addon.db.profile
        return profile and profile.objectiveTracker and profile.objectiveTracker[key]
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
            -- Fallback to profile
            local profile = addon.db and addon.db.profile
            if profile then
                profile.objectiveTracker = profile.objectiveTracker or {}
                profile.objectiveTracker[key] = value
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
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId)
            if addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            if addon.EditMode.RequestApplyChanges then
                addon.EditMode.RequestApplyChanges(0.2)
            end
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
-- Renderer Registry
--------------------------------------------------------------------------------
-- Maps navigation keys to render functions. Add new renderers here.

UIPanel._renderers = {
    cdmQoL = function(self, scrollContent)
        self:RenderCdmQoL(scrollContent)
    end,
    essentialCooldowns = function(self, scrollContent)
        self:RenderEssentialCooldowns(scrollContent)
    end,
    objectiveTracker = function(self, scrollContent)
        self:RenderObjectiveTracker(scrollContent)
    end,
    -- Future renderers will be added here:
    -- profilesManage = function(self, scrollContent) ... end,
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

        -- Expand scroll area to fill space where header was
        if contentPane._scrollFrame then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        -- Hide placeholder
        if contentPane._placeholder then
            contentPane._placeholder:SetText("")
            contentPane._placeholder:Hide()
        end

        -- Reset scroll content height for home
        if scrollContent then
            scrollContent:SetHeight(1)
        end
    else
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
        ufPlayer = "Unit Frames: Player",
        ufTarget = "Unit Frames: Target",
        ufFocus = "Unit Frames: Focus",
        ufPet = "Unit Frames: Pet",
        ufToT = "Unit Frames: Target of Target",
        ufBoss = "Unit Frames: Boss",
        gfParty = "Party Frames",
        gfRaid = "Raid Frames",
        nameplatesUnit = "Unit Nameplates",
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
            self.frame:Hide()
        else
            self.frame:Show()
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
        self.frame:Show()
    end
end

function UIPanel:Hide()
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
