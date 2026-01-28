--------------------------------------------------------------------------------
-- bars/combat.lua
-- Combat deferral systems for unit frame bar styling
-- Queues operations that cannot be performed during combat lockdown
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsCombat = addon.BarsCombat or {}
local Combat = addon.BarsCombat

--------------------------------------------------------------------------------
-- Power Bar Combat Deferral
--------------------------------------------------------------------------------

local pendingPowerBarUnits = {}
local powerBarCombatWatcher = nil

local function ensurePowerBarCombatWatcher()
    if powerBarCombatWatcher then
        return
    end
    powerBarCombatWatcher = CreateFrame("Frame")
    powerBarCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    powerBarCombatWatcher:SetScript("OnEvent", function()
        for unit in pairs(pendingPowerBarUnits) do
            pendingPowerBarUnits[unit] = nil
            -- ApplyUnitFrameBarTexturesFor handles full styling including custom positioning
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor(unit)
            end
        end
    end)
end

function Combat.queuePowerBarReapply(unit)
    ensurePowerBarCombatWatcher()
    pendingPowerBarUnits[unit] = true
end

--------------------------------------------------------------------------------
-- Unit Frame Texture Combat Deferral
--------------------------------------------------------------------------------

local pendingUnitFrameTextureUnits = {}
local unitFrameTextureCombatWatcher = nil

local function ensureUnitFrameTextureCombatWatcher()
    if unitFrameTextureCombatWatcher then
        return
    end
    unitFrameTextureCombatWatcher = CreateFrame("Frame")
    unitFrameTextureCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    unitFrameTextureCombatWatcher:SetScript("OnEvent", function()
        for unit in pairs(pendingUnitFrameTextureUnits) do
            pendingUnitFrameTextureUnits[unit] = nil
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor(unit)
            end
        end
    end)
end

function Combat.queueUnitFrameTextureReapply(unit)
    ensureUnitFrameTextureCombatWatcher()
    pendingUnitFrameTextureUnits[unit] = true
end

--------------------------------------------------------------------------------
-- Raid/Party Frame Combat Deferral
--------------------------------------------------------------------------------
-- We must NEVER apply CompactUnitFrame (raid/party) cosmetic changes during combat,
-- and we must avoid doing synchronous work inside Blizzard's CompactUnitFrame update chains.

local pendingRaidFrameReapply = false
local pendingPartyFrameReapply = false
local raidFrameCombatWatcher = nil

local function ensureRaidFrameCombatWatcher()
    if raidFrameCombatWatcher then
        return
    end
    raidFrameCombatWatcher = CreateFrame("Frame")
    raidFrameCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    raidFrameCombatWatcher:SetScript("OnEvent", function()
        if not pendingRaidFrameReapply and not pendingPartyFrameReapply then
            return
        end
        local doRaid = pendingRaidFrameReapply
        local doParty = pendingPartyFrameReapply
        pendingRaidFrameReapply = false
        pendingPartyFrameReapply = false

        if doRaid then
            if addon.ApplyRaidFrameHealthBarStyle then
                addon.ApplyRaidFrameHealthBarStyle()
            end
            if addon.ApplyRaidFrameStatusTextStyle then
                addon.ApplyRaidFrameStatusTextStyle()
            end
            if addon.ApplyRaidFrameGroupTitlesStyle then
                addon.ApplyRaidFrameGroupTitlesStyle()
            end
            -- Also apply combat-safe overlays (create/update overlays out of combat)
            if addon.ApplyRaidFrameHealthOverlays then
                addon.ApplyRaidFrameHealthOverlays()
            end
            if addon.ApplyRaidFrameNameOverlays then
                addon.ApplyRaidFrameNameOverlays()
            end
        end

        if doParty then
            if addon.ApplyPartyFrameHealthBarStyle then
                addon.ApplyPartyFrameHealthBarStyle()
            end
            if addon.ApplyPartyFrameTitleStyle then
                addon.ApplyPartyFrameTitleStyle()
            end
            -- Also apply combat-safe overlays (create/update overlays out of combat)
            if addon.ApplyPartyFrameHealthOverlays then
                addon.ApplyPartyFrameHealthOverlays()
            end
            if addon.ApplyPartyFrameNameOverlays then
                addon.ApplyPartyFrameNameOverlays()
            end
            -- Apply visibility settings (over absorb glow, etc.)
            if addon.ApplyPartyOverAbsorbGlowVisibility then
                addon.ApplyPartyOverAbsorbGlowVisibility()
            end
        end
    end)
end

function Combat.queueRaidFrameReapply()
    ensureRaidFrameCombatWatcher()
    pendingRaidFrameReapply = true
end

function Combat.queuePartyFrameReapply()
    ensureRaidFrameCombatWatcher()
    pendingPartyFrameReapply = true
end

return Combat
