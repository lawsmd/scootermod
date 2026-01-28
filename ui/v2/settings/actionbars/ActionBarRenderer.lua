-- ActionBarRenderer.lua - Action Bar settings renderer (parameterized for bars 1-8, Pet Bar, Stance Bar)
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ActionBar = {}

local ActionBar = addon.UI.Settings.ActionBar
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function ActionBar.Render(panel, scrollContent, componentId)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        ActionBar.Render(panel, scrollContent, componentId)
    end)

    local function getComponent()
        return addon.Components and addon.Components[componentId]
    end

    local function getSetting(key)
        local comp = getComponent()
        if comp and comp.db then
            return comp.db[key]
        end
        -- Fallback to profile.components if component not loaded
        local profile = addon.db and addon.db.profile
        local components = profile and profile.components
        return components and components[componentId] and components[componentId][key]
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
                profile.components[componentId] = profile.components[componentId] or {}
                profile.components[componentId][key] = value
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

    -- Build backdrop options for selector (returns values and order)
    local function getBackdropOptions()
        local values = { blizzardBg = "Default Blizzard Backdrop" }
        local order = { "blizzardBg" }
        if addon.BuildIconBackdropOptionsContainer then
            local data = addon.BuildIconBackdropOptionsContainer()
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

    -- Determine bar type characteristics
    local isBar1 = (componentId == "actionBar1")
    local isBar2to8 = componentId:match("^actionBar[2-8]$") ~= nil
    local isPetBar = (componentId == "petBar")
    local isStanceBar = (componentId == "stanceBar")
    local hasNumIcons = isBar1 or isBar2to8  -- Only action bars 1-8 have numIcons
    local hasBorderBackdrop = not isStanceBar  -- Stance bar doesn't have border/backdrop in this UI

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = componentId,
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                key = "orientationSelector",
                label = "Orientation",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                    local columnsControl = inner:GetControl("columnsSlider")
                    if columnsControl and columnsControl.SetLabel then
                        columnsControl:SetLabel((v == "V") and "# of Rows" or "# of Columns")
                    end
                end,
                syncCooldown = 0.5,
            })

            local orientation = getSetting("orientation") or "H"
            inner:AddSlider({
                key = "columnsSlider",
                label = (orientation == "V") and "# of Rows" or "# of Columns",
                min = 1, max = 4, step = 1,
                get = function() return getSetting("columns") or 1 end,
                set = function(v) setSetting("columns", v) end,
                debounceKey = componentId .. "_columns",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("columns") end,
                minLabel = "1", maxLabel = "4",
            })

            if hasNumIcons then
                inner:AddSlider({
                    label = "# of Icons", min = 6, max = 12, step = 1,
                    get = function() return getSetting("numIcons") or 12 end,
                    set = function(v) setSetting("numIcons", v) end,
                    debounceKey = componentId .. "_numIcons",
                    debounceDelay = 0.3,
                    onEditModeSync = function() syncEditModeSetting("numIcons") end,
                    minLabel = "6", maxLabel = "12",
                })
            end

            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = componentId .. "_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = componentId,
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = componentId .. "_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Action Bars 1-8 and Pet Bar only, NOT Stance Bar)
    ---------------------------------------------------------------------------
    local hasTextSection = isBar1 or isBar2to8 or isPetBar
    if hasTextSection then
        builder:AddCollapsibleSection({
            title = "Text",
            componentId = componentId,
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
                    NONE = "None",
                    OUTLINE = "Outline",
                    THICKOUTLINE = "Thick Outline",
                }
                local fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE" }

                -- Determine tabs based on bar type
                -- Action Bars and Pet Bar have 4 tabs: Charges, Cooldowns, Hotkey, Macro Name
                local tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                    { key = "hotkey", label = "Keybind" },
                    { key = "macroName", label = "Macro Name" },
                }

                inner:AddTabbedSection({
                    tabs = tabs,
                    componentId = componentId,
                    sectionKey = "textTabs",
                    buildContent = {
                        -------------------------------------------------------
                        -- Charges (textStacks) Tab
                        -------------------------------------------------------
                        charges = function(tabContent, tabBuilder)
                            local function getStacksSetting(key, default)
                                local ts = getSetting("textStacks")
                                if ts and ts[key] ~= nil then return ts[key] end
                                return default
                            end
                            local function setStacksSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textStacks = comp.db.textStacks or {}
                                    comp.db.textStacks[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setStacksSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getStacksSetting("size", 16) end,
                                set = function(v) setStacksSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getStacksSetting("style", "OUTLINE") end,
                                set = function(v) setStacksSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getStacksSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setStacksSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Cooldowns (textCooldown) Tab
                        -------------------------------------------------------
                        cooldowns = function(tabContent, tabBuilder)
                            local function getCooldownSetting(key, default)
                                local tc = getSetting("textCooldown")
                                if tc and tc[key] ~= nil then return tc[key] end
                                return default
                            end
                            local function setCooldownSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textCooldown = comp.db.textCooldown or {}
                                    comp.db.textCooldown[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setCooldownSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getCooldownSetting("size", 14) end,
                                set = function(v) setCooldownSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getCooldownSetting("style", "OUTLINE") end,
                                set = function(v) setCooldownSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getCooldownSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setCooldownSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Hotkey (textHotkey) Tab
                        -------------------------------------------------------
                        hotkey = function(tabContent, tabBuilder)
                            local function getHotkeySetting(key, default)
                                local th = getSetting("textHotkey")
                                if th and th[key] ~= nil then return th[key] end
                                return default
                            end
                            local function setHotkeySetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textHotkey = comp.db.textHotkey or {}
                                    comp.db.textHotkey[key] = value
                                end
                                applyText()
                            end

                            -- Hide Hotkey toggle (stored as textHotkeyHidden)
                            tabBuilder:AddToggle({
                                label = "Hide Hotkey Text",
                                get = function() return getSetting("textHotkeyHidden") or false end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkeyHidden = v
                                    end
                                    applyText()
                                end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getHotkeySetting("fontFace", "FRIZQT__") end,
                                set = function(v) setHotkeySetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getHotkeySetting("size", 14) end,
                                set = function(v) setHotkeySetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getHotkeySetting("style", "OUTLINE") end,
                                set = function(v) setHotkeySetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getHotkeySetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setHotkeySetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getHotkeySetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkey = comp.db.textHotkey or {}
                                        comp.db.textHotkey.offset = comp.db.textHotkey.offset or {}
                                        comp.db.textHotkey.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getHotkeySetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkey = comp.db.textHotkey or {}
                                        comp.db.textHotkey.offset = comp.db.textHotkey.offset or {}
                                        comp.db.textHotkey.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Macro Name (textMacro) Tab
                        -------------------------------------------------------
                        macroName = function(tabContent, tabBuilder)
                            local function getMacroSetting(key, default)
                                local tm = getSetting("textMacro")
                                if tm and tm[key] ~= nil then return tm[key] end
                                return default
                            end
                            local function setMacroSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    comp.db.textMacro = comp.db.textMacro or {}
                                    comp.db.textMacro[key] = value
                                end
                                applyText()
                            end

                            -- Hide Macro Name toggle (stored as textMacroHidden)
                            tabBuilder:AddToggle({
                                label = "Hide Macro Name",
                                get = function() return getSetting("textMacroHidden") or false end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacroHidden = v
                                    end
                                    applyText()
                                end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getMacroSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setMacroSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getMacroSetting("size", 14) end,
                                set = function(v) setMacroSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getMacroSetting("style", "OUTLINE") end,
                                set = function(v) setMacroSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getMacroSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setMacroSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddSlider({
                                label = "Offset X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getMacroSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacro = comp.db.textMacro or {}
                                        comp.db.textMacro.offset = comp.db.textMacro.offset or {}
                                        comp.db.textMacro.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:AddSlider({
                                label = "Offset Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getMacroSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacro = comp.db.textMacro or {}
                                        comp.db.textMacro.offset = comp.db.textMacro.offset or {}
                                        comp.db.textMacro.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-50", maxLabel = "+50",
                            })

                            tabBuilder:Finalize()
                        end,
                    },
                })

                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Border Section (not for Stance Bar)
    ---------------------------------------------------------------------------
    if hasBorderBackdrop then
        builder:AddCollapsibleSection({
            title = "Border",
            componentId = componentId,
            sectionKey = "border",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddToggle({
                    label = "Disable All Borders",
                    get = function() return getSetting("borderDisableAll") or false end,
                    set = function(v) setSetting("borderDisableAll", v) end,
                })

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

                local borderValues, borderOrder = getIconBorderOptions()
                inner:AddSelector({
                    label = "Border Style",
                    values = borderValues,
                    order = borderOrder,
                    get = function() return getSetting("borderStyle") or "square" end,
                    set = function(v) setSetting("borderStyle", v) end,
                })

                inner:AddSlider({
                    label = "Border Thickness", min = 1, max = 8, step = 0.2,
                    get = function() return getSetting("borderThickness") or 1 end,
                    set = function(v) setSetting("borderThickness", v) end,
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
        -- Backdrop Section (not for Stance Bar)
        ---------------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Backdrop",
            componentId = componentId,
            sectionKey = "backdrop",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddToggle({
                    label = "Disable Backdrop",
                    get = function() return getSetting("backdropDisable") or false end,
                    set = function(v) setSetting("backdropDisable", v) end,
                })

                local backdropValues, backdropOrder = getBackdropOptions()
                inner:AddSelector({
                    label = "Backdrop Style",
                    values = backdropValues,
                    order = backdropOrder,
                    get = function() return getSetting("backdropStyle") or "blizzardBg" end,
                    set = function(v) setSetting("backdropStyle", v) end,
                })

                inner:AddSlider({
                    label = "Backdrop Opacity", min = 1, max = 100, step = 1,
                    get = function() return getSetting("backdropOpacity") or 100 end,
                    set = function(v) setSetting("backdropOpacity", v) end,
                    minLabel = "1%", maxLabel = "100%",
                })

                inner:AddToggleColorPicker({
                    label = "Backdrop Tint",
                    getToggle = function() return getSetting("backdropTintEnable") or false end,
                    setToggle = function(v) setSetting("backdropTintEnable", v) end,
                    getColor = function()
                        local c = getSetting("backdropTintColor")
                        return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                    end,
                    setColor = function(r, g, b, a) setSetting("backdropTintColor", {r, g, b, a}) end,
                })

                inner:AddSlider({
                    label = "Backdrop Inset", min = -4, max = 4, step = 1,
                    get = function() return getSetting("backdropInset") or 0 end,
                    set = function(v) setSetting("backdropInset", v) end,
                    minLabel = "-4", maxLabel = "4",
                })

                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Misc/Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = componentId,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if isBar2to8 then
                inner:AddSelector({
                    label = "Bar Visible",
                    values = {
                        always = "Always",
                        combat = "In Combat",
                        not_in_combat = "Not In Combat",
                        hidden = "Hidden",
                    },
                    order = { "always", "combat", "not_in_combat", "hidden" },
                    get = function() return getSetting("barVisibility") or "always" end,
                    set = function(v)
                        setSetting("barVisibility", v)
                        syncEditModeSetting("barVisibility")
                    end,
                    syncCooldown = 0.5,
                })
            end

            if isBar1 or isBar2to8 or isPetBar then
                inner:AddToggle({
                    label = "Always Show Buttons",
                    get = function() return getSetting("alwaysShowButtons") ~= false end,
                    set = function(v)
                        setSetting("alwaysShowButtons", v)
                        syncEditModeSetting("alwaysShowButtons")
                    end,
                })
            end

            if isBar1 then
                inner:AddToggle({
                    label = "Hide Bar Art",
                    get = function() return getSetting("hideBarArt") or false end,
                    set = function(v)
                        setSetting("hideBarArt", v)
                        syncEditModeSetting("hideBarArt")
                    end,
                })

                inner:AddToggle({
                    label = "Hide Bar Scrolling",
                    get = function() return getSetting("hideBarScrolling") or false end,
                    set = function(v)
                        setSetting("hideBarScrolling", v)
                        syncEditModeSetting("hideBarScrolling")
                    end,
                })
            end

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
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityOutOfCombat") or 100 end,
                set = function(v) setSetting("barOpacityOutOfCombat", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityWithTarget") or 100 end,
                set = function(v) setSetting("barOpacityWithTarget", v) end,
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

return ActionBar
