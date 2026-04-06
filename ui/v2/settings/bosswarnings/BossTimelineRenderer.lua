-- BossTimelineRenderer.lua - Boss Timeline settings (coming soon)
local addonName, addon = ...

addon.UI.SettingsPanel:RegisterRenderer("bwTimeline", function(panel, scrollContent)
    panel:ClearContent()
    local builder = addon.UI.SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:AddDescription("Coming soon...")
    builder:Finalize()
end)
