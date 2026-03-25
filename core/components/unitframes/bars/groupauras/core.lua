--------------------------------------------------------------------------------
-- groupauras/core.lua
-- Aura Tracking on group frames (party + raid)
--
-- Renders custom Scoot-styled icons for tracked auras. Buff strip
-- overlay (buffstrip.lua) handles scaling Blizzard's default buff icons.
-- Spell registry, event handling, active-set management, rainbow color
-- engine, graceful degradation.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.AuraTracking = addon.AuraTracking or {}
local HA = addon.AuraTracking

--------------------------------------------------------------------------------
-- Spell Registry
--------------------------------------------------------------------------------
-- Each class maps to an array of { id = spellId, name = "Spell Name" }.
-- Organized by class token for the settings UI class selector.
--------------------------------------------------------------------------------

HA.SPELL_REGISTRY = {
    EVOKER = {
        -- Preservation
        { id = 355941, name = "Dream Breath",        textureId = 5765862 },
        { id = 363502, name = "Dream Flight",        textureId = 5765860 },
        { id = 364343, name = "Echo",                 textureId = 5765863 },
        { id = 366155, name = "Reversion",            textureId = 5765865 },
        { id = 367364, name = "Echo (Reversion)",     textureId = 5765863 },
        { id = 373267, name = "Lifebind",             textureId = 5765864 },
        { id = 376788, name = "Echo (Dream Breath)",  textureId = 5765863 },
        -- Augmentation
        { id = 360827, name = "Blistering Scales",    textureId = 5199623 },
        { id = 395152, name = "Ebon Might",           textureId = 5199630 },
        { id = 410089, name = "Prescience",           textureId = 5199640 },
        { id = 410263, name = "Inferno's Blessing",   textureId = 5199634 },
        { id = 410686, name = "Symbiotic Bloom",      textureId = 5199645 },
        { id = 413984, name = "Shifting Sands",       textureId = 5199644 },
    },
    DRUID = {
        { id = 774,    name = "Rejuvenation",   textureId = 136081 },
        { id = 8936,   name = "Regrowth",        textureId = 136085 },
        { id = 33763,  name = "Lifebloom",        textureId = 134206 },
        { id = 48438,  name = "Wild Growth",      textureId = 236153 },
        { id = 155777, name = "Germination",      textureId = 136081 },
    },
    PRIEST = {
        -- Discipline
        { id = 17,      name = "Power Word: Shield",    textureId = 135940 },
        { id = 194384,  name = "Atonement",              textureId = 458722 },
        { id = 1253593, name = "Void Shield",            textureId = 135940 },
        -- Holy
        { id = 139,     name = "Renew",                  textureId = 135953 },
        { id = 41635,   name = "Prayer of Mending",      textureId = 135944 },
        { id = 77489,   name = "Echo of Light",           textureId = 237541 },
    },
    MONK = {
        { id = 115175, name = "Soothing Mist",    textureId = 606550 },
        { id = 119611, name = "Renewing Mist",    textureId = 627487 },
        { id = 124682, name = "Enveloping Mist",  textureId = 775461 },
        { id = 450769, name = "Aspect of Harmony", textureId = 5765856 },
    },
    SHAMAN = {
        { id = 974,    name = "Earth Shield",          textureId = 136089 },
        { id = 383648, name = "Earth Shield (Talent)",  textureId = 136089 },
        { id = 61295,  name = "Riptide",               textureId = 252995 },
    },
    PALADIN = {
        { id = 53563,   name = "Beacon of Light",      textureId = 236247 },
        { id = 156322,  name = "Eternal Flame",        textureId = 135972 },
        { id = 156910,  name = "Beacon of Faith",       textureId = 236247 },
        { id = 1244893, name = "Beacon of the Savior",  textureId = 236247 },
    },
}

-- Alphabetical class order for selector
HA.CLASS_ORDER = { "DRUID", "EVOKER", "MONK", "PALADIN", "PRIEST", "SHAMAN" }

-- Display names for the class selector
HA.CLASS_LABELS = {
    DRUID   = "Druid",
    EVOKER  = "Evoker",
    MONK    = "Monk",
    PALADIN = "Paladin",
    PRIEST  = "Priest",
    SHAMAN  = "Shaman",
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

-- spellId → registry entry (for textureId lookup; includes linkedIds → parent entry)
HA.SPELL_REGISTRY_BY_ID = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_REGISTRY_BY_ID[entry.id] = entry
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_REGISTRY_BY_ID[linkedId] = entry
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
    iconColor = "original",
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
    local ha = gf and gf.auraTracking
    local spells = ha and ha.spells
    if not spells then return end
    for spellId, config in pairs(spells) do
        -- Only track spells that exist in the registry (ignore stale DB entries)
        if config.enabled and HA.SPELL_REGISTRY_BY_ID[spellId] then
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

local AuraTrackingState = setmetatable({}, { __mode = "k" })

local function getState(frame)
    if not frame then return nil end
    return AuraTrackingState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not AuraTrackingState[frame] then
        AuraTrackingState[frame] = {
            unit = nil,
            iconFrames = {},
        }
    end
    return AuraTrackingState[frame]
end

-- Export for icons.lua and buffstrip.lua
HA._getState = getState
HA._ensureState = ensureState
HA._AuraTrackingState = AuraTrackingState

--------------------------------------------------------------------------------
-- Group Unit Token Set
--------------------------------------------------------------------------------

local GROUP_UNITS = {}
HA._GROUP_UNITS = GROUP_UNITS  -- Export for buffstrip.lua

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
    local r, g, b = HA.HSVtoRGB(rainbowHue, 0.75, 1)
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
        -- Skip during Edit Mode to avoid taint propagation
        if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
           and addon.EditMode.IsEditModeActiveOrOpening() then
            return
        end
        local state = ensureState(frame)
        state.unit = unit
        -- Cache frame height while we have a safe reference (OOC context)
        if not InCombatLockdown() then
            local ok, h = pcall(frame.GetHeight, frame)
            if ok and type(h) == "number" and h > 0 then
                state.cachedHeight = h
            end
        end
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
            if not aura then return end
            local spellId = aura.spellId
            if not spellId then return end
            -- Skip secret spellIds individually (don't abort the whole scan)
            if issecretvalue and issecretvalue(spellId) then return end
            if HA.ACTIVE_TRACKED_IDS[spellId] then
                found[spellId] = {
                    spellId = spellId,
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
            HA.StyleIcon(iconFrame, spellId, auraData, frame, unit)
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

local function DiscoverGroupFrames()
    -- Party frames: CompactPartyFrameMember1..5
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            local ok, unit = pcall(function() return frame.unit end)
            if ok and unit and GROUP_UNITS[unit] then
                local state = ensureState(frame)
                state.unit = unit
            end
        end
    end
    -- Raid frames: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            local ok, unit = pcall(function() return frame.unit end)
            if ok and unit and GROUP_UNITS[unit] then
                local state = ensureState(frame)
                state.unit = unit
            end
        end
    end
end

function HA.RefreshAllAuraDisplays()
    DiscoverGroupFrames()
    for frame, state in pairs(AuraTrackingState) do
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
-- When user enables/disables a spell, rebuild tracked set and refresh all
-- custom icons + buff strip overlays.
--------------------------------------------------------------------------------

local pendingRefresh = false

function HA.OnConfigChanged()
    HA.RebuildActiveTrackedSet()

    if InCombatLockdown() then
        pendingRefresh = true
        return
    end

    HA.RefreshAllAuraDisplays()
    -- Refresh buff icon scaling (installed by buffstrip.lua)
    if HA.RefreshBuffStripScaling then
        HA.RefreshBuffStripScaling()
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
                local ha = db and db.groupFrames and db.groupFrames.auraTracking
                if ha and ha.spells and next(ha.spells) then
                    print("|cff00ff66Scoot:|r Aura Tracking feature unavailable — aura data is protected.")
                end
            end
            return
        end

        RebuildGroupUnits()
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

        -- Find the frame for this unit and update custom icons
        local found = false
        for frame, state in pairs(AuraTrackingState) do
            if state.unit == unit then
                HA.UpdateAurasForFrame(frame, unit)
                found = true
            end
        end
        -- Fallback: discover frames if no match (handles late-spawning companions, etc.)
        if not found then
            DiscoverGroupFrames()
            for frame, state in pairs(AuraTrackingState) do
                if state.unit == unit then
                    HA.UpdateAurasForFrame(frame, unit)
                end
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
            HA.RefreshAllAuraDisplays()
        end
    end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
