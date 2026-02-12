-- settingspanel/renderers.lua - Renderer registry with self-registration support
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel

--------------------------------------------------------------------------------
-- Renderer Registry
--------------------------------------------------------------------------------
-- Renderer files self-register by calling RegisterRenderer() at load time.
-- Only the debugMenu renderer lives here (it has no external module).

UIPanel._renderers = {}

function UIPanel:RegisterRenderer(key, renderFn)
    self._renderers[key] = renderFn
end

--------------------------------------------------------------------------------
-- Debug Menu (inline renderer - no external module)
--------------------------------------------------------------------------------

UIPanel:RegisterRenderer("debugMenu", function(self, scrollContent)
    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    -- Track controls for cleanup on the PANEL so ClearContent() can find them
    self._debugMenuControls = self._debugMenuControls or {}
    for _, ctrl in ipairs(self._debugMenuControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    self._debugMenuControls = {}

    -- Section header
    local headerLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyLabelFont(headerLabel, 14)
    headerLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    headerLabel:SetText("Developer Testing Tools")
    local ar, ag, ab = Theme:GetAccentColor()
    headerLabel:SetTextColor(ar, ag, ab, 1)
    table.insert(self._debugMenuControls, headerLabel)

    local yOffset = -30

    -- Description
    local descLabel = scrollContent:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(descLabel, 11)
    descLabel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    descLabel:SetPoint("RIGHT", scrollContent, "RIGHT", -20, 0)
    descLabel:SetText("These options are for addon development and testing. Use with caution.")
    descLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    descLabel:SetJustifyH("LEFT")
    descLabel:SetWordWrap(true)
    table.insert(self._debugMenuControls, descLabel)

    yOffset = yOffset - 50

    -- Force Secret Restrictions toggle
    local secretCVars = {
        "secretCombatRestrictionsForced",
        "secretChallengeModeRestrictionsForced",
        "secretEncounterRestrictionsForced",
        "secretMapRestrictionsForced",
        "secretPvPMatchRestrictionsForced",
    }

    local toggle = Controls:CreateToggle({
        parent = scrollContent,
        label = "Force Secret Restrictions",
        description = "Enables all secret restriction CVars to simulate combat/instance restrictions for testing taint behavior.",
        get = function()
            local val = GetCVar("secretCombatRestrictionsForced")
            return val == "1"
        end,
        set = function(enabled)
            local newVal = enabled and "1" or "0"
            for _, cvar in ipairs(secretCVars) do
                pcall(SetCVar, cvar, newVal)
            end
        end,
    })
    toggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    toggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    table.insert(self._debugMenuControls, toggle)

    yOffset = yOffset - 70

    -- Keep BugSack Button Separate toggle
    local bugSackToggle = Controls:CreateToggle({
        parent = scrollContent,
        label = "Keep BugSack Button Separate",
        description = "Keep BugSack's minimap button visible outside the addon button container.",
        get = function()
            return addon.db and addon.db.profile and addon.db.profile.bugSackButtonSeparate
        end,
        set = function(enabled)
            if addon.db and addon.db.profile then
                addon.db.profile.bugSackButtonSeparate = enabled
                -- Re-apply minimap styling to update button visibility
                local minimapComp = addon.Components and addon.Components["minimapStyle"]
                if minimapComp and minimapComp.ApplyStyling then
                    minimapComp:ApplyStyling()
                end
            end
        end,
    })
    bugSackToggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    bugSackToggle:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    table.insert(self._debugMenuControls, bugSackToggle)

    yOffset = yOffset - 70

    -- Set content height
    scrollContent:SetHeight(math.abs(yOffset) + 20)
end)
