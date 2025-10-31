local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local function EnsureCallbackContainer(frame)
    if not frame then return end
    if not frame.cbrHandles then
        if Settings and Settings.CreateCallbackHandleContainer then
            frame.cbrHandles = Settings.CreateCallbackHandleContainer()
        else
            frame.cbrHandles = {
                Unregister = function() end,
                RegisterCallback = function() end,
                AddHandle = function() end,
                SetOnValueChangedCallback = function() end,
                IsEmpty = function() return true end,
            }
        end
    end
end

local function renderProfilesManage()
    local function scaleFont(fs, baseFont, scale)
        if not fs or not baseFont then return end
        local face, size, flags = baseFont:GetFont()
        if face and size then
            fs:SetFont(face, math.floor(size * (scale or 1.0) + 0.5), flags)
        end
    end

    local function render()
        local f = panel.frame
        if not f or not f.SettingsList then return end
        local settingsList = f.SettingsList
        settingsList.Header.Title:SetText("Manage Profiles")

        local init = {}
        local widgets = panel._profileWidgets or {}
        panel._profileWidgets = widgets

        local function buildLayoutEntries()
            if not addon.Profiles or not addon.Profiles.GetLayoutMenuEntries then
                return {}
            end
            return addon.Profiles:GetLayoutMenuEntries()
        end

        local function getActiveProfileKey()
            if addon.Profiles and addon.Profiles.GetActiveProfile then
                return addon.Profiles:GetActiveProfile()
            end
            if addon.db and addon.db.GetCurrentProfile then
                return addon.db:GetCurrentProfile()
            end
            return nil
        end

        local function refreshActiveDropdown(dropdown)
            if not dropdown then return end
            local activeKey = getActiveProfileKey()
            local entries = buildLayoutEntries()
            local activeText = nil
            UIDropDownMenu_Initialize(dropdown, function(self)
                for _, entry in ipairs(entries) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = entry.text
                    info.value = entry.key
                    info.func = function()
                        if entry.preset then
                            CloseDropDownMenus()
                            local currentKey = getActiveProfileKey()
                            addon.Profiles:PromptClonePreset(entry.key, dropdown, entry.text, currentKey)
                            return
                        end
                        local key = entry.key
                        if addon.Profiles and addon.Profiles.SwitchToProfile then
                            addon.Profiles:SwitchToProfile(key, { reason = "ManageProfilesDropdown" })
                        end
                        UIDropDownMenu_SetSelectedValue(dropdown, key)
                        UIDropDownMenu_SetText(dropdown, entry.text)
                        if panel and panel.RefreshCurrentCategoryDeferred then
                            panel.RefreshCurrentCategoryDeferred()
                        end
                    end
                    info.checked = (activeKey == entry.key)
                    info.notCheckable = false
                    info.isNotRadio = false
                    info.keepShownOnClick = false
                    UIDropDownMenu_AddButton(info)
                    if activeKey == entry.key then
                        activeText = entry.text
                    end
                end
            end)
            UIDropDownMenu_SetWidth(dropdown, 220)
            UIDropDownMenu_SetSelectedValue(dropdown, activeKey)
            UIDropDownMenu_SetText(dropdown, activeText or activeKey or "Select a layout")
            addon.SettingsPanel._profileDropdown = dropdown
            if addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
                addon.SettingsPanel.UpdateProfileActionButtons()
            end
        end

        local function refreshSpecDropdown(dropdown, specID)
            if not dropdown or not specID then return end
            local assigned = addon.Profiles and addon.Profiles.GetSpecAssignment and addon.Profiles:GetSpecAssignment(specID) or nil
            local entries = buildLayoutEntries()
            UIDropDownMenu_Initialize(dropdown, function(self)
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Use active layout"
                info.value = ""
                info.func = function()
                    if panel and panel.SuspendRefresh then
                        local currentSpecID
                        if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
                            local idx = GetSpecialization()
                            if idx then currentSpecID = select(1, GetSpecializationInfo(idx)) end
                        end
                        local dur = (currentSpecID and currentSpecID == specID) and 0.4 or 0.15
                        panel.SuspendRefresh(dur)
                    end
                    if addon.Profiles and addon.Profiles.SetSpecAssignment then
                        addon.Profiles:SetSpecAssignment(specID, nil)
                    end
                    UIDropDownMenu_SetSelectedValue(dropdown, "")
                    if addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled() then
                        if addon.Profiles.OnPlayerSpecChanged then
                            addon.Profiles:OnPlayerSpecChanged()
                        end
                    end
                end
                info.checked = assigned == nil
                info.notCheckable = false
                info.isNotRadio = false
                UIDropDownMenu_AddButton(info)

                for _, entry in ipairs(entries) do
                    local dropdownInfo = UIDropDownMenu_CreateInfo()
                    dropdownInfo.text = entry.text
                    dropdownInfo.value = entry.key
                    dropdownInfo.func = function()
                        local key = entry.key
                        if panel and panel.SuspendRefresh then
                            local currentSpecID
                            if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
                                local idx = GetSpecialization()
                                if idx then currentSpecID = select(1, GetSpecializationInfo(idx)) end
                            end
                            local dur = (currentSpecID and currentSpecID == specID) and 0.4 or 0.15
                            panel.SuspendRefresh(dur)
                        end
                        if addon.Profiles and addon.Profiles.SetSpecAssignment then
                            addon.Profiles:SetSpecAssignment(specID, key)
                        end
                        UIDropDownMenu_SetSelectedValue(dropdown, key)
                        UIDropDownMenu_SetText(dropdown, entry.text)
                        if addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled() then
                            if addon.Profiles.OnPlayerSpecChanged then
                                addon.Profiles:OnPlayerSpecChanged()
                            end
                        end
                    end
                    dropdownInfo.checked = (assigned == entry.key)
                    dropdownInfo.notCheckable = false
                    dropdownInfo.isNotRadio = false
                    UIDropDownMenu_AddButton(dropdownInfo)
                end
            end)
            UIDropDownMenu_SetWidth(dropdown, 220)
            if assigned then
                local display = nil
                for _, entry in ipairs(entries) do
                    if entry.key == assigned then
                        display = entry.text
                        break
                    end
                end
                UIDropDownMenu_SetSelectedValue(dropdown, assigned)
                UIDropDownMenu_SetText(dropdown, display or assigned)
            else
                UIDropDownMenu_SetSelectedValue(dropdown, "")
                UIDropDownMenu_SetText(dropdown, "Use active layout")
            end
        end

        do
            local infoRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            infoRow.GetExtent = function() return 56 end
            infoRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if frame.ButtonContainer then frame.ButtonContainer:Hide(); frame.ButtonContainer:SetAlpha(0); frame.ButtonContainer:EnableMouse(false) end
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if frame.CreateBtn then frame.CreateBtn:Hide() end
                if frame.SpecEnableCheck then frame.SpecEnableCheck:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end
                if not frame.InfoText then
                    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, 4)
                    text:SetWidth(420)
                    text:SetJustifyH("LEFT")
                    text:SetJustifyV("TOP")
                    text:SetWordWrap(true)
                    text:SetText("ScooterMod profiles stay synchronized with Edit Mode layouts. Switch layouts here or via Edit Mode and ScooterMod will keep them in sync.")
                    scaleFont(text, GameFontHighlight, 1.2)
                    frame.InfoText = text
                else
                    frame.InfoText:Show()
                end
            end
            table.insert(init, infoRow)
        end

        do
            local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                name = "Active Layout",
                sectionKey = "ActiveLayout",
                componentId = "profilesManage",
                expanded = panel:IsSectionExpanded("profilesManage", "ActiveLayout"),
            })
            exp.GetExtent = function() return 30 end
            table.insert(init, exp)
        end

        do
            local sectionRow = Settings.CreateElementInitializer("ScooterActiveListElementTemplate")
            sectionRow.GetExtent = function() return 190 end
            sectionRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.InfoText then frame.InfoText:Hide() end
                if frame.ButtonContainer then frame.ButtonContainer:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end
                frame.IsScooterActiveLayoutRow = true

                if not frame.ActiveDropdown then
                    local dropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
                    dropdown:SetPoint("LEFT", frame, "LEFT", 28, 0)
                    dropdown.align = "RIGHT"
                    dropdown:SetScale(1.5)
                    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dropdown, 170) end
                    if dropdown.SetWidth then dropdown:SetWidth(170) end
                    frame.ActiveDropdown = dropdown
                else
                    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(frame.ActiveDropdown, 170) end
                    if frame.ActiveDropdown.SetWidth then frame.ActiveDropdown:SetWidth(170) end
                end
                refreshActiveDropdown(frame.ActiveDropdown)
                if UIDropDownMenu_SetAnchor then UIDropDownMenu_SetAnchor(frame.ActiveDropdown, 0, 0, "TOPRIGHT", frame.ActiveDropdown, "BOTTOMRIGHT") end
                if panel and panel.StyleDropdownLabel then panel.StyleDropdownLabel(frame.ActiveDropdown, 1.25) end
                if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame.ActiveDropdown) end
                local widgets = panel._profileWidgets or {}
                panel._profileWidgets = widgets
                widgets.ActiveLayoutRow = frame

                local function updateButtons()
                    local current = getActiveProfileKey()
                    local isPreset = current and addon.Profiles and addon.Profiles:IsPreset(current)
                    if frame.RenameBtn then frame.RenameBtn:SetEnabled(not not current and not isPreset) end
                    if frame.DeleteBtn then frame.DeleteBtn:SetEnabled(not not current and not isPreset) end
                    if frame.CopyBtn then frame.CopyBtn:SetEnabled(not not current) end
                end

                local function scaleButton(btn)
                    if not btn then return end
                    local w, h = btn:GetSize()
                    btn:SetSize(math.floor(w * 1.25), math.floor(h * 1.25))
                    if btn.Text and btn.Text.GetFont then
                        local face, size, flags = btn.Text:GetFont()
                        if size then btn.Text:SetFont(face, math.floor(size * 1.25 + 0.5), flags) end
                    end
                end

                if not frame.CreateBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(120, 28)
                    btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -6)
                    btn:SetText("Create")
                    btn:SetMotionScriptsWhileDisabled(true)
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        addon.Profiles:PromptCreateLayout(addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
                    end)
                    frame.CreateBtn = btn
                    scaleButton(btn)
                    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(btn) end
                end

                if not frame.RenameBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(120, 28)
                    btn:SetPoint("TOPRIGHT", frame.CreateBtn, "BOTTOMRIGHT", 0, -8)
                    btn:SetText("Rename")
                    btn:SetMotionScriptsWhileDisabled(true)
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        local current = getActiveProfileKey()
                        addon.Profiles:PromptRenameLayout(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
                    end)
                    frame.RenameBtn = btn
                    scaleButton(btn)
                    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(btn) end
                end

                if not frame.CopyBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(120, 28)
                    btn:SetPoint("TOPRIGHT", frame.RenameBtn, "BOTTOMRIGHT", 0, -8)
                    btn:SetText("Copy")
                    btn:SetMotionScriptsWhileDisabled(true)
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        local current = getActiveProfileKey()
                        if not current then return end
                        if addon.Profiles and addon.Profiles:IsPreset(current) then
                            addon.Profiles:PromptClonePreset(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown, addon.Profiles:GetLayoutDisplayText(current), current)
                        else
                            addon.Profiles:PromptCopyLayout(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
                        end
                    end)
                    frame.CopyBtn = btn
                    scaleButton(btn)
                    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(btn) end
                end

                if not frame.DeleteBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(120, 28)
                    btn:SetPoint("TOPRIGHT", frame.CopyBtn, "BOTTOMRIGHT", 0, -8)
                    btn:SetText(DELETE)
                    btn:SetMotionScriptsWhileDisabled(true)
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        local current = getActiveProfileKey()
                        addon.Profiles:ConfirmDeleteLayout(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
                    end)
                    frame.DeleteBtn = btn
                    scaleButton(btn)
                    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(btn) end
                end

                function frame:UpdateButtons()
                    updateButtons()
                end
                updateButtons()
                addon.SettingsPanel.UpdateProfileActionButtons = function()
                    if frame and frame.UpdateButtons then frame:UpdateButtons() end
                end
            end
            sectionRow:AddShownPredicate(function()
                return panel:IsSectionExpanded("profilesManage", "ActiveLayout")
            end)
            table.insert(init, sectionRow)
        end

        do
            local spacer = Settings.CreateElementInitializer("SettingsListElementTemplate")
            spacer.GetExtent = function() return 12 end
            spacer.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.InfoText then frame.InfoText:Hide() end
                if frame.ButtonContainer then frame.ButtonContainer:Hide(); frame.ButtonContainer:SetAlpha(0); frame.ButtonContainer:EnableMouse(false) end
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if frame.CreateBtn then frame.CreateBtn:Hide() end
                if frame.SpecEnableCheck then frame.SpecEnableCheck:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end
            end
            table.insert(init, spacer)
        end

        do
            local buttonRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            buttonRow.GetExtent = function() return 0 end
            buttonRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.ButtonContainer then
                    frame.ButtonContainer:Hide()
                    frame.ButtonContainer:SetAlpha(0)
                    frame.ButtonContainer:EnableMouse(false)
                end
                frame:Hide()
            end
            buttonRow:AddShownPredicate(function() return false end)
            table.insert(init, buttonRow)
        end

        do
            local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                name = "Spec Profiles",
                sectionKey = "SpecProfiles",
                componentId = "profilesManage",
                expanded = panel:IsSectionExpanded("profilesManage", "SpecProfiles"),
            })
            exp.GetExtent = function() return 30 end
            table.insert(init, exp)
        end

        do
            local enableRow = Settings.CreateElementInitializer("ScooterSpecEnableListElementTemplate")
            enableRow.GetExtent = function() return 45 end
            enableRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.InfoText then frame.InfoText:Hide() end
                if frame.EnableMouse then frame:EnableMouse(false) end
                if frame.ButtonContainer then
                    frame.ButtonContainer:Hide()
                    frame.ButtonContainer:SetAlpha(0)
                    frame.ButtonContainer:EnableMouse(false)
                end
                frame.IsScooterSpecEnabledRow = true
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if frame.CreateBtn then frame.CreateBtn:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if not frame.SpecEnableCheck then
                    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
                    cb.Text:SetText("Enable Spec Profiles")
                    if cb.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(cb.Text) end
                    cb:SetPoint("LEFT", frame, "LEFT", 16, 0)
                    cb:SetScale(1.25)
                    cb:EnableMouse(true)
                    local lvl = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
                    cb:SetFrameLevel(lvl + 100)
                    if cb.SetFrameStrata then cb:SetFrameStrata("DIALOG") end
                    if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -160, 0, 0) end
                    cb:SetScript("OnClick", function(btn)
                        local enabled = btn:GetChecked()
                        if addon.Profiles and addon.Profiles.SetSpecProfilesEnabled then
                            addon.Profiles:SetSpecProfilesEnabled(enabled)
                        end
                        if enabled and addon.Profiles and addon.Profiles.OnPlayerSpecChanged then
                            addon.Profiles:OnPlayerSpecChanged()
                        end
                        if panel and panel.RefreshCurrentCategoryDeferred then
                            panel.RefreshCurrentCategoryDeferred()
                        end
                    end)
                    frame.SpecEnableCheck = cb
                end
                if addon.Profiles and addon.Profiles.IsSpecProfilesEnabled then
                    frame.SpecEnableCheck:SetChecked(addon.Profiles:IsSpecProfilesEnabled())
                else
                    frame.SpecEnableCheck:SetChecked(false)
                end
            end
            enableRow:AddShownPredicate(function()
                return panel:IsSectionExpanded("profilesManage", "SpecProfiles")
            end)
            table.insert(init, enableRow)
        end

        local specOptions = (addon.Profiles and addon.Profiles.GetSpecOptions and addon.Profiles:GetSpecOptions()) or {}
        local SPEC_ROW_SCALE = 1.25
        local NAME_SCALE = 1.2 * SPEC_ROW_SCALE
        local DROPDOWN_SCALE = 1.1 * SPEC_ROW_SCALE
        local ICON_BASE = 28
        local ICON_SIZE = math.floor(ICON_BASE * SPEC_ROW_SCALE + 0.5)
        local specNameMaxWidth = 0
        if #specOptions > 0 then
            local measurer = panel._specMeasureFS
            if not measurer then
                measurer = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                measurer:SetAlpha(0)
                measurer:Hide()
                panel._specMeasureFS = measurer
            end
            for _, s in ipairs(specOptions) do
                measurer:SetText(s.name or ("Spec " .. tostring(s.specIndex)))
                local w = measurer:GetStringWidth() or 0
                if w > specNameMaxWidth then specNameMaxWidth = w end
            end
            specNameMaxWidth = math.floor(specNameMaxWidth * NAME_SCALE + 8.5)
        end
        for _, spec in ipairs(specOptions) do
            local specRow = Settings.CreateElementInitializer("ScooterSpecRowListElementTemplate")
            specRow.GetExtent = function() return 52 end
            specRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.InfoText then frame.InfoText:Hide() end
                if frame.ButtonContainer then
                    frame.ButtonContainer:Hide()
                    frame.ButtonContainer:SetAlpha(0)
                    frame.ButtonContainer:EnableMouse(false)
                end
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if frame.CreateBtn then frame.CreateBtn:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if not frame.SpecName then
                    local icon = frame:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(ICON_SIZE, ICON_SIZE)
                    icon:SetPoint("LEFT", frame, "LEFT", 16, 0)
                    frame.SpecIcon = icon

                    local name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
                    scaleFont(name, GameFontNormal, NAME_SCALE)
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(name) end
                    name:SetJustifyH("LEFT")
                    name:SetWordWrap(false)
                    if specNameMaxWidth and specNameMaxWidth > 0 then
                        name:SetWidth(specNameMaxWidth)
                    end
                    frame.SpecName = name

                    local dropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
                    dropdown:SetPoint("LEFT", name, "RIGHT", 16, -2)
                    dropdown.align = "LEFT"
                    dropdown:SetScale(DROPDOWN_SCALE)
                    frame.SpecDropdown = dropdown
                end
                if frame.SpecIcon then
                    if spec.icon then
                        frame.SpecIcon:SetTexture(spec.icon)
                        frame.SpecIcon:Show()
                    else
                        frame.SpecIcon:Hide()
                    end
                end
                if frame.SpecName then
                    frame.SpecName:SetText(spec.name or ("Spec " .. tostring(spec.specIndex)))
                end
                refreshSpecDropdown(frame.SpecDropdown, spec.specID)
            end
            specRow:AddShownPredicate(function()
                return panel:IsSectionExpanded("profilesManage", "SpecProfiles") and addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled()
            end)
            table.insert(init, specRow)
        end

        settingsList:Display(init)
        if settingsList.RepairDisplay then
            pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end })
        end
        settingsList:Show()
        if f.Canvas then
            f.Canvas:Hide()
        end
        if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfilesSectionVisibility then
            addon.SettingsPanel:UpdateProfilesSectionVisibility()
        end

        do
            local seen = false
            if settingsList and settingsList.GetNumChildren then
                for i = 1, settingsList:GetNumChildren() do
                    local child = select(i, settingsList:GetChildren())
                    if child and child.IsScooterSpecEnabledRow then
                        if seen then
                            child:Hide(); child:SetParent(nil)
                        else
                            seen = true
                        end
                    end
                end
            end
        end
    end

    return { mode = "list", render = render, componentId = "profilesManage" }
end

function panel.RenderProfilesManage()
    return renderProfilesManage()
end


