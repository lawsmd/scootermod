local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local function getPresetList()
    if not addon.Presets or not addon.Presets.GetList then
        return {}
    end
    return addon.Presets:GetList()
end

local function clampCarouselIndex(model, total)
    if total <= 0 then
        model.index = 1
        return
    end
    if model.index < 1 then model.index = 1 end
    if model.index > total then model.index = total end
end

local function ensureCarouselModel()
    panel._presetCarousel = panel._presetCarousel or { index = 1 }
    local list = getPresetList()
    clampCarouselIndex(panel._presetCarousel, #list)
    return panel._presetCarousel, list
end

local function formatBulletList(items)
    if type(items) ~= "table" or #items == 0 then
        return ""
    end
    local lines = {}
    for _, item in ipairs(items) do
        table.insert(lines, "• " .. tostring(item))
    end
    return table.concat(lines, "\n")
end

-- Forward declaration for updatePresetContent
local updatePresetContent

local function setPresetByIndex(newIndex)
    local model, list = ensureCarouselModel()
    local total = #list
    if total == 0 then return end
    if newIndex < 1 then newIndex = 1 end
    if newIndex > total then newIndex = total end
    model.index = newIndex
    -- Directly update the content instead of relying on panel refresh
    updatePresetContent()
end

local function updateCTAState(frame, preset)
    local canApplyPayload = addon.Presets and addon.Presets:IsPayloadReady(preset)
    local depsOk, depsErr = addon.Presets and addon.Presets:CheckDependencies(preset) or false, "Preset system unavailable."
    local actionable = canApplyPayload and depsOk and not preset.comingSoon

    local disabledReason
    if not canApplyPayload then
        disabledReason = "Preset payload pending."
    elseif not depsOk then
        disabledReason = depsErr
    elseif preset.comingSoon then
        disabledReason = "Preset not yet published."
    end

    frame.PrimaryButton:SetEnabled(actionable)
    frame.PrimaryButton:SetAlpha(actionable and 1 or 0.65)
    frame.PrimaryButton:SetText("Create a new profile using this preset")
    if not frame.PrimaryButton.tooltipAnchor then
        local anchor = CreateFrame("Frame", nil, frame.PrimaryButton)
        anchor:SetAllPoints()
        anchor:EnableMouse(true)
        frame.PrimaryButton.tooltipAnchor = anchor
    end
    frame.PrimaryButton.tooltipAnchor:EnableMouse(not actionable)
    frame.PrimaryButton.tooltipAnchor:SetScript("OnEnter", nil)
    frame.PrimaryButton.tooltipAnchor:SetScript("OnLeave", nil)
    if not actionable and disabledReason then
        frame.PrimaryButton.tooltipAnchor:SetScript("OnEnter", function()
            GameTooltip:SetOwner(frame.PrimaryButton, "ANCHOR_RIGHT")
            GameTooltip:SetText(disabledReason, 1, 1, 1, true)
        end)
        frame.PrimaryButton.tooltipAnchor:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
end

-- Create a setting object for the preset selector dropdown
local function createPresetSetting(list)
    local setting = {}
    function setting:GetName() return "Preset" end
    function setting:GetVariable() return "ScooterPresetSelector" end
    function setting:GetVariableType() return "string" end
    function setting:GetDefaultValue() return list[1] and list[1].id or "" end
    function setting:GetValue()
        local model = panel._presetCarousel or { index = 1 }
        local preset = list[model.index]
        return preset and preset.id or ""
    end
    function setting:SetValue(v)
        for i, preset in ipairs(list) do
            if preset.id == v then
                setPresetByIndex(i)
                break
            end
        end
    end
    function setting:SetValueToDefault() end
    function setting:HasCommitFlag() return false end
    return setting
end

local function createPresetOptions(list)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, preset in ipairs(list) do
            container:Add(preset.id, preset.name or preset.id)
        end
        return container:GetData()
    end
end

local function buildHeroWidgets(frame)
    frame:SetHeight(480)
    -- Hide any recycled elements from other templates
    if frame.InfoText then frame.InfoText:Hide() end
    if frame.ButtonContainer then frame.ButtonContainer:Hide() end
    if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
    if frame.RenameBtn then frame.RenameBtn:Hide() end
    if frame.CopyBtn then frame.CopyBtn:Hide() end
    if frame.DeleteBtn then frame.DeleteBtn:Hide() end

    -- Disable the hover highlight effect from SettingsListElementTemplate
    if frame.HighlightTexture then frame.HighlightTexture:Hide() end
    if frame.Highlight then frame.Highlight:Hide() end
    if frame.MouseoverOverlay then frame.MouseoverOverlay:Hide() end
    -- Hide the HoverBackground from the Tooltip child frame
    if frame.Tooltip and frame.Tooltip.HoverBackground then
        frame.Tooltip.HoverBackground:Hide()
        frame.Tooltip.HoverBackground:SetAlpha(0)
    end
    -- Prevent the row itself from showing hover states
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)

    -- Only create widgets once
    if frame.PresetDropdownRow then return end

    -- Preset selector dropdown at the top using SettingsDropdownControlTemplate
    local dropdownRow = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
    dropdownRow:SetPoint("TOP", frame, "TOP", 0, 0)
    dropdownRow:SetSize(300, 40)
    frame.PresetDropdownRow = dropdownRow

    -- Hide the label portion of the dropdown template
    if dropdownRow.Text then dropdownRow.Text:Hide() end

    -- Center the control within the row
    if dropdownRow.Control then
        dropdownRow.Control:ClearAllPoints()
        dropdownRow.Control:SetPoint("CENTER", dropdownRow, "CENTER", 0, 0)
    end

    -- Hero image below dropdown
    local hero = frame:CreateTexture(nil, "ARTWORK")
    hero:SetPoint("TOP", dropdownRow, "BOTTOM", 0, -8)
    hero:SetSize(480, 270)
    hero:SetColorTexture(0.07, 0.07, 0.07, 1)
    frame.HeroTexture = hero

    -- Two-column section below image
    local columnContainer = CreateFrame("Frame", nil, frame)
    columnContainer:SetPoint("TOP", hero, "BOTTOM", 0, -16)
    columnContainer:SetSize(520, 100)
    frame.ColumnContainer = columnContainer

    -- Left column: "Designed for..."
    local leftHeader = columnContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    leftHeader:SetPoint("TOPLEFT", columnContainer, "TOPLEFT", 20, 0)
    leftHeader:SetText("Designed for...")
    leftHeader:SetJustifyH("LEFT")
    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(leftHeader, 18) end
    frame.LeftHeader = leftHeader

    local leftList = columnContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftList:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -6)
    leftList:SetWidth(240)
    leftList:SetJustifyH("LEFT")
    leftList:SetJustifyV("TOP")
    leftList:SetSpacing(4)
    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(leftList, 12) end
    frame.LeftList = leftList

    -- Right column: "Author also recommends..."
    local rightHeader = columnContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rightHeader:SetPoint("TOPLEFT", columnContainer, "TOP", 20, 0)
    rightHeader:SetText("Author also recommends...")
    rightHeader:SetJustifyH("LEFT")
    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(rightHeader, 18) end
    frame.RightHeader = rightHeader

    local rightList = columnContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightList:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -6)
    rightList:SetWidth(240)
    rightList:SetJustifyH("LEFT")
    rightList:SetJustifyV("TOP")
    rightList:SetSpacing(4)
    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(rightList, 12) end
    frame.RightList = rightList

    -- CTA button at the bottom, centered
    local cta = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cta:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    cta:SetSize(320, 32)
    cta:SetText("Create a new profile using this preset")
    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(cta) end
    frame.PrimaryButton = cta
end

local function initPresetDropdown(row, list)
    if not row.PresetDropdownRow then return end
    local dropdownRow = row.PresetDropdownRow

    -- Create setting and options for this render
    local setting = createPresetSetting(list)
    local optionsProvider = createPresetOptions(list)

    -- Initialize the dropdown control
    local data = { setting = setting, options = optionsProvider, name = "" }
    local init = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", data)
    dropdownRow.GetElementData = function() return init end
    init:InitFrame(dropdownRow)

    -- Hide label
    if dropdownRow.Text then dropdownRow.Text:Hide() end

    -- Center the control
    if dropdownRow.Control then
        dropdownRow.Control:ClearAllPoints()
        dropdownRow.Control:SetPoint("CENTER", dropdownRow, "CENTER", 0, 0)
    end

    -- Apply ScooterMod theming to the dropdown (green text and arrows)
    if dropdownRow.Control and panel.ThemeDropdownWithSteppers then
        panel.ThemeDropdownWithSteppers(dropdownRow.Control)
    end
end

-- Function to update the preset content (called when selection changes)
updatePresetContent = function()
    local row = panel._currentPresetRow
    if not row then return end

    local model, list = ensureCarouselModel()
    local preset = list[model.index]
    if not preset then return end

    -- Update hero image
    if row.HeroTexture then
        row.HeroTexture:SetTexture(preset.previewTexture or "Interface\\AddOns\\ScooterMod\\Scooter")
    end

    -- Update two-column content
    if row.LeftList then
        row.LeftList:SetText(formatBulletList(preset.designedFor))
    end
    if row.RightList then
        row.RightList:SetText(formatBulletList(preset.recommends))
    end

    -- Update CTA state and click handler
    if row.PrimaryButton then
        updateCTAState(row, preset)
        row.PrimaryButton:SetScript("OnClick", function() panel:ApplyPresetFromUI(preset) end)
    end
end

function panel:ApplyPresetFromUI(preset)
    if not preset then return end
    if not addon.Presets or not addon.Presets.ApplyPreset then
        addon:Print("Preset system not initialized.")
        return
    end

    if not addon.Dialogs or not addon.Dialogs.Show then
        addon:Print("Dialogs system not initialized.")
        return
    end

    local presetName = preset.name or preset.id or "Preset"
    local defaultName = presetName

    local function prompt(nameSuggestion)
        addon.Dialogs:Show("SCOOTERMOD_APPLY_PRESET", {
            formatArgs = { presetName },
            editBoxText = nameSuggestion or defaultName,
            data = { preset = preset },
            onAccept = function(d, newName)
                local ok, err = addon.Presets:ApplyPreset(d.preset.id, { targetName = newName })
                if not ok then
                    if err and addon.Print then addon:Print(err) end
                    C_Timer.After(0, function()
                        prompt(newName)
                    end)
                    return
                end
                addon:Print(("Preset '%s' is being applied. Your UI will reload shortly."):format(presetName))
            end,
        })
    end

    prompt(defaultName)
end

local function renderProfilesPresets()
    local function render()
        local frame = panel.frame
        local right = frame and frame.RightPane
        if not frame or not right or not right.Display then return end
        if right.SetTitle then
            right:SetTitle("Presets")
        end
        local model, list = ensureCarouselModel()
        local elements = {}

        if #list == 0 then
            local emptyRow = Settings.CreateElementInitializer("ScooterPresetsEmptyTemplate")
            emptyRow.GetExtent = function() return 40 end
            emptyRow.InitFrame = function(_, row)
                if row.InfoText then row.InfoText:Hide() end
                if row.ActiveDropdown then row.ActiveDropdown:Hide() end
                if row.RenameBtn then row.RenameBtn:Hide() end
                if row.CopyBtn then row.CopyBtn:Hide() end
                if row.DeleteBtn then row.DeleteBtn:Hide() end
                if not row.MessageText then
                    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
                    text:SetPoint("LEFT", row, "LEFT", 16, 0)
                    text:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                    text:SetJustifyH("LEFT")
                    text:SetText("Preset collections are coming soon. For now, use Edit Mode to swap between Blizzard's Modern and Classic presets.")
                    row.MessageText = text
                else
                    row.MessageText:Show()
                end
            end
            table.insert(elements, emptyRow)
            right:Display(elements)
            return
        end

        local heroRow = Settings.CreateElementInitializer("ScooterPresetsHeroTemplate")
        heroRow.GetExtent = function() return 490 end
        heroRow.InitFrame = function(_, row)
            -- Store reference to the row for direct updates
            panel._currentPresetRow = row

            -- Build widgets (only creates once)
            buildHeroWidgets(row)

            -- Initialize the dropdown
            initPresetDropdown(row, list)

            -- Update content with current preset
            updatePresetContent()
        end
        table.insert(elements, heroRow)

        right:Display(elements)
    end
    return { mode = "list", render = render, componentId = "profilesPresets" }
end

function panel.RenderProfilesPresets()
    return renderProfilesPresets()
end

