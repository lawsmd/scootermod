-- TooltipRenderer.lua - Tooltip settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Tooltip = {}

local Tooltip = addon.UI.Settings.Tooltip
local SettingsBuilder = addon.UI.SettingsBuilder

function Tooltip.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        Tooltip.Render(panel, scrollContent)
    end)

    -- Helper to get component settings
    local function getComponent()
        return addon.Components and addon.Components["tooltip"]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components.tooltip and components.tooltip[key]
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
                profile.components.tooltip = profile.components.tooltip or {}
                profile.components.tooltip[key] = value
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
        if t.size == nil then t.size = defaults.size end
        if t.style == nil then t.style = defaults.style end
        return t
    end

    -- Font style options
    local fontStyleValues = {
        NONE = "Regular",
        OUTLINE = "Outline",
        THICKOUTLINE = "Thick Outline",
    }
    local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

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

        -- Font size slider
        tabBuilder:AddSlider({
            label = "Font Size",
            description = "The size of this text element.",
            min = 6,
            max = 32,
            step = 1,
            get = function()
                local t = getTextConfig(dbKey)
                return (t and t.size) or defaults.size
            end,
            set = function(v)
                local t = ensureTextConfig(dbKey, defaults)
                if t then
                    t.size = v or defaults.size
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
            end,
            minLabel = "6",
            maxLabel = "32",
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

        tabBuilder:Finalize()
    end

    -- Collapsible section: Text (with tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "tooltip",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "nameTitle", label = "Name & Title" },
                    { key = "everythingElse", label = "Everything Else" },
                    { key = "comparison", label = "Comparison" },
                },
                componentId = "tooltip",
                sectionKey = "textTabs",
                buildContent = {
                    nameTitle = function(tabContent, tabBuilder)
                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for this text element.",
                            get = function()
                                local t = getTextConfig("textTitle")
                                return (t and t.fontFace) or "FRIZQT__"
                            end,
                            set = function(fontKey)
                                local t = ensureTextConfig("textTitle", { fontFace = "FRIZQT__", size = 12, style = "NONE" })
                                if t then
                                    t.fontFace = fontKey or "FRIZQT__"
                                    if addon and addon.ApplyStyles then
                                        addon:ApplyStyles()
                                    end
                                end
                            end,
                        })

                        -- Font size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            description = "The size of this text element.",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function()
                                local t = getTextConfig("textTitle")
                                return (t and t.size) or 12
                            end,
                            set = function(v)
                                local t = ensureTextConfig("textTitle", { fontFace = "FRIZQT__", size = 12, style = "NONE" })
                                if t then
                                    t.size = v or 12
                                    if addon and addon.ApplyStyles then
                                        addon:ApplyStyles()
                                    end
                                end
                            end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            description = "The outline style for this text.",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function()
                                local t = getTextConfig("textTitle")
                                return (t and t.style) or "NONE"
                            end,
                            set = function(v)
                                local t = ensureTextConfig("textTitle", { fontFace = "FRIZQT__", size = 12, style = "NONE" })
                                if t then
                                    t.style = v or "NONE"
                                    if addon and addon.ApplyStyles then
                                        addon:ApplyStyles()
                                    end
                                end
                            end,
                        })

                        -- Class color toggle for player names
                        tabBuilder:AddToggle({
                            label = "Class Color Player Names",
                            description = "Color player character names by their class color. Does not affect NPCs.",
                            get = function()
                                return getSetting("classColorPlayerNames") or false
                            end,
                            set = function(val)
                                setSetting("classColorPlayerNames", val)
                            end,
                        })

                        tabBuilder:Finalize()
                    end,
                    everythingElse = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textEverythingElse", {
                            fontFace = "FRIZQT__",
                            size = 12,
                            style = "NONE",
                        })
                    end,
                    comparison = function(tabContent, tabBuilder)
                        buildTextTabContent(tabBuilder, "textComparison", {
                            fontFace = "FRIZQT__",
                            size = 12,
                            style = "NONE",
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
        componentId = "tooltip",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Tooltip Health Bar",
                description = "Hide the health bar that appears on unit tooltips.",
                get = function()
                    return getSetting("hideHealthBar") or false
                end,
                set = function(val)
                    setSetting("hideHealthBar", val)
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

return Tooltip
