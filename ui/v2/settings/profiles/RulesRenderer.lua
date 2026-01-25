-- RulesRenderer.lua - Profiles Rules settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Profiles = addon.UI.Settings.Profiles or {}
addon.UI.Settings.Profiles.Rules = {}

local Rules = addon.UI.Settings.Profiles.Rules
local SettingsBuilder = addon.UI.SettingsBuilder

-- State management for this renderer
Rules._state = {
    currentControls = {},
}

function Rules.Render(panel, scrollContent)
    panel:ClearContent()

    -- Clean up previous Rules UI controls
    local state = Rules._state
    if state.currentControls then
        for _, control in ipairs(state.currentControls) do
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
    end
    state.currentControls = {}

    local ar, ag, ab = Theme:GetAccentColor()
    local fontPath = Theme:GetFont("VALUE")

    -- Refresh callback
    local function refreshRules()
        Rules.Render(panel, scrollContent)
    end

    local yOffset = -8

    -- Add Rule button
    local addBtn = Controls:CreateButton({
        parent = scrollContent,
        text = "Add Rule",
        width = 200,
        height = 36,
        onClick = function()
            if addon.Rules and addon.Rules.CreateRule then
                local newRule = addon.Rules:CreateRule()
                if newRule and newRule.id then
                    state.editingRules[newRule.id] = true
                end
                refreshRules()
            end
        end,
    })
    addBtn:SetPoint("TOP", scrollContent, "TOP", 0, yOffset)
    table.insert(state.currentControls, addBtn)
    yOffset = yOffset - RULES_ADD_BUTTON_HEIGHT

    -- Get rules
    local rules = addon.Rules and addon.Rules:GetRules() or {}

    if #rules == 0 then
        -- Empty state
        local emptyFrame = CreateFrame("Frame", nil, scrollContent)
        emptyFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", RULES_CARD_LEFT_MARGIN, yOffset - 20)
        emptyFrame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -8, yOffset - 20)
        emptyFrame:SetHeight(40)

        local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
        emptyText:SetFont(fontPath, 12, "")
        emptyText:SetAllPoints()
        emptyText:SetText("No rules configured. Click 'Add Rule' to create your first automation.")
        emptyText:SetTextColor(0.6, 0.6, 0.6, 1)
        emptyText:SetJustifyH("CENTER")

        table.insert(state.currentControls, emptyFrame)
        yOffset = yOffset - RULES_EMPTY_STATE_HEIGHT
    else
        -- Render each rule
        for index, rule in ipairs(rules) do
            rule.displayIndex = index

            local card = CreateRulesCard(scrollContent, rule, refreshRules)
            card:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", RULES_CARD_LEFT_MARGIN, yOffset)
            card:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -8, yOffset)
            yOffset = yOffset - card:GetHeight()

            -- Track for cleanup
            table.insert(state.currentControls, card)

            -- Divider between cards (not after last)
            if index < #rules then
                local divider = CreateRulesDivider(scrollContent)
                divider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
                divider:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, yOffset)
                yOffset = yOffset - RULES_DIVIDER_HEIGHT
                table.insert(state.currentControls, divider)
            end
        end
    end

    -- Set scroll content height
    local totalHeight = math.abs(yOffset) + 20
    scrollContent:SetHeight(totalHeight)
end

return Rules
