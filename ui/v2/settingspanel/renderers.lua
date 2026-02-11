-- settingspanel/renderers.lua - Renderer registry table
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel

--------------------------------------------------------------------------------
-- Renderer Registry
--------------------------------------------------------------------------------
-- Maps navigation keys to render functions. Add new renderers here.

UIPanel._renderers = {
    -- Cooldown Manager (external modules)
    cdmQoL = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.QoL
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    essentialCooldowns = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.EssentialCooldowns
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    utilityCooldowns = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.UtilityCooldowns
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    trackedBuffs = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.TrackedBuffs
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    trackedBars = function(self, scrollContent)
        local M = addon.UI.Settings.CDM and addon.UI.Settings.CDM.TrackedBars
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Action Bars (external modules)
    actionBar1 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar1") end
    end,
    actionBar2 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar2") end
    end,
    actionBar3 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar3") end
    end,
    actionBar4 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar4") end
    end,
    actionBar5 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar5") end
    end,
    actionBar6 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar6") end
    end,
    actionBar7 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar7") end
    end,
    actionBar8 = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "actionBar8") end
    end,
    petBar = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "petBar") end
    end,
    stanceBar = function(self, scrollContent)
        local M = addon.UI.Settings.ActionBar
        if M and M.Render then M.Render(self, scrollContent, "stanceBar") end
    end,
    microBar = function(self, scrollContent)
        local M = addon.UI.Settings.MicroBar
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    extraAbilities = function(self, scrollContent)
        local M = addon.UI.Settings.ExtraAbilities
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Personal Resource Display (external modules)
    prdGeneral = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.General
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    prdHealthBar = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.HealthBar
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    prdPowerBar = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.PowerBar
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    prdClassResource = function(self, scrollContent)
        local M = addon.UI.Settings.PRD and addon.UI.Settings.PRD.ClassResource
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Interface (external modules)
    damageMeter = function(self, scrollContent)
        local M = addon.UI.Settings.DamageMeter
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    tooltip = function(self, scrollContent)
        local M = addon.UI.Settings.Tooltip
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    objectiveTracker = function(self, scrollContent)
        local M = addon.UI.Settings.ObjectiveTracker
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    minimap = function(self, scrollContent)
        local M = addon.UI.Settings.Minimap
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    chat = function(self, scrollContent)
        local M = addon.UI.Settings.Chat
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    misc = function(self, scrollContent)
        local M = addon.UI.Settings.Misc
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- SCT (external module)
    sctDamage = function(self, scrollContent)
        local M = addon.UI.Settings.SctDamage
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Unit Frames (external modules - unchanged)
    ufPlayer = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderPlayer then
            UF.RenderPlayer(self, scrollContent)
        end
    end,
    ufTarget = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderTarget then
            UF.RenderTarget(self, scrollContent)
        end
    end,
    ufFocus = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderFocus then
            UF.RenderFocus(self, scrollContent)
        end
    end,
    ufPet = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderPet then
            UF.RenderPet(self, scrollContent)
        end
    end,
    ufToT = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderToT then
            UF.RenderToT(self, scrollContent)
        end
    end,
    ufFocusTarget = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderFocusTarget then
            UF.RenderFocusTarget(self, scrollContent)
        end
    end,
    ufBoss = function(self, scrollContent)
        local UF = addon.UI and addon.UI.UnitFrames
        if UF and UF.RenderBoss then
            UF.RenderBoss(self, scrollContent)
        end
    end,
    -- Group Frames (external modules - unchanged)
    gfParty = function(self, scrollContent)
        local GF = addon.UI and addon.UI.GroupFrames
        if GF and GF.RenderParty then
            GF.RenderParty(self, scrollContent)
        end
    end,
    gfRaid = function(self, scrollContent)
        local GF = addon.UI and addon.UI.GroupFrames
        if GF and GF.RenderRaid then
            GF.RenderRaid(self, scrollContent)
        end
    end,
    -- Profiles (external modules)
    profilesManage = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Manage
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    profilesPresets = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Presets
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    profilesRules = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Rules
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    profilesImportExport = function(self, scrollContent)
        local M = addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.ImportExport
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Apply All (external modules)
    applyAllFonts = function(self, scrollContent)
        local M = addon.UI.Settings.ApplyAll and addon.UI.Settings.ApplyAll.Fonts
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    applyAllTextures = function(self, scrollContent)
        local M = addon.UI.Settings.ApplyAll and addon.UI.Settings.ApplyAll.Textures
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Buffs/Debuffs (external modules)
    buffs = function(self, scrollContent)
        local M = addon.UI.Settings.Auras and addon.UI.Settings.Auras.Buffs
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    debuffs = function(self, scrollContent)
        local M = addon.UI.Settings.Auras and addon.UI.Settings.Auras.Debuffs
        if M and M.Render then M.Render(self, scrollContent) end
    end,
    -- Debug Menu (hidden by default)
    debugMenu = function(self, scrollContent)
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
    end,
}
