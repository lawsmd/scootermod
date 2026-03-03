-- classauras/shaman.lua - Shaman class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

CA.RegisterAuras("SHAMAN", {
    {
        id = "flameShock",
        label = "Flame Shock",
        auraSpellId = 188389,       -- Flame Shock debuff
        cdmSpellId = 470411,        -- CDM base spell ID (linked: 188389 Flame Shock, override: 470057 Voltaic Blaze)
        cdmBorrow = true,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        enableLabel = "Enable Flame Shock Duration Tracker",
        enableDescription = "Show your target's Flame Shock duration as a dedicated, customizable aura.",
        editModeName = "Flame Shock",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 1.0, 0.5, 0.0, 1.0 },  -- orange
        linkedSpellIds = { 196840 },  -- Frost Shock debuff (CDM links it to same slot via linkedSpellIDs)
        spellOverrides = {
            [196840] = {  -- Frost Shock visual overrides
                overrideSpellId = 196840,
                customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelSnowflake",
                barColor = { 0.4, 0.7, 1.0, 1.0 },   -- frost blue
                textColor = { 0.4, 0.7, 1.0, 1.0 },   -- frost blue
            },
        },
        elements = {
            { type = "text",    key = "duration", source = "duration", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",     customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelFlame", defaultSize = { 32, 32 } },
            { type = "bar",     key = "durationBar", source = "duration", fillMode = "deplete", defaultSize = { 120, 12 } },
        },
        settings = {
            enabled         = { type = "addon", default = false },
            scale           = { type = "addon", default = 100 },
            mode            = { type = "addon", default = "icon" },
            iconMode        = { type = "addon", default = "default" },
            textFont        = { type = "addon", default = "FRIZQT__" },
            textStyle       = { type = "addon", default = "OUTLINE" },
            textSize        = { type = "addon", default = 24 },
            textColor       = { type = "addon", default = { 1.0, 0.5, 0.0, 1.0 } },
            textPosition    = { type = "addon", default = "inside" },
            textOuterAnchor = { type = "addon", default = "RIGHT" },
            textInnerAnchor = { type = "addon", default = "CENTER" },
            hideFromCDM     = { type = "addon", default = true },
            hideText        = { type = "addon", default = false },
            textOffsetX     = { type = "addon", default = 0 },
            textOffsetY     = { type = "addon", default = 0 },
            iconShape       = { type = "addon", default = 0 },
            borderStyle     = { type = "addon", default = "none" },
            borderThickness = { type = "addon", default = 1 },
            borderInsetH    = { type = "addon", default = 0 },
            borderInsetV    = { type = "addon", default = 0 },
            borderTintEnable = { type = "addon", default = false },
            borderTintColor  = { type = "addon", default = { 1, 1, 1, 1 } },
            barWidth                = { type = "addon", default = 120 },
            barHeight               = { type = "addon", default = 12 },
            barForegroundTexture    = { type = "addon", default = "bevelled" },
            barForegroundColorMode  = { type = "addon", default = "custom" },
            barForegroundTint       = { type = "addon", default = { 1.0, 0.5, 0.0, 1.0 } },
            barBackgroundTexture    = { type = "addon", default = "bevelled" },
            barBackgroundColorMode  = { type = "addon", default = "custom" },
            barBackgroundTint       = { type = "addon", default = { 0, 0, 0, 1 } },
            barBackgroundOpacity    = { type = "addon", default = 50 },
            barBorderStyle          = { type = "addon", default = "none" },
            barBorderThickness      = { type = "addon", default = 1 },
            barBorderInsetH         = { type = "addon", default = 0 },
            barBorderInsetV         = { type = "addon", default = 0 },
            barBorderTintEnable     = { type = "addon", default = false },
            barBorderTintColor      = { type = "addon", default = { 1, 1, 1, 1 } },
            barPosition             = { type = "addon", default = "RIGHT" },
            barOffsetX              = { type = "addon", default = 0 },
            barOffsetY              = { type = "addon", default = 0 },
        },
    },
})
