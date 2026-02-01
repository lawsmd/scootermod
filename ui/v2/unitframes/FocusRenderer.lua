-- FocusRenderer.lua - Focus Unit Frame TUI renderer
-- Similar to Target but adds "Use Larger Frame" and "Hide Threat Meter"
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufFocus"
local UNIT_KEY = "Focus"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureUFDB()
    return UF.ensureUFDB(UNIT_KEY)
end

local function ensureTextDB(key)
    return UF.ensureTextDB(UNIT_KEY, key)
end

local function ensurePortraitDB()
    return UF.ensurePortraitDB(UNIT_KEY)
end

local function ensureCastBarDB()
    return UF.ensureCastBarDB(UNIT_KEY)
end

local function ensureNameLevelDB(textKey)
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyBarTextures()
    UF.applyBarTextures(UNIT_KEY)
end

local function applyHealthText()
    UF.applyHealthText(UNIT_KEY)
end

local function applyPowerText()
    UF.applyPowerText(UNIT_KEY)
end

local function applyScaleMult()
    UF.applyScaleMult(UNIT_KEY)
end

local function applyStyles()
    UF.applyStyles()
end

local function applyPortrait()
    UF.applyPortrait(UNIT_KEY)
end

local function applyCastBar()
    UF.applyCastBar(UNIT_KEY)
end

local function applyNameLevelText()
    if addon and addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(UNIT_KEY)
    end
    UF.applyStyles()
end

--------------------------------------------------------------------------------
-- Shared Tab Builders (copied from Target for consistency)
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn, colorValues, colorOrder)
    colorValues = colorValues or UF.healthColorValues
    colorOrder = colorOrder or UF.healthColorOrder

    inner:AddBarTextureSelector({
        label = "Foreground Texture",
        get = function() local t = ensureUFDB() or {}; return t[barPrefix .. "Texture"] or "default" end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "Texture"] = v or "default"; applyFn() end end,
    })

    inner:AddSelectorColorPicker({
        label = "Foreground Color",
        values = colorValues, order = colorOrder,
        get = function() local t = ensureUFDB() or {}; return t[barPrefix .. "ColorMode"] or "default" end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "ColorMode"] = v or "default"; applyFn() end end,
        getColor = function() local t = ensureUFDB() or {}; local c = t[barPrefix .. "Tint"] or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t[barPrefix .. "Tint"] = {r or 1, g or 1, b or 1, a or 1}; applyFn() end end,
        customValue = "custom", hasAlpha = true,
    })

    inner:AddSpacer(8)

    inner:AddBarTextureSelector({
        label = "Background Texture",
        get = function() local t = ensureUFDB() or {}; return t[barPrefix .. "BackgroundTexture"] or "default" end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BackgroundTexture"] = v or "default"; applyFn() end end,
    })

    inner:AddSelectorColorPicker({
        label = "Background Color",
        values = UF.bgColorValues, order = UF.bgColorOrder,
        get = function() local t = ensureUFDB() or {}; return t[barPrefix .. "BackgroundColorMode"] or "default" end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BackgroundColorMode"] = v or "default"; applyFn() end end,
        getColor = function() local t = ensureUFDB() or {}; local c = t[barPrefix .. "BackgroundTint"] or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t[barPrefix .. "BackgroundTint"] = {r or 0, g or 0, b or 0, a or 1}; applyFn() end end,
        customValue = "custom", hasAlpha = true,
    })

    inner:AddSlider({
        label = "Background Opacity",
        min = 0, max = 100, step = 1,
        get = function() local t = ensureUFDB() or {}; return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50 end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50; applyFn() end end,
    })

    inner:Finalize()
end

local function buildBorderTab(inner, barPrefix, applyFn)
    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function() local t = ensureUFDB() or {}; return t[barPrefix .. "BorderStyle"] or "square" end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BorderStyle"] = v or "square"; applyFn() end end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function() local t = ensureUFDB() or {}; return not not t[barPrefix .. "BorderTintEnable"] end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BorderTintEnable"] = not not v; applyFn() end end,
        getColor = function() local t = ensureUFDB() or {}; local c = t[barPrefix .. "BorderTintColor"] or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t[barPrefix .. "BorderTintColor"] = {r or 1, g or 1, b or 1, a or 1}; applyFn() end end,
        hasAlpha = true,
    })

    inner:AddSlider({
        label = "Border Thickness",
        min = 1, max = 8, step = 0.2, precision = 1,
        get = function() local t = ensureUFDB() or {}; return tonumber(t[barPrefix .. "BorderThickness"]) or 1 end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BorderThickness"] = tonumber(v) or 1; applyFn() end end,
    })

    inner:AddSlider({
        label = "Border Inset",
        min = -4, max = 4, step = 1,
        get = function() local t = ensureUFDB() or {}; return tonumber(t[barPrefix .. "BorderInset"]) or 0 end,
        set = function(v) local t = ensureUFDB(); if t then t[barPrefix .. "BorderInset"] = tonumber(v) or 0; applyFn() end end,
    })

    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn, defaultAlignment, colorValues, colorOrder)
    defaultAlignment = defaultAlignment or "LEFT"
    colorValues = colorValues or UF.fontColorValues
    colorOrder = colorOrder or UF.fontColorOrder
    local hiddenKey = textKey:gsub("text", ""):lower() .. "Hidden"

    inner:AddToggle({
        label = "Disable Text",
        get = function() local t = ensureUFDB() or {}; return not not t[hiddenKey] end,
        set = function(v) local t = ensureUFDB(); if t then t[hiddenKey] = v and true or false; applyFn() end end,
    })

    inner:AddFontSelector({
        label = "Font",
        get = function() local s = ensureTextDB(textKey) or {}; return s.fontFace or "FRIZQT__" end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].fontFace = v; applyStyles() end end,
    })

    inner:AddSelector({
        label = "Style",
        values = UF.fontStyleValues, order = UF.fontStyleOrder,
        get = function() local s = ensureTextDB(textKey) or {}; return s.style or "OUTLINE" end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].style = v; applyStyles() end end,
    })

    inner:AddSlider({
        label = "Size",
        min = 6, max = 48, step = 1,
        get = function() local s = ensureTextDB(textKey) or {}; return tonumber(s.size) or 14 end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].size = tonumber(v) or 14; applyStyles() end end,
    })

    inner:AddSelectorColorPicker({
        label = "Color",
        values = colorValues, order = colorOrder,
        get = function() local s = ensureTextDB(textKey) or {}; return s.colorMode or "default" end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].colorMode = v or "default"; applyStyles() end end,
        getColor = function() local s = ensureTextDB(textKey) or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].color = {r or 1, g or 1, b or 1, a or 1}; applyStyles() end end,
        customValue = "custom", hasAlpha = true,
    })

    inner:AddSelector({
        label = "Alignment",
        values = UF.alignmentValues, order = UF.alignmentOrder,
        get = function() local s = ensureTextDB(textKey) or {}; return s.alignment or defaultAlignment end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].alignment = v or defaultAlignment; applyStyles() end end,
    })

    inner:AddSlider({
        label = "Offset X",
        min = -100, max = 100, step = 1,
        get = function() local s = ensureTextDB(textKey) or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].offset = t[textKey].offset or {}; t[textKey].offset.x = tonumber(v) or 0; applyStyles() end end,
    })

    inner:AddSlider({
        label = "Offset Y",
        min = -100, max = 100, step = 1,
        get = function() local s = ensureTextDB(textKey) or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
        set = function(v) local t = ensureUFDB(); if t then t[textKey] = t[textKey] or {}; t[textKey].offset = t[textKey].offset or {}; t[textKey].offset.y = tonumber(v) or 0; applyStyles() end end,
    })

    inner:Finalize()
end

local function buildDirectionTab(inner)
    inner:AddSelector({
        label = "Bar Fill Direction",
        values = UF.fillDirectionValues, order = UF.fillDirectionOrder,
        get = function() local t = ensureUFDB() or {}; return t.healthBarReverseFill and "reverse" or "default" end,
        set = function(v) local t = ensureUFDB(); if t then t.healthBarReverseFill = (v == "reverse"); applyStyles() end end,
    })
    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderFocus(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderFocus(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings (Focus-specific additions)
    --------------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function() local t = ensureUFDB() or {}; return not not t.useCustomBorders end,
        set = function(v) local t = ensureUFDB(); if t then t.useCustomBorders = not not v; if not v then t.healthBarHideBorder = false end; applyBarTextures() end end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    -- Use Larger Frame (Focus-only, Edit Mode controlled)
    builder:AddToggle({
        label = "Use Larger Frame",
        description = "Uses the larger Focus frame variant (Edit Mode setting).",
        get = function()
            return UF.getUseLargerFrame(COMPONENT_ID)
        end,
        set = function(v)
            UF.setUseLargerFrame(COMPONENT_ID, v)
        end,
    })

    builder:AddSlider({
        label = "Frame Size (Scale)",
        description = "Blizzard's Edit Mode scale (100-200%).",
        min = 100, max = 200, step = 5,
        get = function() return UF.getEditModeFrameSize(COMPONENT_ID) end,
        set = function(v) UF.setEditModeFrameSize(COMPONENT_ID, v) end,
        minLabel = "100%", maxLabel = "200%",
        infoIcon = UF.TOOLTIPS.frameSize,
    })

    builder:AddSlider({
        label = "Scale Multiplier",
        description = "Addon multiplier on top of Edit Mode scale.",
        min = 1.0, max = 2.0, step = 0.05, precision = 2,
        get = function() local t = ensureUFDB() or {}; return tonumber(t.scaleMult) or 1.0 end,
        set = function(v) local t = ensureUFDB(); if t then t.scaleMult = tonumber(v) or 1.0; applyScaleMult() end end,
        minLabel = "1.0x", maxLabel = "2.0x",
        infoIcon = UF.TOOLTIPS.scaleMult,
    })

    --------------------------------------------------------------------------------
    -- Health Bar (5 tabs with Direction first)
    --------------------------------------------------------------------------------

    local healthTabs = UF.getHealthBarTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = healthTabs,
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10, max = 100, step = 5,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.healthBarOverlayHeightPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.healthBarOverlayHeightPct = tonumber(v) or 100; applyBarTextures() end end,
                            infoIcon = { tooltipTitle = "Health Bar Height", tooltipText = "Reduces the visible height of the health bar. The bar fill still tracks health correctly, but is cropped to this percentage of its normal height (centered vertically)." },
                        })
                        tabInner:Finalize()
                    end,
                    direction = function(cf, tabInner) buildDirectionTab(tabInner) end,
                    style = function(cf, tabInner) buildStyleTab(tabInner, "healthBar", applyBarTextures) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "healthBar", applyBarTextures) end,
                    percentText = function(cf, tabInner) buildTextTab(tabInner, "textHealthPercent", applyHealthText, "LEFT") end,
                    valueText = function(cf, tabInner) buildTextTab(tabInner, "textHealthValue", applyHealthText, "RIGHT") end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Power Bar (7 tabs)
    --------------------------------------------------------------------------------

    local powerTabs = UF.getPowerBarTabs()

    builder:AddCollapsibleSection({
        title = "Power Bar",
        componentId = COMPONENT_ID,
        sectionKey = "powerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = powerTabs,
                componentId = COMPONENT_ID,
                sectionKey = "powerBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSlider({ label = "X Offset", min = -100, max = 100, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetX) or 0 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarOffsetX = tonumber(v) or 0; applyBarTextures() end end })
                        tabInner:AddSlider({ label = "Y Offset", min = -100, max = 100, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetY) or 0 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarOffsetY = tonumber(v) or 0; applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Height %", min = 10, max = 200, step = 5,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner) buildStyleTab(tabInner, "powerBar", applyBarTextures, UF.powerColorValues, UF.powerColorOrder) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "powerBar", applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Power Bar",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHidden = v and true or false; applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner) buildTextTab(tabInner, "textPowerPercent", applyPowerText, "LEFT") end,
                    valueText = function(cf, tabInner) buildTextTab(tabInner, "textPowerValue", applyPowerText, "RIGHT") end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Name & Level Text
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Name & Level Text",
        componentId = COMPONENT_ID,
        sectionKey = "nameLevelText",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "backdrop", label = "Backdrop" },
                    { key = "border", label = "Border" },
                    { key = "nameText", label = "Name Text" },
                    { key = "levelText", label = "Level Text" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "nameLevelText_tabs",
                buildContent = {
                    backdrop = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Backdrop",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropEnabled = not not v; applyNameLevelText() end end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropTexture or "" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropTexture = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({ label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropBorderEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderEnabled = not not v; applyNameLevelText() end end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropBorderStyle or "square" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderStyle = v or "square"; applyNameLevelText() end end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropBorderTintEnable end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderTintEnable = not not v; applyNameLevelText() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.nameBackdropBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropBorderTintColor = {r,g,b,a}; applyNameLevelText() end end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.2, precision = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderThickness) or 1 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderThickness = tonumber(v) or 1; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Border Inset", min = -4, max = 4, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderInset) or 0 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderInset = tonumber(v) or 0; applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable Name Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameTextHidden = v and true or false; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Name Container Width", min = 80, max = 150, step = 5,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return tonumber(s.containerWidthPct) or 100 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.containerWidthPct = tonumber(v) or 100; applyNameLevelText() end end })
                        tabInner:AddFontSelector({ label = "Name Text Font",
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.fontFace = v; applyNameLevelText() end end })
                        tabInner:AddSelector({ label = "Name Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.style = v; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Name Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end })
                        tabInner:AddSelectorColorPicker({ label = "Name Text Color",
                            values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = ensureNameLevelDB("textName") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textName"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSelector({ label = "Name Text Alignment", values = UF.alignmentValues, order = UF.alignmentOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.alignment or "LEFT" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.alignment = v or "LEFT"; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Name Text Offset X", min = -100, max = 100, step = 1,
                            get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Name Text Offset Y", min = -100, max = 100, step = 1,
                            get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                    levelText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable Level Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.levelTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.levelTextHidden = v and true or false; applyNameLevelText() end end })
                        tabInner:AddFontSelector({ label = "Level Text Font",
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.fontFace = v; applyNameLevelText() end end })
                        tabInner:AddSelector({ label = "Level Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.style = v; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Level Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end })
                        tabInner:AddSelectorColorPicker({ label = "Level Text Color", values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = ensureNameLevelDB("textLevel") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textLevel"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSlider({ label = "Level Text Offset X", min = -100, max = 100, step = 1,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Level Text Offset Y", min = -100, max = 100, step = 1,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Portrait (Focus has 5 tabs - no Personal Text)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "positioning", label = "Positioning" },
                    { key = "sizing", label = "Sizing" },
                    { key = "mask", label = "Mask" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSlider({ label = "X Offset", min = -100, max = 100, step = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.offsetX) or 0 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.offsetX = tonumber(v) or 0; applyPortrait() end end })
                        tabInner:AddSlider({ label = "Y Offset", min = -100, max = 100, step = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.offsetY) or 0 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.offsetY = tonumber(v) or 0; applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Portrait Size (Scale)", min = 50, max = 200, step = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.scale) or 100 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.scale = tonumber(v) or 100; applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Portrait Zoom", min = 100, max = 200, step = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.zoom) or 100 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.zoom = tonumber(v) or 100; applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Use Custom Border",
                            get = function() local t = ensurePortraitDB() or {}; return t.portraitBorderEnable == true end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderEnable = (v == true); applyPortrait() end end })
                        local targetBorderValues = { texture_c = "Circle", texture_s = "Circle with Corner", rare_c = "Rare (Circle)", rare_s = "Rare (Square)" }
                        local targetBorderOrder = { "texture_c", "texture_s", "rare_c", "rare_s" }
                        tabInner:AddSelector({ label = "Border Style", values = targetBorderValues, order = targetBorderOrder,
                            get = function() local t = ensurePortraitDB() or {}; return t.portraitBorderStyle or "texture_c" end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderStyle = v or "texture_c"; applyPortrait() end end })
                        tabInner:AddSlider({ label = "Border Inset", min = 1, max = 8, step = 0.2, precision = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.portraitBorderThickness) or 1 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderThickness = tonumber(v) or 1; applyPortrait() end end })
                        tabInner:AddSelectorColorPicker({ label = "Border Color", values = UF.portraitBorderColorValues, order = UF.portraitBorderColorOrder,
                            get = function() local t = ensurePortraitDB() or {}; return t.portraitBorderColorMode or "texture" end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderColorMode = v or "texture"; applyPortrait() end end,
                            getColor = function() local t = ensurePortraitDB() or {}; local c = t.portraitBorderTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensurePortraitDB(); if t then t.portraitBorderTint = {r,g,b,a}; applyPortrait() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Portrait",
                            get = function() local t = ensurePortraitDB() or {}; return not not t.hidden end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.hidden = v and true or false; applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Cast Bar (7 tabs for Focus - no Cast Time)
    --------------------------------------------------------------------------------

    local castBarTabs = UF.getCastBarTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = COMPONENT_ID,
        sectionKey = "castBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = castBarTabs,
                componentId = COMPONENT_ID,
                sectionKey = "castBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSlider({ label = "X Offset", min = -200, max = 200, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarOffsetX) or 0 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarOffsetX = tonumber(v) or 0; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Y Offset", min = -200, max = 200, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarOffsetY) or 0 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarOffsetY = tonumber(v) or 0; applyCastBar() end end })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Width", min = 50, max = 400, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarWidth) or 195 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarWidth = tonumber(v) or 195; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Height", min = 5, max = 50, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarHeight) or 13 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarHeight = tonumber(v) or 13; applyCastBar() end end })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddBarTextureSelector({ label = "Foreground Texture",
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarTexture or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarTexture = v or "default"; applyCastBar() end end })
                        tabInner:AddSelectorColorPicker({ label = "Foreground Color", values = UF.healthColorValues, order = UF.healthColorOrder,
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({ label = "Background Texture",
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarBackgroundTexture or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundTexture = v or "default"; applyCastBar() end end })
                        tabInner:AddSelectorColorPicker({ label = "Background Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarBackgroundColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarBackgroundTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSlider({ label = "Background Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarBackgroundOpacity) or 50 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundOpacity = tonumber(v) or 50; applyCastBar() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Enable Border",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarBorderEnable end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderEnable = not not v; applyCastBar() end end })
                        local borderValues, borderOrder = UF.buildBarBorderOptions()
                        tabInner:AddSelector({ label = "Border Style", values = borderValues, order = borderOrder,
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarBorderStyle or "square" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderStyle = v or "square"; applyCastBar() end end })
                        tabInner:AddToggleColorPicker({ label = "Border Tint",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarBorderTintEnable end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderTintEnable = not not v; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarBorderTintColor = {r,g,b,a}; applyCastBar() end end,
                            hasAlpha = true })
                        tabInner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.2, precision = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarBorderThickness) or 1 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderThickness = tonumber(v) or 1; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Border Inset", min = -4, max = 4, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarBorderInset) or 0 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderInset = tonumber(v) or 0; applyCastBar() end end })
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Icon",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarIconHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconHidden = v and true or false; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Icon Size", min = 10, max = 64, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarIconSize) or 24 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconSize = tonumber(v) or 24; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Icon X Offset", min = -100, max = 100, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarIconOffsetX) or 0 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconOffsetX = tonumber(v) or 0; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Icon Y Offset", min = -100, max = 100, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarIconOffsetY) or 0 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconOffsetY = tonumber(v) or 0; applyCastBar() end end })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Spell Name",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarSpellNameHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSpellNameHidden = v and true or false; applyCastBar() end end })
                        tabInner:AddFontSelector({ label = "Spell Name Font",
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellName or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellName = t.spellName or {}; t.spellName.fontFace = v; applyCastBar() end end })
                        tabInner:AddSelector({ label = "Spell Name Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellName or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellName = t.spellName or {}; t.spellName.style = v; applyCastBar() end end })
                        tabInner:AddSlider({ label = "Spell Name Size", min = 6, max = 32, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellName or {}; return tonumber(s.size) or 12 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellName = t.spellName or {}; t.spellName.size = tonumber(v) or 12; applyCastBar() end end })
                        tabInner:AddColorPicker({ label = "Spell Name Color",
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellName or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            set = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.spellName = t.spellName or {}; t.spellName.color = {r,g,b,a}; applyCastBar() end end,
                            hasAlpha = true })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Cast Bar",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarHidden = v and true or false; applyCastBar() end end })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Misc (Focus-specific: Hide Threat Meter) - ALWAYS LAST
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Misc",
        componentId = COMPONENT_ID,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Threat Meter",
                get = function() local t = ensureUFDB() or {}; return not not t.hideThreatMeter end,
                set = function(v) local t = ensureUFDB(); if t then t.hideThreatMeter = v and true or false; applyStyles() end end,
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

return UF.RenderFocus
