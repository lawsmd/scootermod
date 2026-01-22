-- BossRenderer.lua - Boss Unit Frames TUI renderer
-- Boss frames have special implementation with conditional settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufBoss"
local UNIT_KEY = "Boss"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureUFDB()
    return UF.ensureUFDB(UNIT_KEY)
end

local function ensureTextDB(key)
    return UF.ensureTextDB(UNIT_KEY, key)
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyBarTextures()
    UF.applyBarTextures(UNIT_KEY)
end

local function applyStyles()
    UF.applyStyles()
end

--------------------------------------------------------------------------------
-- Shared Tab Builders
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
    local borderValues, borderOrder = UF.buildBarBorderOptions()

    inner:AddSelector({
        label = "Border Style",
        values = borderValues, order = borderOrder,
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

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderBoss(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderBoss(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
    --------------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function() local t = ensureUFDB() or {}; return not not t.useCustomBorders end,
        set = function(v) local t = ensureUFDB(); if t then t.useCustomBorders = not not v; applyBarTextures() end end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    builder:AddSlider({
        label = "Scale",
        description = "Overall scale of boss frames.",
        min = 0.5, max = 2.0, step = 0.05, precision = 2,
        get = function() local t = ensureUFDB() or {}; return tonumber(t.scale) or 1.0 end,
        set = function(v) local t = ensureUFDB(); if t then t.scale = tonumber(v) or 1.0; applyStyles() end end,
        minLabel = "0.5x", maxLabel = "2.0x",
    })

    --------------------------------------------------------------------------------
    -- Health Bar (Style, Border tabs)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "healthBar", applyBarTextures) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "healthBar", applyBarTextures) end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Power Bar (Style, Border, Visibility tabs)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Power Bar",
        componentId = COMPONENT_ID,
        sectionKey = "powerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "powerBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "powerBar", applyBarTextures, UF.powerColorValues, UF.powerColorOrder) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "powerBar", applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHidden = v and true or false; applyBarTextures() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Cast Bar
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = COMPONENT_ID,
        sectionKey = "castBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "castBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "castBar", applyBarTextures) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "castBar", applyBarTextures) end,
                },
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

return UF.RenderBoss
