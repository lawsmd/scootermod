-- DamageMeterRenderer.lua - Damage Meter settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.DamageMeter = {}

local DamageMeter = addon.UI.Settings.DamageMeter
local SettingsBuilder = addon.UI.SettingsBuilder

function DamageMeter.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        DamageMeter.Render(panel, scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["damageMeter"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.damageMeter and components.damageMeter[key]
    end

    local function setSetting(key, value)
        local comp = getComponent()
        if comp and comp.db then
            -- Ensure component DB exists
            if addon.EnsureComponentDB then
                addon:EnsureComponentDB(comp)
            end
            comp.db[key] = value
        else
            -- Fallback to profile.components
            local profile = addon.db and addon.db.profile
            if profile then
                profile.components = profile.components or {}
                profile.components.damageMeter = profile.components.damageMeter or {}
                profile.components.damageMeter[key] = value
            end
        end
        -- Apply styles after setting change
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    -- Helper to sync Edit Mode settings after value change (debounced)
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Style selector (parent level, Edit Mode synced, emphasized)
    builder:AddSelector({
        label = "Style",
        description = "Choose the visual style for the damage meter frame. This setting syncs with Edit Mode.",
        values = { [0] = "Default", [1] = "Thin", [2] = "Bordered" },
        order = { 0, 1, 2 },
        emphasized = true,
        get = function() return getSetting("style") or 0 end,
        set = function(value)
            setSetting("style", value)
            syncEditModeSetting("style")
        end,
    })

    -- Layout section
    builder:AddCollapsibleSection({
        title = "Layout",
        componentId = "damageMeter",
        sectionKey = "layout",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Frame Width",
                min = 300, max = 600, step = 10,
                get = function() return getSetting("frameWidth") or 300 end,
                set = function(value)
                    setSetting("frameWidth", value)
                    syncEditModeSetting("frameWidth")
                end,
            })
            inner:AddSlider({
                label = "Frame Height",
                min = 120, max = 400, step = 10,
                get = function() return getSetting("frameHeight") or 200 end,
                set = function(value)
                    setSetting("frameHeight", value)
                    syncEditModeSetting("frameHeight")
                end,
            })
            inner:AddSlider({
                label = "Padding",
                min = 2, max = 10, step = 1,
                get = function() return getSetting("padding") or 4 end,
                set = function(value)
                    setSetting("padding", value)
                    syncEditModeSetting("padding")
                end,
            })
        end,
    })

    -- Bars section (collapsible with tabs inside)
    builder:AddCollapsibleSection({
        title = "Bars",
        componentId = "damageMeter",
        sectionKey = "bars",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "barsTabs",
                tabs = {
                    { key = "sizing", label = "Sizing" },
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                },
                buildContent = {
                    sizing = function(tabContent, tabInner)
                        tabInner:AddSlider({
                            label = "Bar Height",
                            min = 18, max = 40, step = 1,
                            get = function() return getSetting("barHeight") or 20 end,
                            set = function(value)
                                setSetting("barHeight", value)
                                syncEditModeSetting("barHeight")
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(tabContent, tabInner)
                        tabInner:AddBarTextureSelector({
                            label = "Bar Texture",
                            get = function() return getSetting("barTexture") or "pointed" end,
                            set = function(value)
                                setSetting("barTexture", value)
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Show Class Color",
                            description = "Use player class colors for bars instead of a single color. Syncs with Edit Mode.",
                            get = function() return getSetting("showClassColor") end,
                            set = function(value)
                                setSetting("showClassColor", value)
                                syncEditModeSetting("showClassColor")
                                -- Refresh the Foreground Color disabled state
                                if inner and inner.RefreshWidgetState then
                                    inner:RefreshWidgetState("barForegroundColor")
                                end
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Foreground Color",
                            description = "Bar fill color (disabled when using class colors).",
                            widgetKey = "barForegroundColor",
                            get = function()
                                local c = getSetting("barForegroundColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 0.8, 0.2, 0.2, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("barForegroundColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            disabled = function() return getSetting("showClassColor") end,
                        })
                        tabInner:AddColorPicker({
                            label = "Background Color",
                            get = function()
                                local c = getSetting("barBackgroundColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 0.1, 0.1, 0.1, 0.8
                            end,
                            set = function(r, g, b, a)
                                setSetting("barBackgroundColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            description = "Override Blizzard's default bar borders with a custom style.",
                            get = function() return getSetting("useCustomBarBorder") end,
                            set = function(value)
                                setSetting("useCustomBarBorder", value)
                            end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            get = function() return getSetting("barBorderStyle") or "pointed" end,
                            set = function(value)
                                setSetting("barBorderStyle", value)
                            end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            description = "Apply a custom color tint to the border.",
                            get = function() return getSetting("barBorderTintEnabled") end,
                            set = function(value)
                                setSetting("barBorderTintEnabled", value)
                            end,
                            getColor = function()
                                local c = getSetting("barBorderTintColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 1, 1, 1, 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("barBorderTintColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 4, step = 1,
                            get = function() return getSetting("barBorderThickness") or 2 end,
                            set = function(value)
                                setSetting("barBorderThickness", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Icons section
    builder:AddCollapsibleSection({
        title = "Icons",
        componentId = "damageMeter",
        sectionKey = "icons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Show Spec Icon",
                description = "Display specialization icons next to player names. Syncs with Edit Mode.",
                get = function() return getSetting("showSpecIcon") end,
                set = function(value)
                    setSetting("showSpecIcon", value)
                    syncEditModeSetting("showSpecIcon")
                end,
            })
            inner:AddToggleColorPicker({
                label = "Icon Border",
                description = "Show a colored border around spec icons.",
                get = function() return getSetting("iconBorderEnabled") end,
                set = function(value)
                    setSetting("iconBorderEnabled", value)
                end,
                getColor = function()
                    local c = getSetting("iconBorderColor")
                    if c then return c.r, c.g, c.b, c.a end
                    return 0.3, 0.3, 0.3, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("iconBorderColor", { r = r, g = g, b = b, a = a or 1 })
                end,
            })
            inner:AddColorPicker({
                label = "Icon Background",
                get = function()
                    local c = getSetting("iconBackgroundColor")
                    if c then return c.r, c.g, c.b, c.a end
                    return 0, 0, 0, 0.5
                end,
                set = function(r, g, b, a)
                    setSetting("iconBackgroundColor", { r = r, g = g, b = b, a = a or 1 })
                end,
                hasAlpha = true,
            })
        end,
    })

    -- Text section (collapsible with tabs inside)
    local fontStyleValues = {
        ["NONE"] = "None",
        ["OUTLINE"] = "Outline",
        ["THICKOUTLINE"] = "Thick Outline",
        ["MONOCHROME"] = "Monochrome",
    }
    local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME" }

    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "damageMeter",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "textTabs",
                tabs = {
                    { key = "title", label = "Title" },
                    { key = "names", label = "Names" },
                    { key = "numbers", label = "Numbers" },
                },
                buildContent = {
                    title = function(tabContent, tabInner)
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("titleFont") or "default" end,
                            set = function(value)
                                setSetting("titleFont", value)
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getSetting("titleFontStyle") or "OUTLINE" end,
                            set = function(value)
                                setSetting("titleFontStyle", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Color",
                            get = function()
                                local c = getSetting("titleColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 1, 1, 1, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("titleColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    names = function(tabContent, tabInner)
                        tabInner:AddSlider({
                            label = "Text Size",
                            description = "Scale for header/dropdown text. Syncs with Edit Mode.",
                            min = 50, max = 150, step = 10,
                            get = function() return getSetting("textSize") or 100 end,
                            set = function(value) setSetting("textSize", value) end,
                            debounceKey = "UI_damageMeter_textSize",
                            debounceDelay = 0.2,
                            onEditModeSync = function(newValue)
                                syncEditModeSetting("textSize")
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("namesFont") or "default" end,
                            set = function(value)
                                setSetting("namesFont", value)
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getSetting("namesFontStyle") or "OUTLINE" end,
                            set = function(value)
                                setSetting("namesFontStyle", value)
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 8, max = 18, step = 1,
                            get = function() return getSetting("namesFontSize") or 12 end,
                            set = function(value)
                                setSetting("namesFontSize", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Color",
                            get = function()
                                local c = getSetting("namesColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 1, 1, 1, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("namesColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    numbers = function(tabContent, tabInner)
                        tabInner:AddSlider({
                            label = "Text Size",
                            description = "Scale for header/dropdown text. Syncs with Edit Mode.",
                            min = 50, max = 150, step = 10,
                            get = function() return getSetting("textSize") or 100 end,
                            set = function(value) setSetting("textSize", value) end,
                            debounceKey = "UI_damageMeter_textSize",
                            debounceDelay = 0.2,
                            onEditModeSync = function(newValue)
                                syncEditModeSetting("textSize")
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("numbersFont") or "default" end,
                            set = function(value)
                                setSetting("numbersFont", value)
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getSetting("numbersFontStyle") or "OUTLINE" end,
                            set = function(value)
                                setSetting("numbersFontStyle", value)
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 8, max = 18, step = 1,
                            get = function() return getSetting("numbersFontSize") or 12 end,
                            set = function(value)
                                setSetting("numbersFontSize", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Color",
                            get = function()
                                local c = getSetting("numbersColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 1, 0.82, 0, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("numbersColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Windows section (collapsible with tabs inside)
    builder:AddCollapsibleSection({
        title = "Windows",
        componentId = "damageMeter",
        sectionKey = "windows",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "windowsTabs",
                tabs = {
                    { key = "border", label = "Border" },
                    { key = "background", label = "Background" },
                },
                buildContent = {
                    border = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Show Border",
                            description = "Display a border around the damage meter window.",
                            get = function() return getSetting("windowBorderEnabled") end,
                            set = function(value)
                                setSetting("windowBorderEnabled", value)
                            end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            get = function() return getSetting("windowBorderStyle") or "pointed" end,
                            set = function(value)
                                setSetting("windowBorderStyle", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Border Color",
                            get = function()
                                local c = getSetting("windowBorderColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 0.3, 0.3, 0.3, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("windowBorderColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 4, step = 1,
                            get = function() return getSetting("windowBorderThickness") or 2 end,
                            set = function(value)
                                setSetting("windowBorderThickness", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    background = function(tabContent, tabInner)
                        tabInner:AddSlider({
                            label = "Background Opacity",
                            description = "Window background transparency. Syncs with Edit Mode.",
                            min = 0, max = 100, step = 5,
                            get = function() return getSetting("background") or 80 end,
                            set = function(value)
                                setSetting("background", value)
                                syncEditModeSetting("background")
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Custom Backdrop",
                            description = "Use a custom backdrop texture instead of the default.",
                            get = function() return getSetting("customBackdrop") end,
                            set = function(value)
                                setSetting("customBackdrop", value)
                            end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function() return getSetting("backdropTexture") or "pointed" end,
                            set = function(value)
                                setSetting("backdropTexture", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Backdrop Color",
                            get = function()
                                local c = getSetting("backdropColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 0.1, 0.1, 0.1, 0.9
                            end,
                            set = function(r, g, b, a)
                                setSetting("backdropColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Visibility & Misc section
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "damageMeter",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Visibility",
                values = { [0] = "Always", [1] = "In Combat", [2] = "Hidden" },
                order = { 0, 1, 2 },
                get = function() return getSetting("visibility") or 0 end,
                set = function(value)
                    setSetting("visibility", value)
                    syncEditModeSetting("visibility")
                end,
            })
            inner:AddSlider({
                label = "Opacity",
                min = 50, max = 100, step = 5,
                get = function() return getSetting("opacity") or 100 end,
                set = function(value)
                    setSetting("opacity", value)
                    syncEditModeSetting("opacity")
                end,
            })
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

return DamageMeter
