-- classauras/deathknight.lua - Death Knight class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

CA.RegisterAuras("DEATHKNIGHT", {
    {
        id = "lesserGhoulStacks",
        label = "Lesser Ghoul Stacks",
        auraSpellId = 1254252,
        cdmSpellId = 1254252,
        cdmBorrow = true,
        unit = "player",
        filter = "HELPFUL|PLAYER",
        enableLabel = "Enable Lesser Ghoul Stacks Tracker",
        enableDescription = "Show your Lesser Ghoul stacks as a dedicated, customizable aura.",
        editModeName = "Lesser Ghoul Stacks",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.0, 0.8, 0.2, 1.0 },  -- unholy green
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelZombie", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 8, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.0, 0.8, 0.2, 1.0 },
            barForegroundTint = { 0.0, 0.8, 0.2, 1.0 },
        }),
    },
})
