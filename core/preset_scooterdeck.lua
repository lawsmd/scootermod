local addonName, addon = ...

local Presets = addon.Presets
if not Presets or not Presets.Register then
    error("ScooterMod preset payload loaded before Presets API (core/presets.lua). Check ScooterMod.toc load order: core/presets.lua must load before core/preset_*.lua.", 2)
end

-- Placeholder only (payload will be captured later)
Presets:Register({
    id = "ScooterDeck",
    name = "ScooterDeck",
    description = "Steam Deck / controller-focused layout with enlarged text and ConsolePort bindings.",
    wowBuild = "11.2.5",
    version = "PENDING",
    screenClass = "handheld",
    recommendedInput = "ConsolePort",
    tags = { "Handheld", "ConsolePort", "Steam Deck" },
    previewTexture = "Interface\\AddOns\\ScooterMod\\Scooter",
    previewThumbnail = "Interface\\AddOns\\ScooterMod\\Scooter",
    designedFor = { "Steam Deck / handheld displays", "Controller gameplay" },
    recommends = { "ConsolePort (required)" },
    requiresConsolePort = true,
    comingSoon = true,
})
