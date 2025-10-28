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
    if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
        addon.SettingsPanel.RefreshCurrentCategoryDeferred()
    end
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
                -- Ensure pressing Enter accepts the dialog even if StaticPopup plumbing changes
                local parent = self
                edit:SetScript("OnEnterPressed", function()
                    local btn = parent.button1 or parent.Button1
                    if not btn then
                        local buttons = parent.Buttons
                        if buttons and buttons[1] then btn = buttons[1] end
                    end
                    if btn and btn.Click then
                        btn:Click()
                    else
                        local info = parent.which and StaticPopupDialogs[parent.which]
                        if info and info.OnAccept then
                            info.OnAccept(parent, data)
                        end
                        if parent.Hide then parent:Hide() end
                    end
                end)
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

    local manager = prepareManager()
    if not manager or not manager.MakeNewLayout then
        return false, "Edit Mode manager unavailable."
    end

    local presetCopy
    local layouts = getLayouts()
    if layouts and layouts.layouts then
        for _, layout in ipairs(layouts.layouts) do
            if layout.layoutName == presetName and layout.layoutType == Enum.EditModeLayoutType.Preset then
                presetCopy = CopyTable(layout)
                break
            end
        end
    end
    if not presetCopy and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == presetName then
                presetCopy = CopyTable(layout)
                break
            end
        end
    end
    if not presetCopy then
        return false, "Unable to locate preset layout data."
    end

    presetCopy.layoutType = Enum.EditModeLayoutType.Character
    presetCopy.layoutName = newName
    presetCopy.isPreset = nil
    presetCopy.isModified = nil

    manager:MakeNewLayout(CopyTable(presetCopy), Enum.EditModeLayoutType.Character, newName, false)
    prepareManager()
    if LEO and LEO.LoadLayouts then
        LEO:LoadLayouts()
    end

    addLayoutToCache(self, newName)
    self.db.profiles[newName] = deepCopy(self._profileTemplate)
    self._pendingActiveLayout = newName
    self:SwitchToProfile(newName, { reason = "ClonePreset", force = true })
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

    local manager = prepareManager()
    if not manager or not manager.RenameLayout then
        return false, "Edit Mode manager unavailable." end

    manager:RenameLayout(index, newName)
    prepareManager()
    if LEO and LEO.LoadLayouts then
        LEO:LoadLayouts()
    end

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
        self:SwitchToProfile(newName, { reason = "RenameLayout", force = true })
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

    local index, layout = self:FindLayoutIndex(sourceName)
    if not index or not layout then
        return false, "Unable to locate the source layout." end

    local manager = prepareManager()
    if not manager or not manager.MakeNewLayout then
        return false, "Edit Mode manager unavailable." end

    manager:MakeNewLayout(CopyTable(layout), layout.layoutType or Enum.EditModeLayoutType.Character, newName, false)
    prepareManager()
    if LEO and LEO.LoadLayouts then
        LEO:LoadLayouts()
    end

    -- Verify copy persisted in Blizzard's layout list
    do
        local li = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
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

    if self.db and self.db.profiles and self.db.profiles[sourceName] then
        self.db.profiles[newName] = CopyTable(self.db.profiles[sourceName])
    else
        self.db.profiles[newName] = deepCopy(self._profileTemplate)
    end

    addLayoutToCache(self, newName)
    self._pendingActiveLayout = newName
    -- Avoid immediate Edit Mode switch to prevent race with library's layout cache; let RefreshFromEditMode apply it
    self:SwitchToProfile(newName, { reason = "CopyLayout", force = true, skipLayout = true })
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

function Profiles:PerformDeleteLayout(layoutName)
    if not layoutName then return false, "Select a layout to delete." end
    if self:IsPreset(layoutName) then return false, "Preset layouts cannot be deleted." end
    if isCombatLocked() then return false, "Cannot delete layouts during combat." end
    if not ensureLayoutsLoaded() then return false, "Edit Mode layouts are not ready." end

    local index, layout = self:FindLayoutIndex(layoutName)
    if not index or not layout then
        return false, "Unable to locate the selected layout." end

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
    for i, info in ipairs(mgr.layoutInfo and mgr.layoutInfo.layouts or {}) do
        if info.layoutName == layoutName and info.layoutType ~= Enum.EditModeLayoutType.Preset then combinedIndex = i break end
    end
    if not combinedIndex then return false, "Layout not found in manager list." end
    mgr:DeleteLayout(combinedIndex)
    -- Verify via fresh read
    li = C_EditMode.GetLayouts()
    local still = false
    for _, info in ipairs(li.layouts or {}) do if info.layoutName == layoutName then still = true break end end
    if still then return false, "Delete failed to persist; layout still exists." end

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
    local current = self.db:GetCurrentProfile()
    Debug("_setActiveProfile", profileKey, "current=" .. tostring(current), opts.skipLayout and "[skipLayout]" or "", opts.force and "[force]" or "")

    self:EnsureProfileExists(profileKey, { preset = self:IsPreset(profileKey) })

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

    self._lastRequestedLayout = profileKey

    if not opts.skipLayout and ensureLayoutsLoaded() and self._layoutLookup[profileKey] then
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
        if now == 0 or (now - (self._lastPendingApply or 0)) > 0.5 then
            if LEO and LEO.SetActiveLayout then
                pcall(LEO.SetActiveLayout, LEO, pending)
            end
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            self._lastPendingApply = now
            Debug("Re-applied pending layout to Edit Mode", pending)
        end
        if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
            addon.SettingsPanel.RefreshCurrentCategoryDeferred()
        end
        return
    end

    if activeLayout and self._layoutLookup[activeLayout] then
        local options = { skipLayout = true }
        if self._pendingActiveLayout and self._pendingActiveLayout ~= activeLayout then
            options.skipLayout = false
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
