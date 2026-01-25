-- MicroBarRenderer.lua - Micro Bar settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.MicroBar = {}

local MicroBar = addon.UI.Settings.MicroBar
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function MicroBar.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        MicroBar.Render(panel, scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["microBar"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.microBar and components.microBar[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
            comp.db[key] = value
        else
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.microBar = profile.components.microBar or {}
                profile.components.microBar[key] = value
            end
        end
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function() addon:ApplyStyles() end)
        end
    end

    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "microBar",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Orientation",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                end,
                syncCooldown = 0.5,
            })

            inner:AddSelector({
                label = "Direction",
                values = {
                    left = "Left",
                    right = "Right",
                    up = "Up",
                    down = "Down",
                },
                order = { "left", "right", "up", "down" },
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.5,
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "microBar",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Menu Size (Scale)", min = 70, max = 200, step = 5,
                get = function() return getSetting("menuSize") or 100 end,
                set = function(v) setSetting("menuSize", v) end,
                debounceKey = "microBar_menuSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("menuSize") end,
                minLabel = "70%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Eye Size", min = 50, max = 150, step = 5,
                get = function() return getSetting("eyeSize") or 100 end,
                set = function(v) setSetting("eyeSize", v) end,
                debounceKey = "microBar_eyeSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("eyeSize") end,
                minLabel = "50%", maxLabel = "150%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "microBar",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity in Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacity") or 100 end,
                set = function(v) setSetting("barOpacity", v) end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityWithTarget") or 100 end,
                set = function(v) setSetting("barOpacityWithTarget", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityOutOfCombat") or 100 end,
                set = function(v) setSetting("barOpacityOutOfCombat", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddToggle({
                label = "Mouseover Mode",
                get = function() return getSetting("mouseoverMode") or false end,
                set = function(v) setSetting("mouseoverMode", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return MicroBar
