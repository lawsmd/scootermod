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

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("tooltip")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply

    -- Helper to get text config sub-table
    local function getTextConfig(key)
        local comp = getComponent()
        local db = comp and comp.db
        if db and type(db[key]) == "table" then
            return db[key]
        end
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

    local fontStyleValues = Helpers.fontStyleValues
    local fontStyleOrder = Helpers.fontStyleOrder

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

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "tooltip",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Tooltip Scale",
                description = "Scale the size of tooltips. Affects GameTooltip and comparison tooltips.",
                min = 0.5,
                max = 1.5,
                step = 0.05,
                get = function()
                    return getSetting("tooltipScale") or 1.0
                end,
                set = function(v)
                    setSetting("tooltipScale", v)
                end,
                minLabel = "50%",
                maxLabel = "150%",
                precision = 0,
                displayMultiplier = 100,
                displaySuffix = "%",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "tooltip",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                end,
                hasAlpha = true,
            })
            inner:Finalize()
        end,
    })

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

addon.UI.SettingsPanel:RegisterRenderer("tooltip", function(panel, scrollContent)
    Tooltip.Render(panel, scrollContent)
end)

return Tooltip
