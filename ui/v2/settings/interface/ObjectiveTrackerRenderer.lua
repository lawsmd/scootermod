-- ObjectiveTrackerRenderer.lua - Objective Tracker settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ObjectiveTracker = {}

local ObjectiveTracker = addon.UI.Settings.ObjectiveTracker
local SettingsBuilder = addon.UI.SettingsBuilder

function ObjectiveTracker.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        ObjectiveTracker.Render(panel, scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["objectiveTracker"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.objectiveTracker and components.objectiveTracker[key]
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
                profile.components.objectiveTracker = profile.components.objectiveTracker or {}
                profile.components.objectiveTracker[key] = value
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

    -- Helper to get text config sub-table
    local function getTextConfig(key)
        local comp = getComponent()
        local db = comp and comp.db
        if db and type(db[key]) == "table" then
            return db[key]
        end
        return nil
    end

    local function ensureTextConfig(key, defaults)
        local comp = getComponent()
        if not comp then return nil end
        local db = comp.db
        if not db then return nil end

        db[key] = db[key] or {}
        local t = db[key]
        if t.fontFace == nil then t.fontFace = defaults.fontFace end
        if t.style == nil then t.style = defaults.style end
        if t.colorMode == nil then t.colorMode = defaults.colorMode end
        if type(t.color) ~= "table" then
            t.color = { defaults.color[1], defaults.color[2], defaults.color[3], defaults.color[4] }
        end
        return t
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

    -- Font color mode options (for UISelectorColorPicker)
    local fontColorValues = {
        default = "Default",
        custom = "Custom",
    }
    local fontColorOrder = { "default", "custom" }

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "objectiveTracker",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Height",
                description = "Maximum height of the Objective Tracker frame.",
                min = 200,
                max = 1000,
                step = 10,
                get = function() return getSetting("height") or 400 end,
                set = function(v) setSetting("height", v) end,
                minLabel = "200",
                maxLabel = "1000",
                debounceKey = "UI_objectiveTracker_height",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("height")
                end,
            })

            inner:AddSlider({
                label = "Text Size",
                description = "Size of text in the Objective Tracker.",
                min = 10,
                max = 24,
                step = 1,
                get = function() return getSetting("textSize") or 14 end,
                set = function(v) setSetting("textSize", v) end,
                minLabel = "10",
                maxLabel = "24",
                debounceKey = "UI_objectiveTracker_textSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("textSize")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Style
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "objectiveTracker",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Header Backgrounds",
                description = "Remove the backgrounds behind section headers.",
                get = function()
                    return getSetting("hideHeaderBackgrounds") or false
                end,
                set = function(val)
                    setSetting("hideHeaderBackgrounds", val)
                end,
            })

            inner:AddToggleColorPicker({
                label = "Tint Header Background",
                description = "Apply a custom tint color to section header backgrounds.",
                get = function()
                    return getSetting("tintHeaderBackgroundEnable") or false
                end,
                set = function(val)
                    setSetting("tintHeaderBackgroundEnable", val)
                end,
                getColor = function()
                    local c = getSetting("tintHeaderBackgroundColor")
                    if c and type(c) == "table" then
                        return c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("tintHeaderBackgroundColor", { r, g, b, a })
                end,
                hasAlpha = true,
            })

            inner:Finalize()
        end,
    })

    -- Helper to build text tab content (used by all three tabs)
    local function buildTextTabContent(tabBuilder, dbKey, defaults)
        -- Font selector
        tabBuilder:AddFontSelector({
            label = "Font",
            description = "The font used for this text element.",
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.fontFace) or defaults.fontFace
            end,
            set = function(fontKey)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.fontFace = fontKey or defaults.fontFace
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
        })

        -- Font style selector
        tabBuilder:AddSelector({
            label = "Font Style",
            description = "The outline style for this text.",
            values = fontStyleValues,
            order = fontStyleOrder,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.style) or defaults.style
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.style = v or defaults.style
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
        })

        -- Font color selector with inline swatch (UISelectorColorPicker)
        tabBuilder:AddSelectorColorPicker({
            label = "Font Color",
            description = "Color mode for this text. Select 'Custom' to choose a specific color.",
            values = fontColorValues,
            order = fontColorOrder,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.colorMode) or defaults.colorMode
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.colorMode = v or defaults.colorMode
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
            getColor = function()
                local t = getTextConfig(dbKey)
                local c = (t and type(t.color) == "table" and t.color) or defaults.color
                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end,
            setColor = function(r, g, b, a)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.color = { r or 1, g or 1, b or 1, a or 1 }
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
            customValue = "custom",
            hasAlpha = true,
        })

        tabBuilder:Finalize()
    end

    -- Collapsible section: Text (with tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "objectiveTracker",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "header", label = "Header" },
                    { key = "questName", label = "Quest Name" },
                    { key = "questObjective", label = "Quest Objective" },
                },
                componentId = "objectiveTracker",
                sectionKey = "textTabs",
                buildContent = {
                    header = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textHeader", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    questName = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textQuestName", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    questObjective = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textQuestObjective", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 0.8, 0.8, 0.8, 1 },
                        })
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "objectiveTracker",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Background Opacity",
                description = "Overall background opacity of the Objective Tracker.",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "0%",
                maxLabel = "100%",
                debounceKey = "UI_objectiveTracker_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("opacity")
                end,
            })

            inner:AddSlider({
                label = "Opacity In-Instance-Combat",
                description = "Opacity when in combat inside an instance (dungeon/raid).",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityInInstanceCombat") or 100 end,
                set = function(v)
                    setSetting("opacityInInstanceCombat", v)
                    if addon and addon.RefreshOpacityState then
                        addon:RefreshOpacityState()
                    end
                end,
                minLabel = "0%",
                maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

return ObjectiveTracker
