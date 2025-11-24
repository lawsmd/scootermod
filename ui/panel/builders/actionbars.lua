local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local createComponentRenderer = panel.builders and panel.builders.createComponentRenderer

-- Action Bars: simple scaffold renderers (empty collapsible sections)
local function createEmptySectionsRenderer(componentId, title)
    return function()
        local render = function()
            local f = panel.frame
            local right = f and f.RightPane
            if not f or not right or not right.Display then return end

            local init = {}
            local function addHeader(sectionKey, headerName)
                local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                    name = headerName,
                    sectionKey = sectionKey,
                    componentId = componentId,
                    expanded = panel:IsSectionExpanded(componentId, sectionKey),
                })
                expInitializer.GetExtent = function() return 30 end
                table.insert(init, expInitializer)
            end

            -- Positioning, Sizing, Border, Text, Visibility (Misc header key maps to Visibility)
            addHeader("Positioning", "Positioning")
            addHeader("Sizing", "Sizing")
            addHeader("Border", "Border")
            addHeader("Text", "Text")
            addHeader("Misc", "Visibility")

            if right.SetTitle then
                right:SetTitle(title or componentId)
            end

            -- Ensure header "Copy from" control for Unit Frames (Player/Target/Focus)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                local collapseBtn = header and (header.DefaultsButton or header.CollapseAllButton or header.CollapseButton)
                if header then
                    -- Create once (shared with Action Bars header controls)
                    if not header.ScooterCopyFromLabel then
                        local lbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        lbl:SetText("Copy from:")
                        if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                        header.ScooterCopyFromLabel = lbl
                    end
                    if not header.ScooterCopyFromDropdown then
                        local dd = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                        dd:SetSize(180, 22)
                        header.ScooterCopyFromDropdown = dd
                    end
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    -- Position: always anchor to header's top-right to avoid template differences
                    if dd and lbl then
                        dd:ClearAllPoints()
                        dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                        lbl:ClearAllPoints()
                        lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                    end

                    -- Confirmation and error dialogs (one-time registration)
                    if _G and _G.StaticPopupDialogs and not _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_CONFIRM"] then
                        _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_CONFIRM"] = {
                            text = "Copy supported Unit Frame settings from %s to %s?",
                            button1 = "Copy",
                            button2 = CANCEL,
                            OnAccept = function(self, data)
                                if data and addon and addon.CopyUnitFrameSettings then
                                    local ok, err = addon.CopyUnitFrameSettings(data.sourceUnit, data.destUnit, { skipFrameSize = false })
                                    if ok then
                                        if data.dropdown then
                                            data.dropdown._ScooterSelectedId = data.sourceUnit
                                            if data.dropdown.SetText and data.sourceLabel then
                                                data.dropdown:SetText(data.sourceLabel)
                                            end
                                        end
                                    else
                                        if _G and _G.StaticPopup_Show then
                                            local msg
                                            if err == "focus_requires_larger" then
                                                msg = "Cannot copy to Focus unless 'Use Larger Frame' is enabled."
                                            elseif err == "invalid_unit" then
                                                msg = "Copy failed. Unsupported unit selection."
                                            elseif err == "same_unit" then
                                                msg = "Copy failed. Choose a different source frame."
                                            elseif err == "db_unavailable" then
                                                msg = "Copy failed. Profile database unavailable."
                                            else
                                                msg = "Copy failed. Please try again."
                                            end
                                            _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_ERROR"] = _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_ERROR"] or {
                                                text = "%s",
                                                button1 = OKAY,
                                                timeout = 0,
                                                whileDead = 1,
                                                hideOnEscape = 1,
                                                preferredIndex = 3,
                                            }
                                            _G.StaticPopup_Show("SCOOTERMOD_COPY_UF_ERROR", msg)
                                        end
                                    end
                                end
                            end,
                            OnCancel = function(self, data) end,
                            timeout = 0,
                            whileDead = 1,
                            hideOnEscape = 1,
                            preferredIndex = 3,
                        }
                    end

                    -- Populate dropdown only on UF tabs (Player/Target/Focus). Pet excluded entirely.
                    if isUF and dd and dd.SetupMenu then
                        local currentId = componentId
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" } -- Pet excluded
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function()
                                        return dd._ScooterSelectedId == id
                                    end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            -- Fallback: perform copy directly if popup system is unavailable
                                            if addon and addon.CopyUnitFrameSettings then
                                                local ok = addon.CopyUnitFrameSettings(data.sourceUnit, data.destUnit)
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Ensure a neutral prompt if nothing selected yet
                        if dd.SetShown then dd:SetShown(true) end
                        if lbl and lbl.SetShown then lbl:SetShown(true) end
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                    end

                    -- Visibility per tab
                    if lbl then lbl:SetShown(isUF) end
                    if dd then dd:SetShown(isUF) end
                end
            end

            settingsList:Display(init)
            -- Ensure header "Copy from" is present AFTER Display as well (some templates rebuild header)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                if header then
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    if not lbl or not dd then
                        -- Recreate if missing
                        if not header.ScooterCopyFromLabel then
                            local l = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            l:SetText("Copy from:")
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(l) end
                            header.ScooterCopyFromLabel = l
                        end
                        if not header.ScooterCopyFromDropdown then
                            local d = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                            d:SetSize(180, 22)
                            header.ScooterCopyFromDropdown = d
                        end
                        lbl = header.ScooterCopyFromLabel
                        dd  = header.ScooterCopyFromDropdown
                        if dd and lbl then
                            dd:ClearAllPoints(); dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                            lbl:ClearAllPoints(); lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                        end
                    end
                    if isUF and dd and dd.SetupMenu then
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        local currentId = componentId
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function() return dd._ScooterSelectedId == id end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            if addon and addon.CopyUnitFrameSettings then
                                                local ok = addon.CopyUnitFrameSettings(data.sourceUnit, data.destUnit)
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                        if lbl then lbl:SetShown(true) end
                        if dd then dd:SetShown(true) end
                    else
                        if lbl then lbl:SetShown(false) end
                        if dd then dd:SetShown(false) end
                    end
                end
            end
            -- Mirror Action Bars post-display repair to ensure header children are laid out
            local currentCategory = f.CurrentCategory
            if currentCategory and f.CatRenderers then
                local entry = f.CatRenderers[currentCategory]
                if entry then entry._lastInitializers = init end
            end
            if settingsList.RepairDisplay then pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end }) end
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
    end
end
local function createWIPRenderer(componentId, title)
    return function()
        local render = function()
            local f = panel.frame
            if not f or not f.SettingsList then return end
            local init = {}

            local row = Settings.CreateElementInitializer("SettingsListElementTemplate")
            row.GetExtent = function() return 28 end
            row.InitFrame = function(self, frame)
                if frame and frame.Text then
                    frame.Text:SetText("Work in progress")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
                end
            end
            table.insert(init, row)

            local right = f and f.RightPane
            if not f or not right or not right.Display then return end
            if right.SetTitle then
                right:SetTitle(title or componentId)
            end

            -- Ensure header "Copy from" control for Unit Frames (Player/Target/Focus)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                if header then
                    -- Create once
                    if not header.ScooterCopyFromLabel then
                        local lbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        lbl:SetText("Copy from:")
                        if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                        header.ScooterCopyFromLabel = lbl
                    end
                    if not header.ScooterCopyFromDropdown then
                        local dd = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                        dd:SetSize(180, 22)
                        header.ScooterCopyFromDropdown = dd
                    end
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    -- Anchor to the left of Collapse All/Defaults if available, else top-right fallback
                    if dd and lbl then
                        local collapseBtn = header and (header.CollapseAllButton or header.CollapseButton or header.DefaultsButton)
                        dd:ClearAllPoints()
                        if collapseBtn then
                            dd:SetPoint("RIGHT", collapseBtn, "LEFT", -24, 0)
                        else
                            dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                        end
                        lbl:ClearAllPoints()
                        lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                    end

                    -- Populate dropdown only on UF tabs (exclude Pet)
                    if isUF and dd and dd.SetupMenu then
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        local currentId = componentId
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function()
                                        return dd._ScooterSelectedId == id
                                    end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            if addon and addon.CopyUnitFrameSettings then
                                                local ok = addon.CopyUnitFrameSettings(data.sourceUnit, data.destUnit)
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                        if lbl then lbl:SetShown(true) end
                        if dd then dd:SetShown(true) end
                    end

                    -- Visibility per tab
                    if lbl then lbl:SetShown(isUF) end
                    if dd then dd:SetShown(isUF) end
                end
            end

            settingsList:Display(init)

            -- Post-Display: ensure header controls still exist (some templates rebuild header)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                if header then
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    if not lbl or not dd then
                        if not header.ScooterCopyFromLabel then
                            local l = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            l:SetText("Copy from:")
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(l) end
                            header.ScooterCopyFromLabel = l
                        end
                        if not header.ScooterCopyFromDropdown then
                            local d = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                            d:SetSize(180, 22)
                            header.ScooterCopyFromDropdown = d
                        end
                        lbl = header.ScooterCopyFromLabel
                        dd  = header.ScooterCopyFromDropdown
                        if dd and lbl then
                            local collapseBtn = header and (header.CollapseAllButton or header.CollapseButton or header.DefaultsButton)
                            dd:ClearAllPoints()
                            if collapseBtn then
                                dd:SetPoint("RIGHT", collapseBtn, "LEFT", -24, 0)
                            else
                                dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                            end
                            lbl:ClearAllPoints(); lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                        end
                    end
                    if isUF and dd and dd.SetupMenu then
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        local currentId = componentId
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function() return dd._ScooterSelectedId == id end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            if addon and addon.CopyUnitFrameSettings then
                                                local ok = addon.CopyUnitFrameSettings(data.sourceUnit, data.destUnit)
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                        if lbl then lbl:SetShown(true) end
                        if dd then dd:SetShown(true) end
                    else
                        if lbl then lbl:SetShown(false) end
                        if dd then dd:SetShown(false) end
                    end
                end
            end

            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
    end
end

-- Export Action Bars renderers
function panel.RenderActionBar1()  return createComponentRenderer("actionBar1")() end
function panel.RenderActionBar2()  return createComponentRenderer("actionBar2")() end
function panel.RenderActionBar3()  return createComponentRenderer("actionBar3")() end
function panel.RenderActionBar4()  return createComponentRenderer("actionBar4")() end
function panel.RenderActionBar5()  return createComponentRenderer("actionBar5")() end
function panel.RenderActionBar6()  return createComponentRenderer("actionBar6")() end
function panel.RenderActionBar7()  return createComponentRenderer("actionBar7")() end
function panel.RenderActionBar8()  return createComponentRenderer("actionBar8")() end
function panel.RenderStanceBar()   return createComponentRenderer("stanceBar")()           end
function panel.RenderMicroBar()    return createComponentRenderer("microBar")()              end
