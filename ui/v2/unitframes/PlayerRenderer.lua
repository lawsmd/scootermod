-- PlayerRenderer.lua - Player Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufPlayer"
local UNIT_KEY = "Player"

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

local function ensureClassResourceDB()
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t.classResource = t.classResource or {}
    return t.classResource
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

local function applyPortrait()
    UF.applyPortrait(UNIT_KEY)
end

local function applyCastBar()
    UF.applyCastBar(UNIT_KEY)
end

local function applyScaleMult()
    UF.applyScaleMult(UNIT_KEY)
end

local function applyVisibility()
    UF.applyVisibility(UNIT_KEY)
end

local function applyStyles()
    UF.applyStyles()
end

local function applyClassResource()
    if addon and addon.ApplyUnitFrameClassResource then
        addon.ApplyUnitFrameClassResource()
    elseif addon and addon.ApplyStyles then
        addon:ApplyStyles()
    end
end

local function applyNameLevelText()
    if addon and addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(UNIT_KEY)
    end
    UF.applyStyles()
end

--------------------------------------------------------------------------------
-- Shared Tab Builder Helpers
--------------------------------------------------------------------------------

-- These mirror the Pet renderer but may have Player-specific variations

local function buildStyleTab(inner, barPrefix, applyFn, colorValues, colorOrder, colorInfoIcons)
    colorValues = colorValues or UF.healthColorValues
    colorOrder = colorOrder or UF.healthColorOrder
    colorInfoIcons = colorInfoIcons or UF.healthColorInfoIcons

    -- Foreground Texture
    inner:AddBarTextureSelector({
        label = "Foreground Texture",
        get = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "Texture"] or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "Texture"] = v or "default"
            applyFn()
        end,
    })

    -- Foreground Color
    inner:AddSelectorColorPicker({
        label = "Foreground Color",
        values = colorValues,
        order = colorOrder,
        optionInfoIcons = colorInfoIcons,
        get = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "ColorMode"] or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "ColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t[barPrefix .. "Tint"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "Tint"] = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    inner:AddSpacer(8)

    -- Background Texture
    inner:AddBarTextureSelector({
        label = "Background Texture",
        get = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "BackgroundTexture"] or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundTexture"] = v or "default"
            applyFn()
        end,
    })

    -- Background Color
    inner:AddSelectorColorPicker({
        label = "Background Color",
        values = UF.bgColorValues,
        order = UF.bgColorOrder,
        get = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "BackgroundColorMode"] or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t[barPrefix .. "BackgroundTint"] or {0, 0, 0, 1}
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundTint"] = {r or 0, g or 0, b or 0, a or 1}
            applyFn()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    -- Background Opacity
    inner:AddSlider({
        label = "Background Opacity",
        min = 0,
        max = 100,
        step = 1,
        get = function()
            local t = ensureUFDB() or {}
            return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50
            applyFn()
        end,
    })

    inner:Finalize()
end

local function buildBorderTab(inner, barPrefix, applyFn)
    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "BorderStyle"] or "square"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderStyle"] = v or "square"
            applyFn()
        end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function()
            local t = ensureUFDB() or {}
            return not not t[barPrefix .. "BorderTintEnable"]
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderTintEnable"] = not not v
            applyFn()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t[barPrefix .. "BorderTintColor"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderTintColor"] = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        hasAlpha = true,
    })

    inner:AddSlider({
        label = "Border Thickness",
        min = 1,
        max = 8,
        step = 0.5,
        precision = 1,
        get = function()
            local t = ensureUFDB() or {}
            local v = tonumber(t[barPrefix .. "BorderThickness"]) or 1
            return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderThickness"] = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
            applyFn()
        end,
    })

    inner:AddSlider({
        label = "Border Inset",
        min = -4,
        max = 4,
        step = 1,
        get = function()
            local t = ensureUFDB() or {}
            return tonumber(t[barPrefix .. "BorderInset"]) or 0
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderInset"] = tonumber(v) or 0
            applyFn()
        end,
    })

    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn, defaultAlignment, colorValues, colorOrder)
    defaultAlignment = defaultAlignment or "LEFT"
    colorValues = colorValues or UF.fontColorValues
    colorOrder = colorOrder or UF.fontColorOrder
    local hiddenKey = textKey:gsub("text", ""):lower() .. "Hidden"

    -- Disable toggle
    inner:AddToggle({
        label = "Disable Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t[hiddenKey]
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[hiddenKey] = v and true or false
            applyFn()
        end,
    })

    -- Font
    inner:AddFontSelector({
        label = "Font",
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].fontFace = v
            applyStyles()
        end,
    })

    -- Style
    inner:AddSelector({
        label = "Style",
        values = UF.fontStyleValues,
        order = UF.fontStyleOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].style = v
            applyStyles()
        end,
    })

    -- Size
    inner:AddSlider({
        label = "Size",
        min = 6,
        max = 48,
        step = 1,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return tonumber(s.size) or 14
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].size = tonumber(v) or 14
            applyStyles()
        end,
    })

    -- Color
    inner:AddSelectorColorPicker({
        label = "Color",
        values = colorValues,
        order = colorOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].colorMode = v or "default"
            applyStyles()
        end,
        getColor = function()
            local s = ensureTextDB(textKey) or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].color = {r or 1, g or 1, b or 1, a or 1}
            applyStyles()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    -- Alignment
    inner:AddSelector({
        label = "Alignment",
        values = UF.alignmentValues,
        order = UF.alignmentOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.alignment or defaultAlignment
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].alignment = v or defaultAlignment
            applyStyles()
        end,
    })

    inner:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.x) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.x = tonumber(v) or 0
                applyStyles()
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.y) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.y = tonumber(v) or 0
                applyStyles()
            end,
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Health Bar Visibility Tab (Player only)
--------------------------------------------------------------------------------

local function buildHealthVisibilityTab(inner)
    inner:AddToggle({
        label = "Hide the Bar but not its Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideTextureOnly
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideTextureOnly = v and true or false
            applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Hide the Bar but not its Text",
            tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your health.",
        },
    })

    inner:AddToggle({
        label = "Hide Over Absorb Glow",
        description = "Hides the glow effect when absorb shields exceed max health.",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideOverAbsorbGlow
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideOverAbsorbGlow = v and true or false
            applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideOverAbsorbGlow,
    })

    inner:AddToggle({
        label = "Hide Heal Prediction",
        description = "Hides the green heal prediction bar when healing is incoming.",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideHealPrediction
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideHealPrediction = v and true or false
            applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Hide Heal Prediction",
            tooltipText = "Hides the green heal prediction bar that appears on your health bar when you or a party member is casting a heal on you.",
        },
    })

    inner:AddToggle({
        label = "Hide Health Loss Animation",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideHealthLossAnimation
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideHealthLossAnimation = v and true or false
            applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Health Loss Animation",
            tooltipText = "The dark red bar that appears briefly when you take damage, showing the amount of health lost. Hide this to remove the damage flash effect.",
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderPlayer(panel, scrollContent)
    -- Clear existing content
    panel:ClearContent()

    -- Create builder
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference for re-rendering on changes
    builder:SetOnRefresh(function()
        UF.RenderPlayer(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
    --------------------------------------------------------------------------------

    -- Hide Blizzard Frame Art (emphasized master toggle)
    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function()
            local t = ensureUFDB() or {}
            return not not t.useCustomBorders
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            local wasEnabled = t.useCustomBorders
            t.useCustomBorders = not not v
            if not v then
                t.healthBarHideBorder = false
                if wasEnabled then
                    t.powerBarHeightPct = 100
                end
            end
            applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    -- Frame Size (Edit Mode scale)
    builder:AddSlider({
        label = "Frame Size (Scale)",
        description = "Blizzard's Edit Mode scale (100-200%).",
        min = 100,
        max = 200,
        step = 5,
        get = function()
            return UF.getEditModeFrameSize(COMPONENT_ID)
        end,
        set = function(v)
            UF.setEditModeFrameSize(COMPONENT_ID, v)
        end,
        minLabel = "100%",
        maxLabel = "200%",
        infoIcon = UF.TOOLTIPS.frameSize,
    })

    -- Scale Multiplier (addon-only)
    builder:AddSlider({
        label = "Scale Multiplier",
        description = "Addon multiplier on top of Edit Mode scale.",
        min = 1.0,
        max = 2.0,
        step = 0.05,
        precision = 2,
        get = function()
            local t = ensureUFDB() or {}
            return tonumber(t.scaleMult) or 1.0
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.scaleMult = tonumber(v) or 1.0
            applyScaleMult()
        end,
        minLabel = "1.0x",
        maxLabel = "2.0x",
        infoIcon = UF.TOOLTIPS.scaleMult,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Health Bar (5 tabs for Player)
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
                            min = 10,
                            max = 100,
                            step = 5,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.healthBarOverlayHeightPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.healthBarOverlayHeightPct = tonumber(v) or 100
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Health Bar Height",
                                tooltipText = "Reduces the visible height of the health bar. The bar fill still tracks health correctly, but is cropped to this percentage of its normal height (centered vertically).",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        buildStyleTab(tabInner, "healthBar", applyBarTextures)
                    end,
                    border = function(cf, tabInner)
                        buildBorderTab(tabInner, "healthBar", applyBarTextures)
                    end,
                    visibility = function(cf, tabInner)
                        buildHealthVisibilityTab(tabInner)
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthPercent", applyHealthText, "LEFT")
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthValue", applyHealthText, "RIGHT")
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Power Bar (7 tabs)
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
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureUFDB() or {}
                                    return tonumber(t.powerBarOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensureUFDB()
                                    if not t then return end
                                    t.powerBarOffsetX = tonumber(v) or 0
                                    applyBarTextures()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureUFDB() or {}
                                    return tonumber(t.powerBarOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensureUFDB()
                                    if not t then return end
                                    t.powerBarOffsetY = tonumber(v) or 0
                                    applyBarTextures()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10,
                            max = 200,
                            step = 5,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.powerBarHeightPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHeightPct = tonumber(v) or 100
                                applyBarTextures()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        buildStyleTab(tabInner, "powerBar", applyBarTextures, UF.powerColorValues, UF.powerColorOrder)
                    end,
                    border = function(cf, tabInner)
                        buildBorderTab(tabInner, "powerBar", applyBarTextures)
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHidden
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHidden = v and true or false
                                applyBarTextures()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideTextureOnly
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideTextureOnly = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide the Bar but not its Text",
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your power resource.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Full Bar Animations",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideFullSpikes
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideFullSpikes = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Full Bar Animations",
                                tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Power Feedback",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideFeedback
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideFeedback = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Feedback",
                                tooltipText = "Disables the flash animation that plays when you spend or gain power (energy, mana, rage, etc.). This animation shows a quick highlight on the portion of the bar that changed.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Power Bar Spark",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideSpark
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideSpark = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Bar Spark",
                                tooltipText = "Hides the spark/glow indicator that appears at the current power level on certain classes (e.g., Elemental Shaman).",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Mana Cost Predictions",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideManaCostPrediction
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideManaCostPrediction = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Mana Cost Predictions",
                                tooltipText = "Hides the mana/power cost prediction overlay that appears on the power bar when casting a spell. This blue overlay shows how much power will be consumed by the current cast.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerPercent", applyPowerText, "LEFT", UF.fontColorPowerValues, UF.fontColorPowerOrder)
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerValue", applyPowerText, "RIGHT", UF.fontColorPowerValues, UF.fontColorPowerOrder)
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Alternate Power Bar (Player only - conditional)
    --------------------------------------------------------------------------------
    -- Only shown for specs that have an alternate power bar (e.g., Elemental Shaman, Shadow Priest, Brewmaster Monk)

    if addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then

        -- Helper to access the nested altPowerBar config
        local function ensureAltPowerBarDB()
            local t = ensureUFDB()
            if not t then return nil end
            if not t.altPowerBar then
                t.altPowerBar = {}
            end
            return t.altPowerBar
        end

        -- Helper for nested text config
        local function ensureAltPowerTextDB(textKey)
            local apb = ensureAltPowerBarDB()
            if not apb then return nil end
            if not apb[textKey] then
                apb[textKey] = {}
            end
            return apb[textKey]
        end

        local altPowerTabs = {
            { key = "positioning", label = "Positioning" },
            { key = "sizing", label = "Sizing" },
            { key = "style", label = "Style" },
            { key = "border", label = "Border" },
            { key = "visibility", label = "Visibility" },
            { key = "percentText", label = "% Text" },
            { key = "valueText", label = "Value Text" },
        }

        builder:AddCollapsibleSection({
            title = "Alternate Power Bar",
            componentId = COMPONENT_ID,
            sectionKey = "altPowerBar",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddTabbedSection({
                    tabs = altPowerTabs,
                    componentId = COMPONENT_ID,
                    sectionKey = "altPowerBar_tabs",
                    buildContent = {
                        positioning = function(cf, tabInner)
                            tabInner:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -150, max = 150, step = 1,
                                    get = function()
                                        local apb = ensureAltPowerBarDB() or {}
                                        return tonumber(apb.offsetX) or 0
                                    end,
                                    set = function(v)
                                        local apb = ensureAltPowerBarDB()
                                        if not apb then return end
                                        apb.offsetX = tonumber(v) or 0
                                        applyBarTextures()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -150, max = 150, step = 1,
                                    get = function()
                                        local apb = ensureAltPowerBarDB() or {}
                                        return tonumber(apb.offsetY) or 0
                                    end,
                                    set = function(v)
                                        local apb = ensureAltPowerBarDB()
                                        if not apb then return end
                                        apb.offsetY = tonumber(v) or 0
                                        applyBarTextures()
                                    end,
                                },
                            })
                            tabInner:Finalize()
                        end,
                        sizing = function(cf, tabInner)
                            tabInner:AddSlider({
                                label = "Width %",
                                min = 10, max = 150, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.widthPct) or 100
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.widthPct = tonumber(v) or 100
                                    applyBarTextures()
                                end,
                            })
                            tabInner:Finalize()
                        end,
                        style = function(cf, tabInner)
                            -- Foreground Texture
                            tabInner:AddBarTextureSelector({
                                label = "Foreground Texture",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.texture or "default"
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.texture = v or "default"
                                    applyBarTextures()
                                end,
                            })

                            -- Foreground Color
                            tabInner:AddSelectorColorPicker({
                                label = "Foreground Color",
                                values = UF.healthColorValues,
                                order = UF.healthColorOrder,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.colorMode or "default"
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.colorMode = v or "default"
                                    applyBarTextures()
                                end,
                                getColor = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    local c = apb.tint or {1, 1, 1, 1}
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.tint = {r or 1, g or 1, b or 1, a or 1}
                                    applyBarTextures()
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            tabInner:AddSpacer(8)

                            -- Background Texture
                            tabInner:AddBarTextureSelector({
                                label = "Background Texture",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.backgroundTexture or "default"
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.backgroundTexture = v or "default"
                                    applyBarTextures()
                                end,
                            })

                            -- Background Color
                            tabInner:AddSelectorColorPicker({
                                label = "Background Color",
                                values = UF.bgColorValues,
                                order = UF.bgColorOrder,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.backgroundColorMode or "default"
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.backgroundColorMode = v or "default"
                                    applyBarTextures()
                                end,
                                getColor = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    local c = apb.backgroundTint or {0, 0, 0, 1}
                                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.backgroundTint = {r or 0, g or 0, b or 0, a or 1}
                                    applyBarTextures()
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            -- Background Opacity
                            tabInner:AddSlider({
                                label = "Background Opacity",
                                min = 0, max = 100, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.backgroundOpacity) or 50
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.backgroundOpacity = tonumber(v) or 50
                                    applyBarTextures()
                                end,
                            })

                            tabInner:Finalize()
                        end,
                        border = function(cf, tabInner)
                            tabInner:AddBarBorderSelector({
                                label = "Border Style",
                                includeNone = true,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.borderStyle or "square"
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderStyle = v or "square"
                                    applyBarTextures()
                                end,
                            })

                            tabInner:AddToggleColorPicker({
                                label = "Border Tint",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return not not apb.borderTintEnable
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderTintEnable = not not v
                                    applyBarTextures()
                                end,
                                getColor = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    local c = apb.borderTintColor or {1, 1, 1, 1}
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderTintColor = {r or 1, g or 1, b or 1, a or 1}
                                    applyBarTextures()
                                end,
                                hasAlpha = true,
                            })

                            tabInner:AddSlider({
                                label = "Border Thickness",
                                min = 1, max = 8, step = 0.5, precision = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    local v = tonumber(apb.borderThickness) or 1
                                    return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                    applyBarTextures()
                                end,
                            })

                            tabInner:AddSlider({
                                label = "Border Inset",
                                min = -4, max = 4, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.borderInset) or 0
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderInset = tonumber(v) or 0
                                    applyBarTextures()
                                end,
                            })

                            tabInner:Finalize()
                        end,
                        visibility = function(cf, tabInner)
                            tabInner:AddToggle({
                                label = "Hide Alternate Power Bar",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.hidden == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.hidden = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Hide Alternate Power Bar",
                                    tooltipText = "Completely hides the alternate power bar (e.g., Maelstrom for Elemental Shaman, Insanity for Shadow Priest, Stagger for Brewmaster).",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide the Bar but not its Text",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.hideTextureOnly == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.hideTextureOnly = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Hide the Bar but not its Text",
                                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your alternate power resource.",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide Full Bar Animations",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.hideFullSpikes == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.hideFullSpikes = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Full Bar Animations",
                                    tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent.",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide Power Feedback",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.hideFeedback == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.hideFeedback = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Power Feedback",
                                    tooltipText = "Disables the flash animation that plays when you spend or gain alternate power. This animation shows a quick highlight on the portion of the bar that changed.",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide APB Spark",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.hideSpark == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.hideSpark = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "APB Spark",
                                    tooltipText = "Hides the spark/glow indicator that appears at the current power level on the alternate power bar.",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide Mana Cost Predictions",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.hideManaCostPrediction == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.hideManaCostPrediction = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Mana Cost Predictions",
                                    tooltipText = "Hides the power cost prediction overlay that appears on the alternate power bar when casting a spell.",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide Percent Text",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.percentHidden == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.percentHidden = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Hide Percent Text",
                                    tooltipText = "Hides the percentage text overlay on the alternate power bar.",
                                },
                            })

                            tabInner:AddToggle({
                                label = "Hide Value Text",
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return apb.valueHidden == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.valueHidden = (v == true)
                                    applyBarTextures()
                                end,
                                infoIcon = {
                                    tooltipTitle = "Hide Value Text",
                                    tooltipText = "Hides the numeric value text overlay on the alternate power bar.",
                                },
                            })

                            tabInner:Finalize()
                        end,
                        percentText = function(cf, tabInner)
                            -- Font
                            tabInner:AddFontSelector({
                                label = "Font",
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    return s.fontFace or "FRIZQT__"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.fontFace = v
                                    applyBarTextures()
                                end,
                            })

                            -- Style
                            tabInner:AddSelector({
                                label = "Style",
                                values = UF.fontStyleValues,
                                order = UF.fontStyleOrder,
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    return s.style or "OUTLINE"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.style = v
                                    applyBarTextures()
                                end,
                            })

                            -- Size
                            tabInner:AddSlider({
                                label = "Size",
                                min = 6, max = 48, step = 1,
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    return tonumber(s.size) or 14
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.size = tonumber(v) or 14
                                    applyBarTextures()
                                end,
                            })

                            -- Color
                            tabInner:AddSelectorColorPicker({
                                label = "Color",
                                values = UF.fontColorPowerValues,
                                order = UF.fontColorPowerOrder,
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    return s.colorMode or "default"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.colorMode = v or "default"
                                    applyBarTextures()
                                end,
                                getColor = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    local c = s.color or {1, 1, 1, 1}
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.color = {r or 1, g or 1, b or 1, a or 1}
                                    applyBarTextures()
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            -- Alignment
                            tabInner:AddSelector({
                                label = "Alignment",
                                values = UF.alignmentValues,
                                order = UF.alignmentOrder,
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    return s.alignment or "LEFT"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.alignment = v or "LEFT"
                                    applyBarTextures()
                                end,
                            })

                            tabInner:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local s = ensureAltPowerTextDB("textPercent") or {}
                                        local o = s.offset or {}
                                        return tonumber(o.x) or 0
                                    end,
                                    set = function(v)
                                        local s = ensureAltPowerTextDB("textPercent")
                                        if not s then return end
                                        s.offset = s.offset or {}
                                        s.offset.x = tonumber(v) or 0
                                        applyBarTextures()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local s = ensureAltPowerTextDB("textPercent") or {}
                                        local o = s.offset or {}
                                        return tonumber(o.y) or 0
                                    end,
                                    set = function(v)
                                        local s = ensureAltPowerTextDB("textPercent")
                                        if not s then return end
                                        s.offset = s.offset or {}
                                        s.offset.y = tonumber(v) or 0
                                        applyBarTextures()
                                    end,
                                },
                            })

                            tabInner:Finalize()
                        end,
                        valueText = function(cf, tabInner)
                            -- Font
                            tabInner:AddFontSelector({
                                label = "Font",
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    return s.fontFace or "FRIZQT__"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.fontFace = v
                                    applyBarTextures()
                                end,
                            })

                            -- Style
                            tabInner:AddSelector({
                                label = "Style",
                                values = UF.fontStyleValues,
                                order = UF.fontStyleOrder,
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    return s.style or "OUTLINE"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.style = v
                                    applyBarTextures()
                                end,
                            })

                            -- Size
                            tabInner:AddSlider({
                                label = "Size",
                                min = 6, max = 48, step = 1,
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    return tonumber(s.size) or 14
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.size = tonumber(v) or 14
                                    applyBarTextures()
                                end,
                            })

                            -- Color
                            tabInner:AddSelectorColorPicker({
                                label = "Color",
                                values = UF.fontColorPowerValues,
                                order = UF.fontColorPowerOrder,
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    return s.colorMode or "default"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.colorMode = v or "default"
                                    applyBarTextures()
                                end,
                                getColor = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    local c = s.color or {1, 1, 1, 1}
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.color = {r or 1, g or 1, b or 1, a or 1}
                                    applyBarTextures()
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            -- Alignment
                            tabInner:AddSelector({
                                label = "Alignment",
                                values = UF.alignmentValues,
                                order = UF.alignmentOrder,
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    return s.alignment or "RIGHT"
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.alignment = v or "RIGHT"
                                    applyBarTextures()
                                end,
                            })

                            tabInner:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local s = ensureAltPowerTextDB("textValue") or {}
                                        local o = s.offset or {}
                                        return tonumber(o.x) or 0
                                    end,
                                    set = function(v)
                                        local s = ensureAltPowerTextDB("textValue")
                                        if not s then return end
                                        s.offset = s.offset or {}
                                        s.offset.x = tonumber(v) or 0
                                        applyBarTextures()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local s = ensureAltPowerTextDB("textValue") or {}
                                        local o = s.offset or {}
                                        return tonumber(o.y) or 0
                                    end,
                                    set = function(v)
                                        local s = ensureAltPowerTextDB("textValue")
                                        if not s then return end
                                        s.offset = s.offset or {}
                                        s.offset.y = tonumber(v) or 0
                                        applyBarTextures()
                                    end,
                                },
                            })

                            tabInner:Finalize()
                        end,
                    },
                })
                inner:Finalize()
            end,
        })
    end

    --------------------------------------------------------------------------------
    -- Collapsible Section: Class Resource (Player only - dynamic title)
    --------------------------------------------------------------------------------

    local function getClassResourceTitle()
        if addon and addon.UnitFrames_GetPlayerClassResourceTitle then
            return addon.UnitFrames_GetPlayerClassResourceTitle()
        end
        return "Class Resource"
    end

    builder:AddCollapsibleSection({
        title = getClassResourceTitle(),
        componentId = COMPONENT_ID,
        sectionKey = "classResource",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "positioning", label = "Positioning" },
                    { key = "sizing", label = "Sizing" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "classResource_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -150, max = 150, step = 1,
                                get = function()
                                    local cfg = ensureClassResourceDB() or {}
                                    return tonumber(cfg.offsetX) or 0
                                end,
                                set = function(v)
                                    local cfg = ensureClassResourceDB()
                                    if not cfg then return end
                                    cfg.offsetX = tonumber(v) or 0
                                    applyClassResource()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -150, max = 150, step = 1,
                                get = function()
                                    local cfg = ensureClassResourceDB() or {}
                                    return tonumber(cfg.offsetY) or 0
                                end,
                                set = function(v)
                                    local cfg = ensureClassResourceDB()
                                    if not cfg then return end
                                    cfg.offsetY = tonumber(v) or 0
                                    applyClassResource()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = getClassResourceTitle() .. " Scale",
                            min = 50, max = 150, step = 1,
                            get = function()
                                local cfg = ensureClassResourceDB() or {}
                                return tonumber(cfg.scale) or 100
                            end,
                            set = function(v)
                                local cfg = ensureClassResourceDB()
                                if not cfg then return end
                                cfg.scale = tonumber(v) or 100
                                applyClassResource()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide " .. getClassResourceTitle(),
                            get = function()
                                local cfg = ensureClassResourceDB() or {}
                                return cfg.hide == true
                            end,
                            set = function(v)
                                local cfg = ensureClassResourceDB()
                                if not cfg then return end
                                cfg.hide = (v == true)
                                applyClassResource()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Totem Bar (conditional visibility)
    --------------------------------------------------------------------------------
    -- Only shown for classes that use TotemFrame: Shaman, Death Knight, Druid, Monk

    if addon.UnitFrames_TotemBar_ShouldShow and addon.UnitFrames_TotemBar_ShouldShow() then
        local function ensureTotemBarDB()
            local t = UF.ensureUFDB(UNIT_KEY)
            if not t then return nil end
            t.totemBar = t.totemBar or {}
            return t.totemBar
        end

        local function ensureTotemBarIconBordersDB()
            local tb = ensureTotemBarDB()
            if not tb then return nil end
            tb.iconBorders = tb.iconBorders or {}
            return tb.iconBorders
        end

        local function ensureTotemBarTimerTextDB()
            local tb = ensureTotemBarDB()
            if not tb then return nil end
            tb.timerText = tb.timerText or {}
            return tb.timerText
        end

        local function applyTotemBar()
            if addon.ApplyTotemBarStyling then
                addon.ApplyTotemBarStyling()
            end
        end

        builder:AddCollapsibleSection({
            title = "Totem Bar",
            componentId = COMPONENT_ID,
            sectionKey = "totemBar",
            defaultExpanded = false,
            infoIcon = {
                tooltipTitle = "Totem Bar",
                tooltipText = "Displays temporary summons: Shaman totems, DK ghouls/Abomination Limb, Druid Grove Guardians/Efflorescence, and Monk statues.",
            },
            buildContent = function(contentFrame, inner)
                inner:AddTabbedSection({
                    tabs = {
                        { key = "icons", label = "Icons" },
                        { key = "iconBorders", label = "Icon Borders" },
                        { key = "timerText", label = "Timer Text" },
                    },
                    componentId = COMPONENT_ID,
                    sectionKey = "totemBar_tabs",
                    buildContent = {
                        icons = function(cf, tabInner)
                            -- Placeholder for future icon styling options
                            tabInner:AddDescription("Icon styling options coming soon.")
                            tabInner:Finalize()
                        end,
                        iconBorders = function(cf, tabInner)
                            tabInner:AddToggle({
                                label = "Hide Icon Borders",
                                get = function()
                                    local cfg = ensureTotemBarIconBordersDB() or {}
                                    return cfg.hidden == true
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarIconBordersDB()
                                    if not cfg then return end
                                    cfg.hidden = (v == true)
                                    applyTotemBar()
                                end,
                            })
                            tabInner:Finalize()
                        end,
                        timerText = function(cf, tabInner)
                            tabInner:AddToggle({
                                label = "Hide Timer Text",
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    return cfg.hidden == true
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.hidden = (v == true)
                                    applyTotemBar()
                                end,
                            })
                            tabInner:AddFontSelector({
                                label = "Font Face",
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    return cfg.fontFace or "FRIZQT__"
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.fontFace = v or "FRIZQT__"
                                    applyTotemBar()
                                end,
                            })
                            tabInner:AddSlider({
                                label = "Font Size",
                                min = 6, max = 24, step = 1,
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    return tonumber(cfg.size) or 12
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.size = tonumber(v) or 12
                                    applyTotemBar()
                                end,
                            })
                            tabInner:AddSelector({
                                label = "Font Style",
                                values = UF.fontStyleValues,
                                order = UF.fontStyleOrder,
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    return cfg.style or "OUTLINE"
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.style = v or "OUTLINE"
                                    applyTotemBar()
                                end,
                            })
                            tabInner:AddColorPicker({
                                label = "Font Color",
                                hasAlpha = true,
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    local c = cfg.color or { 1, 1, 1, 1 }
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.color = { r or 1, g or 1, b or 1, a or 1 }
                                    applyTotemBar()
                                end,
                            })
                            tabInner:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local cfg = ensureTotemBarTimerTextDB() or {}
                                        local o = cfg.offset or {}
                                        return tonumber(o.x) or 0
                                    end,
                                    set = function(v)
                                        local cfg = ensureTotemBarTimerTextDB()
                                        if not cfg then return end
                                        cfg.offset = cfg.offset or {}
                                        cfg.offset.x = tonumber(v) or 0
                                        applyTotemBar()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local cfg = ensureTotemBarTimerTextDB() or {}
                                        local o = cfg.offset or {}
                                        return tonumber(o.y) or 0
                                    end,
                                    set = function(v)
                                        local cfg = ensureTotemBarTimerTextDB()
                                        if not cfg then return end
                                        cfg.offset = cfg.offset or {}
                                        cfg.offset.y = tonumber(v) or 0
                                        applyTotemBar()
                                    end,
                                },
                            })
                            tabInner:Finalize()
                        end,
                    },
                })
                inner:Finalize()
            end,
        })
    end

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
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.nameBackdropEnabled
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropEnabled = not not v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function()
                                local t = ensureUFDB() or {}
                                return t.nameBackdropTexture or ""
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropTexture = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color",
                            values = UF.bgColorValues,
                            order = UF.bgColorOrder,
                            get = function()
                                local t = ensureUFDB() or {}
                                return t.nameBackdropColorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropColorMode = v or "default"
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local t = ensureUFDB() or {}
                                local c = t.nameBackdropTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropTint = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Width (%)",
                            min = 25, max = 300, step = 1,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.nameBackdropWidthPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropWidthPct = tonumber(v) or 100
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Opacity",
                            min = 0, max = 100, step = 1,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.nameBackdropOpacity) or 50
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropOpacity = tonumber(v) or 50
                                applyNameLevelText()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.nameBackdropBorderEnabled
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderEnabled = not not v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function()
                                local t = ensureUFDB() or {}
                                return t.nameBackdropBorderStyle or "square"
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderStyle = v or "square"
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.nameBackdropBorderTintEnable
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderTintEnable = not not v
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local t = ensureUFDB() or {}
                                local c = t.nameBackdropBorderTintColor or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderTintColor = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function()
                                local t = ensureUFDB() or {}
                                local v = tonumber(t.nameBackdropBorderThickness) or 1
                                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset",
                            min = -4, max = 4, step = 1,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.nameBackdropBorderInset) or 0
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderInset = tonumber(v) or 0
                                applyNameLevelText()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Name Text",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.nameTextHidden
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameTextHidden = v and true or false
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Name Text Font",
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.fontFace = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Name Text Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.style = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Name Text Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.size = tonumber(v) or 14
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Name Text Color",
                            values = UF.fontColorValues,
                            order = UF.fontColorOrder,
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return s.colorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.colorMode = v or "default"
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local s = ensureNameLevelDB("textName") or {}
                                local c = s.color or {1, 0.82, 0, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.color = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddDualSlider({
                            label = "Name Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    levelText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Level Text",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.levelTextHidden
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.levelTextHidden = v and true or false
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Level Text Font",
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.fontFace = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Level Text Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.style = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Level Text Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.size = tonumber(v) or 14
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Level Text Color",
                            values = UF.fontColorValues,
                            order = UF.fontColorOrder,
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return s.colorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.colorMode = v or "default"
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                local c = s.color or {1, 0.82, 0, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.color = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddDualSlider({
                            label = "Level Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Portrait
    --------------------------------------------------------------------------------

    local portraitTabs = UF.getPortraitTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = portraitTabs,
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensurePortraitDB() or {}
                                    return tonumber(t.offsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensurePortraitDB()
                                    if not t then return end
                                    t.offsetX = tonumber(v) or 0
                                    applyPortrait()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensurePortraitDB() or {}
                                    return tonumber(t.offsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensurePortraitDB()
                                    if not t then return end
                                    t.offsetY = tonumber(v) or 0
                                    applyPortrait()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Size (Scale)",
                            min = 50, max = 200, step = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return tonumber(t.scale) or 100
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.scale = tonumber(v) or 100
                                applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Zoom",
                            min = 100, max = 200, step = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return tonumber(t.zoom) or 100
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.zoom = tonumber(v) or 100
                                applyPortrait()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Use Full Circle Mask",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.useFullCircleMask == true
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.useFullCircleMask = (v == true)
                                applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.portraitBorderEnable == true
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderEnable = (v == true)
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Border Style",
                            values = UF.portraitBorderValues,
                            order = UF.portraitBorderOrder,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.portraitBorderStyle or "texture_c"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderStyle = v or "texture_c"
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local v = tonumber(t.portraitBorderThickness) or 1
                                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Border Color",
                            values = UF.portraitBorderColorValues,
                            order = UF.portraitBorderColorOrder,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.portraitBorderColorMode or "texture"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderColorMode = v or "texture"
                                applyPortrait()
                            end,
                            getColor = function()
                                local t = ensurePortraitDB() or {}
                                local c = t.portraitBorderTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderTint = {r, g, b, a}
                                applyPortrait()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    personalText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Personal Text",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return not not t.personalTextHidden
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalTextHidden = v and true or false
                                applyPortrait()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Personal Text Font",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.fontFace = v
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Personal Text Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.style = v
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Personal Text Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.size = tonumber(v) or 14
                                applyPortrait()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Personal Text Color",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.color = {r, g, b, a}
                                applyPortrait()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Portrait",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return not not t.hidden
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.hidden = v and true or false
                                applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Cast Bar (8 tabs for Player)
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
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -200, max = 200, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.castBarOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.castBarOffsetX = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -200, max = 200, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.castBarOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.castBarOffsetY = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Width",
                            min = 50, max = 400, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.castBarWidth) or 195
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarWidth = tonumber(v) or 195
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Height",
                            min = 5, max = 50, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.castBarHeight) or 13
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarHeight = tonumber(v) or 13
                                applyCastBar()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddBarTextureSelector({
                            label = "Foreground Texture",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarTexture or "default"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarTexture = v or "default"
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Foreground Color",
                            values = UF.healthColorValues,
                            order = UF.healthColorOrder,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarColorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarColorMode = v or "default"
                                applyCastBar()
                            end,
                            getColor = function()
                                local t = ensureCastBarDB() or {}
                                local c = t.castBarTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarTint = {r, g, b, a}
                                applyCastBar()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({
                            label = "Background Texture",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarBackgroundTexture or "default"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBackgroundTexture = v or "default"
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Background Color",
                            values = UF.bgColorValues,
                            order = UF.bgColorOrder,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarBackgroundColorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBackgroundColorMode = v or "default"
                                applyCastBar()
                            end,
                            getColor = function()
                                local t = ensureCastBarDB() or {}
                                local c = t.castBarBackgroundTint or {0, 0, 0, 1}
                                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBackgroundTint = {r, g, b, a}
                                applyCastBar()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Background Opacity",
                            min = 0, max = 100, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.castBarBackgroundOpacity) or 50
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBackgroundOpacity = tonumber(v) or 50
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSpacer(8)
                        tabInner:AddToggle({
                            label = "Hide Spark",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarSparkHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spark Color",
                            values = { ["default"] = "Default", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarSparkColorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkColorMode = v or "default"
                                applyCastBar()
                            end,
                            getColor = function()
                                local t = ensureCastBarDB() or {}
                                local c = t.castBarSparkTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkTint = {r, g, b, a}
                                applyCastBar()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarBorderEnable
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderEnable = not not v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarBorderStyle or "square"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderStyle = v or "square"
                                applyCastBar()
                            end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarBorderTintEnable
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderTintEnable = not not v
                                applyCastBar()
                            end,
                            getColor = function()
                                local t = ensureCastBarDB() or {}
                                local c = t.castBarBorderTintColor or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderTintColor = {r, g, b, a}
                                applyCastBar()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local v = tonumber(t.castBarBorderThickness) or 1
                                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset",
                            min = -4, max = 4, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.castBarBorderInset) or 0
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderInset = tonumber(v) or 0
                                applyCastBar()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarIconHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarIconHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Size",
                            min = 10, max = 64, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.castBarIconSize) or 24
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarIconSize = tonumber(v) or 24
                                applyCastBar()
                            end,
                        })
                        tabInner:AddDualSlider({
                            label = "Icon Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.castBarIconOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.castBarIconOffsetX = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.castBarIconOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.castBarIconOffsetY = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spell Name",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarSpellNameHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSpellNameHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Spell Name Font",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellName or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellName = t.spellName or {}
                                t.spellName.fontFace = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Spell Name Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellName or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellName = t.spellName or {}
                                t.spellName.style = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Spell Name Size",
                            min = 6, max = 32, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellName or {}
                                return tonumber(s.size) or 12
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellName = t.spellName or {}
                                t.spellName.size = tonumber(v) or 12
                                applyCastBar()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Spell Name Color",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellName or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellName = t.spellName or {}
                                t.spellName.color = {r, g, b, a}
                                applyCastBar()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    castTime = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Time",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarTimeHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarTimeHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Cast Time Font",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTime or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTime = t.castTime or {}
                                t.castTime.fontFace = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Cast Time Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTime or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTime = t.castTime or {}
                                t.castTime.style = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Cast Time Size",
                            min = 6, max = 32, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTime or {}
                                return tonumber(s.size) or 12
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTime = t.castTime or {}
                                t.castTime.size = tonumber(v) or 12
                                applyCastBar()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Cast Time Color",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTime or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTime = t.castTime or {}
                                t.castTime.color = {r, g, b, a}
                                applyCastBar()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Bar",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Text Border",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.hideTextBorder
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.hideTextBorder = v and true or false
                                applyCastBar()
                            end,
                            tooltip = {
                                tooltipTitle = "Text Border",
                                tooltipText = "Hides the text border frame that appears when the cast bar is unlocked from the Player frame.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Channel Shadow",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.hideChannelingShadow
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.hideChannelingShadow = v and true or false
                                applyCastBar()
                            end,
                            tooltip = {
                                tooltipTitle = "Channel Shadow",
                                tooltipText = "Hides the shadow effect behind the cast bar during channeled spells.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Visibility (moved before Misc)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = COMPONENT_ID,
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity - Out of Combat",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityOutOfCombat) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityOutOfCombat = tonumber(v) or 100
                    applyVisibility()
                end,
                infoIcon = UF.TOOLTIPS.visibilityPriority,
            })

            inner:AddSlider({
                label = "Opacity - In Combat",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityInCombat) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityInCombat = tonumber(v) or 100
                    applyVisibility()
                end,
            })

            inner:AddSlider({
                label = "Opacity - With Target",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityWithTarget) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityWithTarget = tonumber(v) or 100
                    applyVisibility()
                end,
            })

            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Misc (Player-specific) - ALWAYS LAST
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Misc",
        componentId = COMPONENT_ID,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Role Icon",
                get = function()
                    local t = ensureUFDB() or {}
                    return not not t.hideRoleIcon
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.hideRoleIcon = v and true or false
                    applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Hide Group Number",
                get = function()
                    local t = ensureUFDB() or {}
                    return not not t.hideGroupNumber
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.hideGroupNumber = v and true or false
                    applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Allow Off-Screen Dragging",
                description = "Allows moving frames closer to screen edges.",
                get = function()
                    local t = ensureUFDB() or {}
                    return not not t.allowOffScreenDragging
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.allowOffScreenDragging = v and true or false
                    if addon.ApplyOffScreenUnlock then
                        addon.ApplyOffScreenUnlock(UNIT_KEY, v)
                    end
                end,
                infoIcon = UF.TOOLTIPS.offScreenDragging,
            })

            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Finalize
    --------------------------------------------------------------------------------

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderPlayer
