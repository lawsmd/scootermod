local addonName, addon = ...

addon.Presets = addon.Presets or {}
local Presets = addon.Presets

local registry = {}
local order = {}

local function deepCopy(tbl)
    if not tbl then return nil end
    return CopyTable(tbl)
end

local function normalizeId(id)
    if type(id) ~= "string" then return nil end
    id = id:lower():gsub("%s+", "_")
    return id
end

function Presets:Register(data)
    if type(data) ~= "table" then
        error("Preset data must be a table", 2)
    end
    local id = normalizeId(data.id or data.name)
    if not id or id == "" then
        error("Preset requires an id or name", 2)
    end
    if registry[id] then
        error("Preset '" .. id .. "' already registered", 2)
    end

    local entry = deepCopy(data)
    entry.id = id
    entry.name = data.name or id
    entry.version = data.version or "PENDING"
    entry.wowBuild = tostring(data.wowBuild or "")
    entry.description = data.description or ""
    entry.previewTexture = data.previewTexture or "Interface\\AddOns\\ScooterMod\\Scooter"
    entry.previewThumbnail = data.previewThumbnail or entry.previewTexture
    entry.tags = data.tags or {}
    entry.comingSoon = not not data.comingSoon
    entry.requiresConsolePort = not not data.requiresConsolePort
    entry.recommendedInput = data.recommendedInput or (entry.requiresConsolePort and "ConsolePort" or "Mouse + Keyboard")
    entry.screenClass = data.screenClass or "desktop"
    entry.lastUpdated = data.lastUpdated or date("%Y-%m-%d")
    entry.editModeExport = data.editModeExport
    entry.editModeSha256 = data.editModeSha256
    entry.scooterProfile = data.scooterProfile
    entry.profileSha256 = data.profileSha256
    entry.consolePortProfile = data.consolePortProfile
    entry.consolePortSha256 = data.consolePortSha256
    entry.notes = data.notes

    registry[id] = entry
    table.insert(order, id)
    table.sort(order)
end

function Presets:GetList()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = registry[id]
    end
    return list
end

function Presets:GetPreset(id)
    if not id then return nil end
    return registry[normalizeId(id)] or registry[id]
end

function Presets:HasConsolePort()
    return _G.ConsolePort ~= nil
end

function Presets:CheckDependencies(preset)
    if not preset then
        return false, "Preset not found."
    end
    if preset.requiresConsolePort and not self:HasConsolePort() then
        return false, "ConsolePort must be installed to import this preset."
    end
    return true
end

function Presets:IsPayloadReady(preset)
    if not preset then return false end
    if not preset.editModeExport or not preset.scooterProfile then
        return false
    end
    return true
end

function Presets:ApplyPreset(id, opts)
    local preset = self:GetPreset(id)
    if not preset then
        return false, "Preset not found."
    end
    local ok, depErr = self:CheckDependencies(preset)
    if not ok then
        return false, depErr
    end
    if not self:IsPayloadReady(preset) then
        return false, "Preset payload has not shipped yet."
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot import presets during combat."
    end
    if not addon.EditMode or not addon.EditMode.ImportPresetLayout then
        return false, "Preset import helper is not available."
    end
    return addon.EditMode:ImportPresetLayout(preset, opts or {})
end

function Presets:GetDefaultPresetId()
    return order[1]
end

-- -------------------------------------------------------------------------
-- Built-in registry entries (payloads pending)
-- -------------------------------------------------------------------------

Presets:Register({
    id = "ScooterUI",
    name = "ScooterUI",
    description = "Author's flagship desktop layout showcasing ScooterMod styling for raiding and Mythic+.",
    wowBuild = "11.2.5",
    version = "PENDING",
    screenClass = "desktop",
    recommendedInput = "Mouse + Keyboard",
    tags = { "Desktop", "Mythic+", "Raiding" },
    previewTexture = "Interface\\AddOns\\ScooterMod\\Scooter",
    previewThumbnail = "Interface\\AddOns\\ScooterMod\\Scooter",
    comingSoon = true,
})

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
    requiresConsolePort = true,
    comingSoon = true,
})

return Presets

