-- TrackedBarsRenderer.lua - Tracked Bars settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.TrackedBars = {}

local TrackedBars = addon.UI.Settings.CDM.TrackedBars
local SettingsBuilder = addon.UI.SettingsBuilder

function TrackedBars.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        TrackedBars.Render(panel, scrollContent)
    end)

    local function getComponent()
        return addon.Components and addon.Components["trackedBars"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.trackedBars and components.trackedBars[key]
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
                profile.components.trackedBars = profile.components.trackedBars or {}
                profile.components.trackedBars[key] = value
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

    -- Build bar texture options for selector (returns values and order)
    local function getBarTextureOptions()
        local values = { bevelled = "Bevelled" }
        local order = { "bevelled" }
        if addon.BuildBarTextureOptionsContainer then
            local data = addon.BuildBarTextureOptionsContainer()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    -- Build bar border options for selector (returns values and order)
    local function getBarBorderOptions()
        local values = { square = "Default (Square)" }
        local order = { "square" }
        if addon.BuildBarBorderOptionsContainer then
            local data = addon.BuildBarBorderOptionsContainer()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    -- Build icon border options for selector (returns values and order)
    local function getIconBorderOptions()
        local values = { square = "Default (Square)" }
        local order = { "square" }
        if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
            local data = addon.IconBorders.GetDropdownEntries()
            if data and #data > 0 then
                values = {}
                order = {}
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "trackedBars",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 3 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = "trackedBars_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:AddSlider({
                label = "Icon/Bar Padding", min = -20, max = 80, step = 1,
                get = function() return getSetting("iconBarPadding") or 0 end,
                set = function(v) setSetting("iconBarPadding", v) end,
                minLabel = "-20", maxLabel = "80",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "trackedBars",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = "trackedBars_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Bar Width", min = 120, max = 480, step = 2,
                get = function() return getSetting("barWidth") or 220 end,
                set = function(v) setSetting("barWidth", v) end,
                minLabel = "120", maxLabel = "480",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "trackedBars",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Custom Textures",
                get = function() return getSetting("styleEnableCustom") ~= false end,
                set = function(v) setSetting("styleEnableCustom", v) end,
            })

            inner:AddBarTextureSelector({
                label = "Foreground Texture",
                get = function() return getSetting("styleForegroundTexture") or "bevelled" end,
                set = function(v) setSetting("styleForegroundTexture", v) end,
            })

            inner:AddBarTextureSelector({
                label = "Background Texture",
                get = function() return getSetting("styleBackgroundTexture") or "bevelled" end,
                set = function(v) setSetting("styleBackgroundTexture", v) end,
            })

            inner:AddColorPicker({
                label = "Foreground Color",
                get = function()
                    local c = getSetting("styleForegroundColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                set = function(r, g, b, a) setSetting("styleForegroundColor", {r, g, b, a}) end,
            })

            inner:AddColorPicker({
                label = "Background Color",
                get = function()
                    local c = getSetting("styleBackgroundColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 0.9
                end,
                set = function(r, g, b, a) setSetting("styleBackgroundColor", {r, g, b, a}) end,
            })

            inner:AddSlider({
                label = "Background Opacity", min = 0, max = 100, step = 1,
                get = function() return getSetting("styleBackgroundOpacity") or 50 end,
                set = function(v) setSetting("styleBackgroundOpacity", v) end,
                minLabel = "0%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "trackedBars",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Use Custom Border",
                get = function() return getSetting("borderEnable") or false end,
                set = function(v) setSetting("borderEnable", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("borderTintColor", {r, g, b, a}) end,
            })

            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = false,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v) setSetting("borderStyle", v) end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.5,
                precision = 1,
                get = function() local v = getSetting("borderThickness") or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                set = function(v) setSetting("borderThickness", math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:AddSlider({
                label = "Border Inset", min = -4, max = 4, step = 1,
                get = function() return getSetting("borderInset") or 0 end,
                set = function(v) setSetting("borderInset", v) end,
                minLabel = "-4", maxLabel = "4",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Icon Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Icon",
        componentId = "trackedBars",
        sectionKey = "icon",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67, max = 67, step = 1,
                get = function() return getSetting("iconTallWideRatio") or 0 end,
                set = function(v) setSetting("iconTallWideRatio", v) end,
                minLabel = "Wide", maxLabel = "Tall",
            })

            inner:AddToggle({
                label = "Enable Border",
                get = function() return getSetting("iconBorderEnable") or false end,
                set = function(v) setSetting("iconBorderEnable", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("iconBorderTintEnable") or false end,
                set = function(v) setSetting("iconBorderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("iconBorderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("iconBorderTintColor", {r, g, b, a}) end,
            })

            local iconBorderValues, iconBorderOrder = getIconBorderOptions()
            inner:AddSelector({
                label = "Border Style",
                values = iconBorderValues,
                order = iconBorderOrder,
                get = function() return getSetting("iconBorderStyle") or "square" end,
                set = function(v) setSetting("iconBorderStyle", v) end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.5,
                precision = 1,
                get = function() local v = getSetting("iconBorderThickness") or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                set = function(v) setSetting("iconBorderThickness", math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Misc Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "trackedBars",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Visibility Mode",
                values = {
                    always = "Always",
                    combat = "Only in Combat",
                    never = "Hidden",
                },
                order = { "always", "combat", "never" },
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.5,
            })

            inner:AddSlider({
                label = "Opacity in Combat", min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v)
                    setSetting("opacity", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                debounceKey = "trackedBars_opacity",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
                minLabel = "50%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSelector({
                label = "Display Mode",
                values = {
                    both = "Icon & Name",
                    icon = "Icon Only",
                    name = "Name Only",
                },
                order = { "both", "icon", "name" },
                get = function() return getSetting("displayMode") or "both" end,
                set = function(v)
                    setSetting("displayMode", v)
                    syncEditModeSetting("displayMode")
                end,
                syncCooldown = 0.5,
            })

            inner:AddToggle({
                label = "Hide When Inactive",
                get = function() return getSetting("hideWhenInactive") or false end,
                set = function(v)
                    setSetting("hideWhenInactive", v)
                    syncEditModeSetting("hideWhenInactive")
                end,
            })

            inner:AddToggle({
                label = "Show Timer",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            inner:AddToggle({
                label = "Show Tooltips",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

return TrackedBars
