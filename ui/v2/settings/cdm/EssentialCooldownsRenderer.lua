-- EssentialCooldownsRenderer.lua - Essential Cooldowns settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.EssentialCooldowns = {}

local EssentialCooldowns = addon.UI.Settings.CDM.EssentialCooldowns
local SettingsBuilder = addon.UI.SettingsBuilder

-- Text color options (shared across text settings)
local textColorValues = { default = "Default", class = "Class Color", custom = "Custom" }
local textColorOrder = { "default", "class", "custom" }

function EssentialCooldowns.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        EssentialCooldowns.Render(panel, scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["essentialCooldowns"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.essentialCooldowns and components.essentialCooldowns[key]
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
                profile.components.essentialCooldowns = profile.components.essentialCooldowns or {}
                profile.components.essentialCooldowns[key] = value
            end
        end
    end

    -- Helper to sync Edit Mode settings after value change.
    -- Uses skipApply=true: visual updates happen via updaters inside
    -- SyncComponentSettingToEditMode; Edit Mode layout cache is refreshed
    -- by a post-hook on EnterEditMode (see core/editmode.lua).
    local function syncEditModeSetting(settingId)
        local comp = getComponent()
        if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
            addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
        end
    end

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "essentialCooldowns",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use centralized setting patterns for orientation-dependent settings
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation

            -- Get current orientation for initial values
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")

                    -- Dynamically update dependent controls
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end

                    local columnsSlider = inner:GetControl("columnsRows")
                    if columnsSlider then
                        columnsSlider:SetLabel(OrientationPatterns.getColumnsLabel(v))
                    end
                end,
                -- Prevent rapid changes during Edit Mode sync (orientation changes trigger
                -- expensive Apply operations; allow 400ms for sync to complete)
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                key = "columnsRows",
                label = OrientationPatterns.getColumnsLabel(currentOrientation),
                description = OrientationPatterns.getColumnsDescription(currentOrientation),
                min = 1,
                max = 20,
                step = 1,
                get = function() return getSetting("columns") or 12 end,
                set = function(v) setSetting("columns", v) end,
                minLabel = "1",
                maxLabel = "20",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_columns",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("columns")
                end,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                -- Prevent rapid changes during Edit Mode sync
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between cooldown icons in pixels.",
                min = 2,
                max = 14,
                step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px",
                maxLabel = "14px",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "essentialCooldowns",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Icon Size (Scale) - Edit Mode setting
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_essentialCooldowns_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconSize")
                end,
            })

            -- Icon Shape (Tall/Wide Ratio)
            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67,
                max = 67,
                step = 1,
                get = function() return getSetting("tallWideRatio") or 0 end,
                set = function(v)
                    setSetting("tallWideRatio", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "Wide",
                maxLabel = "Tall",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "essentialCooldowns",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use Custom Border toggle
            inner:AddToggle({
                key = "borderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for cooldown icons.",
                get = function() return getSetting("borderEnable") or false end,
                set = function(val)
                    setSetting("borderEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            -- Border Tint toggle+color
            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function()
                    return getSetting("borderTintEnable") or false
                end,
                set = function(val)
                    setSetting("borderTintEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                hasAlpha = true,
            })

            -- Border Style selector
            -- Build options from IconBorders
            local borderStyleValues = { square = "Default" }
            local borderStyleOrder = { "square" }
            if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
                local entries = addon.IconBorders.GetDropdownEntries()
                if entries then
                    borderStyleValues = {}
                    borderStyleOrder = {}
                    for _, entry in ipairs(entries) do
                        local key = entry.value or entry.key
                        local label = entry.text or entry.label or key
                        if key then
                            borderStyleValues[key] = label
                            table.insert(borderStyleOrder, key)
                        end
                    end
                end
            end

            inner:AddSelector({
                key = "borderStyle",
                label = "Border Style",
                description = "Choose the visual style for icon borders.",
                values = borderStyleValues,
                order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            -- Border Thickness slider
            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v)
                    setSetting("borderThickness", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "1",
                maxLabel = "8",
            })

            -- Border Inset slider
            inner:AddSlider({
                label = "Border Inset",
                description = "Move border inward (positive) or outward (negative).",
                min = -4,
                max = 4,
                step = 1,
                get = function() return getSetting("borderInset") or -1 end,
                set = function(v)
                    setSetting("borderInset", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "-4",
                maxLabel = "+4",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Text (contains tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "essentialCooldowns",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Helper to apply text styling
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            -- Font style options
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

            -- Tabbed section for Charges (stacks) and Cooldowns text settings
            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                },
                componentId = "essentialCooldowns",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        -- Helper to get/set textStacks sub-properties
                        local function getStacksSetting(key, default)
                            local ts = getSetting("textStacks")
                            if ts and ts[key] ~= nil then return ts[key] end
                            return default
                        end
                        local function setStacksSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textStacks = comp.db.textStacks or {}
                                comp.db.textStacks[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for charges/stacks text.",
                            get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setStacksSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getStacksSetting("size", 16) end,
                            set = function(v) setStacksSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getStacksSetting("style", "OUTLINE") end,
                            set = function(v) setStacksSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getStacksSetting("colorMode", "default") end,
                            set = function(v) setStacksSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getStacksSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setStacksSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset dual slider (X and Y side-by-side)
                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return offset.x or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100",
                                maxLabel = "+100",
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return offset.y or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100",
                                maxLabel = "+100",
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        -- Helper to get/set textCooldown sub-properties
                        local function getCooldownSetting(key, default)
                            local tc = getSetting("textCooldown")
                            if tc and tc[key] ~= nil then return tc[key] end
                            return default
                        end
                        local function setCooldownSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textCooldown = comp.db.textCooldown or {}
                                comp.db.textCooldown[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for cooldown timer text.",
                            get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setCooldownSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getCooldownSetting("size", 14) end,
                            set = function(v) setCooldownSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getCooldownSetting("style", "OUTLINE") end,
                            set = function(v) setCooldownSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getCooldownSetting("colorMode", "default") end,
                            set = function(v) setCooldownSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getCooldownSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setCooldownSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset X slider
                        tabBuilder:AddSlider({
                            label = "Offset X",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = function()
                                local offset = getCooldownSetting("offset", {x=0, y=0})
                                return offset.x or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                    comp.db.textCooldown.offset.x = v
                                end
                                applyText()
                            end,
                            minLabel = "-100",
                            maxLabel = "+100",
                        })

                        -- Offset Y slider
                        tabBuilder:AddSlider({
                            label = "Offset Y",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = function()
                                local offset = getCooldownSetting("offset", {x=0, y=0})
                                return offset.y or 0
                            end,
                            set = function(v)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                    comp.db.textCooldown.offset.y = v
                                end
                                applyText()
                            end,
                            minLabel = "-100",
                            maxLabel = "+100",
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility & Misc
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "essentialCooldowns",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Opacity While on Cooldown slider (addon-only, highest priority)
            inner:AddSlider({
                label = "Opacity While on Cooldown",
                description = "Opacity for icons currently on cooldown. Takes precedence over other opacity settings.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOnCooldown") or 100 end,
                set = function(v)
                    setSetting("opacityOnCooldown", v)
                    if addon and addon.RefreshCDMCooldownOpacity then
                        addon.RefreshCDMCooldownOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "1%",
                maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Highest Priority",
                    tooltipText = "This setting takes precedence over all other opacity settings. When an icon is on cooldown, this opacity is applied regardless of combat state or target. Set to 100% to disable.",
                },
            })

            -- Visibility Mode selector (Edit Mode setting)
            local visibilityValues = {
                always = "Always",
                combat = "Only in Combat",
                never = "Hidden",
            }
            local visibilityOrder = { "always", "combat", "never" }

            inner:AddSelector({
                label = "Visibility",
                description = "When the cooldown tracker is visible.",
                values = visibilityValues,
                order = visibilityOrder,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            -- Opacity in Combat slider (Edit Mode setting)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%",
                maxLabel = "100%",
                debounceKey = "UI_essentialCooldowns_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("opacity")
                end,
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            -- Opacity Out of Combat slider (addon-only)
            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Opacity when not in combat.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            -- Opacity With Target slider (addon-only)
            inner:AddSlider({
                label = "Opacity With Target",
                description = "Opacity when you have a target.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            -- Show Timer toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Timer",
                description = "Display cooldown timer text on icons.",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            -- Show Tooltips toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Tooltips",
                description = "Display tooltips when hovering over icons.",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

return EssentialCooldowns
