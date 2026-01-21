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

    local function bumpFontByPercent(fs, percent)
        if not fs or type(fs.GetFont) ~= "function" then return end
        local face, size, flags = fs:GetFont()
        size = tonumber(size)
        if not face or not size then return end
        local mult = 1.0 + (tonumber(percent) or 0)
        fs:SetFont(face, math.floor(size * mult + 0.5), flags)
    end

    local function render()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end
        if right.SetTitle then
            right:SetTitle("Manage Profiles")
        end

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
            UIDropDownMenu_SetWidth(dropdown, 180)
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
            -- Spec Profiles requires explicit assignments; if none exists yet, default the UI
            -- display to the active profile (the enable flow seeds assignments for all specs).
            local selectedKey = assigned
            if not selectedKey and addon.Profiles and addon.Profiles.GetActiveProfile then
                selectedKey = addon.Profiles:GetActiveProfile()
            end
            local display = nil
            if selectedKey then
                for _, entry in ipairs(entries) do
                    if entry.key == selectedKey then
                        display = entry.text
                        break
                    end
                end
            end
            UIDropDownMenu_SetSelectedValue(dropdown, selectedKey)
            UIDropDownMenu_SetText(dropdown, display or selectedKey or "Select a layout")
        end

        do
            local infoRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            infoRow.GetExtent = function() return 56 end
            infoRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if frame.ButtonContainer then frame.ButtonContainer:Hide(); frame.ButtonContainer:SetAlpha(0); frame.ButtonContainer:EnableMouse(false) end
                if frame.ActiveLayoutLabel then frame.ActiveLayoutLabel:Hide() end
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if frame.CreateBtn then frame.CreateBtn:Hide() end
                if frame.SpecEnableCheck then frame.SpecEnableCheck:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end
                if frame.DeleteProfileLabel then frame.DeleteProfileLabel:Hide() end
                if frame.DeleteProfileDropdown then frame.DeleteProfileDropdown:Hide() end
                if not frame.InfoText then
                    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, 4)
                    text:SetWidth(420)
                    text:SetJustifyH("LEFT")
                    text:SetJustifyV("TOP")
                    text:SetWordWrap(true)
                    text:SetText("ScooterMod profiles stay synchronized with Edit Mode layouts. Switch layouts here or via Edit Mode and ScooterMod will keep them in sync.")
                    -- Apply Roboto theming for consistency with other labels
                    if panel and panel.ApplyRoboto then
                        panel.ApplyRoboto(text)
                    else
                        scaleFont(text, GameFontHighlight, 1.2)
                    end
                    -- Increase readability: bump disclaimer font size by +20%
                    bumpFontByPercent(text, 0.20)
                    frame.InfoText = text
                else
                    frame.InfoText:Show()
                end
            end
            table.insert(init, infoRow)
        end

        -- Reload warning is now a fixed footer message (non-scrolling) so it doesn't
        -- feel "in the flow" and can't be overlapped by right-pane scrolling content.

        -- Active Layout controls (parent-level, no collapsible section)
        do
            local activeRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            activeRow.GetExtent = function() return 140 end
            activeRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                -- Hide standard template elements
                if frame.Text then frame.Text:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if frame.ButtonContainer then frame.ButtonContainer:Hide(); frame.ButtonContainer:SetAlpha(0); frame.ButtonContainer:EnableMouse(false) end
                -- Hide elements from other row types that may leak via recycling
                if frame.InfoText then frame.InfoText:Hide() end
                if frame.ActiveTestText then frame.ActiveTestText:Hide() end
                if frame.DeleteProfileLabel then frame.DeleteProfileLabel:Hide() end
                if frame.DeleteProfileDropdown then frame.DeleteProfileDropdown:Hide() end
                if frame.SpecEnableCheck then frame.SpecEnableCheck:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end

                -- Centered dropdown
                if not frame.ActiveDropdown then
                    local dropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
                    dropdown:SetPoint("TOP", frame, "TOP", 0, -8)
                    dropdown:SetScale(1.5)
                    UIDropDownMenu_SetWidth(dropdown, 220)
                    frame.ActiveDropdown = dropdown
                end
                refreshActiveDropdown(frame.ActiveDropdown)
                if panel and panel.StyleDropdownLabel then panel.StyleDropdownLabel(frame.ActiveDropdown, 1.25) end
                if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame.ActiveDropdown) end
                frame.ActiveDropdown:Show()

                -- Store reference for external access
                addon.SettingsPanel._profileDropdown = frame.ActiveDropdown

                -- Button helper for styling
                local function styleButton(btn)
                    if not btn then return end
                    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(btn) end
                end

                -- Button state helper
                local function updateButtons()
                    local current = getActiveProfileKey()
                    local isPreset = current and addon.Profiles and addon.Profiles:IsPreset(current)
                    if frame.RenameBtn then frame.RenameBtn:SetEnabled(not not current and not isPreset) end
                    if frame.CopyBtn then frame.CopyBtn:SetEnabled(not not current) end
                end

                -- Horizontal button row centered below dropdown (3 buttons)
                local btnWidth, btnHeight, btnGap = 130, 32, 16
                local totalWidth = (btnWidth * 3) + (btnGap * 2)
                local startX = -totalWidth / 2

                -- Create button
                if not frame.CreateBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(btnWidth, btnHeight)
                    btn:SetText("Create")
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        addon.Profiles:PromptCreateLayout(frame.ActiveDropdown)
                    end)
                    styleButton(btn)
                    frame.CreateBtn = btn
                end
                frame.CreateBtn:ClearAllPoints()
                frame.CreateBtn:SetPoint("TOP", frame.ActiveDropdown, "BOTTOM", startX + (btnWidth/2), -16)
                frame.CreateBtn:Show()

                -- Rename button
                if not frame.RenameBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(btnWidth, btnHeight)
                    btn:SetText("Rename")
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        local current = getActiveProfileKey()
                        addon.Profiles:PromptRenameLayout(current, frame.ActiveDropdown)
                    end)
                    styleButton(btn)
                    frame.RenameBtn = btn
                end
                frame.RenameBtn:ClearAllPoints()
                frame.RenameBtn:SetPoint("LEFT", frame.CreateBtn, "RIGHT", btnGap, 0)
                frame.RenameBtn:Show()

                -- Copy button
                if not frame.CopyBtn then
                    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(btnWidth, btnHeight)
                    btn:SetText("Copy")
                    btn:SetScript("OnClick", function()
                        CloseDropDownMenus()
                        local current = getActiveProfileKey()
                        if not current then return end
                        if addon.Profiles and addon.Profiles:IsPreset(current) then
                            addon.Profiles:PromptClonePreset(current, frame.ActiveDropdown, addon.Profiles:GetLayoutDisplayText(current), current)
                        else
                            addon.Profiles:PromptCopyLayout(current, frame.ActiveDropdown)
                        end
                    end)
                    styleButton(btn)
                    frame.CopyBtn = btn
                end
                frame.CopyBtn:ClearAllPoints()
                frame.CopyBtn:SetPoint("LEFT", frame.RenameBtn, "RIGHT", btnGap, 0)
                frame.CopyBtn:Show()

                -- Hide Delete button if it exists from recycled frame
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end

                -- Update button states
                updateButtons()
                addon.SettingsPanel.UpdateProfileActionButtons = function()
                    updateButtons()
                end
            end
            table.insert(init, activeRow)
        end

        -- "Delete a Profile" collapsible section
        do
            local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                name = "Delete a Profile",
                sectionKey = "DeleteProfile",
                componentId = "profilesManage",
                expanded = panel:IsSectionExpanded("profilesManage", "DeleteProfile"),
            })
            exp.GetExtent = function() return 30 end
            table.insert(init, exp)
        end

        -- Delete a Profile content row
        do
            local deleteRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            deleteRow.GetExtent = function() return 60 end
            deleteRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                -- Hide standard elements
                if frame.Text then frame.Text:Hide() end
                if frame.MessageText then frame.MessageText:Hide() end
                if frame.InfoText then frame.InfoText:Hide() end
                if frame.ButtonContainer then
                    frame.ButtonContainer:Hide()
                    frame.ButtonContainer:SetAlpha(0)
                    frame.ButtonContainer:EnableMouse(false)
                end
                -- Hide Active Layout elements that may leak from recycled frames
                if frame.ActiveLayoutLabel then frame.ActiveLayoutLabel:Hide() end
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if frame.CreateBtn then frame.CreateBtn:Hide() end
                -- Hide Spec Profile elements
                if frame.SpecEnableCheck then frame.SpecEnableCheck:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end

                -- Hide label if it exists from recycled frame
                if frame.DeleteProfileLabel then frame.DeleteProfileLabel:Hide() end

                -- Create the centered dropdown if it doesn't exist
                if not frame.DeleteProfileDropdown then
                    local dropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
                    dropdown:SetPoint("TOP", frame, "TOP", 0, 4)
                    dropdown.align = "LEFT"
                    dropdown:SetScale(1.25)
                    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dropdown, 280) end
                    frame.DeleteProfileDropdown = dropdown
                    if panel and panel.StyleDropdownLabel then panel.StyleDropdownLabel(dropdown, 1.15) end
                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(dropdown) end
                end
                frame.DeleteProfileDropdown:Show()

                -- Helper to get deletable profiles (excludes current and presets)
                local function getDeletableProfiles()
                    local deletable = {}
                    local currentProfile = getActiveProfileKey()
                    local entries = buildLayoutEntries()
                    for _, entry in ipairs(entries) do
                        -- Skip the currently active profile and presets
                        if entry.key ~= currentProfile and not entry.preset then
                            table.insert(deletable, entry)
                        end
                    end
                    return deletable
                end

                -- Refresh the delete dropdown
                local function refreshDeleteDropdown()
                    local dropdown = frame.DeleteProfileDropdown
                    if not dropdown then return end
                    local deletable = getDeletableProfiles()

                    UIDropDownMenu_Initialize(dropdown, function(self)
                        if #deletable == 0 then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = "No profiles available"
                            info.disabled = true
                            info.notCheckable = true
                            UIDropDownMenu_AddButton(info)
                        else
                            for _, entry in ipairs(deletable) do
                                local info = UIDropDownMenu_CreateInfo()
                                info.text = entry.text
                                info.value = entry.key
                                info.notCheckable = true
                                info.func = function()
                                    -- Immediately reset the dropdown text
                                    UIDropDownMenu_SetText(dropdown, "Select a profile...")
                                    CloseDropDownMenus()
                                    -- Confirm deletion via dialog
                                    addon.Profiles:ConfirmDeleteLayout(entry.key, dropdown)
                                end
                                UIDropDownMenu_AddButton(info)
                            end
                        end
                    end)
                    UIDropDownMenu_SetWidth(dropdown, 280)
                    UIDropDownMenu_SetText(dropdown, "Select a profile...")
                end

                refreshDeleteDropdown()

                -- Store refresh function for external calls
                frame.RefreshDeleteDropdown = refreshDeleteDropdown
            end
            deleteRow:AddShownPredicate(function()
                return panel:IsSectionExpanded("profilesManage", "DeleteProfile")
            end)
            table.insert(init, deleteRow)
        end

        -- "Spec Profiles" collapsible section
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
                    -- Centered holder so the checkbox + label can be truly centered as a group.
                    local holder = frame.SpecEnableHolder
                    if not holder then
                        holder = CreateFrame("Frame", nil, frame)
                        holder:SetPoint("CENTER", frame, "CENTER", 0, 0)
                        holder:SetHeight(32)
                        frame.SpecEnableHolder = holder
                    end

                    local cb = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
                    cb.Text:SetText("Enable Spec Profiles")
                    if cb.Text and panel and panel.ApplyRobotoWhite then
                        panel.ApplyRobotoWhite(cb.Text)
                        -- Increase checkbox label readability by +25%
                        bumpFontByPercent(cb.Text, 0.25)
                    end
                    cb:ClearAllPoints()
                    cb:SetPoint("LEFT", holder, "LEFT", 0, 0)
                    cb:SetScale(1.25)
                    cb:EnableMouse(true)
                    local lvl = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
                    cb:SetFrameLevel(lvl + 100)
                    if cb.SetFrameStrata then cb:SetFrameStrata("DIALOG") end
                    if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -160, 0, 0) end
                    cb:SetScript("OnClick", function(btn)
                        local enabled = btn:GetChecked()
                        local wasEnabled = addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled()
                        if addon.Profiles and addon.Profiles.SetSpecProfilesEnabled then
                            addon.Profiles:SetSpecProfilesEnabled(enabled)
                        end
                        -- First-time enable: seed all specs to the currently active profile so
                        -- users don't accidentally leave a spec effectively "unassigned".
                        if enabled and (not wasEnabled) then
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
                        if enabled and addon.Profiles and addon.Profiles.OnPlayerSpecChanged then
                            addon.Profiles:OnPlayerSpecChanged()
                        end
                        -- Spec rows use AddShownPredicate; force a structural
                        -- re-render so their ShouldShow state is re-evaluated.
                        if addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategory then
                            addon.SettingsPanel.RefreshCurrentCategory()
                        end
                    end)
                    -- Apply ScooterMod theming to the checkbox
                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(cb) end
                    frame.SpecEnableCheck = cb

                    -- Resize the holder to the combined width of checkbox + label so the group stays centered.
                    C_Timer.After(0, function()
                        if not frame or not frame.SpecEnableHolder or not frame.SpecEnableCheck then return end
                        local chk = frame.SpecEnableCheck
                        local textW = (chk.Text and chk.Text.GetStringWidth and chk.Text:GetStringWidth()) or 0
                        local boxW = (chk.GetWidth and chk:GetWidth()) or 24
                        -- UICheckButtonTemplate uses a fixed text offset; approximate a small gap.
                        local totalW = math.max(1, boxW + 6 + textW)
                        frame.SpecEnableHolder:SetWidth(totalW)
                    end)
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
                    -- Apply ScooterMod theming to the dropdown
                    if panel and panel.StyleDropdownLabel then panel.StyleDropdownLabel(dropdown, 1.25) end
                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(dropdown) end
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

        right:Display(init)

        -- Bottom-center warning: fixed footer + Rules-style divider above it.
        do
            -- Derive sizes from GameFontHighlight so this adapts across clients.
            local _, baseSize = GameFontHighlight:GetFont()
            baseSize = tonumber(baseSize) or 14

            -- Previous warning used ~1.15 scale, then we increased by +20%.
            -- User feedback: reduce overall warning size by 15% from current.
            local warnScale = 1.15 * 1.20 * 0.85
            local warnSize = math.floor(baseSize * warnScale + 0.5)
            -- Keep RELOAD inline (same size), but bold + underline provides emphasis.
            local reloadSize = warnSize

            if right.SetBottomNotice then
                right:SetBottomNotice({
                    height = 132,
                    messageTop = "Creating, deleting, or switching between profiles will require a ",
                    emphasisWord = "RELOAD",
                    messageSuffix = ".",
                    messageBottom = "ScooterMod only layers customizations on top of the Blizzard UI and a reload is needed to obtain current defaults for fields which you have customized in one profile but not another.",
                    color = { 1.0, 0.82, 0.0, 1.0 },
                    topSize = warnSize,
                    wordSize = reloadSize,
                    bottomSize = warnSize,
                })
            end
        end

        if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfilesSectionVisibility then
            addon.SettingsPanel:UpdateProfilesSectionVisibility()
        end
    end

    return { mode = "list", render = render, componentId = "profilesManage" }
end

function panel.RenderProfilesManage()
    return renderProfilesManage()
end


