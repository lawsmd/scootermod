-- classauras/mage.lua - Mage class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

CA.RegisterAuras("MAGE", {
    {
        id = "freezing",
        label = "Freezing",
        auraSpellId = 1221389,
        cdmSpellId = 1246769,  -- Shatter passive (CDM tracks Freezing stacks under this ID)
        cdmBorrow = true,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        enableLabel = "Enable Freezing Stacks Tracker",
        enableDescription = "Show your target's Freezing stacks as a dedicated, customizable aura.",
        editModeName = "Freezing",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.68, 0.85, 1.0, 1.0 },  -- frost blue
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelSnowflake", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 20, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.68, 0.85, 1.0, 1.0 },
            barForegroundTint = { 0.68, 0.85, 1.0, 1.0 },
        }),
    },
    {
        id = "arcaneSalvo",
        label = "Arcane Salvo",
        auraSpellId = 1242974,
        cdmSpellId = 384452,
        cdmBorrow = true,
        unit = "player",
        filter = "HELPFUL|PLAYER",
        enableLabel = "Enable Arcane Salvo Stacks Tracker",
        enableDescription = "Show your Arcane Salvo stacks as a dedicated, customizable aura.",
        editModeName = "Arcane Salvo",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.58, 0.38, 0.93, 1.0 },  -- arcane purple
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelArcane", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 25, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.58, 0.38, 0.93, 1.0 },
            barForegroundTint = { 0.58, 0.38, 0.93, 1.0 },
        }),
    },
})
