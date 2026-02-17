-- settingspanel/navigation.lua - Back-sync, content cleanup, copy-from, nav handler, titles
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls
local Navigation = addon.UI.Navigation
local SettingsBuilder = addon.UI.SettingsBuilder

-- Import promoted constants from ascii.lua and core.lua
local ASCII_LOGO = UIPanel._ASCII_LOGO
local CONTENT_PADDING = UIPanel._CONTENT_PADDING

-- Edit Mode Back-Sync Handler
-- Marks affected component for refresh and triggers re-render if visible.

function UIPanel:HandleEditModeBackSync(componentId, settingId)
    if not componentId then return end

    self._pendingBackSync[componentId] = true

    local categoryKey = componentId

    if self._currentCategoryKey == categoryKey then
        C_Timer.After(0, function()
            if self.frame and self.frame:IsShown() then
                self:OnNavigationSelect(categoryKey, categoryKey)
            end
        end)
    end
end

function UIPanel:CheckPendingBackSync(componentId)
    if self._pendingBackSync[componentId] then
        self._pendingBackSync[componentId] = nil
        return true
    end
    return false
end

function UIPanel:ClearPendingBackSync()
    wipe(self._pendingBackSync)
end

-- Content Cleanup System
-- Cleans up all content types before rendering a new section.
-- New sections with custom state tracking must add their cleanup logic here.

function UIPanel:ClearContent()
    -- Builder-based content
    if self._currentBuilder then
        self._currentBuilder:Cleanup()
        self._currentBuilder = nil
    end

    -- Rules state-based content
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

    -- Profiles > Manage Profiles state-based content
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

    -- Profiles > Presets state-based content
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

    -- Profiles > Import/Export state-based content
    if self._importExportState and self._importExportState.currentControls then
        for _, control in ipairs(self._importExportState.currentControls) do
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
        self._importExportState.currentControls = {}
    end

    -- Apply All > Fonts state-based content
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

    -- Apply All > Bar Textures state-based content
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

    -- Debug Menu state-based content
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

-- Collapse All Sections

function UIPanel:CollapseAllSections()
    local key = self._currentCategoryKey
    if not key then return end

    local componentId = key

    local sectionStates = addon.UI._sectionStates
    if sectionStates and sectionStates[componentId] then
        for sectionKey in pairs(sectionStates[componentId]) do
            sectionStates[componentId][sectionKey] = false
        end
    end

    self:OnNavigationSelect(key, key)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

-- Update Collapse All Button Visibility

function UIPanel:UpdateCollapseAllButton()
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local collapseBtn = contentPane._collapseAllBtn
    if not collapseBtn then return end

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

-- Copy From Dropdown Management

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

local ACTION_BAR_ORDER = {
    "actionBar1", "actionBar2", "actionBar3", "actionBar4",
    "actionBar5", "actionBar6", "actionBar7", "actionBar8",
}

local UNIT_FRAME_COPY_TARGETS = {
    ufPlayer = true,
    ufTarget = true,
    ufFocus = true,
    ufPet = true,
    ufToT = true,
    ufFocusTarget = true,
    -- ufBoss excluded (no copy support)
}

local UNIT_FRAME_NAMES = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "Target of Target",
    ufFocusTarget = "Target of Focus",
}

local UNIT_FRAME_KEYS = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "TargetOfTarget",
    ufFocusTarget = "FocusTarget",
}

local FULL_UNIT_FRAME_ORDER = { "ufPlayer", "ufTarget", "ufFocus", "ufPet" }

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
        local values = {}
        local order = {}
        for _, barKey in ipairs(ACTION_BAR_ORDER) do
            if barKey ~= key then
                values[barKey] = ACTION_BAR_NAMES[barKey]
                table.insert(order, barKey)
            end
        end

        dropdown:SetOptions(values, order)
        dropdown:ClearSelection()
        dropdown:Show()
        if label then label:Show() end

    -- Check if this is a Unit Frame category
    elseif key and UNIT_FRAME_COPY_TARGETS[key] then
        local values = {}
        local order = {}

        if TOT_FOT_SOURCES[key] then
            for _, sourceKey in ipairs(TOT_FOT_SOURCES[key]) do
                values[sourceKey] = UNIT_FRAME_NAMES[sourceKey]
                table.insert(order, sourceKey)
            end
        else
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
        dropdown:Hide()
        if label then label:Hide() end
    end
end

function UIPanel:HandleCopyFrom(sourceKey)
    local destKey = self._currentCategoryKey
    if not sourceKey or not destKey then return end

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
        if addon and addon.CopyUnitFrameSettings then
            local sourceUnit = UNIT_FRAME_KEYS[sourceKey]
            local destUnit = UNIT_FRAME_KEYS[destKey]
            local ok, err = addon.CopyUnitFrameSettings(sourceUnit, destUnit)

            if ok then
                C_Timer.After(0.1, function()
                    local panel = addon.UI and addon.UI.SettingsPanel
                    if panel and panel._currentCategoryKey == destKey then
                        panel:OnNavigationSelect(destKey, destKey)
                    end
                end)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            else
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
        if addon and addon.CopyActionBarSettings then
            addon.CopyActionBarSettings(sourceKey, destKey)

            C_Timer.After(0.1, function()
                local panel = addon.UI and addon.UI.SettingsPanel
                if panel and panel._currentCategoryKey == destKey then
                    panel:OnNavigationSelect(destKey, destKey)
                end
            end)

            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end
end

-- Navigation Selection Handler

function UIPanel:OnNavigationSelect(key, previousKey)
    local frame = self.frame
    if not frame or not frame._contentPane then return end

    local contentPane = frame._contentPane
    local scrollContent = contentPane._scrollContent
    local isHome = (key == "home" or key == nil)
    local wasHome = (previousKey == "home" or previousKey == nil)

    self._currentCategoryKey = key
    self:CheckPendingBackSync(key)
    self:ClearContent()

    if isHome then
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

        self:StopAsciiAnimation()
        if frame._logo then
            frame._logo:SetText("")
        end
        if frame._logoBtn then
            frame._logoBtn:EnableMouse(false)
        end

        if contentPane._scrollFrame then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        if contentPane._placeholder then
            contentPane._placeholder:SetText("")
            contentPane._placeholder:Hide()
        end

        if contentPane._homeContent then
            contentPane._homeContent:Show()
        end

        if scrollContent then
            scrollContent:SetHeight(1)
        end
    else
        if contentPane._homeContent then
            contentPane._homeContent:Hide()
        end

        if wasHome then
            self:AnimateAsciiReveal()
        elseif frame._logo and frame._logo:GetText() == "" then
            frame._logo:SetText(ASCII_LOGO)
        end
        if frame._logoBtn then
            frame._logoBtn:EnableMouse(true)
        end
        if contentPane._headerTitle then
            contentPane._headerTitle:SetText(self:GetCategoryTitle(key))
            contentPane._headerTitle:Show()
        end
        if contentPane._headerSep then
            contentPane._headerSep:Show()
        end

        if contentPane._scrollFrame and contentPane._header then
            contentPane._scrollFrame:SetPoint("TOPLEFT", contentPane._header, "BOTTOMLEFT", CONTENT_PADDING, -CONTENT_PADDING)
        end

        local renderer = self._renderers and self._renderers[key]
        if renderer and scrollContent then
            if contentPane._placeholder then
                contentPane._placeholder:Hide()
            end
            renderer(self, scrollContent)
        else
            if contentPane._placeholder then
                contentPane._placeholder:Show()
                contentPane._placeholder:SetText(string.format([[
> Selected: %s

Content renderer not yet implemented.

Navigation key: "%s"
]], self:GetCategoryTitle(key), key or "nil"))
            end
            if scrollContent then
                scrollContent:SetHeight(100)
            end
        end
    end

    if contentPane._scrollFrame then
        contentPane._scrollFrame:SetVerticalScroll(0)
    end

    if contentPane._scrollbar and contentPane._scrollbar.Update then
        C_Timer.After(0.05, function()
            contentPane._scrollbar:Update()
        end)
    end

    self:UpdateCollapseAllButton()
    self:UpdateCopyFromDropdown()
end

-- Get Category Display Title (auto-derived from NavModel)

-- Sections whose children get a "Prefix: " in the title.
-- Value is the display prefix (allows abbreviation vs NavModel label).
local TITLE_PREFIX = {
    cdm        = "CDM",
    unitFrames = "Unit Frames",
    prd        = "Personal Resource",
    applyAll   = "Apply All",
    sct        = "SCT",
}

local TITLE_OVERRIDES = {
    ufToT         = "Unit Frames: ToT",
    ufFocusTarget = "Unit Frames: ToF",
}

local _titleCache

local function buildTitleCache()
    if _titleCache then return _titleCache end
    _titleCache = { home = "Home" }
    for _, section in ipairs(Navigation.NavModel) do
        local prefix = TITLE_PREFIX[section.key]
        if section.children then
            for _, child in ipairs(section.children) do
                if TITLE_OVERRIDES[child.key] then
                    _titleCache[child.key] = TITLE_OVERRIDES[child.key]
                elseif prefix then
                    _titleCache[child.key] = prefix .. ": " .. child.label
                else
                    _titleCache[child.key] = child.label
                end
            end
        end
    end
    return _titleCache
end

function UIPanel:GetCategoryTitle(key)
    if not key then return "Home" end
    return buildTitleCache()[key] or key
end
