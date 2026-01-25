-- SctDamageRenderer.lua - Scrolling Combat Text Damage Numbers renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.SctDamage = {}

local SctDamage = addon.UI.Settings.SctDamage
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function SctDamage.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["sctDamage"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.sctDamage and components.sctDamage[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.sctDamage = profile.components.sctDamage or {}
                profile.components.sctDamage[key] = value
            end
        end
    end

    builder:AddDescription(
        "Changes to the damage number font require a full game restart (not just a reload) to take effect. " ..
        "The scale slider applies immediately."
    )

    builder:AddFontSelector({
        label = "Font",
        description = "The font used for floating combat text damage numbers.",
        get = function()
            return getSetting("fontFace") or "FRIZQT__"
        end,
        set = function(fontKey)
            setSetting("fontFace", fontKey or "FRIZQT__")
            local comp = getComponent()
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end,
    })

    builder:AddSlider({
        label = "Font Scale",
        description = "Scale of floating combat text numbers (affects all world text).",
        min = 50,
        max = 150,
        step = 1,
        get = function()
            return getSetting("fontScale") or 100
        end,
        set = function(v)
            setSetting("fontScale", v)
            local comp = getComponent()
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end,
        minLabel = "50%",
        maxLabel = "150%",
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return SctDamage
