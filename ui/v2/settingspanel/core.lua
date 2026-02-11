-- settingspanel/core.lua - Panel construction, initialization, public API, combat safety
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Window = addon.UI.Window
local Controls = addon.UI.Controls
local Navigation = addon.UI.Navigation
local SettingsBuilder = addon.UI.SettingsBuilder

-- Import promoted ASCII data from ascii.lua
local ASCII_LOGO = UIPanel._ASCII_LOGO
local ASCII_MASCOT = UIPanel._ASCII_MASCOT

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

-- Navigation sidebar width
local NAV_WIDTH = 220

-- Content pane scrollbar constants
local CONTENT_SCROLLBAR_WIDTH = 8
local CONTENT_SCROLLBAR_THUMB_MIN = 30
local CONTENT_SCROLLBAR_MARGIN = 8
local CONTENT_PADDING = 8
local CONTENT_SCROLLBAR_BOTTOM_MARGIN = RESIZE_HANDLE_SIZE + 8  -- Clear the resize grip

--------------------------------------------------------------------------------
-- Panel State
--------------------------------------------------------------------------------

UIPanel.frame = nil
UIPanel._initialized = false
UIPanel._currentCategoryKey = nil    -- Currently displayed category
UIPanel._pendingBackSync = {}        -- Components needing refresh from Edit Mode back-sync

-- Store current builder instance for cleanup
UIPanel._currentBuilder = nil

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
    -- The EnterEditMode post-hook (core/editmode/core.lua) handles refreshing
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

    local labelFont2 = Theme:GetFont("LABEL")

    -- Large ASCII art title (anchor point for other elements)
    local homeAscii = homeContainer:CreateFontString(nil, "OVERLAY")
    homeAscii:SetFont(labelFont2, 10, "")  -- Larger than title bar (6pt -> 10pt)
    homeAscii:SetText(ASCII_LOGO)
    homeAscii:SetJustifyH("CENTER")
    homeAscii:SetTextColor(ar, ag, ab, 1)  -- Accent color
    homeAscii:SetPoint("LEFT", homeContainer, "LEFT", 0, 0)

    -- ASCII mascot (above the title, slightly right)
    local homeMascot = homeContainer:CreateFontString(nil, "OVERLAY")
    homeMascot:SetFont(labelFont2, 7.5, "")  -- 25% larger than 6pt
    homeMascot:SetText(ASCII_MASCOT)
    homeMascot:SetJustifyH("LEFT")  -- Must be LEFT to keep ASCII art internally aligned
    homeMascot:SetTextColor(ar, ag, ab, 1)  -- Accent color
    homeMascot:SetPoint("BOTTOM", homeAscii, "TOP", 65, 8)  -- Above title, offset right 65px

    -- "Welcome to" text (above-left of ASCII title)
    local welcomeText = homeContainer:CreateFontString(nil, "OVERLAY")
    welcomeText:SetFont(labelFont2, 16, "")
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

--------------------------------------------------------------------------------
-- Cross-file promotions (consumed by navigation.lua)
--------------------------------------------------------------------------------

UIPanel._CONTENT_PADDING = CONTENT_PADDING
