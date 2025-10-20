local addonName, addon = ...

LibStub("AceAddon-3.0"):NewAddon(addon, "ScooterMod", "AceEvent-3.0")

function addon:OnEnable()
    -- Called when the addon is enabled
end

function addon:OnDisable()
    -- Called when the addon is disabled
end

SLASH_SCOOTERMOD1 = "/scoot"
function SlashCmdList.SCOOTERMOD(msg, editBox)
    addon.SettingsPanel:Toggle()
end
