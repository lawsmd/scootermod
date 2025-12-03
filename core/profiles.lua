local addonName, addon = ...

addon.Profiles = addon.Profiles or {}
local Profiles = addon.Profiles

local LEO = LibStub and LibStub("LibEditModeOverride-1.0")

local DEBUG_PREFIX = "|cffa0ff00ScooterProfiles|r"

local function Debug(...)
    if not addon or not addon._dbgProfiles then return end
    local messages = {}
    for i = 1, select("#", ...) do
        messages[#messages + 1] = tostring(select(i, ...))
    end
    local msg = table.concat(messages, " ")
    if addon.Print then
        addon:Print(DEBUG_PREFIX .. " " .. msg)
    else
        print(DEBUG_PREFIX, msg)
    end
end

local function deepCopy(tbl)
    if not tbl then return {} end
    return CopyTable(tbl)
end

local function ensureLayoutsLoaded()
    if not LEO then return false end
    if not (LEO.IsReady and LEO:IsReady()) then
        return false
    end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then
                return false
            end
        else
            return false
        end
    end
    return true
end

local layoutTypeLabels = {}
if Enum and Enum.EditModeLayoutType then
    layoutTypeLabels[Enum.EditModeLayoutType.Preset] = "Preset"
    layoutTypeLabels[Enum.EditModeLayoutType.Character] = "Character"
    layoutTypeLabels[Enum.EditModeLayoutType.Account] = "Account"
    layoutTypeLabels[Enum.EditModeLayoutType.Override] = "Override"
end

local function LayoutTypeName(layoutType)
    if not layoutType then return "Unknown" end
    return layoutTypeLabels[layoutType] or ("Type" .. tostring(layoutType))
end

local function ensureEditModeFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.MakeNewLayout then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EditMode")
        end
    end
    return EditModeManagerFrame
end

local function prepareManager()
    local manager = ensureEditModeFrame()
    if not manager then return nil end
    local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    if manager.UpdateLayoutInfo and layouts then
        manager:UpdateLayoutInfo(layouts, true)
    elseif layouts then
        manager.layoutInfo = layouts
    end
    if manager.CreateLayoutTbls then
        manager:CreateLayoutTbls()
    end
    return manager
end

local function getLayouts()
    if not C_EditMode or not C_EditMode.GetLayouts then return nil end
    return C_EditMode.GetLayouts()
end

function Profiles:FindLayoutIndex(layoutName)
    local data = getLayouts()
    if not data or not data.layouts then return nil end
    for index, layout in ipairs(data.layouts) do
        if layout.layoutName == layoutName then
            return index, layout
        end
    end
    return nil
end

function Profiles:RestoreDropdownSelection(dropdown, key, displayText)
    if not dropdown then return end
    UIDropDownMenu_SetSelectedValue(dropdown, key)
    UIDropDownMenu_SetText(dropdown, displayText or key or "Select a layout")
    if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
        addon.SettingsPanel.UpdateProfileActionButtons()
    end
end

local function addLayoutToCache(self, layoutName)
    if not layoutName then return end
    self._layoutLookup = self._layoutLookup or {}
    self._layoutLookup[layoutName] = true
    self._sortedEditableLayouts = self._sortedEditableLayouts or {}
    for _, existing in ipairs(self._sortedEditableLayouts) do
        if existing == layoutName then
            return
        end
    end
    table.insert(self._sortedEditableLayouts, layoutName)
    table.sort(self._sortedEditableLayouts, function(a, b)
        return tostring(a) < tostring(b)
    end)
end

local function getCurrentSpecID()
    if type(GetSpecialization) ~= "function" then
        return nil
    end
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    if type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

local function buildDefaultProfile()
    local defaults = addon and addon.GetDefaults and addon:GetDefaults()
    local profileDefaults = defaults and defaults.profile
    return deepCopy(profileDefaults or {})
end

local function isCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    name = strtrim(name)
    if name == "" then return nil end
    return name
end

local function notifyUI()
    -- NOTE (2025-11-17): Layout/profile mutations no longer force a structural
    -- re-render of the ScooterMod settings list. The Profiles page is built to
    -- update its own rows and dropdowns in place, so we avoid calling
    -- RefreshCurrentCategoryDeferred here to prevent right-pane flicker.
end

-- Schedule robust, multi-pass sync after layout mutations to avoid stale lists
local function postMutationSync(self, reason)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    if type(GetTime) == "function" then
        self._postCopySuppressUntil = (GetTime() or 0) + 0.3
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode(reason or "PostMutation")
            else
                self:RequestSync(reason or "PostMutation")
            end
        end)
        C_Timer.After(0.2, function()
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode((reason or "PostMutation") .. "+retry")
            end
        end)
        -- After suppression window, attempt to apply any pending layout to EM
        C_Timer.After(0.35, function()
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode((reason or "PostMutation") .. "+final")
            end
        end)
    end
end

-- Attempt to clear legacy dropdown taint by bouncing a UI panel the same way the
-- library does in its ApplyChanges path. Safe out of combat; no-ops in combat.
local function clearDropdownTaint()
    if InCombatLockdown and InCombatLockdown() then return end
    if type(CloseDropDownMenus) == "function" then pcall(CloseDropDownMenus) end
    if _G.AddonList and type(ShowUIPanel) == "function" and type(HideUIPanel) == "function" then
        pcall(ShowUIPanel, _G.AddonList)
        pcall(HideUIPanel, _G.AddonList)
    end
    -- Also bounce Edit Mode Manager to clear potential stale state before user opens it
    if _G.EditModeManagerFrame and type(ShowUIPanel) == "function" and type(HideUIPanel) == "function" then
        pcall(ShowUIPanel, _G.EditModeManagerFrame)
        pcall(HideUIPanel, _G.EditModeManagerFrame)
    end
end

-- Copy all Edit Mode system settings (including anchors) from one layout to another
local function copyLayoutSettingsByName(sourceName, destName)
    if not sourceName or not destName then return false end
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then return false end
    local li = C_EditMode.GetLayouts()
    if not li or not li.layouts then return false end
    local src, dst, dstIndex
    for idx, layout in ipairs(li.layouts) do
        if layout.layoutName == sourceName then src = layout end
        if layout.layoutName == destName then dst = layout; dstIndex = idx end
    end
    -- If source is a preset, fall back to preset manager
    if not src and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == sourceName then src = layout break end
        end
    end
    if not (src and dst and dst.systems and src.systems) then return false end
    local function indexSystems(layout)
        local map = {}
        for _, sys in ipairs(layout.systems) do
            map[(sys.system or 0) .. ":" .. (sys.systemIndex or 0)] = sys
        end
        return map
    end
    local srcMap = indexSystems(src)
    for _, dsys in ipairs(dst.systems) do
        local key = (dsys.system or 0) .. ":" .. (dsys.systemIndex or 0)
        local ssys = srcMap[key]
        if ssys then
            -- Copy anchor and default-position flags
            if ssys.anchorInfo and dsys.anchorInfo then
                dsys.isInDefaultPosition = not not ssys.isInDefaultPosition
                local sa, da = ssys.anchorInfo, dsys.anchorInfo
                da.point = sa.point; da.relativePoint = sa.relativePoint
                da.offsetX = sa.offsetX; da.offsetY = sa.offsetY
                da.relativeTo = sa.relativeTo
            end
            -- Copy individual setting values by numeric id
            local svalById = {}
            if ssys.settings then
                for _, it in ipairs(ssys.settings) do
                    svalById[it.setting] = it.value
                end
            end
            if dsys.settings then
                for _, it in ipairs(dsys.settings) do
                    local v = svalById[it.setting]
                    if v ~= nil then it.value = v end
                end
            end
        end
    end
    -- Ensure the destination is the active layout so the client reflects changes
    if li.activeLayout and li.layouts[li.activeLayout] and li.layouts[li.activeLayout].layoutName ~= destName then
        for idx, layout in ipairs(li.layouts) do
            if layout.layoutName == destName then li.activeLayout = idx break end
        end
    end
    C_EditMode.SaveLayouts(li)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    return true
end

-- Apply the active profile's Edit Mode-backed settings for a single component
-- directly through the library, then persist with SaveOnly (no UI panel churn).
local function applyComponentEditModeViaLibrary(component)
    if not component or not component.frameName then return end
    local frame = _G[component.frameName]
    if not frame then return end
    if not LEO or not (LEO.IsReady and LEO:IsReady()) then return end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end end

    local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
    local function set(settingEnumOrId, value)
        if not settingEnumOrId or value == nil then return end
        pcall(LEO.SetFrameSetting, LEO, frame, settingEnumOrId, value)
    end

    local db = component.db or {}

    -- Position (anchor to CENTER with offsets from DB)
    do
        local x = tonumber(db.positionX or (component.settings.positionX and component.settings.positionX.default) or 0) or 0
        local y = tonumber(db.positionY or (component.settings.positionY and component.settings.positionY.default) or 0) or 0
        if LEO.ReanchorFrame and _G.UIParent then
            pcall(LEO.ReanchorFrame, LEO, frame, "CENTER", _G.UIParent, "CENTER", x, y)
        end
    end

    -- Orientation
    if component.settings.orientation then
        local v = (db.orientation or component.settings.orientation.default or "H")
        local emv = (v == "H") and 0 or 1
        set((EM and EM.Orientation) or 0, emv)
        if type(frame.UpdateSystemSettingOrientation) == "function" then pcall(frame.UpdateSystemSettingOrientation, frame) end
    end

    -- Columns/Rows (IconLimit)
    if component.settings.columns then
        local v = tonumber(db.columns or component.settings.columns.default or 12) or 12
        set((EM and EM.IconLimit) or 1, v)
        if type(frame.UpdateSystemSettingIconLimit) == "function" then pcall(frame.UpdateSystemSettingIconLimit, frame) end
    end

    -- Direction (IconDirection)
    if component.settings.direction then
        local dir = tostring(db.direction or component.settings.direction.default or "right")
        local orientation = tostring(db.orientation or component.settings.orientation and component.settings.orientation.default or "H")
        local emv
        if orientation == "H" then emv = (dir == "right") and 1 or 0 else emv = (dir == "up") and 1 or 0 end
        set((EM and EM.IconDirection) or 2, emv)
        if type(frame.UpdateSystemSettingIconDirection) == "function" then pcall(frame.UpdateSystemSettingIconDirection, frame) end
    end

    -- Icon Padding
    if component.settings.iconPadding then
        local v = tonumber(db.iconPadding or component.settings.iconPadding.default or 2) or 2
        set((EM and EM.IconPadding) or 4, v)
        if type(frame.UpdateSystemSettingIconPadding) == "function" then pcall(frame.UpdateSystemSettingIconPadding, frame) end
    end

    -- Icon Size (Scale) - raw 50..200 snapped to 10s
    if component.settings.iconSize then
        local v = tonumber(db.iconSize or component.settings.iconSize.default or 100) or 100
        if v < 50 then v = 50 elseif v > 200 then v = 200 end
        v = math.floor(v / 10 + 0.5) * 10
        set((EM and EM.IconSize) or 3, v)
        if type(frame.UpdateSystemSettingIconSize) == "function" then pcall(frame.UpdateSystemSettingIconSize, frame) end
    end

    -- Tracked Bars: Display Mode (BarContent) 0=both,1=icon,2=name
    if component.id == "trackedBars" and component.settings.displayMode and _G.Enum and _G.Enum.EditModeCooldownViewerSetting then
        local v = tostring(db.displayMode or component.settings.displayMode.default or "both")
        local emv = (v == "icon") and 1 or ((v == "name") and 2 or 0)
        set(_G.Enum.EditModeCooldownViewerSetting.BarContent, emv)
        if type(frame.UpdateSystemSettingBarContent) == "function" then pcall(frame.UpdateSystemSettingBarContent, frame) end
    end

    -- Opacity 50..100
    if component.settings.opacity then
        local v = tonumber(db.opacity or component.settings.opacity.default or 100) or 100
        if v < 50 then v = 50 elseif v > 100 then v = 100 end
        set((EM and EM.Opacity) or 5, v)
        if type(frame.UpdateSystemSettingOpacity) == "function" then pcall(frame.UpdateSystemSettingOpacity, frame) end
    end

    -- Visibility dropdown (0 always, 1 combat, 2 hidden)
    if component.settings.visibilityMode then
        local mode = tostring(db.visibilityMode or component.settings.visibilityMode.default or "always")
        local emv = (mode == "combat") and 1 or ((mode == "never") and 2 or 0)
        if EM and EM.VisibleSetting then set(EM.VisibleSetting, emv) else set(0, emv) end
        if type(frame.UpdateSystemSettingVisibleSetting) == "function" then pcall(frame.UpdateSystemSettingVisibleSetting, frame) end
    end

    -- Checkboxes (timers/tooltips/hide-inactive) if present on component
    if component.settings.showTimer and EM and EM.ShowTimer then
        local v = (db.showTimer == nil and component.settings.showTimer.default) or db.showTimer
        set(EM.ShowTimer, v and 1 or 0)
        if type(frame.UpdateSystemSettingShowTimer) == "function" then pcall(frame.UpdateSystemSettingShowTimer, frame) end
    end
    if component.settings.showTooltip and EM and EM.ShowTooltips then
        local v = (db.showTooltip == nil and component.settings.showTooltip.default) or db.showTooltip
        set(EM.ShowTooltips, v and 1 or 0)
        if type(frame.UpdateSystemSettingShowTooltips) == "function" then pcall(frame.UpdateSystemSettingShowTooltips, frame) end
    end
    if component.settings.hideWhenInactive and EM then
        local v = (db.hideWhenInactive == nil and component.settings.hideWhenInactive.default) or db.hideWhenInactive
        -- No stable enum seen earlier; best-effort: try UpdateSystemSettingHideWhenInactive
        if frame.settingDisplayInfo and frame.settingDisplayInfo.hideWhenInactive then
            set(frame.settingDisplayInfo.hideWhenInactive, v and 1 or 0)
        end
        if type(frame.UpdateSystemSettingHideWhenInactive) == "function" then pcall(frame.UpdateSystemSettingHideWhenInactive, frame) end
    end

    if type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
    local ic = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
    if ic and type(ic.UpdateLayout) == "function" then pcall(ic.UpdateLayout, ic) end
end

local function applyAllComponentsEditModeViaLibrary()
    if not addon or not addon.Components then return end
    for _, component in pairs(addon.Components) do
        applyComponentEditModeViaLibrary(component)
    end
    if LEO and LEO.SaveOnly then pcall(LEO.SaveOnly, LEO) end
end

-- Short suppression window after copy/clone to avoid Edit Mode writes while opening the EM UI
function Profiles:IsPostCopySuppressed()
    local untilTs = self and self._postCopySuppressUntil
    if not untilTs then return false end
    local now = GetTime and GetTime() or 0
    return now > 0 and now < untilTs
end

function Profiles:EnsurePopups()
    if Profiles._popupsInitialized then return end

    StaticPopupDialogs = StaticPopupDialogs or {}

    StaticPopupDialogs["SCOOTERMOD_CLONE_PRESET"] = {
        text = "Enter a name for the new layout based on %s:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 32,
        enterClicksFirstButton = true,
        OnShow = function(self, data)
            local textWidget = self.text or self.Text
            if textWidget and textWidget.SetFormattedText then
                textWidget:SetFormattedText(textWidget:GetText(), data.displayText or data.presetName or "Preset")
            end
            local edit = self.editBox or self.EditBox
            if edit then
                local defaultName = data.suggestedName or ((data.presetName or "Preset") .. " Copy")
                edit:SetText(defaultName)
                edit:HighlightText()
            end
        end,
        OnAccept = function(self, data)
            local edit = self.editBox or self.EditBox
            local name = edit and edit:GetText()
            local success, err = addon.Profiles:ClonePresetLayout(data, name)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                self:Hide()
                C_Timer.After(0, function()
                    addon.Profiles:PromptClonePreset(data.presetName, data.dropdown, data.displayText, data.previousKey, name)
                end)
            end
        end,
        OnCancel = function(self, data)
            addon.Profiles:RestoreDropdownSelection(data.dropdown, data.previousKey, data.previousText)
        end,
        OnHide = function(self)
            local edit = self.editBox or self.EditBox
            if edit then edit:SetText("") end
        end,
        EditBoxOnEnterPressed = function(self, data)
			-- Mirror OnAccept exactly to ensure Enter performs the rename
			local parent = self:GetParent()
			local edit = parent and (parent.editBox or parent.EditBox)
			local newName = edit and edit:GetText()
			local currentName = data and data.currentName
			local success, err = addon.Profiles:PerformRenameLayout(currentName, newName)
			if not success then
				if err and addon and addon.Print then addon:Print(err) end
				if parent and parent.Hide then parent:Hide() end
				C_Timer.After(0, function()
					addon.Profiles:PromptRenameLayout(currentName, data and data.dropdown, newName)
				end)
			else
				if parent and parent.Hide then parent:Hide() end
			end
        end,
        timeout = 0,
        whileDead = 1,
        preferredIndex = 3,
    }

    StaticPopupDialogs["SCOOTERMOD_RENAME_LAYOUT"] = {
        text = "Rename layout:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 32,
        enterClicksFirstButton = true,
        OnShow = function(self, data)
            local textWidget = self.text or self.Text
            if textWidget then
            end
            local edit = self.editBox or self.EditBox
            if edit then
                edit:SetText(data.suggested or data.currentName or "")
                edit:HighlightText()
				-- Robust fallback: ensure Enter triggers the rename even if StaticPopup plumbing changes
				local parent = self
				edit:SetScript("OnEnterPressed", function()
					local newName = edit:GetText()
					local currentName = data and data.currentName
					local success, err = addon.Profiles:PerformRenameLayout(currentName, newName)
					if not success then
						if err and addon and addon.Print then addon:Print(err) end
						if parent and parent.Hide then parent:Hide() end
						C_Timer.After(0, function()
							addon.Profiles:PromptRenameLayout(currentName, data and data.dropdown, newName)
						end)
					else
						if parent and parent.Hide then parent:Hide() end
					end
				end)
            end
        end,
        OnAccept = function(self, data)
            local edit = self.editBox or self.EditBox
            local newName = edit and edit:GetText()
            local success, err = addon.Profiles:PerformRenameLayout(data.currentName, newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                self:Hide()
                C_Timer.After(0, function()
                    addon.Profiles:PromptRenameLayout(data.currentName, data.dropdown, newName)
                end)
            end
        end,
        OnCancel = function(self, data)
            addon.Profiles:RestoreDropdownSelection(data.dropdown, data.currentName, data.currentText)
        end,
        OnHide = function(self)
            local edit = self.editBox or self.EditBox
            if edit then edit:SetText("") end
        end,
        EditBoxOnEnterPressed = function(self, data)
            local parent = self:GetParent()
            local button = parent and (parent.button1 or parent.Button1)
            if not button then
                local buttons = parent and parent.Buttons
                if buttons and buttons[1] then button = buttons[1] end
            end
            if button and button.Click then
                button:Click()
            else
                local info = parent and parent.which and StaticPopupDialogs[parent.which]
                if info and info.OnAccept then
                    info.OnAccept(parent, data)
                end
                if parent and parent.Hide then parent:Hide() end
            end
        end,
        timeout = 0,
        whileDead = 1,
        preferredIndex = 3,
    }

    StaticPopupDialogs["SCOOTERMOD_COPY_LAYOUT"] = {
        text = "Copy layout %s:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 32,
        enterClicksFirstButton = true,
        OnShow = function(self, data)
            local textWidget = self.text or self.Text
            if textWidget then
                textWidget:SetFormattedText(textWidget:GetText(), data.sourceName or "")
            end
            local edit = self.editBox or self.EditBox
            if edit then
                edit:SetText(data.suggestedName or ((data.sourceName or "Layout") .. " Copy"))
                edit:HighlightText()
            end
        end,
        OnAccept = function(self, data)
            local edit = self.editBox or self.EditBox
            local newName = edit and edit:GetText()
            local success, err = addon.Profiles:PerformCopyLayout(data.sourceName, newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                self:Hide()
                C_Timer.After(0, function()
                    addon.Profiles:PromptCopyLayout(data.sourceName, data.dropdown, newName)
                end)
            end
        end,
        OnCancel = function(self, data)
            addon.Profiles:RestoreDropdownSelection(data.dropdown, data.sourceName, data.sourceText)
        end,
        OnHide = function(self)
            local edit = self.editBox or self.EditBox
            if edit then edit:SetText("") end
        end,
        EditBoxOnEnterPressed = function(self, data)
            -- Mirror OnAccept exactly to ensure Enter performs the copy
            local parent = self:GetParent()
            local edit = parent and (parent.editBox or parent.EditBox)
            local newName = edit and edit:GetText()
            local src = (data and data.sourceName) or (parent and parent.data and parent.data.sourceName)
            local success, err = addon.Profiles:PerformCopyLayout(src, newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                if parent and parent.Hide then parent:Hide() end
                C_Timer.After(0, function()
                    addon.Profiles:PromptCopyLayout(src, (data and data.dropdown) or (parent and parent.data and parent.data.dropdown), newName)
                end)
            else
                if parent and parent.Hide then parent:Hide() end
            end
        end,
        timeout = 0,
        whileDead = 1,
        preferredIndex = 3,
    }

    StaticPopupDialogs["SCOOTERMOD_DELETE_LAYOUT"] = {
        text = "Delete layout '%s'?",
        button1 = OKAY,
        button2 = CANCEL,
        OnShow = function(self, data)
            local textWidget = self.text or self.Text
            if textWidget then
                textWidget:SetFormattedText(textWidget:GetText(), data.layoutName or "")
            end
        end,
        OnAccept = function(self, data)
            local success, err = addon.Profiles:PerformDeleteLayout(data.layoutName)
            if not success and err and addon and addon.Print then
                addon:Print(err)
            end
        end,
        OnCancel = function(self, data)
            addon.Profiles:RestoreDropdownSelection(data.dropdown, data.layoutName, data.layoutText)
        end,
        timeout = 0,
        whileDead = 1,
        preferredIndex = 3,
    }

    StaticPopupDialogs["SCOOTERMOD_CREATE_LAYOUT"] = {
        text = "Create layout:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 32,
        enterClicksFirstButton = true,
        OnShow = function(self, data)
            local edit = self.editBox or self.EditBox
            if edit then
                local defaultName = (data and data.suggestedName) or "New Layout"
                edit:SetText(defaultName)
                edit:HighlightText()
            end
        end,
        OnAccept = function(self, data)
            local edit = self.editBox or self.EditBox
            local newName = edit and edit:GetText()
            local success, err = addon.Profiles:PerformCreateLayout(newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                self:Hide()
                C_Timer.After(0, function()
                    addon.Profiles:PromptCreateLayout(data and data.dropdown, newName)
                end)
            end
        end,
        OnCancel = function(self, data)
            if data and data.dropdown and addon and addon.Profiles and addon.Profiles.db then
                local current = addon.Profiles.db:GetCurrentProfile()
                addon.Profiles:RestoreDropdownSelection(data.dropdown, current, addon.Profiles:GetLayoutDisplayText(current))
            end
        end,
        OnHide = function(self)
            local edit = self.editBox or self.EditBox
            if edit then edit:SetText("") end
        end,
        EditBoxOnEnterPressed = function(self, data)
            -- Mirror OnAccept exactly to ensure Enter performs the create
            local parent = self:GetParent()
            local edit = parent and (parent.editBox or parent.EditBox)
            local newName = edit and edit:GetText()
            local success, err = addon.Profiles:PerformCreateLayout(newName)
            if not success then
                if err and addon and addon.Print then addon:Print(err) end
                if parent and parent.Hide then parent:Hide() end
                C_Timer.After(0, function()
                    addon.Profiles:PromptCreateLayout((data and data.dropdown) or (parent and parent.data and parent.data.dropdown), newName)
                end)
            else
                if parent and parent.Hide then parent:Hide() end
            end
        end,
        timeout = 0,
        whileDead = 1,
        preferredIndex = 3,
    }

    Profiles._popupsInitialized = true
end

function Profiles:GetLayoutDisplayText(layoutName)
    if not layoutName then return nil end
    for _, entry in ipairs(self:GetLayoutMenuEntries() or {}) do
        if entry.key == layoutName then
            return entry.text
        end
    end
    return layoutName
end

function Profiles:PromptClonePreset(presetName, dropdown, displayText, previousKey, suggested)
    self:EnsurePopups()
    self:RestoreDropdownSelection(dropdown, previousKey, self:GetLayoutDisplayText(previousKey))
    StaticPopup_Show("SCOOTERMOD_CLONE_PRESET", presetName, nil, {
        presetName = presetName,
        dropdown = dropdown,
        displayText = displayText,
        previousKey = previousKey,
        previousText = self:GetLayoutDisplayText(previousKey),
        suggestedName = suggested,
    })
end

function Profiles:PromptRenameLayout(currentName, dropdown, suggested)
    if not currentName or self:IsPreset(currentName) then return end
    self:EnsurePopups()
    StaticPopup_Show("SCOOTERMOD_RENAME_LAYOUT", nil, nil, {
        currentName = currentName,
        currentText = self:GetLayoutDisplayText(currentName),
        dropdown = dropdown,
        suggested = suggested,
    })
end

function Profiles:PromptCopyLayout(sourceName, dropdown, suggested)
    if not sourceName then return end
    self:EnsurePopups()
    StaticPopup_Show("SCOOTERMOD_COPY_LAYOUT", sourceName, nil, {
        sourceName = sourceName,
        sourceText = self:GetLayoutDisplayText(sourceName),
        dropdown = dropdown,
        suggestedName = suggested,
    })
end

function Profiles:PromptCreateLayout(dropdown, suggested)
    self:EnsurePopups()
    StaticPopup_Show("SCOOTERMOD_CREATE_LAYOUT", nil, nil, {
        dropdown = dropdown,
        suggestedName = suggested,
    })
end

function Profiles:ConfirmDeleteLayout(layoutName, dropdown)
    if not layoutName or self:IsPreset(layoutName) then return end
    self:EnsurePopups()
    StaticPopup_Show("SCOOTERMOD_DELETE_LAYOUT", layoutName, nil, {
        layoutName = layoutName,
        layoutText = self:GetLayoutDisplayText(layoutName),
        dropdown = dropdown,
    })
end

local function layoutExists(name)
    return addon.Profiles._layoutLookup and addon.Profiles._layoutLookup[name]
end

local function setProfileAssignment(cfg, fromName, toName)
    if not cfg or not cfg.assignments then return end
    for specID, profile in pairs(cfg.assignments) do
        if profile == fromName then
            cfg.assignments[specID] = toName
        end
    end
end

function Profiles:ClonePresetLayout(data, rawName)
    if isCombatLocked() then
        return false, "Cannot modify layouts during combat."
    end
    if not ensureLayoutsLoaded() then
        return false, "Edit Mode layouts are not ready yet."
    end
    local presetName = data and data.presetName
    local dropdown = data and data.dropdown
    local newName = normalizeName(rawName)
    if not newName then
        return false, "A name is required."
    end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name."
    end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists."
    end

    -- COMPLETELY AVOID EditModeManagerFrame - use only C_EditMode APIs
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end
    
    -- Get the current layout structure
    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return false, "Unable to read layouts." end
    
    -- Find the preset layout to clone
    local presetLayout = nil
    for _, layout in ipairs(layoutInfo.layouts) do
        if layout.layoutName == presetName and layout.layoutType == Enum.EditModeLayoutType.Preset then
            presetLayout = layout
            break
        end
    end
    if not presetLayout and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == presetName then
                presetLayout = layout
                break
            end
        end
    end
    if not presetLayout then
        return false, "Unable to locate preset layout data."
    end
    
    -- Create a deep copy and convert to Character layout type
    local newLayout = CopyTable(presetLayout)
    newLayout.layoutType = Enum.EditModeLayoutType.Character
    newLayout.layoutName = newName
    newLayout.isPreset = nil
    newLayout.isModified = nil
    
    -- Add the new layout to the layouts array
    table.insert(layoutInfo.layouts, newLayout)
    
    -- Save directly via C_EditMode (no manager frame involvement)
    C_EditMode.SaveLayouts(layoutInfo)
    
    -- Reload library state and schedule robust sync
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "ClonePreset")

    -- Create AceDB profile with defaults
    addLayoutToCache(self, newName)
    self.db.profiles[newName] = deepCopy(self._profileTemplate)
    
    -- Defer the profile switch to avoid taint from happening in the same call stack as the copy
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            -- Now switch to the new profile normally (including Edit Mode activation)
            self:SwitchToProfile(newName, { reason = "DeferredCloneSwitch", force = true })
            
            -- Update UI after the switch
            if dropdown then
                self:RestoreDropdownSelection(dropdown, newName, self:GetLayoutDisplayText(newName))
            end
            if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
                addon.SettingsPanel.UpdateProfileActionButtons()
            end
            if addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown then
                local current = self.db:GetCurrentProfile()
                self:RestoreDropdownSelection(addon.SettingsPanel._profileDropdown, current, self:GetLayoutDisplayText(current))
            end
            notifyUI()
        end)
    else
        -- Fallback if C_Timer is unavailable
        self:SwitchToProfile(newName, { reason = "ClonePreset", force = true })
    end
    
    return true
end

function Profiles:RenameProfileData(oldName, newName)
    if not self.db or not self.db.profiles then return end
    if self.db.profiles[newName] then return end
    if self.db.profiles[oldName] then
        self.db.profiles[newName] = CopyTable(self.db.profiles[oldName])
        self.db.profiles[oldName] = nil
    end

    local sv = rawget(self.db, "sv")
    if sv and sv.profileKeys then
        for key, value in pairs(sv.profileKeys) do
            if value == oldName then
                sv.profileKeys[key] = newName
            end
        end
    end

    if self.db.keys and self.db.keys.profile == oldName then
        self.db.keys.profile = newName
        self.db.profile = self.db.profiles[newName]
    end

    local cfg = self:GetSpecConfig()
    setProfileAssignment(cfg, oldName, newName)
end

function Profiles:PerformRenameLayout(oldName, rawNewName)
    if not oldName then return false, "Select a layout to rename." end
    if self:IsPreset(oldName) then return false, "Preset layouts cannot be renamed." end
    if isCombatLocked() then return false, "Cannot rename layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local newName = normalizeName(rawNewName)
    if not newName then return false, "A name is required." end
    if newName == oldName then
        return true
    end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name."
    end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists." end

    local index, layout = self:FindLayoutIndex(oldName)
    if not index or not layout then
        return false, "Unable to locate the selected layout." end
    if layout.layoutType == Enum.EditModeLayoutType.Preset then
        return false, "Preset layouts cannot be renamed." end

    -- Rename using C_EditMode SaveLayouts path (avoids manager UI interactions)
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end
    local li = C_EditMode.GetLayouts()
    if not li or not li.layouts then return false, "Unable to read layouts." end
    local target
    for _, layout in ipairs(li.layouts) do
        if layout.layoutName == oldName then
            target = layout
            break
        end
    end
    if not target then return false, "Unable to locate the selected layout." end
    if target.layoutType == Enum.EditModeLayoutType.Preset then
        return false, "Preset layouts cannot be renamed." end
    target.layoutName = newName
    C_EditMode.SaveLayouts(li)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "RenameLayout")

    self:RenameProfileData(oldName, newName)
    if self._layoutLookup then
        self._layoutLookup[oldName] = nil
    end
    if self._sortedEditableLayouts then
        for idx = #self._sortedEditableLayouts, 1, -1 do
            if self._sortedEditableLayouts[idx] == oldName then
                table.remove(self._sortedEditableLayouts, idx)
            end
        end
    end
    addLayoutToCache(self, newName)
    self._pendingActiveLayout = newName
    if self.db:GetCurrentProfile() == oldName then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function()
                self:SwitchToProfile(newName, { reason = "DeferredRenameSwitch", force = true })
                if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
                    addon.SettingsPanel.UpdateProfileActionButtons()
                end
                if addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown then
                    local current = self.db:GetCurrentProfile()
                    self:RestoreDropdownSelection(addon.SettingsPanel._profileDropdown, current, self:GetLayoutDisplayText(current))
                end
                notifyUI()
            end)
        else
            self:SwitchToProfile(newName, { reason = "RenameLayout", force = true })
        end
    else
        self:RequestSync("RenameLayout")
    end

    if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
        addon.SettingsPanel.UpdateProfileActionButtons()
    end
    if addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown then
        local current = self.db:GetCurrentProfile()
        self:RestoreDropdownSelection(addon.SettingsPanel._profileDropdown, current, self:GetLayoutDisplayText(current))
    end
    notifyUI()
    return true
end

function Profiles:PerformCopyLayout(sourceName, rawNewName)
    if not sourceName then return false, "Select a layout to copy." end
    if isCombatLocked() then return false, "Cannot copy layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local newName = normalizeName(rawNewName)
    if not newName then return false, "A name is required." end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name." end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists." end

    -- COMPLETELY AVOID EditModeManagerFrame - use only C_EditMode APIs
    -- This approach never touches the manager frame, avoiding all taint issues
    
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end
    
    -- Get the current layout structure
    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return false, "Unable to read layouts." end
    
	-- Find the source layout in the structure (robustly after recent renames)
	local sourceLayout = nil
	for _, layout in ipairs(layoutInfo.layouts) do
		if layout.layoutName == sourceName then
			sourceLayout = layout
			break
		end
	end

	-- If not found, force library to reload and try again
	if not sourceLayout then
		if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
		layoutInfo = C_EditMode.GetLayouts()
		if layoutInfo and layoutInfo.layouts then
			for _, layout in ipairs(layoutInfo.layouts) do
				if layout.layoutName == sourceName then
					sourceLayout = layout
					break
				end
			end
		end
	end

	-- Fallback: if still not found, use the active layout's data (user is copying the current profile)
	if not sourceLayout and layoutInfo and layoutInfo.layouts and layoutInfo.activeLayout then
		sourceLayout = layoutInfo.layouts[layoutInfo.activeLayout]
	end

	-- Fallback: consult the manager's reconciled list
	if not sourceLayout then
		local mgr = prepareManager()
		if mgr and mgr.UpdateLayoutInfo then
			mgr:UpdateLayoutInfo(C_EditMode.GetLayouts(), true)
			local li2 = mgr.layoutInfo
			if li2 and li2.layouts then
				for _, layout in ipairs(li2.layouts) do
					if layout.layoutName == sourceName then
						sourceLayout = layout
						break
					end
				end
			end
		end
	end
    
    -- If source is a preset, check the preset manager as well
    if not sourceLayout and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == sourceName then
                sourceLayout = layout
                break
            end
        end
    end
    
	if not sourceLayout then
		return false, "Unable to locate the source layout." end
    
    -- Create a deep copy of the source layout
    local newLayout = CopyTable(sourceLayout)
    newLayout.layoutName = newName
    newLayout.layoutType = sourceLayout.layoutType == Enum.EditModeLayoutType.Preset 
        and Enum.EditModeLayoutType.Character 
        or sourceLayout.layoutType
    newLayout.isPreset = nil
    newLayout.isModified = nil
    
    -- Add the new layout to the layouts array
    table.insert(layoutInfo.layouts, newLayout)
    
    -- Save directly via C_EditMode (no manager frame involvement)
    C_EditMode.SaveLayouts(layoutInfo)
    
    -- Reload library state to see the new layout and schedule sync
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "CopyLayout")

    -- Verify copy persisted
    do
        local li = C_EditMode.GetLayouts()
        local found = false
        if li and li.layouts then
            for _, info in ipairs(li.layouts) do
                if info.layoutName == newName then found = true break end
            end
        end
        if not found then
            return false, "Copy failed to persist."
        end
    end

    -- Copy AceDB profile data
    if self.db and self.db.profiles and self.db.profiles[sourceName] then
        self.db.profiles[newName] = CopyTable(self.db.profiles[sourceName])
    else
        self.db.profiles[newName] = deepCopy(self._profileTemplate)
    end

    -- Update our internal caches
    addLayoutToCache(self, newName)
    
    -- Defer the profile switch to avoid taint from happening in the same call stack as the copy
    -- This is the key: the copy operation itself is clean, but switching immediately causes the warning
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            -- Now switch to the new profile normally (including Edit Mode activation)
            self:SwitchToProfile(newName, { reason = "DeferredCopySwitch", force = true })
            
            -- Update UI after the switch
            if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
                addon.SettingsPanel.UpdateProfileActionButtons()
            end
            if addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown then
                local current = self.db:GetCurrentProfile()
                self:RestoreDropdownSelection(addon.SettingsPanel._profileDropdown, current, self:GetLayoutDisplayText(current))
            end
            notifyUI()
        end)
    else
        -- Fallback if C_Timer is unavailable (shouldn't happen, but be safe)
        self:SwitchToProfile(newName, { reason = "CopyLayout", force = true })
    end
    
    return true
end

function Profiles:PerformCreateLayout(rawNewName)
    if isCombatLocked() then return false, "Cannot create layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local newName = normalizeName(rawNewName)
    if not newName then return false, "A name is required." end
    if C_EditMode and C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(newName) then
        return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name." end
    if self._layoutLookup and self._layoutLookup[newName] then
        return false, "A layout with that name already exists." end

    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then
        return false, "C_EditMode API unavailable." end

    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return false, "Unable to read layouts." end

    -- Choose a base: prefer Modern preset; fallback to active; fallback to any preset
    local base
    for _, l in ipairs(layoutInfo.layouts) do
        if l.layoutType == Enum.EditModeLayoutType.Preset and l.layoutName == "Modern" then base = l break end
    end
    if not base and layoutInfo.activeLayout and layoutInfo.layouts[layoutInfo.activeLayout] then
        base = layoutInfo.layouts[layoutInfo.activeLayout]
    end
    if not base and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}
        base = presets[1]
    end
    if not base then return false, "Unable to locate a base layout for creation." end

    local newLayout = CopyTable(base)
    newLayout.layoutName = newName
    newLayout.layoutType = Enum.EditModeLayoutType.Character
    newLayout.isPreset = nil
    newLayout.isModified = nil

    table.insert(layoutInfo.layouts, newLayout)
    C_EditMode.SaveLayouts(layoutInfo)

    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "CreateLayout")

    -- Create AceDB profile using template defaults
    addLayoutToCache(self, newName)
    self.db.profiles[newName] = deepCopy(self._profileTemplate)

    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            self:SwitchToProfile(newName, { reason = "DeferredCreateSwitch", force = true })
            if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
                addon.SettingsPanel.UpdateProfileActionButtons()
            end
            if addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown then
                local current = self.db:GetCurrentProfile()
                self:RestoreDropdownSelection(addon.SettingsPanel._profileDropdown, current, self:GetLayoutDisplayText(current))
            end
            notifyUI()
        end)
    else
        self:SwitchToProfile(newName, { reason = "CreateLayout", force = true })
    end

    return true
end

function Profiles:PerformDeleteLayout(layoutName)
    if not layoutName then return false, "Select a layout to delete." end
    if self:IsPreset(layoutName) then return false, "Preset layouts cannot be deleted." end
    if isCombatLocked() then return false, "Cannot delete layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    -- Proactively refresh the library to avoid stale lists immediately after mutations
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    local index, layout = self:FindLayoutIndex(layoutName)
    -- Do not fail early on a stale C_EditMode list; manager lookup below is authoritative

    local currentProfile = self.db:GetCurrentProfile()
    if currentProfile == layoutName then
        local fallback
        for _, entry in ipairs(self:GetLayoutMenuEntries() or {}) do
            if entry.key ~= layoutName and not entry.preset then
                fallback = entry.key
                break
            end
        end
        if not fallback then
            local tempName = "New Layout"
            local suffix = 1
            while self._layoutLookup and self._layoutLookup[tempName] do
                suffix = suffix + 1
                tempName = "New Layout " .. suffix
            end
            local success = self:ClonePresetLayout({ presetName = "Modern", dropdown = addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown }, tempName)
            if success then
                fallback = tempName
            end
        end
        if not fallback or fallback == layoutName then
            return false, "Unable to select a replacement layout before deleting." end
        self:SwitchToProfile(fallback, { reason = "DeleteFallback", force = true })
    end

    -- Delete via Blizzard's Edit Mode manager using a combined index to avoid preset offsets
    local li = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    if not li or not li.layouts then return false, "Unable to read layouts." end
    local mgr = prepareManager()
    if not mgr or not mgr.DeleteLayout or not mgr.UpdateLayoutInfo then return false, "Edit Mode manager unavailable." end
    mgr:UpdateLayoutInfo(li, true)
    local combinedIndex
    local targetInfo
    for i, info in ipairs(mgr.layoutInfo and mgr.layoutInfo.layouts or {}) do
        if info.layoutName == layoutName then
            targetInfo = info
            if info.layoutType ~= Enum.EditModeLayoutType.Preset then combinedIndex = i break end
        end
    end
    if targetInfo and targetInfo.layoutType == Enum.EditModeLayoutType.Preset then return false, "Preset layouts cannot be deleted." end
    if not combinedIndex then return false, "Layout not found in manager list." end
    mgr:DeleteLayout(combinedIndex)
    -- Verify via fresh read
    li = C_EditMode.GetLayouts()
    local still = false
    for _, info in ipairs(li.layouts or {}) do if info.layoutName == layoutName then still = true break end end
    if still then return false, "Delete failed to persist; layout still exists." end

    -- Refresh library/cache and UI after successful delete
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    postMutationSync(self, "DeleteLayout")

    if self.db and self.db.profiles then
        self.db.profiles[layoutName] = nil
    end
    if self._layoutLookup then
        self._layoutLookup[layoutName] = nil
    end
    if self._sortedEditableLayouts then
        for i = #self._sortedEditableLayouts, 1, -1 do
            if self._sortedEditableLayouts[i] == layoutName then
                table.remove(self._sortedEditableLayouts, i)
            end
        end
    end
    local sv = rawget(self.db, "sv")
    if sv and sv.profileKeys then
        for key, value in pairs(sv.profileKeys) do
            if value == layoutName then
                sv.profileKeys[key] = nil
            end
        end
    end
    local cfg = self:GetSpecConfig()
    if cfg and cfg.assignments then
        for specID, profileName in pairs(cfg.assignments) do
            if profileName == layoutName then
                cfg.assignments[specID] = nil
            end
        end
    end

    self:RequestSync("DeleteLayout")
    if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
        addon.SettingsPanel.UpdateProfileActionButtons()
    end
    if addon and addon.SettingsPanel and addon.SettingsPanel._profileDropdown then
        local current = self.db:GetCurrentProfile()
        self:RestoreDropdownSelection(addon.SettingsPanel._profileDropdown, current, self:GetLayoutDisplayText(current))
    end
    notifyUI()
    if addon and addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
        addon.EditMode.RefreshSyncAndNotify("DeleteLayout")
    end
    return true
end

function Profiles:DebugDumpLayouts(context)
    if not addon or not addon._dbgProfiles then return end
    if not C_EditMode or not C_EditMode.GetLayouts then return end
    local layoutData = C_EditMode.GetLayouts()
    if not layoutData or not layoutData.layouts then return end

    local lines = {}
    for index, layout in ipairs(layoutData.layouts) do
        local name = layout.layoutName or ("<unnamed " .. tostring(index) .. ">")
        local lType = LayoutTypeName(layout.layoutType)
        local modifier = layout.isPreset and "preset" or (layout.layoutType == Enum.EditModeLayoutType.Preset and "preset" or "custom")
        local dirty = layout.isModified and "modified" or "clean"
        lines[#lines + 1] = string.format("[%d] %s (%s, %s, %s)", index, name, lType, modifier, dirty)
    end

    local activeIndex = layoutData.activeLayout
    local activeLayout = layoutData.layouts[activeIndex]
    if activeLayout then
        Debug(string.format("Layouts(%s): active index=%d name=%s type=%s %s", context or "?", activeIndex or -1, tostring(activeLayout.layoutName), LayoutTypeName(activeLayout.layoutType), activeLayout.isModified and "modified" or "clean"))
    else
        Debug(string.format("Layouts(%s): active index=%s (missing entry)", context or "?", tostring(activeIndex)))
    end
    Debug("Layouts detail:", table.concat(lines, " | "))
end

function Profiles:Initialize()
    if self._initialized then
        return
    end

    if not addon or not addon.db then
        return
    end

    self.db = addon.db
    self._knownLayouts = {}
    self._layoutLookup = {}
    self._presetLookup = {}
    self._profileTemplate = buildDefaultProfile()
    self._pendingActiveLayout = nil
    self._pendingRefreshReason = "Initialize"
    self._lastPendingApply = 0
    self._lastRequestedLayout = nil
    self._initialized = true
    Debug("Initialize")

    if self.db.RegisterCallback then
        self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
        self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileCopied")
        self.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")
        self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileDeleted")
        self.db.RegisterCallback(self, "OnNewProfile", "OnNewProfile")
    end

    self:RequestSync("Initialize")
end

function Profiles:OnNewProfile(_, profileKey)
    if not profileKey then
        return
    end
    self:EnsureProfileExists(profileKey)
end

function Profiles:OnProfileChanged(_, _, newProfileKey)
    if self._suppressProfileCallback then
        return
    end
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    self._lastActiveLayout = newProfileKey
    self:RequestSync("ProfileChanged")
end

function Profiles:OnProfileCopied(_, _, sourceKey)
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    self:RequestSync("ProfileCopied")
end

function Profiles:OnProfileReset()
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    self:RequestSync("ProfileReset")
end

function Profiles:OnProfileDeleted(_, _, profileKey)
    if profileKey and self._layoutLookup then
        self._layoutLookup[profileKey] = nil
    end
    self:RequestSync("ProfileDeleted")
end

function Profiles:IsReady()
    return self._initialized and ensureLayoutsLoaded()
end

function Profiles:RequestSync(reason)
    if ensureLayoutsLoaded() then
        self:RefreshFromEditMode(reason or "RequestSync")
        self._pendingRefreshReason = nil
        return
    end
    self._pendingRefreshReason = reason or self._pendingRefreshReason or "RequestSync"
end

function Profiles:TryPendingSync()
    if self._pendingRefreshReason and ensureLayoutsLoaded() then
        local reason = self._pendingRefreshReason
        self._pendingRefreshReason = nil
        self:RefreshFromEditMode(reason or "PendingSync")
    end
end

function Profiles:GetSpecConfig()
    if not self.db or not self.db.char then
        return nil
    end
    local char = self.db.char
    char.specProfiles = char.specProfiles or {}
    local cfg = char.specProfiles
    if cfg.assignments == nil then
        cfg.assignments = {}
    end
    return cfg
end

function Profiles:IsSpecProfilesEnabled()
    local cfg = self:GetSpecConfig()
    return cfg and cfg.enabled or false
end

function Profiles:SetSpecProfilesEnabled(enabled)
    local cfg = self:GetSpecConfig()
    if cfg then
        cfg.enabled = not not enabled
    end
end

function Profiles:SetSpecAssignment(specID, profileKey)
    if not specID then
        return
    end
    local cfg = self:GetSpecConfig()
    if not cfg then
        return
    end
    if type(profileKey) ~= "string" or profileKey == "" then
        cfg.assignments[specID] = nil
    else
        cfg.assignments[specID] = profileKey
    end
end

function Profiles:GetSpecAssignment(specID)
    local cfg = self:GetSpecConfig()
    if not cfg or not cfg.assignments then
        return nil
    end
    return cfg.assignments[specID]
end

function Profiles:PruneSpecAssignments()
    local cfg = self:GetSpecConfig()
    if not cfg or not cfg.assignments then
        return
    end
    for specID, profileKey in pairs(cfg.assignments) do
        if profileKey and not self._layoutLookup[profileKey] then
            cfg.assignments[specID] = nil
        end
    end
end

function Profiles:GetAvailableLayouts()
    local editable = {}
    local presets = {}
    for _, name in ipairs(self._sortedEditableLayouts or {}) do
        table.insert(editable, name)
    end
    for _, name in ipairs(self._sortedPresetLayouts or {}) do
        table.insert(presets, name)
    end
    return editable, presets
end

function Profiles:GetLayoutMenuEntries()
    local entries = {}
    local editable, presets = self:GetAvailableLayouts()

    for _, name in ipairs(editable) do
        table.insert(entries, {
            key = name,
            text = name,
            preset = false,
        })
    end

    for _, name in ipairs(presets) do
        table.insert(entries, {
            key = name,
            text = string.format("%s (Preset)", name),
            preset = true,
        })
    end

    return entries
end

function Profiles:IsPreset(profileKey)
    return self._presetLookup[profileKey] or false
end

function Profiles:EnsureProfileExists(profileKey, opts)
    if not profileKey or not self.db or not self.db.profiles then
        return
    end
    if self.db.profiles[profileKey] then
        if opts and opts.preset then
            self.db.profiles[profileKey].__preset = true
        end
        Debug("EnsureProfileExists reuse", profileKey, opts and opts.preset and "(preset)" or "")
        return
    end

    local template
    if opts and opts.copyFrom and self.db.profiles[opts.copyFrom] then
        template = deepCopy(self.db.profiles[opts.copyFrom])
    else
        template = deepCopy(self._profileTemplate)
    end

    if opts and opts.preset then
        template.__preset = true
    end

    self.db.profiles[profileKey] = template
    Debug("EnsureProfileExists created", profileKey, opts and opts.preset and "(preset)" or "", opts and opts.copyFrom and ("copy=" .. tostring(opts.copyFrom)) or "")
end

function Profiles:_setActiveProfile(profileKey, opts)
    if not profileKey or not self.db then
        return
    end
    opts = opts or {}
    -- If switching due to a live spec change, briefly suppress settings panel refresh to avoid flicker
    if opts.reason == "SpecChanged" and addon and addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then
        addon.SettingsPanel.SuspendRefresh(0.4)
    end
    local current = self.db:GetCurrentProfile()
    Debug("_setActiveProfile", profileKey, "current=" .. tostring(current), opts.skipLayout and "[skipLayout]" or "", opts.force and "[force]" or "")

    self:EnsureProfileExists(profileKey, { preset = self:IsPreset(profileKey) })

    -- Suppress SCT font change popup during profile switches
    addon._profileSwitchInProgress = true

    if current ~= profileKey or opts.force then
        self._suppressProfileCallback = true
        self.db:SetProfile(profileKey)
        self._suppressProfileCallback = false
        addon:LinkComponentsToDB()
        addon:ApplyStyles()
    else
        addon:LinkComponentsToDB()
        addon:ApplyStyles()
    end

    -- Clear the suppression flag after profile switch completes
    addon._profileSwitchInProgress = false

    self._lastRequestedLayout = profileKey

    if not opts.skipLayout and ensureLayoutsLoaded() and self._layoutLookup[profileKey] then
        -- Suppress EM writes during the brief post-copy window to avoid blocked-action warnings
		if self:IsPostCopySuppressed() then
			self._pendingActiveLayout = profileKey
			Debug("_setActiveProfile suppressed EM write; pending set", profileKey)
			return
		end
		-- Ensure library state is current before switching layouts
		if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
		local names = (LEO and LEO.GetEditableLayoutNames and LEO:GetEditableLayoutNames()) or {}
		local found = false
		for _, n in ipairs(names) do if n == profileKey then found = true break end end
		if not found then
			self._pendingActiveLayout = profileKey
			Debug("Library missing target layout; deferring EM apply", profileKey)
			return
		end
		local active = LEO:GetActiveLayout()
        if active ~= profileKey then
            self._pendingActiveLayout = profileKey
            LEO:SetActiveLayout(profileKey)
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            Debug("_setActiveProfile queued layout apply", profileKey, "previousActive=" .. tostring(active))
        else
            self._pendingActiveLayout = nil
            Debug("_setActiveProfile layout already active", profileKey)
        end
    end

    if addon and addon._dbgProfiles and C_Timer and C_Timer.After then
        local targetName = profileKey
        C_Timer.After(0.2, function()
            if addon and addon._dbgProfiles and LEO and LEO.GetActiveLayout then
                local nowActive = LEO:GetActiveLayout()
                Debug("Active layout after switch", "target=" .. tostring(targetName), "current=" .. tostring(nowActive))
            end
        end)
    end

    self._lastActiveLayout = profileKey
end

function Profiles:SwitchToProfile(profileKey, opts)
    if not profileKey then
        return
    end
    opts = opts or {}
    Debug("SwitchToProfile", profileKey, opts.reason and ("reason=" .. tostring(opts.reason)) or "", opts.skipLayout and "[skipLayout]" or "")
    if not ensureLayoutsLoaded() then
        self:EnsureProfileExists(profileKey)
        self.db:SetProfile(profileKey)
        addon:LinkComponentsToDB()
        addon:ApplyStyles()
        self._pendingActiveLayout = profileKey
        self._pendingRefreshReason = "DeferredSwitch"
        Debug("SwitchToProfile deferred pending sync", profileKey)
        return
    end
    if not self._layoutLookup[profileKey] then
        -- Allow switching to existing AceDB profile even if layout is missing,
        -- but do not attempt to adjust Edit Mode.
        opts.skipLayout = true
        Debug("SwitchToProfile missing layout lookup entry, skipping EM interaction", profileKey)
    end
    self:_setActiveProfile(profileKey, opts)
    self:PruneSpecAssignments()
    if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
        addon.SettingsPanel.UpdateProfileActionButtons()
    end
end

function Profiles:RefreshFromEditMode(origin)
    if not ensureLayoutsLoaded() then
        Debug("RefreshFromEditMode aborted layouts not ready", origin or "?")
        return
    end

    local editableLayouts = LEO:GetEditableLayoutNames() or {}
    local presetLayouts = LEO:GetPresetLayoutNames() or {}
    local activeLayout = LEO:GetActiveLayout()
    Debug("RefreshFromEditMode", origin or "?", "active=" .. tostring(activeLayout), "pending=" .. tostring(self._pendingActiveLayout))

    table.sort(editableLayouts, function(a, b) return tostring(a) < tostring(b) end)
    table.sort(presetLayouts, function(a, b) return tostring(a) < tostring(b) end)

    wipe(self._layoutLookup)
    wipe(self._presetLookup)

    self._sortedEditableLayouts = {}
    self._sortedPresetLayouts = {}

    for _, name in ipairs(editableLayouts) do
        self._layoutLookup[name] = true
        table.insert(self._sortedEditableLayouts, name)
        self:EnsureProfileExists(name, { copyFrom = self._lastActiveLayout })
    end

    for _, name in ipairs(presetLayouts) do
        self._layoutLookup[name] = true
        self._presetLookup[name] = true
        table.insert(self._sortedPresetLayouts, name)
        self:EnsureProfileExists(name, { preset = true })
    end

    self:PruneSpecAssignments()
    if addon and addon._dbgProfiles then
        Debug("Editable:" , table.concat(self._sortedEditableLayouts, ", "))
        Debug("Presets:" , table.concat(self._sortedPresetLayouts, ", "))
    end

    self:DebugDumpLayouts(origin or "Refresh")

    local pending = self._pendingActiveLayout
    if pending and not self._layoutLookup[pending] then
        self._pendingActiveLayout = nil
        pending = nil
        Debug("Pending layout cleared; no lookup entry")
    end
    local currentProfile = self.db:GetCurrentProfile()
    Debug("Refresh state", "profile=" .. tostring(currentProfile), "active=" .. tostring(activeLayout), "pending=" .. tostring(pending))
    if pending and self._layoutLookup[pending] and activeLayout ~= pending then
        if currentProfile ~= pending then
            self:_setActiveProfile(pending, { skipLayout = true, force = true })
            Debug("Applied pending profile while awaiting EM", pending)
        end
        local now = GetTime and GetTime() or 0
        if not self:IsPostCopySuppressed() and (now == 0 or (now - (self._lastPendingApply or 0)) > 0.5) then
            if LEO and LEO.SetActiveLayout then
                pcall(LEO.SetActiveLayout, LEO, pending)
            end
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            self._lastPendingApply = now
            Debug("Re-applied pending layout to Edit Mode", pending)
        else
            Debug("Suppressed EM re-apply during post-copy window", pending)
        end
        if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
            addon.SettingsPanel.RefreshCurrentCategoryDeferred()
        end
        return
    end

    if activeLayout and self._layoutLookup[activeLayout] then
        local options = { skipLayout = true }
        if self._pendingActiveLayout and self._pendingActiveLayout ~= activeLayout then
            options.skipLayout = self:IsPostCopySuppressed() and true or false
            options.force = true
        end
        self:_setActiveProfile(activeLayout, options)
        Debug("Synced active layout from Edit Mode", activeLayout)
    else
        local current = self.db:GetCurrentProfile()
        if current and self._layoutLookup[current] then
            if activeLayout ~= current then
                self:_setActiveProfile(current, { force = true })
                Debug("Forced Edit Mode to current profile", current, "was", tostring(activeLayout))
            end
        elseif self._sortedEditableLayouts[1] then
            self:SwitchToProfile(self._sortedEditableLayouts[1], { force = true })
            Debug("Fallback to first editable layout", self._sortedEditableLayouts[1])
        end
    end

    if activeLayout and self._pendingActiveLayout == activeLayout then
        self._pendingActiveLayout = nil
        Debug("Cleared pending flag; layout now active", activeLayout)
    end

    if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
        addon.SettingsPanel.RefreshCurrentCategoryDeferred()
    end
end

function Profiles:GetActiveProfile()
    return self.db and self.db:GetCurrentProfile()
end

function Profiles:IsActiveProfilePreset()
    local active = self:GetActiveProfile()
    if not active then
        return false
    end
    return self:IsPreset(active)
end

function Profiles:OnPlayerSpecChanged()
    if not self:IsSpecProfilesEnabled() then
        return
    end
    local specID = getCurrentSpecID()
    if not specID then
        return
    end
    local targetProfile = self:GetSpecAssignment(specID)
    if not targetProfile then
        return
    end
    if addon.db:GetCurrentProfile() == targetProfile then
        return
    end
    if not self._layoutLookup[targetProfile] then
        return
    end
    self:SwitchToProfile(targetProfile, { reason = "SpecChanged" })
end

function Profiles:GetSpecOptions()
    local options = {}
    if type(GetNumSpecializations) ~= "function" then
        return options
    end
    local total = GetNumSpecializations() or 0
    for index = 1, total do
        local specID, specName, _, specIcon = GetSpecializationInfo(index)
        if specID then
            table.insert(options, {
                specIndex = index,
                specID = specID,
                name = specName or ("Spec " .. tostring(index)),
                icon = specIcon,
            })
        end
    end
    return options
end

return Profiles
