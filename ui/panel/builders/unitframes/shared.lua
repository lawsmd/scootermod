local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Shared helpers for Unit Frames builders
local shared = panel.UnitFramesShared or {}

local componentToUnit = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus  = "Focus",
    ufPet    = "Pet",
}

function shared.unitKeyFor(componentId)
    return componentToUnit[componentId]
end

function shared.getUiScale()
    return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
end

function shared.pixelsToUiUnits(px)
    local s = shared.getUiScale()
    if s == 0 then return 0 end
    return px / s
end

function shared.uiUnitsToPixels(u)
    local s = shared.getUiScale()
    return math.floor((u * s) + 0.5)
end

shared.sectionOrder = shared.sectionOrder or {
    "root",
    "health",
    "power",
    "classresource",
    "portrait",
    "cast",
    "buffs",
    "misc_focus",
    "visibility",
    "misc_player",
}

function shared.createContext(componentId, title)
    return {
        addon = addon,
        panel = panel,
        componentId = componentId,
        title = title,
    }
end

panel.UnitFramesShared = shared

return shared

