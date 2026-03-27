--------------------------------------------------------------------------------
-- groupauras/buffstrip.lua
-- Blizzard buff icon scaling — applies user-configured scale to all
-- CompactUnitFrame buff icons on party/raid frames.
--
-- Users configure custom Scoot icons (via icons.lua) for auras they care
-- about. This file controls the Blizzard originals' visibility via scaling.
--
-- TAINT TEST: SetScale on Blizzard buff frames from addon context.
-- If this causes taint cascade in combat, this approach must be reverted.
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local NORMAL_SCALE = 1.0
local HIDDEN_SCALE = 0.001  -- Sub-pixel, truly invisible

-- Read user-configured aura scale from DB (slider: 0 = Hidden, 100 = Normal)
local function GetConfiguredScale()
    local db = addon.db and addon.db.profile
    local at = db and db.groupFrames and db.groupFrames.auraTracking
    local val = at and at.auraScale
    if val == nil then return NORMAL_SCALE end  -- default 100% (no change)
    if val <= 0 then return HIDDEN_SCALE end     -- "Hidden" slider position
    return val / 100
end

--------------------------------------------------------------------------------
-- SetScale Hook
--------------------------------------------------------------------------------
-- Post-hook on CompactUnitFrame_UtilSetBuff. Fires after Blizzard's Show()
-- for each buff icon on a group frame. We never read the aura parameter
-- (avoids tainting Blizzard's stored aura tables).
--------------------------------------------------------------------------------

local hookInstalled = false

local function InstallScaleHook()
    if hookInstalled then return end
    if not CompactUnitFrame_UtilSetBuff then return end

    hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(buffFrame, aura)
        if not buffFrame then return end
        buffFrame:SetScale(GetConfiguredScale())
    end)

    hookInstalled = true
end

--------------------------------------------------------------------------------
-- OOC Scale Restoration
--------------------------------------------------------------------------------
-- When config changes out of combat, force-restore scale on known buff frames
-- so the change is visible immediately (without waiting for next UNIT_AURA).
--------------------------------------------------------------------------------

local function RestoreAllBuffScales()
    if InCombatLockdown() then return end
    local targetScale = GetConfiguredScale()

    for frame, state in pairs(HA._AuraTrackingState) do
        if state.unit then
            local ok, buffFrames = pcall(function() return frame.buffFrames end)
            if ok and buffFrames then
                for i = 1, 10 do
                    local bf = buffFrames[i]
                    if not bf then break end
                    pcall(bf.SetScale, bf, targetScale)
                end
            end
        end
    end
end

-- Public API for core.lua config change handler
function HA.RefreshBuffStripScaling()
    RestoreAllBuffScales()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    InstallScaleHook()
    self:UnregisterAllEvents()
end)
