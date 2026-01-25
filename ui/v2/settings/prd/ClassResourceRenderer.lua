-- ClassResourceRenderer.lua - Personal Resource Display Class Resource settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.ClassResource = {}

local ClassResource = addon.UI.Settings.PRD.ClassResource
local SettingsBuilder = addon.UI.SettingsBuilder

function ClassResource.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        ClassResource.Render(panel, scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["prdClassResource"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        return nil
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        end
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdClassResource",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Scale",
                min = 50, max = 150, step = 1,
                get = function() return getSetting("scale") or 100 end,
                set = function(v) setSetting("scale", v) end,
                minLabel = "50%", maxLabel = "150%",
                infoIcon = {
                    tooltipTitle = "Class Resource Scale",
                    tooltipText = "Adjusts the size of the class resource display (combo points, runes, holy power, etc.).",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdClassResource",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Class Resource",
                get = function() return getSetting("hideBar") or false end,
                set = function(v) setSetting("hideBar", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

return ClassResource
