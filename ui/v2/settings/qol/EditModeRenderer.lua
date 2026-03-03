-- EditModeRenderer.lua - Quality of Life: Edit Mode settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.EditMode = {}

local EditMode = addon.UI.Settings.QoL.EditMode
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.qol
end

local function ensureQoL()
    if not (addon and addon.db and addon.db.profile) then return nil end
    addon.db.profile.qol = addon.db.profile.qol or {}
    return addon.db.profile.qol
end

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function EditMode.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:AddToggle({
        label = "Show Nudge Arrows",
        description = "Display clickable arrow buttons on the edges of selected Edit Mode frames for pixel-by-pixel positioning. Shift+click moves 10px.",
        get = function()
            local q = getQoL()
            return (q and q.editModeNudgeArrows) or false
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.editModeNudgeArrows = value
            if addon.EditMode and addon.EditMode.SetNudgeArrowsEnabled then
                addon.EditMode.SetNudgeArrowsEnabled(value)
            end
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("qolEditMode", function(panel, scrollContent)
    EditMode.Render(panel, scrollContent)
end)

return EditMode
