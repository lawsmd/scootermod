local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

--------------------------------------------------------------------------------
-- Group Frames Builder Module
--------------------------------------------------------------------------------
-- This module provides renderers for the Group Frames category:
--   - Party Frames (gfParty)
--   - Raid Frames (gfRaid)
--
-- Frame Targets:
--   Party: PartyFrame / CompactPartyFrame (Enum.EditModeUnitFrameSystemIndices.Party)
--   Raid:  CompactRaidFrameContainer (Enum.EditModeUnitFrameSystemIndices.Raid)
--------------------------------------------------------------------------------

-- Helper: Get Party Frame from Edit Mode
local function getPartyFrame()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Party)
end

-- Helper: Get Raid Frame from Edit Mode
local function getRaidFrame()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Raid)
end

--------------------------------------------------------------------------------
-- Party Frames Renderer (gfParty)
--------------------------------------------------------------------------------
-- Collapsible sections: Positioning, Sizing, Border, Style, Text, Visibility
-- All sections are empty placeholders for now.
--------------------------------------------------------------------------------

function panel.RenderGFParty()
    local componentId = "gfParty"
    local title = "Party Frames"

    local render = function()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        local init = {}

        -- Shared conditional enable/disable state for Party Frames.
        -- IMPORTANT: Do NOT clear these references on every render. The UI recycles row frames and
        -- CreateLocalSetting closures can keep firing; clearing would create the classic "works once" bug.
        panel._gfPartyConditionalFrames = panel._gfPartyConditionalFrames or {}
        local cond = panel._gfPartyConditionalFrames

        local function setRowEnabled(rowFrame, enabled)
            if not rowFrame then return end
            rowFrame:SetAlpha(enabled and 1 or 0.5)

            local control = rowFrame.Control or rowFrame
            local dropdown = control and control.Dropdown
            local slider = control and (control.Slider or control.slider or rowFrame.Slider)
            local checkbox = rowFrame.Checkbox or rowFrame.CheckBox or (control and control.Checkbox)

            if dropdown and dropdown.SetEnabled then
                pcall(dropdown.SetEnabled, dropdown, enabled)
            elseif dropdown and dropdown.EnableMouse then
                pcall(dropdown.EnableMouse, dropdown, enabled)
            end

            if slider and slider.SetEnabled then
                pcall(slider.SetEnabled, slider, enabled)
            elseif slider and slider.EnableMouse then
                pcall(slider.EnableMouse, slider, enabled)
            end

            if checkbox and checkbox.SetEnabled then
                pcall(checkbox.SetEnabled, checkbox, enabled)
            elseif checkbox and checkbox.EnableMouse then
                pcall(checkbox.EnableMouse, checkbox, enabled)
            end
        end

        local function getUseRaidStylePartyFrames()
            local pf = getPartyFrame()
            local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
            if not (pf and EM and addon and addon.EditMode and addon.EditMode.GetSetting) then
                return false
            end
            return (addon.EditMode.GetSetting(pf, EM.UseRaidStylePartyFrames) or 0) == 1
        end

        local function isRaidStyleEnabled()
            if cond and cond.raidStyleValue ~= nil then
                return cond.raidStyleValue and true or false
            end
            local enabled = getUseRaidStylePartyFrames()
            cond.raidStyleValue = enabled and true or false
            return enabled
        end

        local function applyConditionalAvailability()
            local raidStyle = isRaidStyleEnabled()

            -- Traditional-only: Show Background + Frame Size
            setRowEnabled(cond.showBackgroundRow, not raidStyle)
            if cond.sizingRow then
                local r = cond.sizingRow
                setRowEnabled(r._ScooterGF_PartyFrameSizeRow, not raidStyle)
                setRowEnabled(r._ScooterGF_PartyFrameWidthRow, raidStyle)
                setRowEnabled(r._ScooterGF_PartyFrameHeightRow, raidStyle)
            end

            -- Raid-style only: Use Horizontal Layout + Sort By + Display Border
            if cond.posSortRow then
                local r = cond.posSortRow
                setRowEnabled(r._ScooterGF_PartyHorizontalLayoutRow, raidStyle)
                setRowEnabled(r._ScooterGF_PartySortByRow, raidStyle)
            end
            setRowEnabled(cond.displayBorderRow, raidStyle)
        end

        -- Refresh the cached raid-style value from Edit Mode at the start of every render.
        -- This prevents stale checkbox state when the user changes the setting in Edit Mode
        -- while the ScooterMod panel is closed, then immediately reopens ScooterMod.
        cond.raidStyleValue = getUseRaidStylePartyFrames() and true or false

        -- Helper to add a collapsible section header
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

        --------------------------------------------------------------------------------
        -- Parent-level Edit Mode settings (above section headers)
        --------------------------------------------------------------------------------
        do
            local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
            if EM then
                -- Use Raid-Style Party Frames
                do
                    local label = "Use Raid-Style Party Frames"
                    local tooltipText = "Toggles between Raid-Style and Traditional-Style party frames.\n\nRaid-Style uses compact party frames and unlocks additional Edit Mode options."

                    local function getter()
                        return isRaidStyleEnabled()
                    end

                    local function setter(state)
                        local enabled = (state and true or false) and true or false
                        cond.raidStyleValue = enabled
                        applyConditionalAvailability()

                        C_Timer.After(0, function()
                            local pf = getPartyFrame()
                            if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                            local v = enabled and 1 or 0
                            addon.EditMode.WriteSetting(pf, EM.UseRaidStylePartyFrames, v, {
                                updaters = { "UpdateSystemSettingUseRaidStylePartyFrames" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end

                    local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
                    local cbInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
                    cbInit.GetExtent = function() return 34 end

                    do
                        local baseInitFrame = cbInit.InitFrame
                        cbInit.InitFrame = function(self, frame)
                            -- Refresh cached value BEFORE base template init so the checkbox draws correctly.
                            cond.raidStyleValue = getUseRaidStylePartyFrames() and true or false

                            if baseInitFrame then baseInitFrame(self, frame) end

                            if panel and panel.ApplyRobotoWhite then
                                if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
                                local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                                if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                                if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                            end

                            -- Info icon between checkbox and label.
                            local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                            local labelFS = frame.Text or (cb and cb.Text)
                            if cb and labelFS and panel and panel.CreateInfoIcon and not frame.ScooterUseRaidStyleInfoIcon then
                                frame.ScooterUseRaidStyleInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                                local icon = frame.ScooterUseRaidStyleInfoIcon
                                if icon then
                                    icon:ClearAllPoints()
                                    icon:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                                    labelFS:ClearAllPoints()
                                    labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                                    labelFS:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                                    labelFS:SetJustifyH("LEFT")
                                end
                            end

                            applyConditionalAvailability()
                        end
                    end

                    table.insert(init, cbInit)
                end

                -- Show Background (Traditional-only)
                do
                    local label = "Show Background"
                    local tooltipText = "Shows a background panel behind traditional-style party frames.\n\nOnly available when 'Use Raid-Style Party Frames' is disabled."

                    local function getter()
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then return false end
                        return (addon.EditMode.GetSetting(pf, EM.ShowPartyFrameBackground) or 0) == 1
                    end

                    local function setter(state)
                        C_Timer.After(0, function()
                            local pf = getPartyFrame()
                            if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                            local v = (state and true or false) and 1 or 0
                            addon.EditMode.WriteSetting(pf, EM.ShowPartyFrameBackground, v, {
                                updaters = { "UpdateSystemSettingShowPartyFrameBackground" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end

                    local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
                    local cbInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
                    cbInit.GetExtent = function() return 34 end

                    do
                        local baseInitFrame = cbInit.InitFrame
                        cbInit.InitFrame = function(self, frame)
                            if baseInitFrame then baseInitFrame(self, frame) end

                            if panel and panel.ApplyRobotoWhite then
                                if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
                                local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                                if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                                if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                            end

                            -- Info icon between checkbox and label.
                            local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                            local labelFS = frame.Text or (cb and cb.Text)
                            if cb and labelFS and panel and panel.CreateInfoIcon and not frame.ScooterShowBackgroundInfoIcon then
                                frame.ScooterShowBackgroundInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                                local icon = frame.ScooterShowBackgroundInfoIcon
                                if icon then
                                    icon:ClearAllPoints()
                                    icon:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                                    labelFS:ClearAllPoints()
                                    labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                                    labelFS:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                                    labelFS:SetJustifyH("LEFT")
                                end
                            end

                            cond.showBackgroundRow = frame
                            applyConditionalAvailability()
                        end
                    end

                    table.insert(init, cbInit)
                end
            end
        end

        -- 1. Positioning & Sorting section header
        addHeader("Positioning", "Positioning & Sorting")

        -- Positioning & Sorting content (raid-style only controls, shown always but greyed out when inactive)
        do
            local posSortInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
            -- Height: 16 top + 34 checkbox + 34 dropdown = 84; use 110 for clearance.
            posSortInit.GetExtent = function() return 110 end
            posSortInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Positioning")
            end)
            posSortInit.InitFrame = function(self, frame)
                if frame._ScooterGFPartyPosSortBuilt then
                    cond.posSortRow = frame
                    if frame._ScooterGF_RefreshFromEditMode then
                        pcall(frame._ScooterGF_RefreshFromEditMode)
                    end
                    applyConditionalAvailability()
                    return
                end
                frame._ScooterGFPartyPosSortBuilt = true

                if frame.Text then
                    frame.Text:SetText("")
                    frame.Text:Hide()
                end

                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                local Sort = _G.Enum and _G.Enum.SortPlayersBy
                if not (EM and Sort) then return end

                local function sortByOptions()
                    local container = Settings.CreateControlTextContainer()
                    container:Add(Sort.Role, "Role")
                    container:Add(Sort.Group, "Group")
                    container:Add(Sort.Alphabetical, "Alphabetical")
                    return container:GetData()
                end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                local function addDropdown(parent, label, optionsProvider, getter, setter, yRef)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                        name = label,
                        setting = setting,
                        options = optionsProvider,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    local lbl = row and (row.Text or row.Label)
                    if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                    if row.Control and panel and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(row.Control)
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                local function addCheckbox(parent, label, getter, setter, yRef)
                    local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
                    local row = CreateFrame("Frame", nil, parent, "SettingsCheckboxControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    if panel and panel.ApplyRobotoWhite then
                        if row.Text then panel.ApplyRobotoWhite(row.Text) end
                        local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
                        if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                        if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                local function addLeftInfoIcon(row, tooltipText)
                    if not (row and panel and panel.CreateInfoIcon) then return end
                    local labelFS = row.Text or row.Label
                    if not labelFS or row.ScooterInfoIcon then return end

                    row.ScooterInfoIcon = panel.CreateInfoIcon(row, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                    local icon = row.ScooterInfoIcon
                    if not icon then return end

                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
                    labelFS:ClearAllPoints()
                    labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    labelFS:SetJustifyH("LEFT")

                    local ctrl = row.Control
                    local dropdown = ctrl and ctrl.Dropdown
                    local slider = (ctrl and ctrl.Slider) or row.Slider
                    local cb = row.Checkbox or row.CheckBox or (ctrl and ctrl.Checkbox)
                    if slider then
                        labelFS:SetPoint("RIGHT", slider, "LEFT", -8, 0)
                    elseif dropdown then
                        labelFS:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
                    elseif cb then
                        labelFS:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    else
                        labelFS:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    end
                end

                local y = { y = -16 }

                -- Use Horizontal Layout (raid-style only)
                local horizTooltip = "Arranges party member frames horizontally instead of vertically.\n\nOnly available when 'Use Raid-Style Party Frames' is enabled."
                local horizRow = addCheckbox(frame, "Use Horizontal Layout",
                    function()
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then return false end
                        return (addon.EditMode.GetSetting(pf, EM.UseHorizontalGroups) or 0) == 1
                    end,
                    function(state)
                        C_Timer.After(0, function()
                            local pf = getPartyFrame()
                            if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                            local v = (state and true or false) and 1 or 0
                            addon.EditMode.WriteSetting(pf, EM.UseHorizontalGroups, v, {
                                updaters = { "UpdateSystemSettingUseHorizontalGroups" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                    y)
                addLeftInfoIcon(horizRow, horizTooltip)

                -- Sort By (raid-style only)
                local sortTooltip = "Controls how players are sorted within the party.\n\nOnly available when 'Use Raid-Style Party Frames' is enabled."
                frame._ScooterGF_PartySortByValue = nil

                -- Expose a refresh helper so this row can resync cached values when reused.
                frame._ScooterGF_RefreshFromEditMode = function()
                    local pf = getPartyFrame()
                    if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then return end
                    frame._ScooterGF_PartySortByValue = addon.EditMode.GetSetting(pf, EM.SortPlayersBy) or Sort.Group
                end

                local sortRow = addDropdown(frame, "Sort By", sortByOptions,
                    function()
                        if frame._ScooterGF_PartySortByValue == nil then
                            local pf = getPartyFrame()
                            if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then
                                frame._ScooterGF_PartySortByValue = Sort.Group
                            else
                                frame._ScooterGF_PartySortByValue = addon.EditMode.GetSetting(pf, EM.SortPlayersBy) or Sort.Group
                            end
                        end
                        return frame._ScooterGF_PartySortByValue
                    end,
                    function(v)
                        local val = tonumber(v) or Sort.Group
                        frame._ScooterGF_PartySortByValue = val
                        C_Timer.After(0, function()
                            local pf = getPartyFrame()
                            if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                            addon.EditMode.WriteSetting(pf, EM.SortPlayersBy, val, {
                                updaters = { "UpdateSystemSettingSortPlayersBy" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                    y)
                addLeftInfoIcon(sortRow, sortTooltip)

                frame._ScooterGF_PartyHorizontalLayoutRow = horizRow
                frame._ScooterGF_PartySortByRow = sortRow
                cond.posSortRow = frame

                applyConditionalAvailability()
            end
            table.insert(init, posSortInit)
        end

        -- 2. Sizing section header (placeholder)
        addHeader("Sizing", "Sizing")

        -- Sizing content (Width/Height for raid-style; Frame Size for traditional)
        do
            local sizeInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
            -- Height: 16 top + 34 + 34 + 34 = 118; use 140 for clearance.
            sizeInit.GetExtent = function() return 140 end
            sizeInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Sizing")
            end)
            sizeInit.InitFrame = function(self, frame)
                if frame._ScooterGFPartySizingBuilt then
                    cond.sizingRow = frame
                    applyConditionalAvailability()
                    return
                end
                frame._ScooterGFPartySizingBuilt = true

                if frame.Text then
                    frame.Text:SetText("")
                    frame.Text:Hide()
                end

                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                if not EM then return end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                        return fmtInt(v)
                    end)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                        name = label,
                        setting = setting,
                        options = options,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    if row.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(row) end
                    yRef.y = yRef.y - 34
                    return row
                end

                local function addLeftInfoIcon(row, tooltipText)
                    if not (row and panel and panel.CreateInfoIcon) then return end
                    local labelFS = row.Text or row.Label
                    if not labelFS or row.ScooterInfoIcon then return end

                    row.ScooterInfoIcon = panel.CreateInfoIcon(row, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                    local icon = row.ScooterInfoIcon
                    if not icon then return end

                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
                    labelFS:ClearAllPoints()
                    labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    labelFS:SetJustifyH("LEFT")

                    local ctrl = row.Control
                    local slider = (ctrl and ctrl.Slider) or row.Slider
                    if slider then
                        labelFS:SetPoint("RIGHT", slider, "LEFT", -8, 0)
                    else
                        labelFS:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    end
                end

                local y = { y = -16 }

                -- Frame Width (raid-style only)
                local widthRow = addSlider(frame, "Frame Width", 72, 144, 2,
                    function()
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then return 72 end
                        return addon.EditMode.GetSetting(pf, EM.FrameWidth) or 72
                    end,
                    function(v)
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                        local val = tonumber(v) or 72
                        val = math.max(72, math.min(144, val))
                        addon.EditMode.WriteSetting(pf, EM.FrameWidth, val, {
                            updaters = { "UpdateSystemSettingFrameWidth" },
                            suspendDuration = 0.25,
                        })
                    end,
                    y)

                -- Frame Height (raid-style only)
                local heightRow = addSlider(frame, "Frame Height", 36, 72, 2,
                    function()
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then return 36 end
                        return addon.EditMode.GetSetting(pf, EM.FrameHeight) or 36
                    end,
                    function(v)
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                        local val = tonumber(v) or 36
                        val = math.max(36, math.min(72, val))
                        addon.EditMode.WriteSetting(pf, EM.FrameHeight, val, {
                            updaters = { "UpdateSystemSettingFrameHeight" },
                            suspendDuration = 0.25,
                        })
                    end,
                    y)

                -- Frame Size (traditional only)
                local sizeTooltip = "Scales the traditional-style party frames.\n\nOnly available when 'Use Raid-Style Party Frames' is disabled."
                local frameSizeRow = addSlider(frame, "Frame Size (Scale)", 100, 200, 5,
                    function()
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.GetSetting) then return 100 end
                        local v = addon.EditMode.GetSetting(pf, EM.FrameSize)
                        if v == nil then return 100 end
                        -- Some clients can return index (0..20); normalize to 100..200.
                        if v <= 20 then return 100 + (v * 5) end
                        return math.max(100, math.min(200, v))
                    end,
                    function(raw)
                        local pf = getPartyFrame()
                        if not (pf and addon and addon.EditMode and addon.EditMode.WriteSetting) then return end
                        local val = tonumber(raw) or 100
                        val = math.max(100, math.min(200, val))
                        addon.EditMode.WriteSetting(pf, EM.FrameSize, val, {
                            updaters = { "UpdateSystemSettingFrameSize" },
                            suspendDuration = 0.25,
                        })
                    end,
                    y)
                addLeftInfoIcon(frameSizeRow, sizeTooltip)

                frame._ScooterGF_PartyFrameWidthRow = widthRow
                frame._ScooterGF_PartyFrameHeightRow = heightRow
                frame._ScooterGF_PartyFrameSizeRow = frameSizeRow
                cond.sizingRow = frame

                applyConditionalAvailability()
            end
            table.insert(init, sizeInit)
        end

        -- 3. Border section header
        addHeader("Border", "Border")

        -- Border content: Display Border (raid-style only)
        do
            local label = "Display Border"
            local tooltipText = "Enables Blizzard's default border around the entire party frame cluster.\n\nOnly available when 'Use Raid-Style Party Frames' is enabled."

            local function getter()
                local pf = getPartyFrame()
                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                if not (pf and EM and addon and addon.EditMode and addon.EditMode.GetSetting) then
                    return false
                end
                return (addon.EditMode.GetSetting(pf, EM.DisplayBorder) or 0) == 1
            end

            local function setter(state)
                local pf = getPartyFrame()
                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                if not (pf and EM and addon and addon.EditMode and addon.EditMode.WriteSetting) then
                    return
                end
                local v = (state and true or false) and 1 or 0
                C_Timer.After(0, function()
                    addon.EditMode.WriteSetting(pf, EM.DisplayBorder, v, {
                        updaters = { "UpdateSystemSettingDisplayBorder" },
                        suspendDuration = 0.25,
                    })
                end)
            end

            local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
            local cbInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
            cbInit.GetExtent = function() return 34 end
            cbInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Border")
            end)

            do
                local baseInitFrame = cbInit.InitFrame
                cbInit.InitFrame = function(self, frame)
                    if baseInitFrame then baseInitFrame(self, frame) end

                    if panel and panel.ApplyRobotoWhite then
                        if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
                        local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                        if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                        if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                    end

                    -- Info icon between checkbox and label.
                    local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                    local labelFS = frame.Text or (cb and cb.Text)
                    if cb and labelFS and panel and panel.CreateInfoIcon and not frame.ScooterDisplayBorderInfoIcon then
                        frame.ScooterDisplayBorderInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                        local icon = frame.ScooterDisplayBorderInfoIcon
                        if icon then
                            icon:ClearAllPoints()
                            icon:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                            labelFS:ClearAllPoints()
                            labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                            labelFS:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                            labelFS:SetJustifyH("LEFT")
                        end
                    end

                    cond.displayBorderRow = frame
                    applyConditionalAvailability()
                end
            end

            table.insert(init, cbInit)
        end

        -- 4. Style section header with Health Bar styling controls
        addHeader("Style", "Style")

        -- Style section content: Health Bar Foreground/Background Texture & Color
        local styleInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
        styleInit.GetExtent = function() return 224 end
        styleInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Style")
        end)
        styleInit.InitFrame = function(self, frame)
            if frame._ScooterPartyStyleBuilt then return end
            frame._ScooterPartyStyleBuilt = true

            if frame.Text then
                frame.Text:SetText("")
                frame.Text:Hide()
            end

            local function getPartyDB()
                local db = addon and addon.db and addon.db.profile
                local gf = db and rawget(db, "groupFrames") or nil
                return gf and rawget(gf, "party") or nil
            end

            local function ensurePartyDB()
                local db = addon and addon.db and addon.db.profile
                if not db then return nil end
                db.groupFrames = db.groupFrames or {}
                db.groupFrames.party = db.groupFrames.party or {}
                return db.groupFrames.party
            end

            local function applyNow()
                if addon and addon.ApplyPartyFrameHealthBarStyle then
                    addon.ApplyPartyFrameHealthBarStyle()
                end
            end

            local y = -16

            -- 1. Foreground Texture dropdown
            local function texOpts() return addon.BuildBarTextureOptionsContainer() end
            local function getTex()
                local t = getPartyDB() or {}
                return t.healthBarTexture or "default"
            end
            local function setTex(v)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarTexture = v
                applyNow()
            end
            local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
            local initTexDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "Foreground Texture",
                setting = texSetting,
                options = texOpts
            })
            local fTex = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            fTex.GetElementData = function() return initTexDrop end
            fTex:SetPoint("TOPLEFT", 4, y)
            fTex:SetPoint("TOPRIGHT", -16, y)
            initTexDrop:InitFrame(fTex)
            if panel and panel.ApplyRobotoWhite then
                local lbl = fTex and (fTex.Text or fTex.Label)
                if lbl then panel.ApplyRobotoWhite(lbl) end
            end
            if fTex.Control and panel.ThemeDropdownWithSteppers then
                panel.ThemeDropdownWithSteppers(fTex.Control)
            end
            if fTex.Control and addon.InitBarTextureDropdown then
                addon.InitBarTextureDropdown(fTex.Control, texSetting)
            end
            y = y - 34

            -- 2. Foreground Color (dropdown + inline swatch)
            local function fgColorOpts()
                local container = Settings.CreateControlTextContainer()
                container:Add("default", "Default")
                container:Add("texture", "Texture Original")
                container:Add("class", "Class Color")
                container:Add("custom", "Custom")
                return container:GetData()
            end
            local function getFgColorMode()
                local t = getPartyDB() or {}
                return t.healthBarColorMode or "default"
            end
            local function setFgColorMode(v)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarColorMode = v or "default"
                applyNow()
            end
            local function getFgTint()
                local t = getPartyDB() or {}
                local c = t.healthBarTint or {1, 1, 1, 1}
                return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
            end
            local function setFgTint(r, g, b, a)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarTint = { r or 1, g or 1, b or 1, a or 1 }
                applyNow()
            end
            local yRef = { y = y }
            panel.DropdownWithInlineSwatch(frame, yRef, {
                label = "Foreground Color",
                getMode = getFgColorMode,
                setMode = setFgColorMode,
                getColor = getFgTint,
                setColor = setFgTint,
                options = fgColorOpts,
                insideButton = true,
            })
            y = yRef.y

            -- Spacer between Foreground and Background
            do
                local spacer = CreateFrame("Frame", nil, frame, "SettingsListElementTemplate")
                spacer:SetHeight(20)
                spacer:SetPoint("TOPLEFT", 4, y)
                spacer:SetPoint("TOPRIGHT", -16, y)
                if spacer.Text then spacer.Text:SetText("") end
                y = y - 24
            end

            -- 3. Background Texture dropdown
            local function getBgTex()
                local t = getPartyDB() or {}
                return t.healthBarBackgroundTexture or "default"
            end
            local function setBgTex(v)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarBackgroundTexture = v
                applyNow()
            end
            local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
            local initBgTexDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "Background Texture",
                setting = bgTexSetting,
                options = texOpts
            })
            local fBgTex = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            fBgTex.GetElementData = function() return initBgTexDrop end
            fBgTex:SetPoint("TOPLEFT", 4, y)
            fBgTex:SetPoint("TOPRIGHT", -16, y)
            initBgTexDrop:InitFrame(fBgTex)
            if panel and panel.ApplyRobotoWhite then
                local lbl = fBgTex and (fBgTex.Text or fBgTex.Label)
                if lbl then panel.ApplyRobotoWhite(lbl) end
            end
            if fBgTex.Control and panel.ThemeDropdownWithSteppers then
                panel.ThemeDropdownWithSteppers(fBgTex.Control)
            end
            if fBgTex.Control and addon.InitBarTextureDropdown then
                addon.InitBarTextureDropdown(fBgTex.Control, bgTexSetting)
            end
            y = y - 34

            -- 4. Background Color (dropdown + inline swatch)
            local function bgColorOpts()
                local container = Settings.CreateControlTextContainer()
                container:Add("default", "Default")
                container:Add("texture", "Texture Original")
                container:Add("custom", "Custom")
                return container:GetData()
            end
            local function getBgColorMode()
                local t = getPartyDB() or {}
                return t.healthBarBackgroundColorMode or "default"
            end
            local function setBgColorMode(v)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarBackgroundColorMode = v or "default"
                applyNow()
            end
            local function getBgTint()
                local t = getPartyDB() or {}
                local c = t.healthBarBackgroundTint or {0, 0, 0, 1}
                return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
            end
            local function setBgTint(r, g, b, a)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
                applyNow()
            end
            yRef = { y = y }
            panel.DropdownWithInlineSwatch(frame, yRef, {
                label = "Background Color",
                getMode = getBgColorMode,
                setMode = setBgColorMode,
                getColor = getBgTint,
                setColor = setBgTint,
                options = bgColorOpts,
                insideButton = true,
            })
            y = yRef.y

            -- 5. Background Opacity slider (0-100)
            local function getBgOpacity()
                local t = getPartyDB() or {}
                return t.healthBarBackgroundOpacity or 50
            end
            local function setBgOpacity(v)
                local t = ensurePartyDB()
                if not t then return end
                t.healthBarBackgroundOpacity = tonumber(v) or 50
                applyNow()
            end
            local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
            local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
            bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                return tostring(math.floor(v + 0.5))
            end)
            local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                name = "Background Opacity",
                setting = bgOpacitySetting,
                options = bgOpacityOpts
            })
            local fOpa = CreateFrame("Frame", nil, frame, "SettingsSliderControlTemplate")
            fOpa.GetElementData = function() return bgOpacityInit end
            fOpa:SetPoint("TOPLEFT", 4, y)
            fOpa:SetPoint("TOPRIGHT", -16, y)
            bgOpacityInit:InitFrame(fOpa)
            if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
            if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
        end
        table.insert(init, styleInit)

        -- 5. Text section header (contains tabbed section)
        addHeader("Text", "Text")

        local textTabs = {
            sectionTitle = "",
            tabAText = "Player Name",
            build = function(frame)
                local function getTextDB()
                    local db = addon and addon.db and addon.db.profile
                    local gf = db and rawget(db, "groupFrames") or nil
                    local party = gf and rawget(gf, "party") or nil
                    return party and rawget(party, "textPlayerName") or nil
                end

                local function ensureTextDB()
                    local db = addon and addon.db and addon.db.profile
                    if not db then return nil end
                    db.groupFrames = db.groupFrames or {}
                    db.groupFrames.party = db.groupFrames.party or {}
                    db.groupFrames.party.textPlayerName = db.groupFrames.party.textPlayerName or {
                        fontFace = "FRIZQT__",
                        size = 12,
                        style = "OUTLINE",
                        color = { 1, 1, 1, 1 },
                        offset = { x = 0, y = 0 },
                    }
                    return db.groupFrames.party.textPlayerName
                end

                local function applyNow()
                    if addon and addon.ApplyPartyFrameTextStyle then
                        addon.ApplyPartyFrameTextStyle()
                    end
                end

                local function fontOptions()
                    if addon and addon.BuildFontOptionsContainer then
                        return addon.BuildFontOptionsContainer()
                    end
                    return Settings.CreateControlTextContainer():GetData()
                end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                local function addDropdown(parent, label, optionsProvider, getter, setter, yRef)
                    local setting = CreateLocalSetting(label, "string", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                        name = label,
                        setting = setting,
                        options = optionsProvider,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    local lbl = row and (row.Text or row.Label)
                    if lbl and panel and panel.ApplyRobotoWhite then
                        panel.ApplyRobotoWhite(lbl)
                    end
                    if row.Control and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(row.Control)
                    end
                    if label:lower():find("font", 1, true) and not label:lower():find("style", 1, true) then
                        if row.Control and row.Control.Dropdown and addon and addon.InitFontDropdown then
                            addon.InitFontDropdown(row.Control.Dropdown, setting, optionsProvider)
                        end
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                        return fmtInt(v)
                    end)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                        name = label,
                        setting = setting,
                        options = options,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    if row.Text and panel and panel.ApplyRobotoWhite then
                        panel.ApplyRobotoWhite(row.Text)
                    end
                    if panel and panel.ApplyControlTheme then
                        panel.ApplyControlTheme(row)
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                local function addStyleDropdown(parent, label, getter, setter, yRef)
                    local function styleOptions()
                        local container = Settings.CreateControlTextContainer()
                        container:Add("NONE", "Regular")
                        container:Add("OUTLINE", "Outline")
                        container:Add("THICKOUTLINE", "Thick Outline")
                        container:Add("HEAVYTHICKOUTLINE", "Heavy Thick Outline")
                        container:Add("SHADOW", "Shadow")
                        container:Add("SHADOWOUTLINE", "Shadow Outline")
                        container:Add("SHADOWTHICKOUTLINE", "Shadow Thick Outline")
                        container:Add("HEAVYSHADOWTHICKOUTLINE", "Heavy Shadow Thick Outline")
                        return container:GetData()
                    end
                    addDropdown(parent, label, styleOptions, getter, setter, yRef)
                end

                local function addColorRow(parent, label, getter, setter, yRef)
                    local row = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                    row:SetHeight(26)
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    if row.Text then
                        row.Text:SetText(label)
                        if panel and panel.ApplyRobotoWhite then
                            panel.ApplyRobotoWhite(row.Text)
                        end
                    end
                    local right = CreateFrame("Frame", nil, row)
                    right:SetSize(250, 26)
                    right:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    row.Text:ClearAllPoints()
                    row.Text:SetPoint("LEFT", row, "LEFT", 36.5, 0)
                    row.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                    row.Text:SetJustifyH("LEFT")
                    local function getColorTable()
                        local r, g, b, a = getter()
                        return { r or 1, g or 1, b or 1, a or 1 }
                    end
                    local function setColorTable(r, g, b, a)
                        setter(r, g, b, a)
                    end
                    local swatch = CreateColorSwatch(right, getColorTable, setColorTable, true)
                    swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                    yRef.y = yRef.y - 34
                    return row
                end

                if frame.PageA then
                    local y = { y = -50 }

                    addDropdown(frame.PageA, "Player Name Font", fontOptions,
                        function()
                            local cfg = getTextDB() or {}
                            return cfg.fontFace or "FRIZQT__"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.fontFace = v end
                            applyNow()
                        end,
                        y)

                    addSlider(frame.PageA, "Player Name Size", 6, 32, 1,
                        function()
                            local cfg = getTextDB() or {}
                            return tonumber(cfg.size) or 12
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.size = tonumber(v) or 12 end
                            applyNow()
                        end,
                        y)

                    addStyleDropdown(frame.PageA, "Player Name Style",
                        function()
                            local cfg = getTextDB() or {}
                            return cfg.style or "OUTLINE"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.style = v end
                            applyNow()
                        end,
                        y)

                    addColorRow(frame.PageA, "Player Name Color",
                        function()
                            local cfg = getTextDB() or {}
                            local c = cfg.color or { 1, 1, 1, 1 }
                            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                        end,
                        function(r, g, b, a)
                            local cfg = ensureTextDB()
                            if cfg then cfg.color = { r or 1, g or 1, b or 1, a or 1 } end
                            applyNow()
                        end,
                        y)

                    -- Player Name Alignment (9-way anchor)
                    local function alignmentOptions()
                        local container = Settings.CreateControlTextContainer()
                        container:Add("TOPLEFT", "Top-Left")
                        container:Add("TOP", "Top-Center")
                        container:Add("TOPRIGHT", "Top-Right")
                        container:Add("LEFT", "Left")
                        container:Add("CENTER", "Center")
                        container:Add("RIGHT", "Right")
                        container:Add("BOTTOMLEFT", "Bottom-Left")
                        container:Add("BOTTOM", "Bottom-Center")
                        container:Add("BOTTOMRIGHT", "Bottom-Right")
                        return container:GetData()
                    end
                    addDropdown(frame.PageA, "Player Name Alignment", alignmentOptions,
                        function()
                            local cfg = getTextDB() or {}
                            return cfg.anchor or "TOPLEFT"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.anchor = v or "TOPLEFT" end
                            applyNow()
                        end,
                        y)

                    addSlider(frame.PageA, "Player Name Offset X", -50, 50, 1,
                        function()
                            local cfg = getTextDB() or {}
                            local o = cfg.offset or {}
                            return tonumber(o.x) or 0
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then
                                cfg.offset = cfg.offset or {}
                                cfg.offset.x = tonumber(v) or 0
                            end
                            applyNow()
                        end,
                        y)

                    addSlider(frame.PageA, "Player Name Offset Y", -50, 50, 1,
                        function()
                            local cfg = getTextDB() or {}
                            local o = cfg.offset or {}
                            return tonumber(o.y) or 0
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then
                                cfg.offset = cfg.offset or {}
                                cfg.offset.y = tonumber(v) or 0
                            end
                            applyNow()
                        end,
                        y)
                end
            end,
        }

        local textInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", textTabs)
        -- Height: 50 top + (7 controls * 34) = 288px, rounded to 304px for safety
        textInit.GetExtent = function() return 304 end
        textInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Text")
        end)
        table.insert(init, textInit)

        -- 6. Visibility section header (placeholder)
        addHeader("Visibility", "Visibility")

        -- Set right pane title
        if right.SetTitle then
            right:SetTitle(title)
        end

        right:Display(init)
    end

    return { mode = "list", render = render, componentId = componentId }
end

--------------------------------------------------------------------------------
-- Raid Frames Renderer (gfRaid)
--------------------------------------------------------------------------------
-- Collapsible sections: Positioning, Sizing*, Border, Style, Text, Visibility
-- *Sizing uses a tabbed section with 10-man, 25-man, 40-man tabs
--------------------------------------------------------------------------------

function panel.RenderGFRaid()
    local componentId = "gfRaid"
    local title = "Raid Frames"

    local render = function()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        local init = {}

        -- Shared conditional enable/disable state for this render pass.
        -- We store references for the *current* acquired row frames so a change in one control
        -- (e.g., Groups) can update availability of related controls (Border / Sort By / Column Size)
        -- without requiring a full category rebuild.
        panel._gfRaidConditionalFrames = panel._gfRaidConditionalFrames or {}
        local cond = panel._gfRaidConditionalFrames
        -- IMPORTANT:
        -- Do NOT clear these references on every render. The Settings system recycles row frames,
        -- and our CreateLocalSetting closures can continue firing after a refresh. Clearing here
        -- would make subsequent availability updates no-op (exactly the “works once” symptom).

        -- Helper to add a collapsible section header
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

        local function getRaidGroupDisplayType()
            local rf = getRaidFrame()
            local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
            local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
            if not (rf and EM and RGD and addon and addon.EditMode and addon.EditMode.GetSetting) then
                return (RGD and RGD.SeparateGroupsVertical) or 0
            end
            return addon.EditMode.GetSetting(rf, EM.RaidGroupDisplayType) or RGD.SeparateGroupsVertical
        end

        local function isCombineGroupsMode()
            local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
            if not RGD then return false end
            -- Prefer cached value (updated immediately by dropdown steppers) over Edit Mode reads.
            local v = (cond and cond.groupsValue) or getRaidGroupDisplayType()
            return v == RGD.CombineGroupsVertical or v == RGD.CombineGroupsHorizontal
        end

        local function setRowEnabled(rowFrame, enabled)
            if not rowFrame then return end
            rowFrame:SetAlpha(enabled and 1 or 0.5)

            -- Try to disable the interactive widget(s) inside the standard Blizzard templates.
            local control = rowFrame.Control or rowFrame
            local dropdown = control and control.Dropdown
            local slider = control and (control.Slider or control.slider or rowFrame.Slider)
            local checkbox = rowFrame.Checkbox or rowFrame.CheckBox or (control and control.Checkbox)

            if dropdown and dropdown.SetEnabled then
                pcall(dropdown.SetEnabled, dropdown, enabled)
            elseif dropdown and dropdown.EnableMouse then
                pcall(dropdown.EnableMouse, dropdown, enabled)
            end

            if slider and slider.SetEnabled then
                pcall(slider.SetEnabled, slider, enabled)
            elseif slider and slider.EnableMouse then
                pcall(slider.EnableMouse, slider, enabled)
            end

            if checkbox and checkbox.SetEnabled then
                pcall(checkbox.SetEnabled, checkbox, enabled)
            elseif checkbox and checkbox.EnableMouse then
                pcall(checkbox.EnableMouse, checkbox, enabled)
            end
        end

        local function applyConditionalAvailability()
            local combine = isCombineGroupsMode()
            -- Sort By + Column Size are Combine-only
            if cond.posSortRow then
                local r = cond.posSortRow
                setRowEnabled(r._ScooterGF_RaidSortByRow, combine)
                setRowEnabled(r._ScooterGF_RaidColumnSizeRow, combine)
            end
            -- Display Border is Separate-only
            if cond.borderRow then
                setRowEnabled(cond.borderRow, not combine)
            end
        end

        -- 1. Positioning & Sorting section header
        addHeader("Positioning", "Positioning & Sorting")

        -- Positioning & Sorting section content (flat; NO 10/25/40 tabs).
        -- IMPORTANT: ViewRaidSize is a *preview* selector in Edit Mode; these settings are global.
        do
            local posSortInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
            -- Height: 16 top + 34 Groups dropdown + 34 Sort By dropdown + 34 Column Size slider = 118; use 140 for clearance.
            posSortInit.GetExtent = function() return 140 end
            posSortInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Positioning")
            end)
            posSortInit.InitFrame = function(self, frame)
                if frame._ScooterGFRaidPosSortBuilt then
                    -- Re-register references for this render pass (rows get recycled).
                    cond.posSortRow = frame
                    cond.groupsValue = frame._ScooterGF_RaidGroupsValue or cond.groupsValue
                    -- If this row instance is being reused after Edit Mode changes, refresh the cached
                    -- values from Edit Mode so reopening ScooterMod shows the latest state immediately.
                    if frame._ScooterGF_RefreshFromEditMode then
                        pcall(frame._ScooterGF_RefreshFromEditMode)
                    end
                    -- Re-apply conditional enable/disable in case the frame is recycled and state changed.
                    applyConditionalAvailability()
                    return
                end
                frame._ScooterGFRaidPosSortBuilt = true

                if frame.Text then
                    frame.Text:SetText("")
                    frame.Text:Hide()
                end

                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
                local Sort = _G.Enum and _G.Enum.SortPlayersBy
                if not (EM and RGD and Sort) then return end

                local function groupsOptions()
                    local container = Settings.CreateControlTextContainer()
                    container:Add(RGD.SeparateGroupsVertical, "Separate Groups (Vertical)")
                    container:Add(RGD.SeparateGroupsHorizontal, "Separate Groups (Horizontal)")
                    container:Add(RGD.CombineGroupsVertical, "Combine Groups (Vertical)")
                    container:Add(RGD.CombineGroupsHorizontal, "Combine Groups (Horizontal)")
                    return container:GetData()
                end

                local function sortByOptions()
                    local container = Settings.CreateControlTextContainer()
                    container:Add(Sort.Role, "Role")
                    container:Add(Sort.Group, "Group")
                    container:Add(Sort.Alphabetical, "Alphabetical")
                    return container:GetData()
                end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                local function addDropdown(parent, label, optionsProvider, getter, setter, yRef)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                        name = label,
                        setting = setting,
                        options = optionsProvider,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    local lbl = row and (row.Text or row.Label)
                    if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                    if row.Control and panel and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(row.Control)
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                        return fmtInt(v)
                    end)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                        name = label,
                        setting = setting,
                        options = options,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    if row.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(row) end
                    yRef.y = yRef.y - 34
                    return row
                end

                local y = { y = -16 }

                -- Groups (RaidGroupDisplayType)
                frame._ScooterGF_RaidGroupsValue = getRaidGroupDisplayType()
                cond.groupsValue = frame._ScooterGF_RaidGroupsValue

                -- Expose a refresh helper so this row can resync its cached values when reused.
                frame._ScooterGF_RefreshFromEditMode = function()
                    local rf = getRaidFrame()
                    if not (rf and addon and addon.EditMode and addon.EditMode.GetSetting) then return end
                    frame._ScooterGF_RaidGroupsValue = addon.EditMode.GetSetting(rf, EM.RaidGroupDisplayType) or RGD.SeparateGroupsVertical
                    cond.groupsValue = frame._ScooterGF_RaidGroupsValue
                    frame._ScooterGF_RaidSortByValue = addon.EditMode.GetSetting(rf, EM.SortPlayersBy) or Sort.Role
                end
                local groupsRow = addDropdown(frame, "Groups", groupsOptions,
                    function()
                        -- Use cached value so steppers update immediately.
                        if frame._ScooterGF_RaidGroupsValue == nil then
                            frame._ScooterGF_RaidGroupsValue = getRaidGroupDisplayType()
                        end
                        return frame._ScooterGF_RaidGroupsValue
                    end,
                    function(v)
                        local val = tonumber(v) or RGD.SeparateGroupsVertical

                        -- Update local cache immediately so stepper arrows always advance instantly.
                        frame._ScooterGF_RaidGroupsValue = val
                        cond.groupsValue = val
                        applyConditionalAvailability()

                        -- Defer Edit Mode writes to avoid taint in dropdown Pick callbacks.
                        C_Timer.After(0, function()
                            local rf = getRaidFrame()
                            if not rf or not addon or not addon.EditMode or not addon.EditMode.WriteSetting then return end
                            addon.EditMode.WriteSetting(rf, EM.RaidGroupDisplayType, val, {
                                updaters = { "UpdateSystemSettingRaidGroupDisplayType" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                    y)

                -- Sort By (Combine Groups only)
                local sortByTooltip = "Controls how players are sorted within the combined raid view.\n\nOnly available when 'Groups' is set to 'Combine Groups'."
                frame._ScooterGF_RaidSortByValue = nil
                local sortByRow = addDropdown(frame, "Sort By", sortByOptions,
                    function()
                        -- Use cached value to keep dropdown steppers responsive.
                        if frame._ScooterGF_RaidSortByValue == nil then
                            local rf = getRaidFrame()
                            if not rf or not addon or not addon.EditMode or not addon.EditMode.GetSetting then
                                frame._ScooterGF_RaidSortByValue = Sort.Role
                            else
                                frame._ScooterGF_RaidSortByValue = addon.EditMode.GetSetting(rf, EM.SortPlayersBy) or Sort.Role
                            end
                        end
                        return frame._ScooterGF_RaidSortByValue
                    end,
                    function(v)
                        local val = tonumber(v) or Sort.Role
                        frame._ScooterGF_RaidSortByValue = val
                        C_Timer.After(0, function()
                            local rf = getRaidFrame()
                            if not rf or not addon or not addon.EditMode or not addon.EditMode.WriteSetting then return end
                            addon.EditMode.WriteSetting(rf, EM.SortPlayersBy, val, {
                                updaters = { "UpdateSystemSettingSortPlayersBy" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                    y)

                -- Column Size (RowSize) (Combine Groups only)
                local colSizeTooltip = "Sets the number of unit frames per row/column in the combined raid view.\n\nOnly available when 'Groups' is set to 'Combine Groups'."
                local colSizeRow = addSlider(frame, "Column Size", 2, 10, 1,
                    function()
                        local rf = getRaidFrame()
                        if not rf or not addon or not addon.EditMode or not addon.EditMode.GetSetting then return 2 end
                        return addon.EditMode.GetSetting(rf, EM.RowSize) or 2
                    end,
                    function(v)
                        local rf = getRaidFrame()
                        if not rf or not addon or not addon.EditMode or not addon.EditMode.WriteSetting then return end
                        local val = tonumber(v) or 2
                        val = math.max(2, math.min(10, val))
                        addon.EditMode.WriteSetting(rf, EM.RowSize, val, {
                            updaters = { "UpdateSystemSettingRowSize" },
                            suspendDuration = 0.25,
                        })
                    end,
                    y)

                -- Add info icons to the LEFT of the labels for Sort By and Column Size.
                local function addLeftInfoIcon(row, tooltipText)
                    if not (row and panel and panel.CreateInfoIcon) then return end
                    local labelFS = row.Text or row.Label
                    if not labelFS or row.ScooterInfoIcon then return end

                    row.ScooterInfoIcon = panel.CreateInfoIcon(row, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                    local icon = row.ScooterInfoIcon
                    if not icon then return end

                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
                    labelFS:ClearAllPoints()
                    labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    labelFS:SetJustifyH("LEFT")

                    -- Preserve the default relationship: keep the label from overlapping the control area.
                    local ctrl = row.Control
                    local slider = (ctrl and ctrl.Slider) or row.Slider
                    local dropdown = ctrl and ctrl.Dropdown
                    if slider then
                        labelFS:SetPoint("RIGHT", slider, "LEFT", -8, 0)
                    elseif dropdown then
                        labelFS:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
                    else
                        labelFS:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    end
                end
                addLeftInfoIcon(sortByRow, sortByTooltip)
                addLeftInfoIcon(colSizeRow, colSizeTooltip)

                -- Persist references on the row so future re-inits can re-register.
                frame._ScooterGF_RaidGroupsRow = groupsRow
                frame._ScooterGF_RaidSortByRow = sortByRow
                frame._ScooterGF_RaidColumnSizeRow = colSizeRow
                cond.posSortRow = frame

                applyConditionalAvailability()
            end
            table.insert(init, posSortInit)
        end

        -- 2. Sizing section header (flat; NO 10/25/40 tabs)
        addHeader("Sizing", "Sizing")
        do
            local sizeInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
            -- Height: 16 top + 34 width + 34 height = 84; use 100 for clearance.
            sizeInit.GetExtent = function() return 100 end
            sizeInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Sizing")
            end)
            sizeInit.InitFrame = function(self, frame)
                if frame._ScooterGFRaidSizingBuilt then return end
                frame._ScooterGFRaidSizingBuilt = true

                if frame.Text then
                    frame.Text:SetText("")
                    frame.Text:Hide()
                end

                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                if not EM then return end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                        return fmtInt(v)
                    end)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                        name = label,
                        setting = setting,
                        options = options,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    if row.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(row) end
                    yRef.y = yRef.y - 34
                    return row
                end

                local y = { y = -16 }

                -- Frame Width (raw 72..144, step 2)
                addSlider(frame, "Frame Width", 72, 144, 2,
                    function()
                        local rf = getRaidFrame()
                        if not rf or not addon or not addon.EditMode or not addon.EditMode.GetSetting then return 72 end
                        return addon.EditMode.GetSetting(rf, EM.FrameWidth) or 72
                    end,
                    function(v)
                        local rf = getRaidFrame()
                        if not rf or not addon or not addon.EditMode or not addon.EditMode.WriteSetting then return end
                        local val = tonumber(v) or 72
                        val = math.max(72, math.min(144, val))
                        addon.EditMode.WriteSetting(rf, EM.FrameWidth, val, {
                            updaters = { "UpdateSystemSettingFrameWidth" },
                            suspendDuration = 0.25,
                        })
                    end,
                    y)

                -- Frame Height (raw 36..72, step 2)
                addSlider(frame, "Frame Height", 36, 72, 2,
                    function()
                        local rf = getRaidFrame()
                        if not rf or not addon or not addon.EditMode or not addon.EditMode.GetSetting then return 36 end
                        return addon.EditMode.GetSetting(rf, EM.FrameHeight) or 36
                    end,
                    function(v)
                        local rf = getRaidFrame()
                        if not rf or not addon or not addon.EditMode or not addon.EditMode.WriteSetting then return end
                        local val = tonumber(v) or 36
                        val = math.max(36, math.min(72, val))
                        addon.EditMode.WriteSetting(rf, EM.FrameHeight, val, {
                            updaters = { "UpdateSystemSettingFrameHeight" },
                            suspendDuration = 0.25,
                        })
                    end,
                    y)
            end
            table.insert(init, sizeInit)
        end

        -- 3. Border section header (empty placeholder)
        addHeader("Border", "Border")

        -- Border section content: Display Border (Edit Mode) + info icon tooltip.
        do
            local label = "Display Border"
            local tooltipText = "Enables Blizzard's default border around each raid GROUP.\n\nOnly available when 'Groups' is set to 'Separate Groups'.\n\nThe border settings below are ScooterMod custom borders that apply to each individual unit frame."

            local function getter()
                local rf = getRaidFrame()
                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                if not (rf and EM and addon and addon.EditMode and addon.EditMode.GetSetting) then
                    return false
                end
                return (addon.EditMode.GetSetting(rf, EM.DisplayBorder) or 0) == 1
            end

            local function setter(state)
                local rf = getRaidFrame()
                local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
                if not (rf and EM and addon and addon.EditMode and addon.EditMode.WriteSetting) then
                    return
                end
                local v = (state and true or false) and 1 or 0
                C_Timer.After(0, function()
                    addon.EditMode.WriteSetting(rf, EM.DisplayBorder, v, {
                        updaters = { "UpdateSystemSettingDisplayBorder" },
                        suspendDuration = 0.25,
                    })
                end)
            end

            local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
            local cbInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
            cbInit.GetExtent = function() return 34 end
            cbInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Border")
            end)

            do
                local baseInitFrame = cbInit.InitFrame
                cbInit.InitFrame = function(self, frame)
                    -- Build with default initializer first
                    if baseInitFrame then
                        baseInitFrame(self, frame)
                    end

                    if panel and panel.ApplyRobotoWhite then
                        if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
                        local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                        if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                        if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                    end

                    -- Info icon positioned BETWEEN checkbox and label (icon is "to the left of the setting label").
                    local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                    local labelFS = frame.Text or (cb and cb.Text)
                    if cb and labelFS and panel and panel.CreateInfoIcon and not frame.ScooterDisplayBorderInfoIcon then
                        frame.ScooterDisplayBorderInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 0, 0, 32)
                        local icon = frame.ScooterDisplayBorderInfoIcon
                        if icon then
                            icon:ClearAllPoints()
                            icon:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                            labelFS:ClearAllPoints()
                            labelFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                            labelFS:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                            labelFS:SetJustifyH("LEFT")
                        end
                    end

                    -- Register this specific row so Groups can disable it when Combine Groups is selected.
                    cond.borderRow = frame
                    applyConditionalAvailability()
                end
            end

            table.insert(init, cbInit)
        end

        -- 4. Style section header with Health Bar styling controls
        addHeader("Style", "Style")

        -- Style section content: Health Bar Foreground/Background Texture & Color
        -- Uses ScooterListElementTemplate for direct control layout under collapsible header
        local styleInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
        -- Height: 16 top + 34 foreground tex + 34 fg color + 24 spacer + 34 bg tex + 34 bg color + 48 opacity
        styleInit.GetExtent = function() return 224 end
        styleInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Style")
        end)
        styleInit.InitFrame = function(self, frame)
            -- Avoid rebuilding if already built
            if frame._ScooterRaidStyleBuilt then return end
            frame._ScooterRaidStyleBuilt = true

            -- Hide default list element text
            if frame.Text then
                frame.Text:SetText("")
                frame.Text:Hide()
            end

            -- Helper: ensure groupFrames.raid DB exists
            local function ensureRaidDB()
                local db = addon and addon.db and addon.db.profile
                if not db then return nil end
                db.groupFrames = db.groupFrames or {}
                db.groupFrames.raid = db.groupFrames.raid or {}
                return db.groupFrames.raid
            end

            local function applyNow()
                if addon and addon.ApplyRaidFrameHealthBarStyle then
                    addon.ApplyRaidFrameHealthBarStyle()
                end
            end

            local y = -16

            -- 1. Foreground Texture dropdown
            local function texOpts() return addon.BuildBarTextureOptionsContainer() end
            local function getTex()
                local t = ensureRaidDB() or {}
                return t.healthBarTexture or "default"
            end
            local function setTex(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarTexture = v
                applyNow()
            end
            local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
            local initTexDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "Foreground Texture",
                setting = texSetting,
                options = texOpts
            })
            local fTex = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            fTex.GetElementData = function() return initTexDrop end
            fTex:SetPoint("TOPLEFT", 4, y)
            fTex:SetPoint("TOPRIGHT", -16, y)
            initTexDrop:InitFrame(fTex)
            if panel and panel.ApplyRobotoWhite then
                local lbl = fTex and (fTex.Text or fTex.Label)
                if lbl then panel.ApplyRobotoWhite(lbl) end
            end
            if fTex.Control and panel.ThemeDropdownWithSteppers then
                panel.ThemeDropdownWithSteppers(fTex.Control)
            end
            if fTex.Control and addon.InitBarTextureDropdown then
                addon.InitBarTextureDropdown(fTex.Control, texSetting)
            end
            y = y - 34

            -- 2. Foreground Color (dropdown + inline swatch)
            local function fgColorOpts()
                local container = Settings.CreateControlTextContainer()
                container:Add("default", "Default")
                container:Add("texture", "Texture Original")
                container:Add("class", "Class Color")
                container:Add("custom", "Custom")
                return container:GetData()
            end
            local function getFgColorMode()
                local t = ensureRaidDB() or {}
                return t.healthBarColorMode or "default"
            end
            local function setFgColorMode(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarColorMode = v or "default"
                applyNow()
            end
            local function getFgTint()
                local t = ensureRaidDB() or {}
                local c = t.healthBarTint or {1, 1, 1, 1}
                return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
            end
            local function setFgTint(r, g, b, a)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarTint = { r or 1, g or 1, b or 1, a or 1 }
                applyNow()
            end
            local yRef = { y = y }
            panel.DropdownWithInlineSwatch(frame, yRef, {
                label = "Foreground Color",
                getMode = getFgColorMode,
                setMode = setFgColorMode,
                getColor = getFgTint,
                setColor = setFgTint,
                options = fgColorOpts,
                insideButton = true,
            })
            y = yRef.y

            -- Spacer between Foreground and Background
            do
                local spacer = CreateFrame("Frame", nil, frame, "SettingsListElementTemplate")
                spacer:SetHeight(20)
                spacer:SetPoint("TOPLEFT", 4, y)
                spacer:SetPoint("TOPRIGHT", -16, y)
                if spacer.Text then spacer.Text:SetText("") end
                y = y - 24
            end

            -- 3. Background Texture dropdown
            local function getBgTex()
                local t = ensureRaidDB() or {}
                return t.healthBarBackgroundTexture or "default"
            end
            local function setBgTex(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundTexture = v
                applyNow()
            end
            local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
            local initBgTexDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "Background Texture",
                setting = bgTexSetting,
                options = texOpts
            })
            local fBgTex = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            fBgTex.GetElementData = function() return initBgTexDrop end
            fBgTex:SetPoint("TOPLEFT", 4, y)
            fBgTex:SetPoint("TOPRIGHT", -16, y)
            initBgTexDrop:InitFrame(fBgTex)
            if panel and panel.ApplyRobotoWhite then
                local lbl = fBgTex and (fBgTex.Text or fBgTex.Label)
                if lbl then panel.ApplyRobotoWhite(lbl) end
            end
            if fBgTex.Control and panel.ThemeDropdownWithSteppers then
                panel.ThemeDropdownWithSteppers(fBgTex.Control)
            end
            if fBgTex.Control and addon.InitBarTextureDropdown then
                addon.InitBarTextureDropdown(fBgTex.Control, bgTexSetting)
            end
            y = y - 34

            -- 4. Background Color (dropdown + inline swatch)
            local function bgColorOpts()
                local container = Settings.CreateControlTextContainer()
                container:Add("default", "Default")
                container:Add("texture", "Texture Original")
                container:Add("custom", "Custom")
                return container:GetData()
            end
            local function getBgColorMode()
                local t = ensureRaidDB() or {}
                return t.healthBarBackgroundColorMode or "default"
            end
            local function setBgColorMode(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundColorMode = v or "default"
                applyNow()
            end
            local function getBgTint()
                local t = ensureRaidDB() or {}
                local c = t.healthBarBackgroundTint or {0, 0, 0, 1}
                return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
            end
            local function setBgTint(r, g, b, a)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
                applyNow()
            end
            yRef = { y = y }
            panel.DropdownWithInlineSwatch(frame, yRef, {
                label = "Background Color",
                getMode = getBgColorMode,
                setMode = setBgColorMode,
                getColor = getBgTint,
                setColor = setBgTint,
                options = bgColorOpts,
                insideButton = true,
            })
            y = yRef.y

            -- 5. Background Opacity slider (0-100)
            local function getBgOpacity()
                local t = ensureRaidDB() or {}
                return t.healthBarBackgroundOpacity or 50
            end
            local function setBgOpacity(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundOpacity = tonumber(v) or 50
                applyNow()
            end
            local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
            local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
            bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                return tostring(math.floor(v + 0.5))
            end)
            local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                name = "Background Opacity",
                setting = bgOpacitySetting,
                options = bgOpacityOpts
            })
            local fOpa = CreateFrame("Frame", nil, frame, "SettingsSliderControlTemplate")
            fOpa.GetElementData = function() return bgOpacityInit end
            fOpa:SetPoint("TOPLEFT", 4, y)
            fOpa:SetPoint("TOPRIGHT", -16, y)
            bgOpacityInit:InitFrame(fOpa)
            if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
            if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
        end
        table.insert(init, styleInit)

        -- 5. Text section header (contains tabbed section)
        addHeader("Text", "Text")

        -- Text tabbed section: Player Name tab (more tabs can be added later)
        local textTabs = {
            sectionTitle = "",
            tabAText = "Player Name",
            build = function(frame)
                -- Helper: read groupFrames.raid.textPlayerName DB (Zero-Touch: does not create tables)
                local function getTextDB()
                    local db = addon and addon.db and addon.db.profile
                    local gf = db and rawget(db, "groupFrames") or nil
                    local raid = gf and rawget(gf, "raid") or nil
                    return raid and rawget(raid, "textPlayerName") or nil
                end

                -- Helper: ensure groupFrames.raid.textPlayerName DB exists (for setters only)
                local function ensureTextDB()
                    local db = addon and addon.db and addon.db.profile
                    if not db then return nil end
                    db.groupFrames = db.groupFrames or {}
                    db.groupFrames.raid = db.groupFrames.raid or {}
                    db.groupFrames.raid.textPlayerName = db.groupFrames.raid.textPlayerName or {
                        fontFace = "FRIZQT__",
                        size = 12,
                        style = "OUTLINE",
                        color = { 1, 1, 1, 1 },
                        offset = { x = 0, y = 0 },
                    }
                    return db.groupFrames.raid.textPlayerName
                end

                local function applyNow()
                    if addon and addon.ApplyRaidFrameTextStyle then
                        addon.ApplyRaidFrameTextStyle()
                    end
                end

                local function fontOptions()
                    if addon and addon.BuildFontOptionsContainer then
                        return addon.BuildFontOptionsContainer()
                    end
                    return Settings.CreateControlTextContainer():GetData()
                end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                -- Helper: create a dropdown control
                local function addDropdown(parent, label, optionsProvider, getter, setter, yRef)
                    local setting = CreateLocalSetting(label, "string", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                        name = label,
                        setting = setting,
                        options = optionsProvider,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    local lbl = row and (row.Text or row.Label)
                    if lbl and panel and panel.ApplyRobotoWhite then
                        panel.ApplyRobotoWhite(lbl)
                    end
                    -- Apply ScooterMod theming to dropdown text and arrows
                    if row.Control and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(row.Control)
                    end
                    -- Wire font picker for font dropdowns
                    if label:lower():find("font", 1, true) and not label:lower():find("style", 1, true) then
                        if row.Control and row.Control.Dropdown and addon and addon.InitFontDropdown then
                            addon.InitFontDropdown(row.Control.Dropdown, setting, optionsProvider)
                        end
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                -- Helper: create a slider control
                local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                        return fmtInt(v)
                    end)
                    local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                    local initializer = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                        name = label,
                        setting = setting,
                        options = options,
                    })
                    local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                    row.GetElementData = function() return initializer end
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    initializer:InitFrame(row)
                    if row.Text and panel and panel.ApplyRobotoWhite then
                        panel.ApplyRobotoWhite(row.Text)
                    end
                    if panel and panel.ApplyControlTheme then
                        panel.ApplyControlTheme(row)
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                -- Helper: create a font style dropdown
                local function addStyleDropdown(parent, label, getter, setter, yRef)
                    local function styleOptions()
                        local container = Settings.CreateControlTextContainer()
                        container:Add("NONE", "Regular")
                        container:Add("OUTLINE", "Outline")
                        container:Add("THICKOUTLINE", "Thick Outline")
                        container:Add("HEAVYTHICKOUTLINE", "Heavy Thick Outline")
                        container:Add("SHADOW", "Shadow")
                        container:Add("SHADOWOUTLINE", "Shadow Outline")
                        container:Add("SHADOWTHICKOUTLINE", "Shadow Thick Outline")
                        container:Add("HEAVYSHADOWTHICKOUTLINE", "Heavy Shadow Thick Outline")
                        return container:GetData()
                    end
                    addDropdown(parent, label, styleOptions, getter, setter, yRef)
                end

                -- Helper: create a color row with swatch
                local function addColorRow(parent, label, getter, setter, yRef)
                    local row = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                    row:SetHeight(26)
                    row:SetPoint("TOPLEFT", 4, yRef.y)
                    row:SetPoint("TOPRIGHT", -16, yRef.y)
                    if row.Text then
                        row.Text:SetText(label)
                        if panel and panel.ApplyRobotoWhite then
                            panel.ApplyRobotoWhite(row.Text)
                        end
                    end
                    local right = CreateFrame("Frame", nil, row)
                    right:SetSize(250, 26)
                    right:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    row.Text:ClearAllPoints()
                    row.Text:SetPoint("LEFT", row, "LEFT", 36.5, 0)
                    row.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                    row.Text:SetJustifyH("LEFT")
                    local function getColorTable()
                        local r, g, b, a = getter()
                        return { r or 1, g or 1, b or 1, a or 1 }
                    end
                    local function setColorTable(r, g, b, a)
                        setter(r, g, b, a)
                    end
                    local swatch = CreateColorSwatch(right, getColorTable, setColorTable, true)
                    swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                    yRef.y = yRef.y - 34
                    return row
                end

                -- PageA: Player Name text settings (Baseline 6 + Alignment)
                if frame.PageA then
                    local y = { y = -50 }

                    -- 1. Font Face
                    addDropdown(frame.PageA, "Player Name Font", fontOptions,
                        function()
                            local cfg = getTextDB() or {}
                            return cfg.fontFace or "FRIZQT__"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.fontFace = v end
                            applyNow()
                        end,
                        y)

                    -- 2. Font Size
                    addSlider(frame.PageA, "Player Name Size", 6, 32, 1,
                        function()
                            local cfg = getTextDB() or {}
                            return tonumber(cfg.size) or 12
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.size = tonumber(v) or 12 end
                            applyNow()
                        end,
                        y)

                    -- 3. Font Style
                    addStyleDropdown(frame.PageA, "Player Name Style",
                        function()
                            local cfg = getTextDB() or {}
                            return cfg.style or "OUTLINE"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.style = v end
                            applyNow()
                        end,
                        y)

                    -- 4. Font Color
                    addColorRow(frame.PageA, "Player Name Color",
                        function()
                            local cfg = getTextDB() or {}
                            local c = cfg.color or { 1, 1, 1, 1 }
                            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                        end,
                        function(r, g, b, a)
                            local cfg = ensureTextDB()
                            if cfg then cfg.color = { r or 1, g or 1, b or 1, a or 1 } end
                            applyNow()
                        end,
                        y)

                    -- 5. Player Name Alignment (9-way anchor)
                    local function alignmentOptions()
                        local container = Settings.CreateControlTextContainer()
                        container:Add("TOPLEFT", "Top-Left")
                        container:Add("TOP", "Top-Center")
                        container:Add("TOPRIGHT", "Top-Right")
                        container:Add("LEFT", "Left")
                        container:Add("CENTER", "Center")
                        container:Add("RIGHT", "Right")
                        container:Add("BOTTOMLEFT", "Bottom-Left")
                        container:Add("BOTTOM", "Bottom-Center")
                        container:Add("BOTTOMRIGHT", "Bottom-Right")
                        return container:GetData()
                    end
                    addDropdown(frame.PageA, "Player Name Alignment", alignmentOptions,
                        function()
                            local cfg = getTextDB() or {}
                            return cfg.anchor or "TOPLEFT"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.anchor = v or "TOPLEFT" end
                            applyNow()
                        end,
                        y)

                    -- 6. X Offset
                    addSlider(frame.PageA, "Player Name Offset X", -50, 50, 1,
                        function()
                            local cfg = getTextDB() or {}
                            local o = cfg.offset or {}
                            return tonumber(o.x) or 0
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then
                                cfg.offset = cfg.offset or {}
                                cfg.offset.x = tonumber(v) or 0
                            end
                            applyNow()
                        end,
                        y)

                    -- 7. Y Offset
                    addSlider(frame.PageA, "Player Name Offset Y", -50, 50, 1,
                        function()
                            local cfg = getTextDB() or {}
                            local o = cfg.offset or {}
                            return tonumber(o.y) or 0
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then
                                cfg.offset = cfg.offset or {}
                                cfg.offset.y = tonumber(v) or 0
                            end
                            applyNow()
                        end,
                        y)
                end
            end,
        }

        local textInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", textTabs)
        -- Height: 50 top + (7 controls * 34) = 288px, rounded to 304px for safety
        textInit.GetExtent = function() return 304 end
        textInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Text")
        end)
        table.insert(init, textInit)

        -- 6. Visibility section header (empty placeholder)
        addHeader("Visibility", "Visibility")

        -- Set right pane title
        if right.SetTitle then
            right:SetTitle(title)
        end

        right:Display(init)
    end

    return { mode = "list", render = render, componentId = componentId }
end

