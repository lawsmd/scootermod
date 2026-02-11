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

--------------------------------------------------------------------------------
-- Edit Mode Back-Sync Handler
--------------------------------------------------------------------------------
-- Called by addon.EditMode when Edit Mode writes values back to ScooterMod.
-- Marks the affected component for refresh and triggers re-render if visible.
--------------------------------------------------------------------------------

-- Lookup table mapping componentId to navigation key
local COMPONENT_TO_NAV_KEY = {
    essentialCooldowns = "essentialCooldowns",
    utilityCooldowns   = "utilityCooldowns",
    trackedBuffs       = "trackedBuffs",
    trackedBars        = "trackedBars",
    cdmQoL             = "cdmQoL",
    -- Unit Frames
    ufPlayer = "ufPlayer",
    ufTarget = "ufTarget",
    ufFocus  = "ufFocus",
    ufPet    = "ufPet",
    ufToT    = "ufToT",
    ufBoss   = "ufBoss",
    -- Buffs/Debuffs
    buffs   = "buffs",
    debuffs = "debuffs",
    -- Group Frames
    gfParty = "gfParty",
    gfRaid  = "gfRaid",
    -- Action Bars (actual componentIds from editmode are actionBar1-8, not ab1-8)
    actionBar1 = "actionBar1",
    actionBar2 = "actionBar2",
    actionBar3 = "actionBar3",
    actionBar4 = "actionBar4",
    actionBar5 = "actionBar5",
    actionBar6 = "actionBar6",
    actionBar7 = "actionBar7",
    actionBar8 = "actionBar8",
    -- Micro/Menu bar
    microBar = "microBar",
    -- Damage Meter
    damageMeter = "damageMeter",
    -- Objective Tracker
    objectiveTracker = "objectiveTracker",
}

function UIPanel:HandleEditModeBackSync(componentId, settingId)
    if not componentId then return end

    -- Mark component as needing refresh
    self._pendingBackSync[componentId] = true

    -- Map componentId to navigation key via lookup table
    local categoryKey = COMPONENT_TO_NAV_KEY[componentId]

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

    -- 4b. Clean up Profiles > Import/Export state-based content
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
        profilesImportExport = "Import/Export",
        applyAllFonts = "Apply All: Fonts",
        applyAllTextures = "Apply All: Bar Textures",
        damageMeter = "Damage Meters",
        tooltip = "Tooltip",
        objectiveTracker = "Objective Tracker",
        minimap = "Minimap",
        chat = "Chat",
        misc = "Misc.",
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
