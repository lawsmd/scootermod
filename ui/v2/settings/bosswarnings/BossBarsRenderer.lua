-- BossBarsRenderer.lua - Boss Bars settings (coming soon)
local addonName, addon = ...

addon.UI.SettingsPanel:RegisterRenderer("bwBars", function(panel, scrollContent)
    panel:ClearContent()
    local builder = addon.UI.SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:AddDescription("Coming soon...")
    builder:Finalize()
end)
