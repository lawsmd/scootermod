-- MinimapRenderer.lua - Minimap settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Minimap = {}

local Minimap = addon.UI.Settings.Minimap
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Minimap.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:AddDescription(
        "Minimap customization is coming soon.\n\n" ..
        "This section will include options for positioning, scale, and visibility of minimap buttons."
    )

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return Minimap
