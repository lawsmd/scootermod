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

local function setCarouselIndex(delta)
    local model, list = ensureCarouselModel()
    local total = #list
    if total == 0 then return end
    model.index = model.index + delta
    if model.index < 1 then model.index = total end
    if model.index > total then model.index = 1 end
    if panel.RefreshCurrentCategoryDeferred then
        panel.RefreshCurrentCategoryDeferred()
    end
end

local function formatTags(tags)
    if type(tags) ~= "table" or #tags == 0 then
        return "Preset"
    end
    return table.concat(tags, " • ")
end

local function applyPresetStatus(frame, preset)
    local statusParts = {}
    if preset.version then
        table.insert(statusParts, preset.version)
    end
    if preset.wowBuild and preset.wowBuild ~= "" then
        table.insert(statusParts, "Build " .. preset.wowBuild)
    end
    if preset.comingSoon then
        table.insert(statusParts, "Coming Soon")
    end
    frame.PresetStatus:SetText(table.concat(statusParts, " • "))

    local depText
    if preset.requiresConsolePort then
        depText = "Requires ConsolePort"
    else
        depText = preset.recommendedInput or "Mouse + Keyboard"
    end
    frame.PresetDependencies:SetText(depText)
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
    frame.PrimaryButton:SetText(actionable and ("Create a new profile using " .. (preset.name or "Preset")) or disabledReason or "Unavailable")
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

local function buildHeroWidgets(frame)
    frame:SetHeight(420)
    if frame.InfoText then frame.InfoText:Hide() end
    if frame.ButtonContainer then frame.ButtonContainer:Hide() end
    if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
    if frame.RenameBtn then frame.RenameBtn:Hide() end
    if frame.CopyBtn then frame.CopyBtn:Hide() end
    if frame.DeleteBtn then frame.DeleteBtn:Hide() end

    if frame.HeroTexture then return end

    local hero = frame:CreateTexture(nil, "ARTWORK")
    hero:SetPoint("TOP", frame, "TOP", 0, -12)
    hero:SetSize(520, 292)
    hero:SetColorTexture(0.07, 0.07, 0.07, 1)
    frame.HeroTexture = hero

    local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    prev:SetSize(32, 32)
    prev:SetPoint("LEFT", hero, "LEFT", -40, 0)
    prev:SetText("⟨")
    prev:SetScript("OnClick", function() setCarouselIndex(-1) end)
    frame.NavPrev = prev

    local nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nextBtn:SetSize(32, 32)
    nextBtn:SetPoint("RIGHT", hero, "RIGHT", 40, 0)
    nextBtn:SetText("⟩")
    nextBtn:SetScript("OnClick", function() setCarouselIndex(1) end)
    frame.NavNext = nextBtn

    local pagination = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pagination:SetPoint("TOP", hero, "BOTTOM", 0, -6)
    panel.ApplyRobotoWhite(pagination)
    frame.PaginationText = pagination

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", pagination, "BOTTOM", 0, -6)
    title:SetText("Preset")
    panel.ApplyRobotoWhite(title)
    frame.PresetTitle = title

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOP", title, "BOTTOM", 0, -2)
    panel.ApplyRobotoWhite(status)
    frame.PresetStatus = status

    local tags = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tags:SetPoint("TOP", status, "BOTTOM", 0, -4)
    panel.ApplyRobotoWhite(tags)
    frame.PresetTags = tags

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOP", tags, "BOTTOM", 0, -10)
    desc:SetWidth(520)
    desc:SetJustifyH("CENTER")
    desc:SetJustifyV("TOP")
    panel.ApplyRobotoWhite(desc)
    frame.PresetDescription = desc

    local deps = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deps:SetPoint("TOP", desc, "BOTTOM", 0, -8)
    panel.ApplyRobotoWhite(deps)
    frame.PresetDependencies = deps

    local cta = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cta:SetPoint("TOP", deps, "BOTTOM", 0, -16)
    cta:SetSize(320, 28)
    cta:SetText("Create profile")
    panel.ApplyControlTheme(cta)
    frame.PrimaryButton = cta

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOP", cta, "BOTTOM", 0, -6)
    note:SetText("Imports the preset, creates a new profile, and reloads your UI.")
    panel.ApplyRobotoWhite(note)
    frame.CTANote = note
end

function panel:ApplyPresetFromUI(preset)
    if not preset then return end
    if not addon.Presets or not addon.Presets.ApplyPreset then
        addon:Print("Preset system not initialized.")
        return
    end
    local success, result = addon.Presets:ApplyPreset(preset.id)
    if success then
        addon:Print(("Preset '%s' is being applied. Your UI will reload shortly."):format(preset.name or preset.id or "Preset"))
    else
        addon:Print(result or "Unable to apply preset.")
    end
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
            local emptyRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
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

        local heroRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
        heroRow.GetExtent = function() return 430 end
        heroRow.InitFrame = function(_, row)
            buildHeroWidgets(row)
            local preset = list[model.index]
            if preset then
                row.HeroTexture:SetTexture(preset.previewTexture or "Interface\\AddOns\\ScooterMod\\Scooter")
                row.PresetTitle:SetText(preset.name or "Preset")
                row.PresetDescription:SetText(preset.description or "Hand-crafted ScooterMod preset.")
                row.PresetTags:SetText(formatTags(preset.tags))
                row.PaginationText:SetText(string.format("%d / %d", model.index, #list))
                applyPresetStatus(row, preset)
                updateCTAState(row, preset)
                row.PrimaryButton:SetScript("OnClick", function() panel:ApplyPresetFromUI(preset) end)
            end
        end
        table.insert(elements, heroRow)

        right:Display(elements)
    end
    return { mode = "list", render = render, componentId = "profilesPresets" }
end

function panel.RenderProfilesPresets()
    return renderProfilesPresets()
end


