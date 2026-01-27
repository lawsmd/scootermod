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

    -- CVar helpers for per-profile damage meter enable
    local function getDamageMeterEnabledFromCVar()
        local v
        if C_CVar and C_CVar.GetCVar then
            v = C_CVar.GetCVar("damageMeterEnabled")
        elseif GetCVar then
            v = GetCVar("damageMeterEnabled")
        end
        return (v == "1") or false
    end

    local function setDamageMeterEnabledCVar(enabled)
        local value = (enabled and "1") or "0"
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "damageMeterEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "damageMeterEnabled", value)
        end
    end

    local function getProfileDamageMeterSettings()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.damageMeterSettings
    end

    local function ensureProfileDamageMeterSettings()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.damageMeterSettings = addon.db.profile.damageMeterSettings or {}
        return addon.db.profile.damageMeterSettings
    end

    builder:AddToggle({
        label = "Enable Damage Meters Per-Profile",
        description = "When enabled, the Damage Meter will be active for this profile. This overrides the character-wide Blizzard setting.",
        get = function()
            local s = getProfileDamageMeterSettings()
            if s and s.enableDamageMeter ~= nil then
                return s.enableDamageMeter
            end
            return getDamageMeterEnabledFromCVar()
        end,
        set = function(value)
            local s = ensureProfileDamageMeterSettings()
            if not s then return end
            s.enableDamageMeter = value
            setDamageMeterEnabledCVar(value)
            -- Re-apply styling if enabling
            if value and addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
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

    -- Font style values used by multiple sections
    local fontStyleValues = {
        ["NONE"] = "Regular",
        ["OUTLINE"] = "Outline",
        ["THICKOUTLINE"] = "Thick Outline",
        ["HEAVYTHICKOUTLINE"] = "Heavy Thick Outline",
        ["SHADOW"] = "Shadow",
        ["SHADOWOUTLINE"] = "Shadow Outline",
        ["SHADOWTHICKOUTLINE"] = "Shadow Thick Outline",
        ["HEAVYSHADOWTHICKOUTLINE"] = "Heavy Shadow Thick Outline",
    }
    local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE", "HEAVYSHADOWTHICKOUTLINE" }

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
                    { key = "namesText", label = "Names Text" },
                    { key = "numbersText", label = "Numbers Text" },
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
                                -- Refresh the Foreground Color selector disabled state
                                local fgColorControl = tabInner:GetControl("barForegroundColor")
                                if fgColorControl and fgColorControl.Refresh then
                                    fgColorControl:Refresh()
                                end
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Foreground Color",
                            description = "Bar fill color when 'Show Class Color' is disabled. Disabled when class colors are enabled above.",
                            key = "barForegroundColor",
                            values = {
                                ["default"] = "Default",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                return getSetting("barForegroundColorMode") or "default"
                            end,
                            set = function(value)
                                setSetting("barForegroundColorMode", value)
                            end,
                            getColor = function()
                                local c = getSetting("barForegroundTint")
                                if c then
                                    return c.r or c[1] or 1, c.g or c[2] or 0.8, c.b or c[3] or 0, c.a or c[4] or 1
                                end
                                return 1, 0.8, 0, 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("barForegroundTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = false,
                            disabled = function() return getSetting("showClassColor") end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Background Color",
                            description = "Bar background color mode.",
                            values = {
                                ["default"] = "Default",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                return getSetting("barBackgroundColorMode") or "default"
                            end,
                            set = function(value)
                                setSetting("barBackgroundColorMode", value)
                            end,
                            getColor = function()
                                local c = getSetting("barBackgroundTint")
                                if c then
                                    return c.r or c[1] or 0.1, c.g or c[2] or 0.1, c.b or c[3] or 0.1, c.a or c[4] or 0.8
                                end
                                return 0.1, 0.1, 0.1, 0.8
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("barBackgroundTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(tabContent, tabInner)
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            description = "Select 'No Border' to use Blizzard's default, or choose a custom border style.",
                            includeNone = true,
                            get = function() return getSetting("barBorderStyle") or "none" end,
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
                            min = 0.5, max = 4, step = 0.5,
                            get = function() return getSetting("barBorderThickness") or 1 end,
                            set = function(value)
                                setSetting("barBorderThickness", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    namesText = function(tabContent, tabInner)
                        -- Helper to get/set textNames sub-table
                        local function getTextNames()
                            local t = getSetting("textNames")
                            return t or {}
                        end
                        local function setTextNamesProp(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textNames = comp.db.textNames or {}
                                comp.db.textNames[key] = value
                            end
                            if addon and addon.ApplyStyles then
                                C_Timer.After(0, function()
                                    if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                end)
                            end
                        end

                        tabInner:AddSlider({
                            label = "Text Size",
                            description = "Scale for bar text. Syncs with Edit Mode.",
                            min = 50, max = 150, step = 10,
                            get = function() return getSetting("textSize") or 100 end,
                            set = function(value) setSetting("textSize", value) end,
                            debounceKey = "UI_damageMeter_textSize",
                            debounceDelay = 0.2,
                            onEditModeSync = function(newValue)
                                syncEditModeSetting("textSize")
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Scale Multiplier",
                            description = "Multiplies the Edit Mode 'Text Size' setting.",
                            min = 0.5, max = 1.5, step = 0.05,
                            precision = 2,
                            get = function()
                                local t = getTextNames()
                                return t.scaleMultiplier or 1.0
                            end,
                            set = function(value)
                                setTextNamesProp("scaleMultiplier", value)
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function()
                                local t = getTextNames()
                                return t.fontFace or "FRIZQT__"
                            end,
                            set = function(value)
                                setTextNamesProp("fontFace", value)
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function()
                                local t = getTextNames()
                                return t.fontStyle or "OUTLINE"
                            end,
                            set = function(value)
                                setTextNamesProp("fontStyle", value)
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Color",
                            values = {
                                ["default"] = "Default",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                local t = getTextNames()
                                return t.colorMode or "default"
                            end,
                            set = function(value)
                                setTextNamesProp("colorMode", value)
                            end,
                            getColor = function()
                                local t = getTextNames()
                                local c = t.color
                                if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
                                return 1, 1, 1, 1
                            end,
                            setColor = function(r, g, b, a)
                                setTextNamesProp("color", { r, g, b, a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    numbersText = function(tabContent, tabInner)
                        -- Helper to get/set textNumbers sub-table
                        local function getTextNumbers()
                            local t = getSetting("textNumbers")
                            return t or {}
                        end
                        local function setTextNumbersProp(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textNumbers = comp.db.textNumbers or {}
                                comp.db.textNumbers[key] = value
                            end
                            if addon and addon.ApplyStyles then
                                C_Timer.After(0, function()
                                    if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                end)
                            end
                        end

                        tabInner:AddSlider({
                            label = "Text Size",
                            description = "Scale for bar text. Syncs with Edit Mode.",
                            min = 50, max = 150, step = 10,
                            get = function() return getSetting("textSize") or 100 end,
                            set = function(value) setSetting("textSize", value) end,
                            debounceKey = "UI_damageMeter_textSize",
                            debounceDelay = 0.2,
                            onEditModeSync = function(newValue)
                                syncEditModeSetting("textSize")
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Scale Multiplier",
                            description = "Multiplies the Edit Mode 'Text Size' setting.",
                            min = 0.5, max = 1.5, step = 0.05,
                            precision = 2,
                            get = function()
                                local t = getTextNumbers()
                                return t.scaleMultiplier or 1.0
                            end,
                            set = function(value)
                                setTextNumbersProp("scaleMultiplier", value)
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function()
                                local t = getTextNumbers()
                                return t.fontFace or "FRIZQT__"
                            end,
                            set = function(value)
                                setTextNumbersProp("fontFace", value)
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function()
                                local t = getTextNumbers()
                                return t.fontStyle or "OUTLINE"
                            end,
                            set = function(value)
                                setTextNumbersProp("fontStyle", value)
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Color",
                            values = {
                                ["default"] = "Default",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                local t = getTextNumbers()
                                return t.colorMode or "default"
                            end,
                            set = function(value)
                                setTextNumbersProp("colorMode", value)
                            end,
                            getColor = function()
                                local t = getTextNumbers()
                                local c = t.color
                                if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
                                return 1, 1, 1, 1
                            end,
                            setColor = function(r, g, b, a)
                                setTextNumbersProp("color", { r, g, b, a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Title Bar section (collapsible with tabs inside)
    builder:AddCollapsibleSection({
        title = "Title Bar",
        componentId = "damageMeter",
        sectionKey = "titleBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "titleBarTabs",
                tabs = {
                    { key = "titleText", label = "Title Text" },
                    { key = "buttons", label = "Buttons" },
                    { key = "backdrop", label = "Backdrop" },
                },
                buildContent = {
                    titleText = function(tabContent, tabInner)
                        -- Helper to get/set textTitle sub-table
                        local function getTextTitle()
                            local t = getSetting("textTitle")
                            return t or {}
                        end
                        local function setTextTitleProp(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textTitle = comp.db.textTitle or {}
                                comp.db.textTitle[key] = value
                            end
                            if addon and addon.ApplyStyles then
                                C_Timer.After(0, function()
                                    if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                end)
                            end
                        end

                        -- Scale Multiplier slider (0.5-1.5)
                        tabInner:AddSlider({
                            label = "Scale Multiplier",
                            description = "Adjusts the size of title text.",
                            min = 0.5, max = 1.5, step = 0.05,
                            precision = 2,
                            get = function()
                                local t = getTextTitle()
                                return t.scaleMultiplier or 1.0
                            end,
                            set = function(value)
                                setTextTitleProp("scaleMultiplier", value)
                            end,
                        })

                        -- Font selector
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function()
                                local t = getTextTitle()
                                return t.fontFace or "FRIZQT__"
                            end,
                            set = function(value)
                                setTextTitleProp("fontFace", value)
                            end,
                        })

                        -- Font Style selector
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function()
                                local t = getTextTitle()
                                return t.fontStyle or "OUTLINE"
                            end,
                            set = function(value)
                                setTextTitleProp("fontStyle", value)
                            end,
                        })

                        -- Color with default/custom mode
                        -- Blizzard default is GameFontNormalMed1 gold: r=1.0, g=0.82, b=0
                        local TITLE_DEFAULT_COLOR = { 1.0, 0.82, 0, 1 }
                        tabInner:AddSelectorColorPicker({
                            label = "Color",
                            values = {
                                ["default"] = "Default (Gold)",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                local t = getTextTitle()
                                return t.colorMode or "default"
                            end,
                            set = function(value)
                                setTextTitleProp("colorMode", value)
                            end,
                            getColor = function()
                                local t = getTextTitle()
                                local c = t.color
                                if c then return c[1] or TITLE_DEFAULT_COLOR[1], c[2] or TITLE_DEFAULT_COLOR[2], c[3] or TITLE_DEFAULT_COLOR[3], c[4] or TITLE_DEFAULT_COLOR[4] end
                                return TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4]
                            end,
                            setColor = function(r, g, b, a)
                                setTextTitleProp("color", { r, g, b, a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Show Session in Title toggle
                        tabInner:AddToggle({
                            label = "Show Session in Title",
                            description = "Display the session type alongside the meter type (e.g., 'DPS (Current)', 'HPS (Overall)', 'Interrupts (Segment 3)').",
                            get = function()
                                return getSetting("showSessionInTitle") or false
                            end,
                            set = function(value)
                                setSetting("showSessionInTitle", value)
                            end,
                        })

                        -- Right-click title to open meter type menu
                        tabInner:AddToggle({
                            label = "Right-Click to Switch Meter Type",
                            description = "Right-click the title text to open the meter type menu (DPS, HPS, Interrupts, etc.).",
                            get = function()
                                return getSetting("titleTextRightClickMeterType") or false
                            end,
                            set = function(value)
                                setSetting("titleTextRightClickMeterType", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    buttons = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Icons",
                            description = "Removes button backgrounds for a cleaner look. Replaces the dropdown arrow and gear icons with tintable overlays, hides the session button background.",
                            get = function()
                                return getSetting("buttonIconOverlaysEnabled") or false
                            end,
                            set = function(value)
                                setSetting("buttonIconOverlaysEnabled", value)
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Icon Tint",
                            description = "Apply a color tint to all buttons. Works best with 'Use Custom Icons' enabled for uniform results.",
                            values = {
                                ["default"] = "Default",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                return getSetting("buttonTintMode") or "default"
                            end,
                            set = function(value)
                                setSetting("buttonTintMode", value)
                            end,
                            getColor = function()
                                local c = getSetting("buttonTint")
                                if c then return c.r or c[1] or 1, c.g or c[2] or 0.82, c.b or c[3] or 0, c.a or c[4] or 1 end
                                return 1, 0.82, 0, 1  -- Default to gold like title text
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("buttonTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    backdrop = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Show Header Backdrop",
                            description = "Show or hide the header bar background texture.",
                            get = function()
                                local v = getSetting("headerBackdropShow")
                                return v == nil or v  -- Default to true
                            end,
                            set = function(value)
                                setSetting("headerBackdropShow", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Backdrop Tint",
                            description = "Apply a color tint to the header backdrop.",
                            get = function()
                                local c = getSetting("headerBackdropTint")
                                if c then return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1 end
                                return 1, 1, 1, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("headerBackdropTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            hasAlpha = true,
                            disabled = function()
                                local show = getSetting("headerBackdropShow")
                                return show == false
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
            -- Helper to check if icons are disabled (showSpecIcon is off)
            local function iconsDisabled()
                return not getSetting("showSpecIcon")
            end

            inner:AddToggle({
                label = "Show Spec Icon",
                description = "Display specialization icons next to player names. Syncs with Edit Mode.",
                get = function() return getSetting("showSpecIcon") end,
                set = function(value)
                    setSetting("showSpecIcon", value)
                    syncEditModeSetting("showSpecIcon")
                    -- Refresh all controls in this section to update disabled states
                    C_Timer.After(0, function()
                        if inner and inner._controls then
                            for _, control in ipairs(inner._controls) do
                                if control and control.Refresh then
                                    pcall(control.Refresh, control)
                                end
                            end
                        end
                    end)
                end,
            })

            -- Use Custom Border toggle
            inner:AddToggle({
                key = "iconBorderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for spec icons.",
                get = function() return getSetting("iconBorderEnable") or false end,
                set = function(val)
                    setSetting("iconBorderEnable", val)
                end,
                disabled = iconsDisabled,
            })

            -- Border Tint toggle+color
            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function()
                    return getSetting("iconBorderTintEnable") or false
                end,
                set = function(val)
                    setSetting("iconBorderTintEnable", val)
                end,
                getColor = function()
                    local c = getSetting("iconBorderTintColor")
                    if c then
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("iconBorderTintColor", { r = r, g = g, b = b, a = a })
                end,
                hasAlpha = true,
                disabled = iconsDisabled,
            })

            -- Border Thickness slider
            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function() return getSetting("iconBorderThickness") or 1 end,
                set = function(v)
                    setSetting("iconBorderThickness", v)
                end,
                minLabel = "1",
                maxLabel = "8",
                disabled = iconsDisabled,
            })

            -- Horizontal Inset slider (left/right edges)
            inner:AddSlider({
                label = "Horizontal Inset",
                description = "Move left/right edges inward (positive) or outward (negative).",
                min = -4,
                max = 4,
                step = 1,
                get = function() return getSetting("iconBorderInsetH") or 0 end,
                set = function(v)
                    setSetting("iconBorderInsetH", v)
                end,
                minLabel = "-4",
                maxLabel = "+4",
                disabled = iconsDisabled,
            })

            -- Vertical Inset slider (top/bottom edges)
            inner:AddSlider({
                label = "Vertical Inset",
                description = "Move top/bottom edges inward (positive) or outward (negative).",
                min = -4,
                max = 4,
                step = 1,
                get = function() return getSetting("iconBorderInsetV") or 2 end,
                set = function(v)
                    setSetting("iconBorderInsetV", v)
                end,
                minLabel = "-4",
                maxLabel = "+4",
                disabled = iconsDisabled,
            })

            -- JiberishIcons Integration
            inner:AddDescription("JiberishIcons Integration")

            local jiAvailable = addon.IsJiberishIconsAvailable and addon.IsJiberishIconsAvailable()

            if not jiAvailable then
                inner:AddDescription("Install ElvUI_JiberishIcons to enable custom class icons.")
            else
                inner:AddToggle({
                    label = "Use JiberishIcons Class Icons",
                    description = "Replace spec icons with styled class icons from ElvUI_JiberishIcons.",
                    get = function() return getSetting("jiberishIconsEnabled") or false end,
                    set = function(value)
                        setSetting("jiberishIconsEnabled", value)
                    end,
                    disabled = iconsDisabled,
                })

                inner:AddSelector({
                    label = "Icon Style",
                    description = "Choose the JiberishIcons style for class icons.",
                    values = addon.GetJiberishIconsStyles and addon.GetJiberishIconsStyles() or {},
                    get = function() return getSetting("jiberishIconsStyle") or "fabled" end,
                    set = function(value)
                        setSetting("jiberishIconsStyle", value)
                    end,
                    disabled = function()
                        return iconsDisabled() or not getSetting("jiberishIconsEnabled")
                    end,
                })
            end
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
