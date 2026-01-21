-- Tabbed.lua - Horizontal tabs for organizing sub-settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local TAB_HEIGHT = 26
local TAB_PADDING = 16  -- Horizontal padding per side of tab text
local TAB_SPACING = 2   -- Gap between tabs
local TAB_BAR_PADDING = 8  -- Padding on sides of tab bar
local TAB_ROW_SPACING = 2  -- Gap between tab rows when multi-row
local TABBED_BORDER_WIDTH = 1
local TABBED_BORDER_ALPHA = 0.6
local TABBED_CONTENT_PADDING = 8
local MAX_TABS_PER_ROW = 5

--------------------------------------------------------------------------------
-- Session storage for selected tab state
--------------------------------------------------------------------------------

addon.UI._tabStates = addon.UI._tabStates or {}

local function GetTabState(componentId, sectionKey, defaultTab)
    addon.UI._tabStates[componentId] = addon.UI._tabStates[componentId] or {}
    local state = addon.UI._tabStates[componentId][sectionKey]
    if state == nil then
        return defaultTab
    end
    return state
end

local function SetTabState(componentId, sectionKey, tabKey)
    addon.UI._tabStates[componentId] = addon.UI._tabStates[componentId] or {}
    addon.UI._tabStates[componentId][sectionKey] = tabKey
end

--------------------------------------------------------------------------------
-- TabbedSection: Horizontal tabs for organizing sub-settings
--------------------------------------------------------------------------------
-- Creates a tabbed section with:
--   - Horizontal tab bar at top (supports up to 9 tabs in 2 rows)
--   - Each tab has its own content frame
--   - Dynamic height based on selected tab's content
--   - UI aesthetic (accent color borders, hover effects)
--
-- Options table:
--   tabs          : Array of { key = "uniqueKey", label = "Display Label" }
--   parent        : Parent frame (required)
--   componentId   : Component identifier for state storage
--   sectionKey    : Section identifier for state storage
--   defaultTab    : Key of tab to show by default (optional, defaults to first tab)
--   onTabChange   : Callback function(newTabKey, oldTabKey) (optional)
--   name          : Global frame name (optional)
--------------------------------------------------------------------------------

function Controls:CreateTabbedSection(options)
    local theme = GetTheme()
    if not options or not options.parent or not options.tabs or #options.tabs == 0 then
        return nil
    end

    local parent = options.parent
    local tabs = options.tabs
    local componentId = options.componentId or "unknown"
    local sectionKey = options.sectionKey or "tabs"
    local defaultTab = options.defaultTab or tabs[1].key
    local onTabChange = options.onTabChange
    local name = options.name

    -- Get initial selected tab from session storage
    local selectedTabKey = GetTabState(componentId, sectionKey, defaultTab)

    -- Validate selected tab exists
    local tabExists = false
    for _, tab in ipairs(tabs) do
        if tab.key == selectedTabKey then
            tabExists = true
            break
        end
    end
    if not tabExists then
        selectedTabKey = tabs[1].key
    end

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- Calculate tab row layout
    local numTabs = #tabs
    local hasSecondRow = numTabs > MAX_TABS_PER_ROW
    local tabBarHeight = hasSecondRow and (TAB_HEIGHT * 2 + TAB_ROW_SPACING) or TAB_HEIGHT

    -- Main container frame
    local section = CreateFrame("Frame", name, parent)
    section._selectedTabKey = selectedTabKey
    section._componentId = componentId
    section._sectionKey = sectionKey
    section._tabs = tabs
    section._tabButtons = {}
    section._tabContents = {}
    section._contentHeights = {}

    ----------------------------------------------------------------------------
    -- Tab bar container
    ----------------------------------------------------------------------------
    local tabBar = CreateFrame("Frame", nil, section)
    tabBar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
    tabBar:SetHeight(tabBarHeight)
    section._tabBar = tabBar

    ----------------------------------------------------------------------------
    -- Content container (below tab bar)
    ----------------------------------------------------------------------------
    local contentContainer = CreateFrame("Frame", nil, section)
    contentContainer:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    contentContainer:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    -- Height set dynamically based on selected tab content
    section._contentContainer = contentContainer

    -- Content border textures (all 4 sides)
    local contentBorders = {}

    -- TOP border
    local topBorder = contentContainer:CreateTexture(nil, "BORDER", nil, -1)
    topBorder:SetPoint("TOPLEFT", contentContainer, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", contentContainer, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(TABBED_BORDER_WIDTH)
    topBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
    contentBorders.TOP = topBorder

    -- LEFT border
    local leftBorder = contentContainer:CreateTexture(nil, "BORDER", nil, -1)
    leftBorder:SetPoint("TOPLEFT", contentContainer, "TOPLEFT", 0, -TABBED_BORDER_WIDTH)
    leftBorder:SetPoint("BOTTOMLEFT", contentContainer, "BOTTOMLEFT", 0, TABBED_BORDER_WIDTH)
    leftBorder:SetWidth(TABBED_BORDER_WIDTH)
    leftBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
    contentBorders.LEFT = leftBorder

    -- RIGHT border
    local rightBorder = contentContainer:CreateTexture(nil, "BORDER", nil, -1)
    rightBorder:SetPoint("TOPRIGHT", contentContainer, "TOPRIGHT", 0, -TABBED_BORDER_WIDTH)
    rightBorder:SetPoint("BOTTOMRIGHT", contentContainer, "BOTTOMRIGHT", 0, TABBED_BORDER_WIDTH)
    rightBorder:SetWidth(TABBED_BORDER_WIDTH)
    rightBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
    contentBorders.RIGHT = rightBorder

    -- BOTTOM border
    local bottomBorder = contentContainer:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", contentContainer, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", contentContainer, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(TABBED_BORDER_WIDTH)
    bottomBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
    contentBorders.BOTTOM = bottomBorder

    section._contentBorders = contentBorders

    -- Content background
    local contentBg = contentContainer:CreateTexture(nil, "BACKGROUND", nil, -8)
    contentBg:SetPoint("TOPLEFT", TABBED_BORDER_WIDTH, 0)
    contentBg:SetPoint("BOTTOMRIGHT", -TABBED_BORDER_WIDTH, TABBED_BORDER_WIDTH)
    contentBg:SetColorTexture(0, 0, 0, 0.15)
    section._contentBg = contentBg

    ----------------------------------------------------------------------------
    -- Create tab buttons and content frames
    ----------------------------------------------------------------------------
    local function CreateTabButton(tabData, index)
        local tabBtn = CreateFrame("Button", nil, tabBar)
        tabBtn:SetHeight(TAB_HEIGHT)
        tabBtn:EnableMouse(true)
        tabBtn:RegisterForClicks("AnyUp")

        -- Calculate text width for button sizing
        local labelFont = theme:GetFont("LABEL")
        local tempFS = tabBtn:CreateFontString(nil, "OVERLAY")
        tempFS:SetFont(labelFont, 12, "")
        tempFS:SetText(tabData.label)
        local textWidth = tempFS:GetStringWidth()
        tempFS:Hide()

        local btnWidth = textWidth + (TAB_PADDING * 2)
        tabBtn:SetWidth(btnWidth)

        -- Selected fill background (accent color, shown when selected)
        local selectedFill = tabBtn:CreateTexture(nil, "BACKGROUND", nil, -7)
        selectedFill:SetPoint("TOPLEFT", 1, -1)
        selectedFill:SetPoint("BOTTOMRIGHT", -1, 1)
        selectedFill:SetColorTexture(ar, ag, ab, 1)
        selectedFill:Hide()
        tabBtn._selectedFill = selectedFill

        -- Hover background (subtle highlight)
        local hoverBg = tabBtn:CreateTexture(nil, "BACKGROUND", nil, -8)
        hoverBg:SetPoint("TOPLEFT", 1, -1)
        hoverBg:SetPoint("BOTTOMRIGHT", -1, 1)
        hoverBg:SetColorTexture(ar, ag, ab, 0.15)
        hoverBg:Hide()
        tabBtn._hoverBg = hoverBg

        -- Tab border (full box)
        local tabBorders = {}

        local tabTopBorder = tabBtn:CreateTexture(nil, "BORDER", nil, -1)
        tabTopBorder:SetPoint("TOPLEFT", tabBtn, "TOPLEFT", 0, 0)
        tabTopBorder:SetPoint("TOPRIGHT", tabBtn, "TOPRIGHT", 0, 0)
        tabTopBorder:SetHeight(1)
        tabTopBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
        tabBorders.TOP = tabTopBorder

        local tabBottomBorder = tabBtn:CreateTexture(nil, "BORDER", nil, -1)
        tabBottomBorder:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 0)
        tabBottomBorder:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
        tabBottomBorder:SetHeight(1)
        tabBottomBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
        tabBorders.BOTTOM = tabBottomBorder

        local tabLeftBorder = tabBtn:CreateTexture(nil, "BORDER", nil, -1)
        tabLeftBorder:SetPoint("TOPLEFT", tabBtn, "TOPLEFT", 0, -1)
        tabLeftBorder:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 1)
        tabLeftBorder:SetWidth(1)
        tabLeftBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
        tabBorders.LEFT = tabLeftBorder

        local tabRightBorder = tabBtn:CreateTexture(nil, "BORDER", nil, -1)
        tabRightBorder:SetPoint("TOPRIGHT", tabBtn, "TOPRIGHT", 0, -1)
        tabRightBorder:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 1)
        tabRightBorder:SetWidth(1)
        tabRightBorder:SetColorTexture(ar, ag, ab, TABBED_BORDER_ALPHA)
        tabBorders.RIGHT = tabRightBorder

        tabBtn._borders = tabBorders

        -- Label
        local labelStr = tabBtn:CreateFontString(nil, "OVERLAY")
        labelStr:SetFont(labelFont, 12, "")
        labelStr:SetPoint("CENTER", 0, 0)
        labelStr:SetText(tabData.label)
        labelStr:SetTextColor(ar, ag, ab, 1)
        tabBtn._label = labelStr

        -- Store tab key
        tabBtn._tabKey = tabData.key
        tabBtn._tabIndex = index

        -- Click handler
        tabBtn:SetScript("OnClick", function(self)
            section:SelectTab(self._tabKey)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        end)

        -- Hover handlers
        tabBtn:SetScript("OnEnter", function(self)
            if section._selectedTabKey ~= self._tabKey then
                self._hoverBg:Show()
            end
        end)

        tabBtn:SetScript("OnLeave", function(self)
            self._hoverBg:Hide()
        end)

        return tabBtn
    end

    local function CreateTabContent(tabData, index)
        local content = CreateFrame("Frame", nil, contentContainer)
        content:SetPoint("TOPLEFT", contentContainer, "TOPLEFT", TABBED_BORDER_WIDTH + TABBED_CONTENT_PADDING, -TABBED_CONTENT_PADDING)
        content:SetPoint("TOPRIGHT", contentContainer, "TOPRIGHT", -(TABBED_BORDER_WIDTH + TABBED_CONTENT_PADDING), -TABBED_CONTENT_PADDING)
        -- Height managed dynamically
        content._tabKey = tabData.key
        content._tabIndex = index
        return content
    end

    -- Create all tabs
    for i, tabData in ipairs(tabs) do
        local tabBtn = CreateTabButton(tabData, i)
        local tabContent = CreateTabContent(tabData, i)

        section._tabButtons[tabData.key] = tabBtn
        section._tabContents[tabData.key] = tabContent
        section._contentHeights[tabData.key] = 100  -- Default, updated by builder
    end

    ----------------------------------------------------------------------------
    -- Position tabs (with multi-row support)
    ----------------------------------------------------------------------------
    local function LayoutTabs()
        local allTabs = {}
        for _, tabData in ipairs(tabs) do
            table.insert(allTabs, section._tabButtons[tabData.key])
        end

        if #allTabs == 0 then return end

        -- Split into rows: bottom row (first 5), top row (6+)
        local bottomCount = math.min(MAX_TABS_PER_ROW, #allTabs)
        local bottomRow = {}
        for i = 1, bottomCount do
            table.insert(bottomRow, allTabs[i])
        end

        local topRow = {}
        if #allTabs > MAX_TABS_PER_ROW then
            for i = MAX_TABS_PER_ROW + 1, #allTabs do
                table.insert(topRow, allTabs[i])
            end
        end

        -- Position bottom row (left-aligned)
        local xOffset = TAB_BAR_PADDING
        local yOffset = hasSecondRow and -(TAB_HEIGHT + TAB_ROW_SPACING) or 0

        for i, tabBtn in ipairs(bottomRow) do
            tabBtn:ClearAllPoints()
            tabBtn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", xOffset, yOffset)
            xOffset = xOffset + tabBtn:GetWidth() + TAB_SPACING
        end

        -- Position top row (left-aligned, above bottom row)
        if #topRow > 0 then
            xOffset = TAB_BAR_PADDING
            for i, tabBtn in ipairs(topRow) do
                tabBtn:ClearAllPoints()
                tabBtn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", xOffset, 0)
                xOffset = xOffset + tabBtn:GetWidth() + TAB_SPACING
            end
        end
    end

    LayoutTabs()

    ----------------------------------------------------------------------------
    -- Tab selection state update
    ----------------------------------------------------------------------------
    local function UpdateTabVisuals()
        for key, tabBtn in pairs(section._tabButtons) do
            local isSelected = (key == section._selectedTabKey)
            tabBtn._selectedFill:SetShown(isSelected)
            tabBtn._hoverBg:Hide()

            if isSelected then
                -- Selected: inverted colors (accent fill, dark text)
                tabBtn._label:SetTextColor(0, 0, 0, 1)
            else
                -- Not selected: accent text, no fill
                local r, g, b = theme:GetAccentColor()
                tabBtn._label:SetTextColor(r, g, b, 1)
            end
        end

        -- Show/hide content frames
        for key, content in pairs(section._tabContents) do
            content:SetShown(key == section._selectedTabKey)
        end
    end

    local function UpdateSectionHeight()
        local contentHeight = section._contentHeights[section._selectedTabKey] or 100
        local totalContentHeight = contentHeight + (TABBED_CONTENT_PADDING * 2) + TABBED_BORDER_WIDTH

        contentContainer:SetHeight(totalContentHeight)
        section:SetHeight(tabBarHeight + totalContentHeight)
    end

    -- Initialize visual state
    UpdateTabVisuals()
    UpdateSectionHeight()

    ----------------------------------------------------------------------------
    -- Theme subscription
    ----------------------------------------------------------------------------
    local subscribeKey = "TabbedSection_" .. componentId .. "_" .. sectionKey
    section._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update content borders
        for _, tex in pairs(section._contentBorders) do
            tex:SetColorTexture(r, g, b, TABBED_BORDER_ALPHA)
        end

        -- Update tab buttons
        for key, tabBtn in pairs(section._tabButtons) do
            local isSelected = (key == section._selectedTabKey)

            -- Update selected fill color
            tabBtn._selectedFill:SetColorTexture(r, g, b, 1)
            tabBtn._hoverBg:SetColorTexture(r, g, b, 0.15)

            -- Update tab borders
            if tabBtn._borders then
                for _, tex in pairs(tabBtn._borders) do
                    tex:SetColorTexture(r, g, b, TABBED_BORDER_ALPHA)
                end
            end

            -- Update label color based on selected state
            if isSelected then
                tabBtn._label:SetTextColor(0, 0, 0, 1)  -- Dark text on accent fill
            else
                tabBtn._label:SetTextColor(r, g, b, 1)  -- Accent text
            end
        end
    end)

    ----------------------------------------------------------------------------
    -- Public methods
    ----------------------------------------------------------------------------
    function section:SelectTab(tabKey)
        if tabKey == self._selectedTabKey then return end

        local oldKey = self._selectedTabKey
        self._selectedTabKey = tabKey
        SetTabState(self._componentId, self._sectionKey, tabKey)

        UpdateTabVisuals()
        UpdateSectionHeight()

        if onTabChange then
            onTabChange(tabKey, oldKey)
        end
    end

    function section:GetSelectedTab()
        return self._selectedTabKey
    end

    function section:GetTabContent(tabKey)
        return self._tabContents[tabKey]
    end

    function section:SetTabContentHeight(tabKey, height)
        self._contentHeights[tabKey] = height
        if tabKey == self._selectedTabKey then
            UpdateSectionHeight()
        end
    end

    function section:GetHeight()
        local contentHeight = self._contentHeights[self._selectedTabKey] or 100
        local totalContentHeight = contentHeight + (TABBED_CONTENT_PADDING * 2) + TABBED_BORDER_WIDTH
        return tabBarHeight + totalContentHeight
    end

    function section:GetTabBarHeight()
        return tabBarHeight
    end

    function section:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        -- Clean up any inner builders stored on content frames
        for key, content in pairs(self._tabContents) do
            if content._innerBuilder and content._innerBuilder.Cleanup then
                content._innerBuilder:Cleanup()
            end
        end
    end

    return section
end
