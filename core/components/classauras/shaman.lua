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
        settings = CA.DefaultSettings({
            textColor = { 1.0, 0.5, 0.0, 1.0 },
            barForegroundTint = { 1.0, 0.5, 0.0, 1.0 },
        }),
    },
})
