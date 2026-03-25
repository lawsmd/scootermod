--------------------------------------------------------------------------------
-- groupauras/core.lua
-- Healer Aura tracking on group frames (party + raid)
--
-- Hides Blizzard's default buff icons for tracked healer auras and replaces
-- them with custom Scoot-styled icons. Spell registry, event handling,
-- active-set management, rainbow color engine, graceful degradation.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.HealerAuras = addon.HealerAuras or {}
local HA = addon.HealerAuras

--------------------------------------------------------------------------------
-- Spell Registry
--------------------------------------------------------------------------------
-- Each class maps to an array of { id = spellId, name = "Spell Name" }.
-- Organized by class token for the settings UI class selector.
--------------------------------------------------------------------------------

HA.SPELL_REGISTRY = {
    EVOKER = {
        -- Preservation
        { id = 355941, name = "Dream Breath" },
        { id = 363502, name = "Dream Flight" },
        { id = 364343, name = "Echo" },
        { id = 366155, name = "Reversion" },
        { id = 367364, name = "Echo (Reversion)" },
        { id = 373267, name = "Lifebind" },
        { id = 376788, name = "Echo (Dream Breath)" },
        -- Augmentation
        { id = 360827, name = "Blistering Scales" },
        { id = 395152, name = "Ebon Might" },
        { id = 410089, name = "Prescience" },
        { id = 410263, name = "Inferno's Blessing" },
        { id = 410686, name = "Symbiotic Bloom" },
        { id = 413984, name = "Shifting Sands" },
        -- Raid buffs
        { id = 369459, name = "Source of Magic" },
        -- Blessing of the Bronze (one UI entry, all 13 class variants tracked together)
        { id = 381748, name = "Blessing of the Bronze", linkedIds = {
            381732, 381741, 381746, 381748, 381749, 381750, 381751,
            381752, 381753, 381754, 381756, 381757, 381758,
        }},
    },
    DRUID = {
        { id = 774,    name = "Rejuvenation" },
        { id = 8936,   name = "Regrowth" },
        { id = 33763,  name = "Lifebloom" },
        { id = 48438,  name = "Wild Growth" },
        { id = 155777, name = "Germination" },
        -- Raid buff
        { id = 1126,   name = "Mark of the Wild" },
    },
    PRIEST = {
        -- Discipline
        { id = 17,      name = "Power Word: Shield" },
        { id = 194384,  name = "Atonement" },
        { id = 1253593, name = "Void Shield" },
        -- Holy
        { id = 139,     name = "Renew" },
        { id = 41635,   name = "Prayer of Mending" },
        { id = 77489,   name = "Echo of Light" },
        -- Raid buff
        { id = 21562,   name = "Power Word: Fortitude" },
    },
    MONK = {
        { id = 115175, name = "Soothing Mist" },
        { id = 119611, name = "Renewing Mist" },
        { id = 124682, name = "Enveloping Mist" },
        { id = 450769, name = "Aspect of Harmony" },
    },
    SHAMAN = {
        { id = 974,    name = "Earth Shield" },
        { id = 383648, name = "Earth Shield (Talent)" },
        { id = 61295,  name = "Riptide" },
        -- Raid buff
        { id = 462854, name = "Skyfury" },
    },
    PALADIN = {
        { id = 53563,   name = "Beacon of Light" },
        { id = 156322,  name = "Eternal Flame" },
        { id = 156910,  name = "Beacon of Faith" },
        { id = 1244893, name = "Beacon of the Savior" },
    },
    MAGE = {
        { id = 1459, name = "Arcane Intellect" },
    },
    WARRIOR = {
        { id = 6673, name = "Battle Shout" },
    },
}

-- Alphabetical class order for selector
HA.CLASS_ORDER = { "DRUID", "EVOKER", "MAGE", "MONK", "PALADIN", "PRIEST", "SHAMAN", "WARRIOR" }

-- Display names for the class selector
HA.CLASS_LABELS = {
    DRUID   = "Druid",
    EVOKER  = "Evoker",
    MAGE    = "Mage",
    MONK    = "Monk",
    PALADIN = "Paladin",
    PRIEST  = "Priest",
    SHAMAN  = "Shaman",
    WARRIOR = "Warrior",
}

-- Reverse lookup: spellId → classToken (includes linkedIds)
HA.SPELL_TO_CLASS = {}
for classToken, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_TO_CLASS[entry.id] = classToken
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_TO_CLASS[linkedId] = classToken
            end
        end
    end
end

-- spellId → display name (includes linkedIds → parent name)
HA.SPELL_NAMES = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_NAMES[entry.id] = entry.name
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_NAMES[linkedId] = entry.name
            end
        end
    end
end

-- linkedId → primary entry id (so linked variants share config with their parent)
HA.LINKED_TO_PRIMARY = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.LINKED_TO_PRIMARY[linkedId] = entry.id
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Per-Spell Default Settings
--------------------------------------------------------------------------------

HA.SPELL_DEFAULTS = {
    enabled = false,
    iconStyle = "spell",
    iconColor = "custom",
    iconCustomColor = { 1, 1, 1, 1 },
    iconScale = 100,
    position = "inside",
    anchor = "TOPRIGHT",
    offsetX = 0,
    offsetY = 0,
}

--------------------------------------------------------------------------------
-- Active Tracked Set
--------------------------------------------------------------------------------
-- Rebuilt when user changes config. Only enabled spells are in this set.
--------------------------------------------------------------------------------

HA.ACTIVE_TRACKED_IDS = {}

function HA.RebuildActiveTrackedSet()
    wipe(HA.ACTIVE_TRACKED_IDS)
    local db = addon.db and addon.db.profile
    local gf = db and db.groupFrames
    local ha = gf and gf.healerAuras
    local spells = ha and ha.spells
    if not spells then return end
    for spellId, config in pairs(spells) do
        if config.enabled then
            HA.ACTIVE_TRACKED_IDS[spellId] = true
            -- Also add all linked variants (e.g., Blessing of the Bronze per-class IDs)
            for _, classSpells in pairs(HA.SPELL_REGISTRY) do
                for _, entry in ipairs(classSpells) do
                    if entry.id == spellId and entry.linkedIds then
                        for _, linkedId in ipairs(entry.linkedIds) do
                            HA.ACTIVE_TRACKED_IDS[linkedId] = true
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Weak-keyed State Table (taint prevention)
--------------------------------------------------------------------------------
-- Stores all Scoot state per CompactUnitFrame externally.
-- Never write properties directly to Blizzard frames.
--------------------------------------------------------------------------------

local HealerAuraState = setmetatable({}, { __mode = "k" })

local function getState(frame)
    if not frame then return nil end
    return HealerAuraState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not HealerAuraState[frame] then
        HealerAuraState[frame] = {
            unit = nil,
            iconFrames = {},
        }
    end
    return HealerAuraState[frame]
end

-- Export for icons.lua
HA._getState = getState
HA._ensureState = ensureState
HA._HealerAuraState = HealerAuraState

--------------------------------------------------------------------------------
-- Group Unit Token Set
--------------------------------------------------------------------------------

local GROUP_UNITS = {}

local function RebuildGroupUnits()
    wipe(GROUP_UNITS)
    GROUP_UNITS["player"] = true
    if IsInRaid() then
        for i = 1, 40 do
            GROUP_UNITS["raid" .. i] = true
        end
    else
        for i = 1, 4 do
            GROUP_UNITS["party" .. i] = true
        end
    end
end

--------------------------------------------------------------------------------
-- HSV to RGB Conversion (for rainbow engine)
--------------------------------------------------------------------------------

function HA.HSVtoRGB(h, s, v)
    if s == 0 then return v, v, v end
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q
    end
end

--------------------------------------------------------------------------------
-- Rainbow Color Engine
--------------------------------------------------------------------------------
-- Shared OnUpdate frame, self-disabling when no rainbow icons are active.
-- All icons in rainbow mode share the same hue phase for visual coherence.
--------------------------------------------------------------------------------

HA._rainbowIcons = {}
local rainbowIcons = HA._rainbowIcons
local RAINBOW_CYCLE_PERIOD = 3.0
local rainbowHue = 0

local rainbowFrame = CreateFrame("Frame")
rainbowFrame:SetScript("OnUpdate", function(self, elapsed)
    if not next(rainbowIcons) then
        self:Hide()
        return
    end
    rainbowHue = (rainbowHue + elapsed / RAINBOW_CYCLE_PERIOD) % 1
    local r, g, b = HA.HSVtoRGB(rainbowHue, 1, 1)
    for tex in pairs(rainbowIcons) do
        if tex:IsVisible() then
            tex:SetVertexColor(r, g, b, 1)
        end
    end
end)
rainbowFrame:Hide()

function HA.RegisterRainbowIcon(texture)
    rainbowIcons[texture] = true
    rainbowFrame:Show()
end

function HA.UnregisterRainbowIcon(texture)
    rainbowIcons[texture] = nil
end

--------------------------------------------------------------------------------
-- Graceful Degradation
--------------------------------------------------------------------------------

HA._featureAvailable = nil

function HA.IsFeatureAvailable()
    if HA._featureAvailable ~= nil then
        return HA._featureAvailable
    end
    -- Test a canary spell to see if aura data is readable
    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(774) -- Rejuvenation
    end)
    if not ok or not info then
        HA._featureAvailable = false
        return false
    end
    -- Check if spellID is a secret value
    if issecretvalue and pcall(issecretvalue, info.spellID) then
        local isSecret = issecretvalue(info.spellID)
        if isSecret then
            HA._featureAvailable = false
            return false
        end
    end
    HA._featureAvailable = true
    return true
end

--------------------------------------------------------------------------------
-- Hide Hook — Suppress Blizzard buff icons for tracked spells
--------------------------------------------------------------------------------
-- Post-hook on CompactUnitFrame_UtilSetBuff. Fires after Blizzard's Show(),
-- so our Hide() wins. pcall wraps spellId access for secret-safety.
--------------------------------------------------------------------------------

local hideHookInstalled = false

local function InstallHideHook()
    if hideHookInstalled then return end
    if not CompactUnitFrame_UtilSetBuff then return end

    hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(buffFrame, aura)
        if not aura then return end
        local ok, isTracked = pcall(function()
            return aura.spellId and HA.ACTIVE_TRACKED_IDS[aura.spellId]
        end)
        if ok and isTracked then
            buffFrame:Hide()
        end
    end)

    hideHookInstalled = true
end

--------------------------------------------------------------------------------
-- Frame-to-Unit Mapping
--------------------------------------------------------------------------------
-- Hooks CompactUnitFrame_SetUnit to cache which unit token each frame has.
-- This avoids reading frame.unit directly (which could be tainted).
--------------------------------------------------------------------------------

local frameToUnitHookInstalled = false

local function InstallFrameToUnitHook()
    if frameToUnitHookInstalled then return end
    if not CompactUnitFrame_SetUnit then return end

    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
        if not frame then return end
        local state = ensureState(frame)
        state.unit = unit
        if unit and GROUP_UNITS[unit] then
            HA.UpdateAurasForFrame(frame, unit)
        else
            HA.HideAllAurasForFrame(frame)
        end
    end)

    frameToUnitHookInstalled = true
end

--------------------------------------------------------------------------------
-- Aura Scanning
--------------------------------------------------------------------------------

local function ScanAurasForUnit(unit)
    local found = {}
    if not unit or not AuraUtil or not AuraUtil.ForEachAura then return found end

    local ok = pcall(function()
        AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
            if aura and aura.spellId and HA.ACTIVE_TRACKED_IDS[aura.spellId] then
                found[aura.spellId] = {
                    spellId = aura.spellId,
                    icon = aura.icon,
                    duration = aura.duration or 0,
                    expirationTime = aura.expirationTime or 0,
                    applications = aura.applications or 0,
                    auraInstanceID = aura.auraInstanceID,
                }
            end
        end, true) -- usePackedAura = true
    end)

    return found
end

function HA.UpdateAurasForFrame(frame, unit)
    if not frame or not unit then return end
    if not next(HA.ACTIVE_TRACKED_IDS) then
        HA.HideAllAurasForFrame(frame)
        return
    end

    -- Skip during Edit Mode
    if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
       and addon.EditMode.IsEditModeActiveOrOpening() then
        return
    end

    local state = ensureState(frame)
    local currentAuras = ScanAurasForUnit(unit)

    -- Hide icons for auras no longer present
    for spellId, iconFrame in pairs(state.iconFrames) do
        if not currentAuras[spellId] then
            if HA.ReleaseIcon then
                HA.ReleaseIcon(iconFrame)
            end
            state.iconFrames[spellId] = nil
        end
    end

    -- Show/update icons for present auras
    for spellId, auraData in pairs(currentAuras) do
        local iconFrame = state.iconFrames[spellId]
        if not iconFrame and HA.AcquireIcon then
            iconFrame = HA.AcquireIcon(frame)
            state.iconFrames[spellId] = iconFrame
        end
        if iconFrame and HA.StyleIcon then
            HA.StyleIcon(iconFrame, spellId, auraData, frame)
        end
    end
end

function HA.HideAllAurasForFrame(frame)
    if not frame then return end
    local state = getState(frame)
    if not state then return end
    for spellId, iconFrame in pairs(state.iconFrames) do
        if HA.ReleaseIcon then
            HA.ReleaseIcon(iconFrame)
        end
    end
    wipe(state.iconFrames)
end

function HA.RefreshAllAuraDisplays()
    for frame, state in pairs(HealerAuraState) do
        if state.unit and GROUP_UNITS[state.unit] then
            HA.UpdateAurasForFrame(frame, state.unit)
        else
            HA.HideAllAurasForFrame(frame)
        end
    end
end

--------------------------------------------------------------------------------
-- Config Change Refresh
--------------------------------------------------------------------------------
-- When user enables/disables a spell, force Blizzard to re-evaluate buff
-- display and refresh our custom icons.
--------------------------------------------------------------------------------

local pendingRefresh = false

function HA.OnConfigChanged()
    HA.RebuildActiveTrackedSet()

    -- Force Blizzard to re-evaluate buff display on all active group frames
    if InCombatLockdown() then
        pendingRefresh = true
        return
    end

    HA.ForceBlizzardAuraRefresh()
    HA.RefreshAllAuraDisplays()
end

function HA.ForceBlizzardAuraRefresh()
    if not CompactUnitFrame_UpdateAuras then return end

    for frame, state in pairs(HealerAuraState) do
        if state.unit then
            pcall(CompactUnitFrame_UpdateAuras, frame)
        end
    end
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not HA.IsFeatureAvailable() then
            -- One-time warning
            if not HA._secretWarningShown then
                HA._secretWarningShown = true
                -- Only warn if user has any spells configured
                local db = addon.db and addon.db.profile
                local ha = db and db.groupFrames and db.groupFrames.healerAuras
                if ha and ha.spells and next(ha.spells) then
                    print("|cff00ff66Scoot:|r Healer Auras feature unavailable — aura data is protected.")
                end
            end
            return
        end

        RebuildGroupUnits()
        InstallHideHook()
        InstallFrameToUnitHook()
        HA.RebuildActiveTrackedSet()

        -- Delayed initial scan (frames need time to initialize)
        C_Timer.After(1.0, function()
            HA.RefreshAllAuraDisplays()
        end)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not GROUP_UNITS[unit] then return end
        if not next(HA.ACTIVE_TRACKED_IDS) then return end

        -- Find the frame for this unit and update
        for frame, state in pairs(HealerAuraState) do
            if state.unit == unit then
                HA.UpdateAurasForFrame(frame, unit)
            end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildGroupUnits()
        C_Timer.After(0.1, function()
            HA.RefreshAllAuraDisplays()
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRefresh then
            pendingRefresh = false
            HA.ForceBlizzardAuraRefresh()
            HA.RefreshAllAuraDisplays()
        end
    end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
