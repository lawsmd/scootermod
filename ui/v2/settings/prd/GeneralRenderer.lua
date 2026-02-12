-- GeneralRenderer.lua - Personal Resource Display General settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.General = {}

local General = addon.UI.Settings.PRD.General
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function General.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        General.Render(panel, scrollContent)
    end)

    -- CVar helpers
    local function getPRDEnabledFromCVar()
        if GetCVarBool then
            return GetCVarBool("nameplateShowSelf")
        end
        if C_CVar and C_CVar.GetCVar then
            return C_CVar.GetCVar("nameplateShowSelf") == "1"
        end
        return false
    end

    local function setPRDEnabledCVar(enabled)
        local value = (enabled and "1") or "0"
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "nameplateShowSelf", value)
        elseif SetCVar then
            pcall(SetCVar, "nameplateShowSelf", value)
        end
    end

    -- Profile data helpers
    local function getProfilePRDSettings()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.prdSettings
    end

    local function ensureProfilePRDSettings()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.prdSettings = addon.db.profile.prdSettings or {}
        return addon.db.profile.prdSettings
    end

    builder:AddToggle({
        label = "Enable the PRD Per-Profile",
        description = "When enabled, the Personal Resource Display will be active for this profile. This overrides the character-wide Blizzard setting.",
        get = function()
            local s = getProfilePRDSettings()
            if s and s.enablePRD ~= nil then
                return s.enablePRD
            end
            return getPRDEnabledFromCVar()
        end,
        set = function(value)
            local s = ensureProfilePRDSettings()
            if not s then return end
            s.enablePRD = value
            setPRDEnabledCVar(value)
            -- Re-apply styling so borders/overlays respond to the change
            if addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("prdGeneral", function(panel, scrollContent)
    General.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return General
