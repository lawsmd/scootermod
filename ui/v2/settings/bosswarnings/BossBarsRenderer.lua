-- BossBarsRenderer.lua - Boss Bars settings (coming soon)
local addonName, addon = ...

addon.UI.SettingsPanel:RegisterRenderer("bwBars", function(panel, scrollContent)
    panel:ClearContent()
    local builder = addon.UI.SettingsBuilder:CreateFor(scrollContent)
    builder:AddDescription("Coming soon...")
    builder:Finalize()
end)
